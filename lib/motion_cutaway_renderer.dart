/// Renders a motion cutaway (see [ReferenceSceneBuilder]) to an MP4 with the
/// Motion FFmpeg adapter. The clip is then placed on the timeline like a
/// B-roll clip, so it is exported, saved and editable with the existing
/// timeline tools. Any failure returns null and the export simply continues
/// without the cutaway.
///
/// Next to every clip a `<clip>.motion.json` file is written with the scene
/// layers, so the layers can be edited later (see MotionSceneEditorPage) and
/// the clip re-rendered through [renderBuilt].
///
/// Besides pixel sprites, words and backgrounds the renderer draws semantic
/// library visuals, the full-canvas set pieces of the story world (see
/// [WorldSetPieces]) and transparent VFX overlays (procedural PNGs), and
/// applies the cinematic look stored in the project's `look` asset as a
/// post-grade. The overlays move (see [MotionVfxAnimator]: smoke rises,
/// embers climb, rays sweep...), light-type overlays are screen-blended, and
/// the look includes real Bloom and Halation (see [CinematicVfx.buildGraph]).
/// Every step has a fallback: if the full look fails the single-stream grade
/// is tried, then no grade at all; if the screen blend fails the overlays
/// are composited normally; if the camera render fails the clip is rendered
/// flat. A filter missing from the bundled FFmpegKit never costs the cutaway.
///
/// The cutaway is built by the continuous scene generator (several beats,
/// each with its own composition, see [ContinuousSceneGenerator]); if that
/// fails the plain scene builder is used. Inside one export the first scene
/// of every cutaway also differs from the last scene of the cutaway before it
/// (see [SceneLayoutMemory]), so the composition keeps changing across the
/// whole video. Every scene also gets a depth camera, planned by the
/// cinematic camera director (see [CinematicCameraDirector]) as one shot
/// list in scene order (crane reveal, dolly, orbit, crane, window entry and
/// arrival), with every shot starting where the previous one ended; the
/// older [DepthCameraPlanner] is the fallback. The camera is folded into the
/// layer expressions, and if the camera render fails the clip is rendered
/// again flat, so a camera problem never costs the cutaway either.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

import 'cinematic_camera_director.dart';
import 'cinematic_vfx.dart';
import 'continuous_scene_generator.dart';
import 'depth_camera_planner.dart';
import 'motion_ffmpeg_adapter.dart';
import 'motion_graphics.dart' show MotionMood;
import 'motion_scene_json.dart';
import 'motion_vfx_animator.dart';
import 'motion_vfx_overlay.dart';
import 'motion_visual_library.dart';
import 'pixel_art_sprites.dart';
import 'reference_scene_builder.dart';
import 'scene_layout_memory.dart';
import 'scene_richness_guard.dart';
import 'text_render.dart';
import 'world_set_pieces.dart';

class MotionCutawayClip {
  final String path;
  final double duration;

  const MotionCutawayClip({required this.path, required this.duration});
}

class MotionCutawayRenderer {
  MotionCutawayRenderer._();

  /// Master switch for motion cutaways in exported videos.
  static bool enabled = true;

  /// Give every scene of a new cutaway a depth camera.
  static bool depthCameraEnabled = true;

  /// The motion canvas is rendered at most this many pixels on its short
  /// side (then scaled to the video size by the timeline overlay).
  static const int maxShortSide = 720;

  /// Strength of the clip-wide cinematic grade (0..1). Kept moderate for
  /// phones.
  static const double lookIntensity = 0.4;

  static int _even(double value) {
    var result = value.round();
    if (result.isOdd) result++;
    return result < 2 ? 2 : result;
  }

  static String _quote(String arg) =>
      '"${arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// Width and height of a PNG file, read from its header.
  static Future<List<int>?> _pngSize(String path) async {
    final raf = await File(path).open();
    try {
      final head = await raf.read(24);
      if (head.length < 24) return null;
      final w = (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19];
      final h = (head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23];
      if (w <= 0 || h <= 0) return null;
      return <int>[w, h];
    } finally {
      await raf.close();
    }
  }

  static int _mix(int from, int to, double t, int shift) {
    final a = (from >> shift) & 0xFF;
    final b = (to >> shift) & 0xFF;
    return (a + (b - a) * t).round();
  }

  /// Pixel-grid vertical gradient used as the scene background.
  static Uint8List _backgroundPng(int top, int bottom, int w, int h) {
    const lowW = 90;
    final lowH = math.max(8, (lowW * h / w).round());
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final ly = math.min(lowH - 1, y * lowH ~/ h);
      final t = ly / math.max(1, lowH - 1);
      final r0 = _mix(top, bottom, t, 16);
      final g0 = _mix(top, bottom, t, 8);
      final b0 = _mix(top, bottom, t, 0);
      for (var x = 0; x < w; x++) {
        final lx = math.min(lowW - 1, x * lowW ~/ w);
        final dither = ((lx + ly) & 1) == 0 ? 0 : 4;
        final grid = (lx % 10 == 0 || ly % 10 == 0) ? 8 : 0;
        final bump = dither + grid;
        final i = (y * w + x) * 4;
        rgba[i] = math.min(255, r0 + bump);
        rgba[i + 1] = math.min(255, g0 + bump);
        rgba[i + 2] = math.min(255, b0 + bump);
        rgba[i + 3] = 255;
      }
    }
    return PixelPngEncoder.encodeRgba(rgba, width: w, height: h);
  }

  /// The effects of the cinematic look stored in [specs], or an empty list
  /// when there is none (or VFX are switched off).
  static List<CinematicEffect> _lookEffects(Map<String, SceneAssetSpec> specs) {
    if (!ReferenceSceneBuilder.vfxEnabled) return const <CinematicEffect>[];
    for (final spec in specs.values) {
      if (spec.kind != SceneAssetKind.look) continue;
      final preset = CinematicVfx.preset(spec.spriteKey ?? '');
      if (preset == null) return const <CinematicEffect>[];
      return preset.effects;
    }
    return const <CinematicEffect>[];
  }

  /// Same plan with the single-stream [filters] appended to the composed
  /// picture.
  static MotionFfmpegPlan _withLook(
    MotionFfmpegPlan plan,
    List<String> filters,
  ) {
    return _withGraph(
      plan,
      '[${plan.outputLabel}]${filters.join(',')}[vfx]',
    );
  }

  /// Same plan with the complete filter [graph] (from the plan's output pad
  /// to the pad `vfx`) appended.
  static MotionFfmpegPlan _withGraph(MotionFfmpegPlan plan, String graph) {
    return MotionFfmpegPlan(
      width: plan.width,
      height: plan.height,
      frameRate: plan.frameRate,
      inputs: plan.inputs,
      filterComplex: '${plan.filterComplex};$graph',
      outputLabel: 'vfx',
      totalDuration: plan.totalDuration,
      skippedLayerIds: plan.skippedLayerIds,
    );
  }

  static Future<bool> _run(MotionFfmpegPlan plan, String out) async {
    final command = plan.arguments(outputPath: out).map(_quote).join(' ');
    final session = await FFmpegKit.execute(command);
    final ok = ReturnCode.isSuccess(await session.getReturnCode());
    final file = File(out);
    if (ok && file.existsSync() && file.lengthSync() > 0) return true;
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    return false;
  }

  /// Renders [plan] with the cinematic look: the complete graph first (it
  /// includes Bloom and Halation), then the single-stream grade, then no
  /// grade at all.
  static Future<bool> _runWithLook(
    MotionFfmpegPlan plan,
    String out,
    List<CinematicEffect> effects,
  ) async {
    if (effects.isNotEmpty) {
      final graph = CinematicVfx.buildGraph(
        input: plan.outputLabel,
        output: 'vfx',
        effects: effects,
        intensity: lookIntensity,
      );
      if (graph != null && await _run(_withGraph(plan, graph), out)) {
        return true;
      }
      final hasSplit = effects.any((e) => !CinematicVfx.isSingleStream(e));
      final safe = CinematicVfx.safeChain(effects, intensity: lookIntensity);
      if (hasSplit && safe.isNotEmpty && await _run(_withLook(plan, safe), out)) {
        return true;
      }
    }
    return _run(plan, out);
  }

  /// Stable seed from an asset key, so a re-render draws the same overlay.
  static int _seedFor(String key) =>
      key.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7FFFFFFF);

  /// Builds the cutaway of [spec]: the continuous generator first (and its
  /// last layout is remembered for the next cutaway of the same export), the
  /// plain scene builder as the fallback.
  static ReferenceSceneResult _build({
    required CutawaySpec spec,
    required int stamp,
    required int index,
    required int width,
    required int height,
    required MotionMood mood,
  }) {
    if (ContinuousSceneGenerator.enabled) {
      try {
        final plan = ContinuousSceneGenerator.build(
          id: 'cut$index',
          spec: spec,
          width: width,
          height: height,
          mood: mood,
          variant: index,
          previousLayout: SceneLayoutMemory.previousFor(stamp),
        );
        if (plan.layouts.isNotEmpty) {
          SceneLayoutMemory.remember(stamp, plan.layouts.last);
        }
        return plan.result;
      } catch (_) {
        // Fall through to the plain builder.
      }
    }
    return ReferenceSceneBuilder.buildCutaway(
      id: 'cut$index',
      spec: spec,
      width: width,
      height: height,
      mood: mood,
      variant: index,
    );
  }

  /// Renders [spec] to `motion_scene_<stamp>_<index>.mp4` inside [dir].
  /// Every temporary image is added to [temps]. Returns null on failure.
  static Future<MotionCutawayClip?> render({
    required CutawaySpec spec,
    required String dir,
    required int stamp,
    required int index,
    required int outW,
    required int outH,
    required MotionMood mood,
    required String fontFamily,
    required List<String> temps,
  }) async {
    if (!enabled) return null;
    try {
      final shortSide = math.min(outW, outH);
      final factor = shortSide > maxShortSide ? maxShortSide / shortSide : 1.0;
      final mw = _even(outW * factor);
      final mh = _even(outH * factor);

      // Several beats with different compositions; the plain builder is the
      // fallback if the generator cannot handle the phrase.
      var built = _build(
        spec: spec,
        stamp: stamp,
        index: index,
        width: mw,
        height: mh,
        mood: mood,
      );

      // Thin scenes get a faint giant word and moving atmosphere; a problem
      // here only means the scene stays as built.
      try {
        built = SceneRichnessGuard.enrich(built);
      } catch (_) {}

      // Camera per scene, planned as one shot list in scene order across the
      // whole export; if the director fails the older planner is tried, and a
      // problem in both only means a flat cutaway.
      if (depthCameraEnabled) {
        try {
          built = CinematicCameraDirector.upgrade(
            built,
            mood: mood,
            state: CameraDirectorMemory.stateFor(stamp),
          );
        } catch (_) {
          try {
            built = DepthCameraPlanner.upgrade(
              built,
              mood: mood,
              variant: index,
            );
          } catch (_) {}
        }
      }

      final clip = await renderBuilt(
        built: built,
        dir: dir,
        stamp: stamp,
        index: index,
        fontFamily: fontFamily,
        temps: temps,
      );
      if (clip == null) return null;

      return MotionCutawayClip(
        path: clip.path,
        duration: math.min(spec.duration, clip.duration),
      );
    } catch (_) {
      return null;
    }
  }

  /// Renders an already built (or edited) motion project to
  /// `motion_scene_<stamp>_<index>.mp4` inside [dir], and writes its editable
  /// description next to it. Temporary images and the description file are
  /// added to [temps]; the MP4 itself is left to the caller. Returns null on
  /// failure.
  ///
  /// A clip shorter than [minSeconds] is not rendered (null). The default of
  /// one second suits cutaways; the world scenes pass a smaller value because
  /// their windows can be as short as half a second.
  static Future<MotionCutawayClip?> renderBuilt({
    required ReferenceSceneResult built,
    required String dir,
    required int stamp,
    required int index,
    required String fontFamily,
    required List<String> temps,
    double minSeconds = 1.0,
  }) async {
    try {
      // Moving overlays; a problem here only means static overlays.
      var scene = built;
      try {
        scene = MotionVfxAnimator.animate(built);
      } catch (_) {}

      final mw = scene.project.width;
      final mh = scene.project.height;

      final assets = <String, MotionRenderAsset>{};
      final spritePaths = <String, String>{};
      final visualPaths = <String, String>{};
      final fontSize = math.min(mw, mh) * 0.14;
      var fontReady = false;

      for (final entry in scene.assets.entries) {
        final key = entry.key;
        final asset = entry.value;
        final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

        if (asset.kind == SceneAssetKind.background) {
          final bgPath = '$dir/mot_${stamp}_${index}_$safe.png';
          await File(bgPath).writeAsBytes(
            _backgroundPng(asset.topColor, asset.bottomColor, mw, mh),
            flush: true,
          );
          temps.add(bgPath);
          assets[key] = MotionRenderAsset(
            path: bgPath,
            aspect: mh / mw,
            widthFraction: 1.0,
          );
        } else if (asset.kind == SceneAssetKind.sprite) {
          final sprite = PixelSprites.byKey(asset.spriteKey ?? '');
          if (sprite == null) continue;
          final cached = spritePaths[sprite.key];
          final spritePath =
              cached ?? '$dir/mot_${stamp}_${index}_${sprite.key}.png';
          if (cached == null) {
            await File(spritePath).writeAsBytes(
              sprite.toPng(scale: 8),
              flush: true,
            );
            temps.add(spritePath);
            spritePaths[sprite.key] = spritePath;
          }
          assets[key] = MotionRenderAsset(
            path: spritePath,
            aspect: sprite.height / sprite.width,
            widthFraction: asset.widthFraction,
          );
        } else if (asset.kind == SceneAssetKind.visual) {
          // Semantic library illustration, or a full-canvas set piece of the
          // story world (`set:<name>`); a failure only skips this layer.
          final visualId = asset.spriteKey ?? '';
          final setName = WorldSetPieces.nameOf(visualId);
          if (setName != null) {
            if (!WorldSetPieces.has(setName)) continue;
            try {
              final cached = visualPaths[visualId];
              final setPath =
                  cached ?? '$dir/mot_${stamp}_${index}_set_$setName.png';
              if (cached == null) {
                await File(setPath).writeAsBytes(
                  await WorldSetPieces.renderPng(
                    setName,
                    width: mw,
                    height: mh,
                  ),
                  flush: true,
                );
                temps.add(setPath);
                visualPaths[visualId] = setPath;
              }
              assets[key] = MotionRenderAsset(
                path: setPath,
                aspect: mh / mw,
                widthFraction: asset.widthFraction,
              );
            } catch (_) {
              continue;
            }
            continue;
          }
          if (MotionVisualLibrary.byId(visualId) == null) continue;
          try {
            final cached = visualPaths[visualId];
            final visualPath =
                cached ?? '$dir/mot_${stamp}_${index}_vis_$visualId.png';
            if (cached == null) {
              await File(visualPath).writeAsBytes(
                await MotionVisualLibrary.renderPng(
                  visualId,
                  size: 512,
                  seed: _seedFor(visualId) + index,
                ),
                flush: true,
              );
              temps.add(visualPath);
              visualPaths[visualId] = visualPath;
            }
            assets[key] = MotionRenderAsset(
              path: visualPath,
              aspect: 1.0,
              widthFraction: asset.widthFraction,
            );
          } catch (_) {
            continue;
          }
        } else if (asset.kind == SceneAssetKind.overlay) {
          // Transparent VFX layer. It is drawn a little larger than the
          // canvas (the animator sets the factor) so that its movement never
          // shows an edge, and 1:1 so it is never scaled. A failure only
          // skips this layer.
          MotionOverlayKind? overlayKind;
          for (final kind in MotionOverlayKind.values) {
            if (kind.name == asset.spriteKey) overlayKind = kind;
          }
          if (overlayKind == null) continue;
          try {
            final overlayPath = '$dir/mot_${stamp}_${index}_$safe.png';
            final factor = asset.widthFraction < 1.0
                ? 1.0
                : (asset.widthFraction > 1.5 ? 1.5 : asset.widthFraction);
            final ow = _even(mw * factor);
            final oh = _even(mh * factor);
            final companion = key.startsWith('bg:fx2_');
            await File(overlayPath).writeAsBytes(
              await MotionVfxOverlay.renderPng(
                kind: overlayKind,
                width: ow,
                height: oh,
                seed: _seedFor(key),
                intensity: companion ? 0.38 : 0.5,
              ),
              flush: true,
            );
            temps.add(overlayPath);
            assets[key] = MotionRenderAsset(
              path: overlayPath,
              aspect: oh / ow,
              widthFraction: ow / mw,
              screen: MotionVfxOverlay.prefersScreen(overlayKind),
            );
          } catch (_) {
            continue;
          }
        } else if (asset.kind == SceneAssetKind.look) {
          // Not a layer: applied to the whole clip below.
          continue;
        } else {
          final text = asset.text;
          if (text == null || text.trim().isEmpty) continue;
          if (!fontReady) {
            await TextRender.prepareFont(
              fontFamily: fontFamily,
              fontSize: fontSize,
              style: 'bold_center',
            );
            fontReady = true;
          }
          final wordPath = '$dir/mot_${stamp}_${index}_$safe.png';
          await TextRender.png(
            text: text,
            outPath: wordPath,
            width: mw,
            fontSize: fontSize,
            fontFamily: fontFamily,
            style: 'bold_center',
          );
          temps.add(wordPath);
          final size = await _pngSize(wordPath);
          if (size == null) continue;
          assets[key] = MotionRenderAsset(
            path: wordPath,
            aspect: size[1] / size[0],
            widthFraction: 1.0,
          );
        }
      }

      final out = '$dir/motion_scene_${stamp}_$index.mp4';
      final look = _lookEffects(scene.assets);
      final hasCamera =
          scene.project.scenes.any((s) => s.camera?.isActive ?? false);
      final hasScreen = assets.values.any((a) => a.screen);

      // Try the depth camera first, then the flat composition; each of them
      // with the screen blend first, then with normal overlays. Every attempt
      // is tried with the full cinematic grade, then the single-stream grade,
      // then without it, so a filter missing from the bundled FFmpegKit never
      // costs the cutaway.
      var ok = false;
      var duration = 0.0;
      final cameras = hasCamera ? const <bool>[true, false] : const <bool>[false];
      final blends = hasScreen ? const <bool>[true, false] : const <bool>[false];
      for (final withCamera in cameras) {
        for (final withBlend in blends) {
          final plan = MotionFfmpegAdapter.build(
            project: scene.project,
            assets: assets,
            depthCamera: withCamera,
            blendModes: withBlend,
          );
          if (plan.totalDuration < minSeconds) return null;
          ok = await _runWithLook(plan, out, look);
          if (ok) {
            duration = plan.totalDuration;
            break;
          }
        }
        if (ok) break;
      }
      if (!ok) return null;

      // The editable description is optional: the clip works without it.
      try {
        final sidecar = MotionSceneJson.sidecarPathFor(out);
        await MotionSceneJson.writeFor(
          out,
          MotionSceneDocument(
            project: scene.project,
            assets: scene.assets,
            fontFamily: fontFamily,
          ),
        );
        temps.add(sidecar);
      } catch (_) {}

      return MotionCutawayClip(path: out, duration: duration);
    } catch (_) {
      return null;
    }
  }
}
