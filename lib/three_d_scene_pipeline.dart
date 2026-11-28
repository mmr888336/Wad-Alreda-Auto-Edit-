import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:filament_renderer/filament_renderer.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'camera_hint_bridge.dart';
import 'cinematic_world.dart' show WorldScene;
import 'cue_windows.dart';
import 'depth_camera_model.dart' show DepthCameraMove, SceneCamera;
import 'filament_scene_exporter.dart';
import 'khronos_model_catalog.dart';
import 'motion_scene_model.dart' show MotionScene;
import 'person_anchored_compositor.dart';
import 'person_tracking_service.dart';
import 'render_router.dart' show SceneRouting;
import 'scene_frame_guard.dart';
import 'settings.dart';
import 'silence_cutter.dart' show SilenceCutter;
import 'story_understanding.dart' show StoryBeat, StorySegment;
import 'story_world_bridge.dart' show StoryWorldBridge, StoryWorldPlan;
import 'three_d_asset_resolver.dart';
import 'three_d_asset_service.dart';
import 'three_d_crash_guard.dart';
import 'three_d_progress.dart';
import 'three_d_query_planner.dart';
import 'three_d_stage_log.dart';
import 'timeline_engine.dart';
import 'visual_tracking_engine.dart';
import 'world3d_scene_runner.dart';
import 'world_flat_renderer.dart';
import 'world_look_grade.dart';
import 'world_scene_camera.dart';
import 'world_scene_compositor.dart';

class ThreeDScenePipelineResult {
  final bool applied;
  final int scenesRendered;
  final List<String> notes;

  /// Stage-by-stage log of this export (search, download, GLB inspection,
  /// Filament load, capture, compositing). Null only for results created
  /// outside the pipeline.
  final ThreeDExportSummary? summary;

  const ThreeDScenePipelineResult({
    required this.applied,
    required this.scenesRendered,
    this.notes = const <String>[],
    this.summary,
  });
}

class _ThreeDCue {
  final double start;
  final double end;
  final String query;

  const _ThreeDCue({
    required this.start,
    required this.end,
    required this.query,
  });

  double get duration => end - start;
}

/// What the world path gives back for one scene window.
class _WorldCueOutcome {
  final World3DSceneResult result;
  final WorldScene world;
  final MotionScene motion;

  const _WorldCueOutcome({
    required this.result,
    required this.world,
    required this.motion,
  });
}

/// A world scene waiting for the full-background composition.
/// [worldClipPath] is null when the scene fell back to 2.5D.
class _WorldEntry {
  final int sceneNumber;
  final _ThreeDCue cue;
  final WorldScene world;
  final MotionScene motion;
  final SceneRouting routing;
  final String? worldClipPath;

  const _WorldEntry({
    required this.sceneNumber,
    required this.cue,
    required this.world,
    required this.motion,
    required this.routing,
    required this.worldClipPath,
  });
}

/// Automatic 3D scene pipeline:
/// - Reads real caption timestamps.
/// - Creates scene windows.
/// - Plans the story world once ([StoryWorldBridge]) and, for every scene
///   window, builds its [WorldScene] and [MotionScene] and renders the 3D
///   WORLD through the render router ([renderWorldScene]): plan, GLB,
///   inspection, Filament load, manual camera, capture. A scene whose world
///   fails goes back to the 2.5D engine. A clip that is black, transparent or
///   flat is a failure too (see [SceneFrameGuard]).
/// - Only when the world path is not available for a scene (no story, the
///   switch [worldRenderingEnabled] is off) it falls back to the old path:
///   turns the spoken words into English search keywords, searches and
///   downloads GLB assets (with a built-in safety net) and loads each asset
///   into the native Filament renderer.
/// - Captures camera movement. The camera of each scene follows the story:
///   the captions are read as a story and the camera hint of the beat spoken
///   during the scene picks the camera (see [CameraHintBridge] and
///   [WorldSceneCamera]); a scene without a hint keeps the old fixed cycle.
///   The camera of a world scene is the same for the 3D world and for the
///   2.5D layers (it is carried by the [MotionScene]).
/// - Composes the world scenes as the FULL BACKGROUND of their windows (see
///   [WorldSceneCompositor]): the captured world is the picture, graded with
///   the [WorldLook] of the scene ([WorldLookGrade]), the flat 2.5D layers
///   (and the atmosphere particles of the look) are drawn on top of it, the
///   person of the video is cut out and drawn above the world, and the
///   captions and the hook title are drawn again on top of everything. A scene
///   that fell back to 2.5D is drawn whole by the 2.5D engine
///   ([WorldFlatRenderer]). If that composition fails, the world clips go back
///   to the previous "screen" composition. Switch: [worldBackgroundEnabled].
/// - Tracks the main person (Phase 1) and anchors each library 3D scene to
///   them (Phase 2); scenes that cannot be anchored keep the old panel.
/// - Composites rendered library scenes into the exported video.
///
/// Every stage of every scene is logged (see [ThreeDExportSummary]): search,
/// download, GLB inspection, Filament load, camera, readiness, capture,
/// renderer release and compositing (and, for a world scene, plan, GLB and
/// manual camera, then the 2.5D layers and the world composition). Both the
/// START and the END of each stage are written, so a crash shows exactly which
/// stage was running. A failed attempt is reported with the stage it failed
/// in, so a problem is never blamed on the wrong step. The log of the latest
/// export is kept in [lastExportSummary] and, line by line, on disk (see
/// [ThreeDCrashGuard]) so it survives a crash.
///
/// The crash note is replaced as soon as a model finishes capturing, so a
/// later crash (releasing the renderer, the next search, compositing) is never
/// blamed on a model that worked.
///
/// Live progress is reported through `onProgress` for the whole phase.
///
/// The native Filament view is only needed while scenes are rendered. As soon
/// as the last scene is captured the pipeline calls `onRenderingDone`, so the
/// screen can release the view (GPU memory and heat) before the 2.5D layers,
/// person tracking and compositing start.
class ThreeDScenePipeline {
  ThreeDScenePipeline._();

  static const int _maximumScenesPerExport = 6;
  static const int _maximumAttemptsPerScene = 4;

  /// A transient capture failure (for example PixelCopy right after a model
  /// swap) is retried on the same model instead of throwing it away.
  static const int _maximumCaptureTries = 3;

  // The 3D card is drawn at ~46% of the video's short edge, so a ~620 px
  // square at 18 fps is plenty and captures far faster than the previous
  // full-size 24 fps render.
  static const int _captureSize = 624;
  static const int _captureFrameRate = 18;

  // Share of the 3D phase bar: scenes, then the 2.5D layers of the world
  // scenes, then the world composition, then person tracking, then the
  // compositing of library scenes.
  static const double _sceneShare = 0.50;
  static const double _flatStart = 0.50;
  static const double _worldCompositeStart = 0.58;
  static const double _trackingStart = 0.66;
  static const double _compositeStart = 0.78;

  /// Phase 2 switch: follow the tracked person with the 3D scenes.
  /// Any failure falls back to the previous panel compositing.
  static bool personAnchoringEnabled = true;

  /// When no library has a model for a scene, use a neutral built-in model
  /// instead of leaving the scene without 3D.
  static bool genericFallbackEnabled = true;

  /// Master switch of the world path. When true, every scene that has a story
  /// world is rendered through [renderWorldScene] (and goes back to 2.5D if
  /// that fails) instead of searching and downloading a library model. When
  /// false the whole export behaves exactly as before.
  static bool worldRenderingEnabled = true;

  /// When true the world clips are composed as the FULL BACKGROUND of their
  /// windows with the 2.5D layers on top. When false the world clips are
  /// blended over the picture in "screen" mode, as before.
  static bool worldBackgroundEnabled = true;

  /// Stage log of the most recent [apply] call (also when it ended early).
  static ThreeDExportSummary? lastExportSummary;

  /// The old fixed camera cycle. It is still the camera of a scene when the
  /// story gives no hint for it (see [CameraHintBridge.filamentModeFor]).
  static const List<String> _cameraModes = <String>[
    'orbit',
    'push_in',
    'pull_out',
    'orbit_fast',
  ];

  static String _compactQuery(String value) {
    final normalized = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.length <= 150) return normalized;
    return normalized.substring(0, 150).trim();
  }

  static String _assetKey(ThreeDAsset asset) =>
      '${asset.provider.name}:${asset.id}';

  static double _unit(double value) =>
      value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();

  /// Where each stage starts inside one scene's share of the bar.
  static double _stageStart(ThreeDStage stage) => switch (stage) {
        ThreeDStage.worldPlan => 0.00,
        ThreeDStage.worldGlb => 0.05,
        ThreeDStage.search => 0.00,
        ThreeDStage.download => 0.10,
        ThreeDStage.inspect => 0.35,
        ThreeDStage.filamentLoad => 0.40,
        ThreeDStage.camera => 0.50,
        ThreeDStage.manualCamera => 0.50,
        ThreeDStage.ready => 0.52,
        ThreeDStage.capture => 0.60,
        ThreeDStage.rendererRelease => 1.00,
        ThreeDStage.worldFlat => 1.00,
        ThreeDStage.worldFallback => 1.00,
        ThreeDStage.worldComposite => 1.00,
        ThreeDStage.composite => 1.00,
      };

  static double _sceneFraction(int index, int count, ThreeDStage stage) {
    if (count <= 0) return 0.0;
    return (index + _stageStart(stage)) / count * _sceneShare;
  }

  /// Test hook: the scene windows [_buildCues] derives from a timeline.
  @visibleForTesting
  static List<({double start, double end, String query})> debugCues(
    TimelineProject project,
  ) {
    return _buildCues(project)
        .map((cue) => (start: cue.start, end: cue.end, query: cue.query))
        .toList();
  }

  /// Test hook: how many query words appear in a model title.
  @visibleForTesting
  static int relevanceScore(String title, String query) =>
      _relevanceScore(title, query);

  /// Test hook: the story beat that [start]..[end] overlaps the most.
  @visibleForTesting
  static StoryBeat? debugBeatFor(
    List<StoryBeat> beats,
    double start,
    double end,
  ) =>
      _beatFor(beats, start, end);

  /// The caption layers of [project] as story segments, in time order.
  static List<StorySegment> _captionSegments(TimelineProject project) {
    final captions = project
        .layersOfType(TimelineLayerType.caption)
        .where(
          (layer) =>
              layer.visible &&
              layer.text != null &&
              layer.text!.trim().isNotEmpty &&
              layer.end > layer.start,
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    return <StorySegment>[
      for (final layer in captions)
        StorySegment(
          text: layer.text!.trim(),
          start: layer.start,
          end: layer.end,
        ),
    ];
  }

  /// The story of the video, read from the caption layers of [project]: one
  /// segment per caption, in time order. Its beats carry the camera hints
  /// that pick the camera of each 3D scene. Empty when there are no captions
  /// or the story cannot be planned (every scene then keeps the fixed cycle).
  static List<StoryBeat> _storyBeats(TimelineProject project) {
    return CameraHintBridge.beatsOf(_captionSegments(project));
  }

  /// The story and the 3D world planned once for the whole video, or null
  /// when the world path is off, there are no captions or the story cannot be
  /// planned (every scene then keeps the old library path).
  static StoryWorldPlan? _worldPlan(TimelineProject project) {
    if (!worldRenderingEnabled) return null;

    final segments = _captionSegments(project);
    if (segments.isEmpty) return null;

    try {
      final plan = StoryWorldBridge.plan(segments);
      return plan.story.beats.isEmpty ? null : plan;
    } catch (_) {
      return null;
    }
  }

  /// The beat that overlaps the time range [start]..[end] the most, or null.
  static StoryBeat? _beatFor(
    List<StoryBeat> beats,
    double start,
    double end,
  ) {
    StoryBeat? best;
    var bestOverlap = 0.0;

    for (final beat in beats) {
      final overlap = math.min(end, beat.segment.end) -
          math.max(start, beat.segment.start);

      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        best = beat;
      }
    }

    return best;
  }

  /// Creates time windows using the caption layers of the existing timeline.
  ///
  /// Nearby captions are grouped together. Long groups are split into
  /// windows of at most eight seconds to match the native capture limit.
  static List<_ThreeDCue> _buildCues(TimelineProject project) {
    final captions = project
        .layersOfType(TimelineLayerType.caption)
        .where(
          (layer) =>
              layer.visible &&
              layer.text != null &&
              layer.text!.trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (captions.isEmpty) {
      return <_ThreeDCue>[];
    }

    final cues = <_ThreeDCue>[];
    final group = <TimelineLayer>[];
    var groupEnd = 0.0;

    void flushGroup() {
      if (group.isEmpty) return;

      final groupStart = group.first.start
          .clamp(0.0, project.duration)
          .toDouble();

      var lastEnd = 0.0;

      for (final layer in group) {
        if (layer.end > lastEnd) {
          lastEnd = layer.end;
        }
      }

      lastEnd = lastEnd
          .clamp(0.0, project.duration)
          .toDouble();

      var cursor = groupStart;

      while (lastEnd - cursor >= 0.5) {
        final chunkEnd =
            math.min(lastEnd, cursor + 8.0).toDouble();

        final words = group
            .where(
              (layer) =>
                  layer.start < chunkEnd && layer.end > cursor,
            )
            .map((layer) => layer.text!.trim())
            .where((text) => text.isNotEmpty)
            .join(' ');

        final query = _compactQuery(words);

        if (chunkEnd - cursor >= 0.5 && query.length >= 2) {
          cues.add(
            _ThreeDCue(
              start: cursor,
              end: chunkEnd,
              query: query,
            ),
          );
        }

        cursor = chunkEnd;
      }

      group.clear();
      groupEnd = 0.0;
    }

    for (final caption in captions) {
      final start = caption.start
          .clamp(0.0, project.duration)
          .toDouble();

      final end = caption.end
          .clamp(0.0, project.duration)
          .toDouble();

      if (end <= start) continue;

      if (group.isNotEmpty && start - groupEnd > 1.1) {
        flushGroup();
      }

      group.add(caption);

      if (end > groupEnd) {
        groupEnd = end;
      }
    }

    flushGroup();

    // A 3D scene over full-screen B-roll hides the picture and ends up as a
    // small card on top of it: keep the scenes where the speaker is on screen.
    final broll = <TimeWindow>[
      for (final layer in project.layersOfType(TimelineLayerType.broll))
        if (layer.visible && layer.end > layer.start)
          (start: layer.start, end: layer.end),
    ];
    if (broll.isNotEmpty) {
      final free = <_ThreeDCue>[];
      for (final cue in cues) {
        final part = CueWindows.longestFreePart(
          start: cue.start,
          end: cue.end,
          blocked: broll,
        );
        if (part != null) {
          free.add(
            _ThreeDCue(start: part.start, end: part.end, query: cue.query),
          );
        }
      }
      cues
        ..clear()
        ..addAll(free);
    }

    if (cues.length <= _maximumScenesPerExport) {
      return cues;
    }

    // Select windows across the whole video instead of keeping only
    // the first windows of a long project.
    final selected = <_ThreeDCue>[];

    for (var index = 0; index < _maximumScenesPerExport; index++) {
      final sourceIndex = (
        index * (cues.length - 1) /
        (_maximumScenesPerExport - 1)
      ).round();

      selected.add(cues[sourceIndex]);
    }

    return selected;
  }

  static int _relevanceScore(String title, String query) {
    final normalizedTitle = title.toLowerCase();

    final words = query
        .toLowerCase()
        .split(RegExp(r'[\s،,.;:!?؟]+'))
        .where((word) => word.length >= 2)
        .toSet();

    var score = 0;

    for (final word in words) {
      if (normalizedTitle.contains(word)) {
        score++;
      }
    }

    return score;
  }

  /// Candidate models for one scene, best first: online libraries for the
  /// first keyword that has results, then the built-in catalog. Models that
  /// crashed the app before ([blockedKeys]) are left out and counted.
  static Future<({List<ThreeDAsset> assets, int blocked})> _candidateAssets({
    required ThreeDAssetService service,
    required List<String> keywords,
    required int sceneIndex,
    required Set<String> blockedKeys,
  }) async {
    final candidates = <ThreeDAsset>[];

    for (final keyword in keywords.take(4)) {
      try {
        final found = await service.search(keyword);
        if (found.isEmpty) continue;

        final ranked = List<ThreeDAsset>.from(found)
          ..sort(
            (a, b) => _relevanceScore(b.title, keyword)
                .compareTo(_relevanceScore(a.title, keyword)),
          );

        candidates.addAll(ranked.take(3));
        break;
      } catch (_) {
        continue;
      }
    }

    candidates.addAll(
      KhronosModelCatalog.match(keywords)
          .take(2)
          .map(KhronosModelCatalog.asset),
    );

    if (candidates.isEmpty && genericFallbackEnabled) {
      candidates.add(
        KhronosModelCatalog.asset(
          KhronosModelCatalog.fallbackFor(sceneIndex),
        ),
      );
    }

    final seen = <String>{};
    final assets = <ThreeDAsset>[];
    var blocked = 0;

    for (final asset in candidates) {
      final key = _assetKey(asset);

      if (!seen.add(key)) continue;

      if (blockedKeys.contains(key)) {
        blocked++;
        continue;
      }

      assets.add(asset);
    }

    return (assets: assets, blocked: blocked);
  }

  /// Waits for the actual Android Filament SurfaceView to render the GLB.
  /// Also used by the offline self-test on the diagnostics screen.
  static Future<void> waitUntilRenderable(int viewId) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final diagnostics =
          await FilamentRenderer.getViewDiagnostics(viewId);

      final surfaceReady = diagnostics['surfaceReady'] == true;
      final modelLoaded = diagnostics['modelLoaded'] == true;

      final renderedFrames =
          (diagnostics['framesRendered'] as num?)?.toInt() ?? 0;

      if (surfaceReady && modelLoaded && renderedFrames >= 2) {
        return;
      }

      final error = diagnostics['lastError'];

      if (error != null && error.toString().trim().isNotEmpty) {
        throw StateError('Filament renderer error: $error');
      }

      await Future<void>.delayed(
        const Duration(milliseconds: 200),
      );
    }

    throw TimeoutException(
      'Filament SurfaceView did not become ready.',
      const Duration(seconds: 20),
    );
  }

  /// Captures one scene. A PixelCopy failure (the surface had no frame to
  /// copy yet, for example right after a model swap) is transient: the same
  /// model is captured again after a short wait instead of being discarded
  /// and downloading a different one.
  static Future<String> _captureWithRetry({
    required int viewId,
    required double durationSeconds,
    void Function(String message)? onStatus,
  }) async {
    var attempt = 0;

    while (true) {
      attempt++;

      try {
        return await FilamentSceneExporter.captureAndEncode(
          viewId: viewId,
          durationSeconds: durationSeconds,
          frameRate: _captureFrameRate,
          width: _captureSize,
          height: _captureSize,
          onStatus: onStatus,
        );
      } catch (error) {
        final text = '$error';

        final transient =
            text.contains('PIXEL_COPY') || text.contains('PixelCopy');

        if (!transient || attempt >= _maximumCaptureTries) {
          rethrow;
        }

        onStatus?.call(
          'تعذر التقاط الإطار؛ إعادة المحاولة ($attempt من $_maximumCaptureTries)...',
        );

        await Future<void>.delayed(
          Duration(milliseconds: 700 * attempt),
        );

        await waitUntilRenderable(viewId);
      }
    }
  }

  /// Renders the 3D WORLD of one scene through the render router.
  ///
  /// The scene passes through: plan -> GLB -> inspection -> Filament load ->
  /// manual camera -> capture (see [World3DSceneRunner]); every stage is
  /// written to [summary] and to the crash breadcrumb. Any failure returns the
  /// whole scene to the 2.5D engine (the result's routing is then a fallback),
  /// so a failed 3D render never costs a scene. Never throws.
  ///
  /// The captured clip of a rendered scene is owned by the caller (delete its
  /// folder when the clip is no longer needed).
  static Future<World3DSceneResult> renderWorldScene({
    required int viewId,
    required MotionScene motion,
    required WorldScene world,
    required int sceneNumber,
    required ThreeDExportSummary summary,
    Map<String, Uint8List> billboardImages = const <String, Uint8List>{},
    DepthCameraMove move = DepthCameraMove.none,
    double intensity = 0.8,
    ThreeDAssetResolver? resolver,
    void Function(String message)? onStatus,
    void Function(ThreeDStage stage)? onStage,
  }) {
    return World3DSceneRunner.run(
      motion: motion,
      world: world,
      sceneNumber: sceneNumber,
      summary: summary,
      billboardImages: billboardImages,
      move: move,
      intensity: intensity,
      resolver: resolver,
      onStage: (stage) {
        // Written BEFORE the stage starts, so a native crash names it. The
        // world is generated by the app (no asset key), so no model is ever
        // blocked because of it.
        ThreeDCrashGuard.markSync(
          ThreeDBreadcrumb(
            scene: sceneNumber,
            stage: stage,
            at: DateTime.now(),
            assetTitle: 'مشهد عالم 3D',
          ),
        );
        onStatus?.call('مشهد $sceneNumber — ${stage.label}...');
        onStage?.call(stage);
      },
      ops: World3DNativeOps(
        loadModel: (path) async {
          await FilamentRenderer.loadModelFromFile(
            viewId: viewId,
            filePath: path,
          );
        },
        setManualCamera: () async {
          await FilamentRenderer.setCameraMotion(
            viewId: viewId,
            mode: 'manual',
          );
        },
        waitUntilRenderable: () => waitUntilRenderable(viewId),
        capture: (seconds) => _captureWithRetry(
          viewId: viewId,
          durationSeconds: seconds,
          onStatus: onStatus,
        ),
        verifyClip: (path) =>
            SceneFrameGuard.isClean(path, File(path).parent.path),
      ),
    );
  }

  /// The world path of one scene window of [apply]: finds the story beat of
  /// the window, builds its [WorldScene] and [MotionScene] and renders it with
  /// [renderWorldScene]. Returns null when the world path is not available for
  /// this window (no story world, no beat, switch off): the caller then keeps
  /// the old library path. A non-null result is final: either the world was
  /// rendered or the scene goes back to 2.5D.
  ///
  /// The camera of the scene comes from the story (see [WorldSceneCamera]):
  /// the SAME camera is carried by the [MotionScene] (the 2.5D layers and the
  /// 2.5D fallback use it) and drives the 3D camera path. [previousCamera] is
  /// the camera of the 3D scene shown right before this one (null when it is
  /// not adjacent) and [hasNext] tells whether another one is shown right
  /// after it, so an entry into the window and its arrival stay together.
  /// [onCamera] receives the camera chosen for the scene (null for none).
  static Future<_WorldCueOutcome?> _renderWorldCue({
    required int viewId,
    required StoryWorldPlan? plan,
    required _ThreeDCue cue,
    required int sceneNumber,
    required ThreeDExportSummary summary,
    SceneCamera? previousCamera,
    bool hasNext = false,
    ThreeDAssetResolver? resolver,
    void Function(SceneCamera? camera)? onCamera,
    void Function(String message)? onStatus,
    void Function(ThreeDStage stage)? onStage,
  }) async {
    if (!worldRenderingEnabled || plan == null) return null;

    try {
      final beat = _beatFor(plan.story.beats, cue.start, cue.end);
      if (beat == null) return null;

      final worldScene = plan.worldSceneOf(beat.index);
      if (worldScene == null) return null;

      final baseMotion = StoryWorldBridge.sceneFor(
        worldScene,
        start: cue.start,
        end: cue.end,
      );

      final camera = WorldSceneCamera.plan(
        scene: baseMotion,
        beats: plan.story.beats,
        previous: previousCamera,
        hasNext: hasNext,
      );
      onCamera?.call(camera);

      final motion =
          camera == null ? baseMotion : baseMotion.withCamera(camera);

      final result = await renderWorldScene(
        viewId: viewId,
        motion: motion,
        world: worldScene,
        sceneNumber: sceneNumber,
        summary: summary,
        move: camera?.move ?? DepthCameraMove.none,
        intensity: camera?.intensity ?? 0.8,
        resolver: resolver,
        onStatus: onStatus,
        onStage: onStage,
      );

      return _WorldCueOutcome(
        result: result,
        world: worldScene,
        motion: motion,
      );
    } catch (_) {
      return null;
    }
  }

  /// Draws the 2.5D part of every world scene and returns the clips for the
  /// full-background composition:
  /// - a scene rendered in 3D: its world clip, plus (when there are flat
  ///   layers or look particles) a 2.5D clip of those layers to go on top;
  /// - a scene that fell back: a 2.5D clip of the whole scene.
  /// Every clip carries the [WorldLook] of its scene (when [WorldLookGrade] is
  /// enabled), so the compositor grades it and the atmosphere particles are
  /// drawn. A failure here never stops the export: the world clip is used
  /// without the flat layers, and a fallback scene stays as it is in the video.
  static Future<List<WorldBackgroundClip>> _prepareWorldClips({
    required List<_WorldEntry> entries,
    required String videoPath,
    required AppSettings settings,
    required ThreeDExportSummary summary,
    required List<String> notes,
    required Set<String> temporaryDirectories,
    void Function(double fraction, String message, ThreeDStage stage)?
        onPhase,
  }) async {
    final clips = <WorldBackgroundClip>[];

    // Canvas of the 2.5D clips: the video's aspect, short side at most 720.
    var width = 0;
    var height = 0;

    if (WorldFlatRenderer.enabled) {
      try {
        final info = await SilenceCutter.probe(videoPath);
        final shortSide = math.min(info.w, info.h);
        final factor = shortSide > WorldFlatRenderer.maxShortSide
            ? WorldFlatRenderer.maxShortSide / shortSide
            : 1.0;
        width = WorldFlatRenderer.evenSize(info.w * factor);
        height = WorldFlatRenderer.evenSize(info.h * factor);
      } catch (_) {
        width = 0;
        height = 0;
      }
    }

    Directory? work;

    if (width > 0 && height > 0) {
      try {
        final created = await Directory.systemTemp.createTemp('world_flat_');
        temporaryDirectories.add(created.path);
        work = created;
      } catch (_) {
        work = null;
      }
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final font =
        settings.captionFont == 'auto' ? 'Cairo' : settings.captionFont;
    final temps = <String>[];
    final gradeLook = WorldLookGrade.enabled;

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final worldClip = entry.worldClipPath;
      final stage = worldClip == null
          ? ThreeDStage.worldFallback
          : ThreeDStage.worldFlat;
      final label = 'مشهد ${entry.sceneNumber}';

      onPhase?.call(
        _flatStart +
            (_worldCompositeStart - _flatStart) * (index / entries.length),
        '$label — ${stage.label}...',
        stage,
      );

      ThreeDCrashGuard.markSync(
        ThreeDBreadcrumb(
          scene: entry.sceneNumber,
          stage: stage,
          at: DateTime.now(),
          assetTitle: 'مشهد عالم 3D',
        ),
      );
      summary.begin(entry.sceneNumber, stage);
      final watch = Stopwatch()..start();

      var outcome = const WorldFlatOutcome();
      final directory = work;

      if (directory != null) {
        outcome = await WorldFlatRenderer.renderScene(
          world: entry.world,
          motion: entry.motion,
          routing: entry.routing,
          wholeScene: worldClip == null,
          width: width,
          height: height,
          idPrefix: 'w${entry.sceneNumber}',
          dir: directory.path,
          stamp: stamp,
          index: index,
          fontFamily: font,
          temps: temps,
          withLook: gradeLook,
        );
      }

      if (worldClip != null) {
        // The world is drawn by Filament; the flat layers go on top of it.
        final overlay = outcome.path;

        if (outcome.error != null) {
          summary.record(
            entry.sceneNumber,
            stage,
            ok: false,
            elapsed: watch.elapsed,
            detail: outcome.error,
          );
          notes.add(
            '$label: تعذر رسم طبقات 2.5D فوق العالم (${outcome.error})؛ '
            'عُرض العالم بدونها.',
          );
        } else {
          summary.record(
            entry.sceneNumber,
            stage,
            ok: true,
            elapsed: watch.elapsed,
            detail: overlay == null
                ? (directory == null
                    ? 'تخطي (محرك 2.5D غير متاح)'
                    : 'لا توجد طبقات 2.5D فوق العالم')
                : '${outcome.layerCount} طبقة 2.5D فوق العالم',
          );
        }

        clips.add(
          WorldBackgroundClip(
            path: worldClip,
            start: entry.cue.start,
            end: entry.cue.end,
            overlayPath: overlay,
            look: gradeLook ? entry.world.look : null,
          ),
        );
      } else {
        // The scene fell back from 3D: the 2.5D engine draws all of it.
        final path = outcome.path;

        if (path == null) {
          summary.record(
            entry.sceneNumber,
            stage,
            ok: false,
            elapsed: watch.elapsed,
            detail: outcome.error ??
                (directory == null
                    ? 'محرك 2.5D غير متاح'
                    : 'لا توجد طبقات للرسم'),
          );
          notes.add(
            '$label: تعذر رسم المشهد بمحرك 2.5D؛ بقي كما هو في الفيديو.',
          );
        } else {
          summary.record(
            entry.sceneNumber,
            stage,
            ok: true,
            elapsed: watch.elapsed,
            detail: '${outcome.layerCount} طبقة',
          );
          notes.add('$label: رُسم بمحرك 2.5D بعد الرجوع من 3D.');
          clips.add(
            WorldBackgroundClip(
              path: path,
              start: entry.cue.start,
              end: entry.cue.end,
              look: gradeLook ? entry.world.look : null,
            ),
          );
        }
      }
    }

    return clips;
  }

  /// Phase 1 + 2: tracks the main person and composites the scenes around
  /// them. Returns null (and removes any partial file) when nothing could be
  /// anchored, so the caller uses the previous panel compositing.
  /// [videoPath] is the base the scenes are drawn on; the person is tracked
  /// in [trackingVideoPath] (the original video) when it is given.
  static Future<String?> _compositeAnchored({
    required String videoPath,
    String? trackingVideoPath,
    required List<ThreeDSceneClip> scenes,
    required TimelineProject timeline,
    required AppSettings settings,
    required List<String> notes,
    void Function(String message)? onStatus,
    void Function(double fraction, String message)? onPhase,
  }) async {
    onStatus?.call('جاري تتبع الشخص لربط المجسمات به...');
    onPhase?.call(_trackingStart, 'جاري تتبع الشخص لربط المجسمات به...');

    final run = await PersonTrackingService.analyzeVideo(
      trackingVideoPath ?? videoPath,
      config: TrackingConfig(
        sampleFps: 6,
        frameWidth: 480,
        maxSeconds: timeline.duration.clamp(1.0, 120.0).toDouble(),
        maxFrames: 720,
      ),
      onStatus: onStatus,
      onProgress: (value) => onPhase?.call(
        _trackingStart +
            (_compositeStart - _trackingStart) * _unit(value),
        'جاري تتبع الشخص لربط المجسمات به...',
      ),
    );

    final track = run.result.primaryTrack;

    if (track == null) {
      notes.add(
        'لم يتم اكتشاف شخص في الفيديو؛ استُخدم التركيب العادي للمجسمات.',
      );
      return null;
    }

    final result = await PersonAnchoredCompositor.composite(
      videoPath: videoPath,
      scenes: scenes,
      duration: timeline.duration,
      track: track,
      maximumQuality: settings.maximumQuality,
      onStatus: onStatus,
      onProgress: (value) => onPhase?.call(
        _compositeStart + (1.0 - _compositeStart) * _unit(value),
        'جاري دمج مشاهد 3D مع الفيديو...',
      ),
    );

    if (result.anchoredScenes == 0 || result.path.isEmpty) {
      notes.add(
        'الشخص غير ظاهر بما يكفي في نوافذ المشاهد؛ استُخدم التركيب العادي.',
      );
      notes.addAll(result.notes);
      return null;
    }

    notes.add(
      'تم ربط ${result.anchoredScenes} مشهد 3D بحركة الشخص'
      '${result.pipScenes > 0 ? ' (و${result.pipScenes} بالتركيب العادي)' : ''}.',
    );
    notes.addAll(result.notes);

    return result.path;
  }

  static Future<ThreeDScenePipelineResult> apply({
    required int viewId,
    required String videoPath,
    required TimelineProject timeline,
    required AppSettings settings,
    void Function(String message)? onStatus,
    void Function(ThreeDProgress progress)? onProgress,

    /// Called once every scene is rendered and the native Filament view is no
    /// longer needed (before the 2.5D layers, person tracking and compositing).
    Future<void> Function()? onRenderingDone,
  }) async {
    final notes = <String>[];
    final sceneClips = <ThreeDSceneClip>[];
    final worldEntries = <_WorldEntry>[];
    final temporaryDirectories = <String>{};

    // Starts a fresh on-disk log; every stage is appended as it happens, so
    // the log is complete up to the moment of a crash.
    await ThreeDCrashGuard.begin();

    // Every stage of this export is recorded here and printed as it happens:
    // one line when a stage starts and one when it ends.
    final summary = ThreeDExportSummary(
      onEvent: (event) {
        final line = event.toLine();
        debugPrint('[3D] $line');
        ThreeDCrashGuard.appendLogSync(line);
      },
      onStart: (scene, stage, detail) {
        final line = ThreeDStageEvent.startLine(scene, stage, detail: detail);
        debugPrint('[3D] $line');
        ThreeDCrashGuard.appendLogSync(line);
      },
    );
    lastExportSummary = summary;

    String? compositePath;
    String? worldCompositePath;
    Stopwatch? compositeWatch;

    // The world is generated by the app, so it does not need the online
    // libraries: the export stops here only when BOTH paths are off.
    if (!settings.online3DAssetsEnabled && !worldRenderingEnabled) {
      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: const <String>[
          'مصادر المجسمات ثلاثية الأبعاد معطلة من الإعدادات.',
        ],
        summary: summary,
      );
    }

    final sourceFile = File(videoPath);

    if (!await sourceFile.exists()) {
      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: const <String>[
          'ملف الفيديو المطلوب لإضافة 3D غير موجود.',
        ],
        summary: summary,
      );
    }

    final cues = _buildCues(timeline);

    if (cues.isEmpty) {
      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: const <String>[
          'لم تتوفر توقيتات كابشن كافية لتحديد مواضع مشاهد 3D.',
        ],
        summary: summary,
      );
    }

    // The story of the video: its camera hints pick the camera of each scene.
    final storyBeats = _storyBeats(timeline);

    // The story world, planned once: the same character and one fixed layout
    // per environment in every scene of the video.
    final worldPlan = _worldPlan(timeline);

    // Reports live progress for the whole 3D phase (0..1).
    void report(
      double fraction,
      String message, {
      ThreeDStage? stage,
      int scene = 0,
    }) {
      final callback = onProgress;
      if (callback == null) return;

      callback(
        ThreeDProgress(
          fraction: _unit(fraction),
          message: message,
          stage: stage,
          scene: scene,
          sceneCount: cues.length,
        ),
      );
    }

    final blockedKeys = await ThreeDCrashGuard.blacklistedKeys();
    final service = ThreeDAssetService(settings: settings);

    // One resolver per export (not per scene), reusing the service above.
    // Any failure leaves it null: the world path then keeps its current
    // behaviour (props without a 3D model keep their billboard).
    ThreeDAssetResolver? resolver;
    try {
      resolver = ThreeDAssetResolver(service: service, settings: settings);
    } catch (_) {
      resolver = null;
    }

    try {
      // The camera the world path gave to the scene before the current one
      // (null when that scene had none or was not a world scene).
      SceneCamera? lastWorldCamera;

      for (var index = 0; index < cues.length; index++) {
        final cue = cues[index];
        final sceneNumber = index + 1;

        // The camera of this scene: the hint of the story beat spoken during
        // it (enter the window = push in, arrive from it = pull out, orbit...).
        // Without a hint the old fixed cycle decides.
        final cameraMode = CameraHintBridge.filamentModeFor(
          storyBeats,
          cue.start,
          cue.end,
          fallback: _cameraModes[index % _cameraModes.length],
        );

        onStatus?.call(
          'جاري تجهيز مشهد 3D $sceneNumber من ${cues.length} '
          '(${cue.start.toStringAsFixed(1)}s – '
          '${cue.end.toStringAsFixed(1)}s)...',
        );

        // The camera story only links 3D scenes that are shown one right after
        // the other (an entry into the window and its arrival).
        final previousCamera = index > 0 &&
                WorldSceneCamera.areAdjacent(cues[index - 1].end, cue.start)
            ? lastWorldCamera
            : null;
        final hasNextScene = index < cues.length - 1 &&
            WorldSceneCamera.areAdjacent(cue.end, cues[index + 1].start);
        SceneCamera? cueCamera;

        // World path: the scene is built from the story world (WorldScene +
        // MotionScene) and rendered through the render router. A non-null
        // result is final for this scene: rendered, or back to 2.5D.
        final worldOutcome = await _renderWorldCue(
          viewId: viewId,
          plan: worldPlan,
          cue: cue,
          sceneNumber: sceneNumber,
          summary: summary,
          previousCamera: previousCamera,
          hasNext: hasNextScene,
          resolver: resolver,
          onCamera: (camera) => cueCamera = camera,
          onStatus: onStatus,
          onStage: (stage) => report(
            _sceneFraction(index, cues.length, stage),
            'مشهد $sceneNumber من ${cues.length} — ${stage.label}',
            stage: stage,
            scene: sceneNumber,
          ),
        );

        lastWorldCamera = worldOutcome == null ? null : cueCamera;

        if (worldOutcome != null) {
          final worldResult = worldOutcome.result;
          notes.addAll(worldResult.notes);

          final clip = worldResult.clipPath;

          if (worldResult.rendered && clip != null) {
            // The world finished everything it was asked to do: replace its
            // crash note, so whatever happens next is never blamed on it.
            final lastWorldScene = index == cues.length - 1;

            ThreeDCrashGuard.markSync(
              ThreeDBreadcrumb(
                scene: lastWorldScene ? 0 : sceneNumber + 1,
                stage: lastWorldScene
                    ? ThreeDStage.rendererRelease
                    : ThreeDStage.search,
                at: DateTime.now(),
              ),
            );

            temporaryDirectories.add(File(clip).parent.path);

            if (worldBackgroundEnabled) {
              // Composed later as the full background of the window.
              worldEntries.add(
                _WorldEntry(
                  sceneNumber: sceneNumber,
                  cue: cue,
                  world: worldOutcome.world,
                  motion: worldOutcome.motion,
                  routing: worldResult.routing,
                  worldClipPath: clip,
                ),
              );
            } else {
              sceneClips.add(
                ThreeDSceneClip(
                  path: clip,
                  start: cue.start,
                  end: cue.end,
                ),
              );
            }

            notes.add(
              'مشهد $sceneNumber: عالم 3D من القصة '
              '(${worldResult.routing.world.length} طبقة 3D، '
              '${worldResult.routing.flat.length} طبقة 2.5D).',
            );
          } else if (worldBackgroundEnabled && worldResult.fellBack) {
            // A scene that fell back is drawn whole by the 2.5D engine.
            worldEntries.add(
              _WorldEntry(
                sceneNumber: sceneNumber,
                cue: cue,
                world: worldOutcome.world,
                motion: worldOutcome.motion,
                routing: worldResult.routing,
                worldClipPath: null,
              ),
            );
          }

          // The failure of a fallback scene is already in the log and the notes.
          continue;
        }

        // The old library path needs the online sources.
        if (!settings.online3DAssetsEnabled) {
          notes.add(
            'مشهد $sceneNumber: لا يوجد عالم 3D لهذا المشهد، ومصادر المجسمات '
            'معطلة من الإعدادات.',
          );
          continue;
        }

        report(
          _sceneFraction(index, cues.length, ThreeDStage.search),
          'مشهد $sceneNumber من ${cues.length} — البحث عن مجسم مناسب...',
          stage: ThreeDStage.search,
          scene: sceneNumber,
        );

        // From here on a crash belongs to THIS scene's search, never to the
        // model of the previous scene (its note is replaced right now).
        ThreeDCrashGuard.markSync(
          ThreeDBreadcrumb(
            scene: sceneNumber,
            stage: ThreeDStage.search,
            at: DateTime.now(),
          ),
        );
        summary.begin(sceneNumber, ThreeDStage.search);

        final searchWatch = Stopwatch()..start();
        var searchDone = false;

        try {
          final keywords = await ThreeDQueryPlanner.keywords(
            settings,
            cue.query,
          );

          final found = await _candidateAssets(
            service: service,
            keywords: keywords,
            sceneIndex: index,
            blockedKeys: blockedKeys,
          );

          final candidates = found.assets;
          final blockedNote = found.blocked > 0
              ? ' — ${found.blocked} محظور بعد انهيار سابق'
              : '';

          searchDone = true;

          summary.record(
            sceneNumber,
            ThreeDStage.search,
            ok: candidates.isNotEmpty,
            elapsed: searchWatch.elapsed,
            detail: candidates.isEmpty
                ? 'لا توجد مرشحات (${keywords.take(3).join('، ')})$blockedNote'
                : '${candidates.length} مرشح '
                    '(${keywords.take(3).join('، ')})$blockedNote',
          );

          if (candidates.isEmpty) {
            notes.add(
              'لم يتم العثور على مجسم GLB مناسب للمشهد $sceneNumber '
              '(${keywords.take(3).join('، ')})$blockedNote.',
            );

            if (service.warnings.isNotEmpty) {
              notes.addAll(service.warnings.take(3));
            }

            continue;
          }

          String? scenePath;
          ThreeDAsset? usedAsset;
          final attemptFailures = <String>[];

          for (final asset in candidates.take(_maximumAttemptsPerScene)) {
            // Tracks where the attempt is, so a failure is reported in the
            // stage that really failed.
            var stage = ThreeDStage.download;
            final stopwatch = Stopwatch()..start();
            final assetKey = _assetKey(asset);

            // Writes the breadcrumb BEFORE the stage starts (a native crash
            // cannot be caught, so the note says where it happened), logs the
            // start of the stage and updates the live progress.
            void announce(ThreeDStage at) {
              ThreeDCrashGuard.markSync(
                ThreeDBreadcrumb(
                  scene: sceneNumber,
                  stage: at,
                  at: DateTime.now(),
                  assetKey: assetKey,
                  assetTitle: asset.title,
                ),
              );

              summary.begin(sceneNumber, at, detail: asset.title);

              report(
                _sceneFraction(index, cues.length, at),
                'مشهد $sceneNumber من ${cues.length} — ${at.label}: ${asset.title}',
                stage: at,
                scene: sceneNumber,
              );
            }

            // Records the finished stage and moves on to the next one.
            void finish(ThreeDStage done, {ThreeDStage? next}) {
              summary.record(
                sceneNumber,
                done,
                ok: true,
                elapsed: stopwatch.elapsed,
                detail: asset.title,
              );

              if (next != null) {
                stage = next;
                announce(next);
              }

              stopwatch
                ..reset()
                ..start();
            }

            try {
              announce(ThreeDStage.download);

              onStatus?.call(
                'جاري تنزيل المجسم: ${asset.title}...',
              );

              // Download + full GLB inspection: a bad file is rejected here.
              // The service tells us when the download ends and the
              // inspection begins, so they are logged as two stages.
              final modelPath = await service.download(
                asset,
                onInspecting: () => finish(
                  ThreeDStage.download,
                  next: ThreeDStage.inspect,
                ),
              );

              finish(ThreeDStage.inspect, next: ThreeDStage.filamentLoad);

              onStatus?.call(
                'جاري تحميل المجسم داخل محرك Filament...',
              );

              await FilamentRenderer.loadModelFromFile(
                viewId: viewId,
                filePath: modelPath,
              );

              finish(ThreeDStage.filamentLoad, next: ThreeDStage.camera);

              await FilamentRenderer.setCameraMotion(
                viewId: viewId,
                mode: cameraMode,
              );

              finish(ThreeDStage.camera, next: ThreeDStage.ready);

              // Let the new model render a few frames before capturing.
              await Future<void>.delayed(
                const Duration(milliseconds: 350),
              );

              await waitUntilRenderable(viewId);

              finish(ThreeDStage.ready, next: ThreeDStage.capture);

              onStatus?.call(
                'جاري تصوير حركة الكاميرا للمشهد $sceneNumber...',
              );

              final capturedPath = await _captureWithRetry(
                viewId: viewId,
                durationSeconds: cue.duration,
                onStatus: onStatus,
              );

              final sceneFile = File(capturedPath);

              if (!await sceneFile.exists() ||
                  await sceneFile.length() < 2048) {
                throw FileSystemException(
                  '3D scene video was not created correctly.',
                  capturedPath,
                );
              }

              finish(ThreeDStage.capture);

              // The model finished everything it was asked to do. Replace its
              // crash note right away, so whatever happens next (the next
              // search, releasing the renderer) is never blamed on it.
              final lastScene = index == cues.length - 1;

              ThreeDCrashGuard.markSync(
                ThreeDBreadcrumb(
                  scene: lastScene ? 0 : sceneNumber + 1,
                  stage: lastScene
                      ? ThreeDStage.rendererRelease
                      : ThreeDStage.search,
                  at: DateTime.now(),
                ),
              );

              temporaryDirectories.add(sceneFile.parent.path);
              scenePath = capturedPath;
              usedAsset = asset;
              break;
            } catch (error) {
              summary.record(
                sceneNumber,
                stage,
                ok: false,
                elapsed: stopwatch.elapsed,
                detail: '${asset.title}: $error',
              );

              attemptFailures.add(
                '${asset.title} [مرحلة: ${stage.label}]: $error',
              );
            }
          }

          if (scenePath == null || usedAsset == null) {
            notes.add(
              'تعذر تجهيز مجسم للمشهد $sceneNumber: '
              '${attemptFailures.isEmpty ? 'غير معروف' : attemptFailures.join(' | ')}',
            );
            continue;
          }

          if (attemptFailures.isNotEmpty) {
            notes.add(
              'مشهد $sceneNumber: فشلت ${attemptFailures.length} '
              'محاولة قبل النجاح (${attemptFailures.join(' | ')}).',
            );
          }

          notes.add(
            'مشهد $sceneNumber: ${keywords.take(3).join('، ')} ← ${usedAsset.title}',
          );

          // A capture that never finished decodes as a bright green band, and a
          // model that got no light is captured black or empty; such a scene is
          // dropped instead of being shown over the speaker.
          final frameVerdict = await SceneFrameGuard.inspect(
            scenePath,
            File(scenePath).parent.path,
          );
          if (frameVerdict != SceneFrameVerdict.clean) {
            final reason = frameVerdict == SceneFrameVerdict.blank
                ? 'إطارات المجسم سوداء أو فارغة'
                : 'إطارات المجسم تالفة (شاشة خضراء)';
            notes.add('مشهد $sceneNumber: $reason؛ تم تخطيه بدل عرضه.');
            try {
              File(scenePath).deleteSync();
            } catch (_) {}
            continue;
          }

          sceneClips.add(
            ThreeDSceneClip(
              path: scenePath,
              start: cue.start,
              end: cue.end,
            ),
          );
        } catch (error) {
          if (!searchDone) {
            summary.record(
              sceneNumber,
              ThreeDStage.search,
              ok: false,
              elapsed: searchWatch.elapsed,
              detail: '$error',
            );
          }

          notes.add(
            'تعذر تجهيز مشهد 3D $sceneNumber: $error',
          );
        }
      }

      final worldRendered =
          worldEntries.where((entry) => entry.worldClipPath != null).length;
      final worldFellBack = worldEntries.length - worldRendered;

      notes.add(
        'ملخص 3D: تم تجهيز ${sceneClips.length + worldRendered} من ${cues.length} مشهد'
        '${worldFellBack > 0 ? '، و$worldFellBack مشهد يُرسم بـ 2.5D' : ''}.',
      );

      if (sceneClips.isEmpty && worldEntries.isEmpty) {
        notes.add(
          'لم يتم إنشاء أي مشهد 3D؛ تم الاحتفاظ بالفيديو الأصلي دون تغييره.',
        );
        notes.add(summary.headline);

        return ThreeDScenePipelineResult(
          applied: false,
          scenesRendered: 0,
          notes: notes,
          summary: summary,
        );
      }

      // Every scene is rendered: the native Filament view is not needed any
      // more. Let the screen release it now, so its GPU memory is free (and
      // the phone cools down) before tracking and compositing start. This is
      // its own stage: a native crash while releasing the view must be
      // reported as such and never blamed on the last model.
      final releaseWatch = Stopwatch()..start();

      ThreeDCrashGuard.markSync(
        ThreeDBreadcrumb(
          scene: 0,
          stage: ThreeDStage.rendererRelease,
          at: DateTime.now(),
        ),
      );
      summary.begin(0, ThreeDStage.rendererRelease);

      report(
        _sceneShare,
        'اكتمل تجهيز المشاهد؛ جاري تحرير محرك العرض...',
        stage: ThreeDStage.rendererRelease,
      );

      try {
        await onRenderingDone?.call();

        summary.record(
          0,
          ThreeDStage.rendererRelease,
          ok: true,
          elapsed: releaseWatch.elapsed,
        );
      } catch (error) {
        // Releasing the view must never stop the export.
        summary.record(
          0,
          ThreeDStage.rendererRelease,
          ok: false,
          elapsed: releaseWatch.elapsed,
          detail: '$error',
        );
      }

      // World scenes: the 2.5D layers go on top of the world, and a scene that
      // fell back is drawn whole by the 2.5D engine. Then the world is composed
      // as the FULL BACKGROUND of its window. If that fails, the world clips go
      // back to the previous "screen" composition below.
      var worldComposed = 0;
      String? worldPath;

      if (worldEntries.isNotEmpty) {
        final worldClips = await _prepareWorldClips(
          entries: worldEntries,
          videoPath: videoPath,
          settings: settings,
          summary: summary,
          notes: notes,
          temporaryDirectories: temporaryDirectories,
          onPhase: (fraction, message, stage) =>
              report(fraction, message, stage: stage),
        );

        if (worldClips.isNotEmpty) {
          ThreeDCrashGuard.markSync(
            ThreeDBreadcrumb(
              scene: 0,
              stage: ThreeDStage.worldComposite,
              at: DateTime.now(),
            ),
          );
          summary.begin(
            0,
            ThreeDStage.worldComposite,
            detail: '${worldClips.length} مشهد',
          );

          final worldWatch = Stopwatch()..start();

          onStatus?.call(
            'جاري تركيب ${worldClips.length} مشاهد عالم كخلفية كاملة...',
          );
          report(
            _worldCompositeStart,
            'جاري تركيب العالم كخلفية كاملة...',
            stage: ThreeDStage.worldComposite,
          );

          try {
            final composed = await WorldSceneCompositor.composite(
              videoPath: videoPath,
              clips: worldClips,
              duration: timeline.duration,
              maximumQuality: settings.maximumQuality,
              // The captions and the hook title are drawn again on top of the
              // world, and the person is cut out of the video above it.
              textOverlays: WorldTextOverlay.fromTimeline(timeline),
              onStatus: onStatus,
              onProgress: (value) => report(
                _worldCompositeStart +
                    (_trackingStart - _worldCompositeStart) * _unit(value),
                'جاري تركيب العالم كخلفية كاملة...',
                stage: ThreeDStage.worldComposite,
              ),
            );

            worldPath = composed;
            worldCompositePath = composed;
            worldComposed = worldClips.length;

            summary.record(
              0,
              ThreeDStage.worldComposite,
              ok: true,
              elapsed: worldWatch.elapsed,
              detail: '$worldComposed مشهد كخلفية كاملة',
            );
            notes.add(
              'التركيب: $worldComposed مشهد عالم كخلفية كاملة '
              '(الشخص والكابشن وطبقات 2.5D فوقها).',
            );
          } catch (error) {
            worldPath = null;

            summary.record(
              0,
              ThreeDStage.worldComposite,
              ok: false,
              elapsed: worldWatch.elapsed,
              detail: '$error',
            );
            notes.add(
              'تعذر تركيب العالم كخلفية كاملة؛ استُخدم التركيب القديم (screen): $error',
            );

            for (final entry in worldEntries) {
              final path = entry.worldClipPath;
              if (path == null) continue;

              sceneClips.add(
                ThreeDSceneClip(
                  path: path,
                  start: entry.cue.start,
                  end: entry.cue.end,
                ),
              );
            }
          }
        }
      }

      final String resultPath;
      Stopwatch? libraryWatch;
      var libraryDetail = '';

      if (sceneClips.isEmpty) {
        final composedWorld = worldPath;

        if (composedWorld == null) {
          notes.add(
            'لم يتم تركيب أي مشهد؛ تم الاحتفاظ بالفيديو الأصلي دون تغييره.',
          );
          notes.add(summary.headline);

          return ThreeDScenePipelineResult(
            applied: false,
            scenesRendered: 0,
            notes: notes,
            summary: summary,
          );
        }

        resultPath = composedWorld;
      } else {
        // Library scenes (and world clips when the full-background composition
        // is off or failed): drawn on the composed video, the person is
        // tracked in the original one.
        final baseVideoPath = worldPath ?? videoPath;

        onStatus?.call(
          'جاري تركيب ${sceneClips.length} مشاهد 3D في الفيديو...',
        );

        report(
          _trackingStart,
          'اكتمل تجهيز المشاهد؛ جاري التركيب مع الفيديو...',
          stage: ThreeDStage.composite,
        );

        // From here on a crash belongs to tracking / compositing, not a model.
        ThreeDCrashGuard.markSync(
          ThreeDBreadcrumb(
            scene: 0,
            stage: ThreeDStage.composite,
            at: DateTime.now(),
          ),
        );
        summary.begin(0, ThreeDStage.composite);

        final watch = Stopwatch()..start();
        compositeWatch = watch;
        libraryWatch = watch;

        String? anchoredPath;

        if (personAnchoringEnabled && PersonTrackingService.hasDetector) {
          if (await ThreeDCrashGuard.isAnchoringDisabled()) {
            notes.add(
              'ربط المجسمات بالشخص معطّل بعد انهيار سابق؛ استُخدم التركيب العادي '
              '(يمكن إعادة تفعيله من تقرير 3D).',
            );
          } else {
            try {
              anchoredPath = await _compositeAnchored(
                videoPath: baseVideoPath,
                trackingVideoPath: videoPath,
                scenes: sceneClips,
                timeline: timeline,
                settings: settings,
                notes: notes,
                onStatus: onStatus,
                onPhase: (fraction, message) => report(
                  fraction,
                  message,
                  stage: ThreeDStage.composite,
                ),
              );
            } catch (error) {
              anchoredPath = null;
              notes.add(
                'تعذر ربط المجسمات بالشخص؛ تم استخدام التركيب العادي: $error',
              );
            }
          }
        }

        if (anchoredPath == null) {
          notes.add('التركيب: عادي (بدون ربط بحركة الشخص).');
        }

        resultPath = anchoredPath ??
            await FilamentSceneExporter.compositeScenesOverVideo(
              videoPath: baseVideoPath,
              scenes: sceneClips,
              duration: timeline.duration,
              maximumQuality: settings.maximumQuality,
              onStatus: onStatus,
              onProgress: (value) => report(
                _compositeStart + (1.0 - _compositeStart) * _unit(value),
                'جاري دمج مشاهد 3D مع الفيديو...',
                stage: ThreeDStage.composite,
              ),
            );

        libraryDetail = anchoredPath != null
            ? '${sceneClips.length} مشهد؛ مربوط بحركة الشخص'
            : '${sceneClips.length} مشهد؛ تركيب عادي';
      }

      compositePath = resultPath;

      final compositeFile = File(resultPath);

      if (!await compositeFile.exists() ||
          await compositeFile.length() < 4096) {
        throw FileSystemException(
          'ملف الفيديو بعد دمج مشاهد 3D غير صالح.',
          resultPath,
        );
      }

      // Keep the original export path to preserve saved-project references.
      final backupPath =
          '$videoPath.before_3d_${DateTime.now().millisecondsSinceEpoch}';

      final backupFile = File(backupPath);

      await sourceFile.rename(backupPath);

      try {
        await compositeFile.rename(videoPath);

        if (await backupFile.exists()) {
          await backupFile.delete();
        }
      } catch (_) {
        if (!await sourceFile.exists() &&
            await backupFile.exists()) {
          await backupFile.rename(videoPath);
        }

        rethrow;
      }

      final finishedLibraryWatch = libraryWatch;

      if (finishedLibraryWatch != null) {
        summary.record(
          0,
          ThreeDStage.composite,
          ok: true,
          elapsed: finishedLibraryWatch.elapsed,
          detail: libraryDetail,
        );
      }

      notes.add(summary.headline);

      report(
        1.0,
        'اكتمل دمج مشاهد 3D مع الفيديو النهائي.',
        stage: ThreeDStage.composite,
      );

      onStatus?.call(
        'اكتمل دمج مشاهد 3D مع الفيديو النهائي.',
      );

      return ThreeDScenePipelineResult(
        applied: true,
        scenesRendered: sceneClips.length + worldComposed,
        notes: notes,
        summary: summary,
      );
    } catch (error) {
      final failedWatch = compositeWatch;

      // Only an error after compositing started belongs to that stage; the
      // earlier stages are already logged one by one.
      if (failedWatch != null) {
        summary.record(
          0,
          ThreeDStage.composite,
          ok: false,
          elapsed: failedWatch.elapsed,
          detail: '$error',
        );
      }

      notes.add('تعذر إكمال مرحلة دمج 3D: $error');
      notes.add(summary.headline);

      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: sceneClips.length,
        notes: notes,
        summary: summary,
      );
    } finally {
      // The 3D phase ended normally (success or handled failure): there was
      // no crash, so the breadcrumb is removed and the log gets its headline.
      ThreeDCrashGuard.appendLogSync(summary.headline);
      ThreeDCrashGuard.clearBreadcrumbSync();

      service.dispose();

      for (final directoryPath in temporaryDirectories) {
        try {
          final directory = Directory(directoryPath);

          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        } catch (_) {}
      }

      // Partial or intermediate files (a renamed result no longer exists).
      for (final leftover in <String?>[compositePath, worldCompositePath]) {
        if (leftover == null) continue;

        try {
          final file = File(leftover);

          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }
}
