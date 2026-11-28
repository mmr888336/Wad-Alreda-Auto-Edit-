/// World scene runner: renders ONE scene of the 3D world through the render
/// router, stage by stage, with an automatic fall back to the 2.5D engine.
///
/// The stages, in order (each one is logged on its own, so a failure is never
/// blamed on the wrong step):
///
///   1. plan    ([ThreeDStage.worldPlan])      story world -> 3D scene
///   2. GLB     ([ThreeDStage.worldGlb])       3D scene -> GLB file
///   3. inspect ([ThreeDStage.inspect])        the GLB is checked before native
///   4. load    ([ThreeDStage.filamentLoad])   Filament loads the GLB
///   5. manual  ([ThreeDStage.manualCamera])   native camera = manual, so the
///                                             camera rig of the GLB moves it
///   6. ready   ([ThreeDStage.ready])          the surface draws real frames
///   7. capture ([ThreeDStage.capture])        frames -> clip
///
/// Any failure (a thrown error, a rejected GLB, a bad clip) returns the whole
/// scene to the 2.5D engine through [RenderRouter.fallbackOf]: a failed 3D
/// render never costs a scene. A clip that is corrupt (green frames) or empty
/// (black, transparent, one flat colour) is a bad clip too. Props that have no
/// picture are handed back to 2.5D ([RenderRouter.handBack]) instead of
/// vanishing.
///
/// The native calls are injected ([World3DNativeOps]) so the whole flow is
/// tested without a device.
library;

import 'dart:io';
import 'dart:typed_data';

import 'cinematic_world.dart' show WorldScene;
import 'depth_camera_model.dart' show DepthCameraMove;
import 'glb_inspector.dart';
import 'motion_scene_model.dart';
import 'render_router.dart';
import 'three_d_asset_resolver.dart';
import 'three_d_stage_log.dart';
import 'world3d_glb_builder.dart';
import 'world3d_planner.dart';
import 'world3d_rig.dart' show World3DNativeCamera;

/// What the runner needs from the native Filament view.
class World3DNativeOps {
  const World3DNativeOps({
    required this.loadModel,
    required this.setManualCamera,
    required this.waitUntilRenderable,
    required this.capture,
    this.verifyClip,
  });

  /// Loads the GLB at the given path into the view.
  final Future<void> Function(String glbPath) loadModel;

  /// Puts the native camera in `manual` mode (it stays still, the camera rig
  /// animation inside the GLB moves the world).
  final Future<void> Function() setManualCamera;

  /// Completes when the surface draws real frames of the loaded model.
  final Future<void> Function() waitUntilRenderable;

  /// Captures [seconds] of the view and returns the path of the clip.
  final Future<String> Function(double seconds) capture;

  /// True when the clip is clean (no half-decoded green frames, and not black,
  /// transparent or empty). Optional.
  final Future<bool> Function(String clipPath)? verifyClip;
}

/// The outcome of one world scene.
class World3DSceneResult {
  const World3DSceneResult({
    required this.routing,
    this.clipPath,
    this.failedStage,
    this.notes = const <String>[],
  });

  /// Which layers each engine draws. A fallback routing means the 2.5D
  /// engine draws the whole scene.
  final SceneRouting routing;

  /// The captured clip of the 3D world (null on a fallback).
  final String? clipPath;

  /// The stage that failed, or null (no failure, or a fallback decided by the
  /// router before any stage ran).
  final ThreeDStage? failedStage;

  final List<String> notes;

  /// True when Filament drew the world of this scene.
  bool get rendered => clipPath != null && routing.usesFilament;

  /// True when the 2.5D engine draws the whole scene.
  bool get fellBack => routing.fallback;
}

class _StageFailure implements Exception {
  const _StageFailure(this.stage, this.error);

  final ThreeDStage stage;
  final Object error;

  @override
  String toString() => '${stage.label}: $error';
}

class _BuiltGlb {
  const _BuiltGlb(this.glb, this.path);

  final World3DGlb glb;
  final String path;
}

class World3DSceneRunner {
  World3DSceneRunner._();

  static const double _minSeconds = 0.5;
  static const double _maxSeconds = 8.0;

  /// Seconds the camera rig rests at the first and the last pose, so the
  /// capture never starts or ends in the middle of the move.
  static const double _hold = 0.5;

  /// Renders the world of [motion] ([world] is its 3D plan).
  ///
  /// [sceneNumber] is the 1-based number used in the log. [move] and
  /// [intensity] are the camera of the scene. Never throws: every problem
  /// comes back as a fallback result.
  static Future<World3DSceneResult> run({
    required MotionScene motion,
    required WorldScene world,
    required int sceneNumber,
    required World3DNativeOps ops,
    required ThreeDExportSummary summary,
    Map<String, Uint8List> billboardImages = const <String, Uint8List>{},
    DepthCameraMove move = DepthCameraMove.none,
    double intensity = 0.8,
    bool filamentReady = true,
    Duration settle = const Duration(milliseconds: 350),
    void Function(ThreeDStage stage)? onStage,
    ThreeDAssetResolver? resolver,
  }) async {
    final notes = <String>[];
    final label = 'مشهد $sceneNumber';

    var routing = RenderRouter.route(motion, filamentReady: filamentReady);
    if (routing.fallback) {
      notes.add('$label: يُرسم بمحرك 2.5D (${routing.reason}).');
      return World3DSceneResult(routing: routing, notes: notes);
    }

    // A prop the 3D world has no picture for would vanish: 2.5D keeps it.
    routing = RenderRouter.handBack(motion, routing, (layer) {
      final key = layer.assetKey;
      if (key == null || !key.startsWith('decor:')) return false;
      if (World3DPlanner.isSetPiece(key, layer.scale)) return false;
      return !billboardImages.containsKey(key);
    });
    if (routing.fallback) {
      notes.add('$label: يُرسم بمحرك 2.5D (${routing.reason}).');
      return World3DSceneResult(routing: routing, notes: notes);
    }

    Future<T> step<T>(
      ThreeDStage stage,
      Future<T> Function() body, {
      String? Function(T value)? describe,
    }) async {
      onStage?.call(stage);
      summary.begin(sceneNumber, stage);
      final watch = Stopwatch()..start();
      try {
        final value = await body();
        summary.record(
          sceneNumber,
          stage,
          ok: true,
          elapsed: watch.elapsed,
          detail: describe?.call(value),
        );
        return value;
      } catch (error) {
        summary.record(
          sceneNumber,
          stage,
          ok: false,
          elapsed: watch.elapsed,
          detail: '$error',
        );
        throw _StageFailure(stage, error);
      }
    }

    Directory? folder;

    try {
      final seconds = motion.duration.isFinite
          ? motion.duration.clamp(_minSeconds, _maxSeconds).toDouble()
          : 3.0;

      // 0. Resolve + download the 3D models of the props (decor layers).
      //    Any failure here is non-fatal: the prop keeps its billboard.
      final resolved = await _resolveProps(
        motion: motion,
        sceneNumber: sceneNumber,
        resolver: resolver,
        summary: summary,
        notes: notes,
        label: label,
        onStage: onStage,
      );
      final modelBytes = await _loadModelBytes(
        resolved: resolved,
        sceneNumber: sceneNumber,
        summary: summary,
        notes: notes,
        label: label,
        onStage: onStage,
      );

      // 1. Plan.
      final planned = await step<World3DScene>(
        ThreeDStage.worldPlan,
        () async => World3DPlanner.plan(
          world,
          stage: World3DNativeCamera.stage(),
          move: move,
          intensity: intensity,
          resolved: resolved,
        ),
        describe: (scene) => '${scene.objects.length} جسم',
      );

      // 2. GLB.
      final built = await step<_BuiltGlb>(
        ThreeDStage.worldGlb,
        () async {
          final glb = World3DGlbBuilder.build(
            planned,
            billboardImages: billboardImages,
            modelBytes: modelBytes,
            cameraSeconds: seconds,
            holdStart: _hold,
            holdEnd: _hold,
          );
          final directory =
              await Directory.systemTemp.createTemp('world3d_scene_');
          folder = directory;
          final file = File('${directory.path}/world_scene_$sceneNumber.glb');
          await file.writeAsBytes(glb.bytes, flush: true);
          return _BuiltGlb(glb, file.path);
        },
        describe: (value) =>
            '${value.glb.objectCount} كائن، ${value.glb.triangleCount} مثلث'
            '${value.glb.animated ? '، حركة كاميرا' : ''}',
      );

      if (built.glb.skipped.isNotEmpty) {
        notes.add(
          '$label: عناصر خارج GLB: ${built.glb.skipped.join('، ')}.',
        );
      }

      // 3. Inspect: a bad file must never reach the native engine.
      await step<GlbReport>(
        ThreeDStage.inspect,
        () async {
          final report = await GlbInspector.inspectFile(built.path);
          final reason = report.rejection;
          if (reason != null) throw StateError(reason);
          return report;
        },
        describe: (report) =>
            '${report.vertexCount} نقطة، ${report.animationCount} أنيميشن',
      );

      // 4. Load.
      await step<Object?>(ThreeDStage.filamentLoad, () async {
        await ops.loadModel(built.path);
        return null;
      });

      // 5. Manual camera.
      await step<Object?>(ThreeDStage.manualCamera, () async {
        await ops.setManualCamera();
        return null;
      });

      // 6. Ready: let the model draw a few frames before capturing.
      await step<Object?>(ThreeDStage.ready, () async {
        if (settle > Duration.zero) await Future<void>.delayed(settle);
        await ops.waitUntilRenderable();
        return null;
      });

      // 7. Capture.
      final clip = await step<String>(
        ThreeDStage.capture,
        () async {
          final clipPath = await ops.capture(seconds);
          final file = File(clipPath);
          if (!await file.exists() || await file.length() < 2048) {
            throw FileSystemException(
              '3D world clip was not created correctly.',
              clipPath,
            );
          }
          final verify = ops.verifyClip;
          if (verify != null && !await verify(clipPath)) {
            try {
              await file.delete();
            } catch (_) {}
            throw StateError(
              'إطارات المشهد غير صالحة (شاشة خضراء أو سوداء أو فارغة).',
            );
          }
          return clipPath;
        },
        describe: (path) => path.split('/').last,
      );

      return World3DSceneResult(
        routing: routing,
        clipPath: clip,
        notes: notes,
      );
    } on _StageFailure catch (failure) {
      notes.add(
        '$label: فشلت مرحلة ${failure.stage.label} (${failure.error})؛ '
        'رُجع المشهد كاملاً إلى 2.5D.',
      );
      return World3DSceneResult(
        routing: RenderRouter.fallbackOf(
          motion,
          '${failure.stage.label}: ${failure.error}',
        ),
        failedStage: failure.stage,
        notes: notes,
      );
    } catch (error) {
      notes.add('$label: خطأ غير متوقع ($error)؛ رُجع المشهد كاملاً إلى 2.5D.');
      return World3DSceneResult(
        routing: RenderRouter.fallbackOf(motion, 'unexpected: $error'),
        notes: notes,
      );
    } finally {
      final directory = folder;
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Resolves the 3D models of the props of [motion] (the `decor:` layers
  /// that are not set pieces) and downloads them, at most two at a time.
  ///
  /// Never throws: a network error, a missing key or a rejected GLB only
  /// leaves that prop without a model, so it keeps its billboard.
  static Future<Map<String, ResolvedAsset>> _resolveProps({
    required MotionScene motion,
    required int sceneNumber,
    required ThreeDAssetResolver? resolver,
    required ThreeDExportSummary summary,
    required List<String> notes,
    required String label,
    void Function(ThreeDStage stage)? onStage,
  }) async {
    if (resolver == null) return const <String, ResolvedAsset>{};

    // The props of the scene: `decor:` layers that are not set pieces.
    final props = <String, String>{};
    for (final layer in motion.layers) {
      final key = layer.assetKey;
      if (key == null || !key.startsWith('decor:')) continue;
      if (World3DPlanner.isSetPiece(key, layer.scale)) continue;
      final text = layer.text?.trim() ?? '';
      props[key] = text.isNotEmpty
          ? text
          : key.substring('decor:'.length).replaceAll('_', ' ');
    }
    if (props.isEmpty) return const <String, ResolvedAsset>{};

    // The beat text: the words of the scene's layers (WorldScene has no
    // caption of its own). zone/shot/caption are not available here.
    final beatText = motion.layers
        .map((layer) => layer.text?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .join(' ');

    // 1. Resolve (one search for the whole beat).
    onStage?.call(ThreeDStage.search);
    summary.begin(sceneNumber, ThreeDStage.search);
    final watch = Stopwatch()..start();
    Map<String, ResolvedAsset> resolved;
    try {
      resolved = await resolver.resolveForBeat(
        beatText: beatText,
        props: props,
      );
      summary.record(
        sceneNumber,
        ThreeDStage.search,
        ok: true,
        elapsed: watch.elapsed,
        detail: '${resolved.length} أصل',
      );
    } catch (error) {
      summary.record(
        sceneNumber,
        ThreeDStage.search,
        ok: false,
        elapsed: watch.elapsed,
        detail: '$error',
      );
      notes.add('$label: تعذّر إيجاد مجسمات (${error})؛ تبقى الصور المسطحة.');
      return const <String, ResolvedAsset>{};
    }

    // 2. Download, at most two at a time.
    final entries = resolved.entries.toList();
    final updated = <String, ResolvedAsset>{};
    var index = 0;

    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= entries.length) return;
        final entry = entries[i];
        final assetKey = entry.key;
        final asset = entry.value;

        onStage?.call(ThreeDStage.download);
        summary.begin(sceneNumber, ThreeDStage.download);
        final downloadWatch = Stopwatch()..start();
        try {
          final path = await resolver.service.download(
            asset.asset,
            onInspecting: () {
              summary.begin(sceneNumber, ThreeDStage.inspect);
            },
          );
          summary.record(
            sceneNumber,
            ThreeDStage.download,
            ok: true,
            elapsed: downloadWatch.elapsed,
            detail: path.split('/').last,
          );
          updated[assetKey] = asset.copyWith(localPath: path);
        } catch (error) {
          summary.record(
            sceneNumber,
            ThreeDStage.download,
            ok: false,
            elapsed: downloadWatch.elapsed,
            detail: '$error',
          );
          notes.add(
            '$label: تعذّر تنزيل مجسم $assetKey (${error})؛ تبقى الصورة المسطحة.',
          );
        }
      }
    }

    final workers = <Future<void>>[
      for (var i = 0; i < 2 && i < entries.length; i++) worker(),
    ];
    await Future.wait(workers);

    return updated;
  }

  /// Reads the downloaded GLBs into [World3DGlbBuilder.build]'s `modelBytes`,
  /// keyed by `assetKey`. A model that fails inspection is left out (the
  /// builder then skips it and lists it in `skipped`).
  static Future<Map<String, Uint8List>> _loadModelBytes({
    required Map<String, ResolvedAsset> resolved,
    required int sceneNumber,
    required ThreeDExportSummary summary,
    required List<String> notes,
    required String label,
    void Function(ThreeDStage stage)? onStage,
  }) async {
    if (resolved.isEmpty) return const <String, Uint8List>{};

    onStage?.call(ThreeDStage.inspect);
    summary.begin(sceneNumber, ThreeDStage.inspect);
    final watch = Stopwatch()..start();
    final bytes = <String, Uint8List>{};
    try {
      for (final entry in resolved.entries) {
        final path = entry.value.localPath;
        if (path == null || path.isEmpty) continue;
        final data = await World3DGlbBuilder.readModel(path);
        if (data != null) bytes[entry.key] = data;
      }
      summary.record(
        sceneNumber,
        ThreeDStage.inspect,
        ok: true,
        elapsed: watch.elapsed,
        detail: '${bytes.length} مجسم',
      );
    } catch (error) {
      summary.record(
        sceneNumber,
        ThreeDStage.inspect,
        ok: false,
        elapsed: watch.elapsed,
        detail: '$error',
      );
      notes.add('$label: تعذّر فحص المجسمات (${error})؛ تبقى الصور المسطحة.');
    }
    return bytes;
  }
}
