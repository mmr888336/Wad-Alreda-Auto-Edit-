/// Gives the VFX overlay layers of a built motion project their motion.
///
/// The scene builders add one static overlay (smoke, dust, embers, rays...)
/// per scene with a tiny vertical drift. This step runs right before a clip
/// is rendered and:
///  * replaces the drift with a motion that fits the overlay kind (smoke
///    rises and sways, embers climb, light rays and light leaks sweep,
///    rain falls, sparkles wander);
///  * enlarges the overlay asset (see [MotionVfxOverlay.travelFactor]) so the
///    travel never shows its edges and never scales the picture up;
///  * adds one companion overlay of another kind to short cutaways, so a
///    scene has two moving layers (for example smoke and sparkles).
///
/// It is idempotent: an edited scene that is rendered again gets the same
/// result. Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'motion_scene_model.dart';
import 'motion_vfx_overlay.dart';
import 'motion_visual_pipeline.dart';
import 'reference_scene_builder.dart';

class MotionVfxAnimator {
  MotionVfxAnimator._();

  /// Master switch: when false the project is returned unchanged.
  static bool enabled = true;

  /// Add a companion overlay to every scene of a short cutaway.
  static bool extraLayerEnabled = true;

  /// Longer cutaways (more scenes) get no companion layer, to keep the
  /// render light on phones.
  static const int maxScenesForExtra = 3;

  static const String _prefix = 'bg:fx';

  /// True for the asset key of an overlay layer.
  static bool isOverlayKey(String? key) => key != null && key.startsWith(_prefix);

  static int _seedOf(String key) =>
      key.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7FFFFFFF);

  static MotionOverlayKind? _kindOf(String? name) {
    if (name == null) return null;
    for (final kind in MotionOverlayKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// Keyframes (layer-local time, normalised canvas units) for an overlay of
  /// [kind] that lives [dur] seconds. The travel always stays inside what
  /// [MotionVfxOverlay.travelFactor] hides.
  static List<MotionKeyframe> keysFor(MotionOverlayKind kind, double dur, int seed) {
    final r = math.Random(seed);
    final s = r.nextBool() ? 1.0 : -1.0;
    MotionKeyframe k(double t, double x, double y) => MotionKeyframe(
          time: t,
          x: x,
          y: y,
          scale: 1,
          easing: MotionEase.easeInOut,
        );
    final mid = dur * 0.5;
    switch (kind) {
      case MotionOverlayKind.smoke:
        return <MotionKeyframe>[
          k(0, 0.5 - 0.03 * s, 0.56),
          k(mid, 0.5 + 0.03 * s, 0.51),
          k(dur, 0.5 - 0.01 * s, 0.46),
        ];
      case MotionOverlayKind.embers:
        return <MotionKeyframe>[
          k(0, 0.5 - 0.03 * s, 0.60),
          k(mid, 0.5 + 0.03 * s, 0.50),
          k(dur, 0.5 - 0.02 * s, 0.40),
        ];
      case MotionOverlayKind.dust:
        return <MotionKeyframe>[
          k(0, 0.5 - 0.04 * s, 0.52),
          k(mid, 0.5, 0.50),
          k(dur, 0.5 + 0.04 * s, 0.48),
        ];
      case MotionOverlayKind.bokeh:
        return <MotionKeyframe>[
          k(0, 0.5 - 0.03 * s, 0.53),
          k(mid, 0.5 + 0.02 * s, 0.50),
          k(dur, 0.5 + 0.03 * s, 0.47),
        ];
      case MotionOverlayKind.volumetricRays:
        return <MotionKeyframe>[
          k(0, 0.5 - 0.03 * s, 0.50),
          k(mid, 0.5 + 0.03 * s, 0.50),
          k(dur, 0.5 - 0.03 * s, 0.50),
        ];
      case MotionOverlayKind.lightLeak:
        return <MotionKeyframe>[
          k(0, 0.5 - 0.04 * s, 0.50),
          k(dur, 0.5 + 0.04 * s, 0.50),
        ];
      case MotionOverlayKind.rain:
        return <MotionKeyframe>[
          k(0, 0.5, 0.45),
          k(dur, 0.5, 0.55),
        ];
      case MotionOverlayKind.sparkles:
        return <MotionKeyframe>[
          k(0, 0.5 - 0.03 * s, 0.52),
          k(mid, 0.5 + 0.03 * s, 0.48),
          k(dur, 0.5 - 0.02 * s, 0.51),
        ];
      case MotionOverlayKind.shadow:
        return <MotionKeyframe>[k(0, 0.5, 0.5), k(dur, 0.5, 0.5)];
    }
  }

  static MotionLayer _withKeys(MotionLayer l, List<MotionKeyframe> keys) {
    return MotionLayer(
      id: l.id,
      start: l.start,
      end: l.end,
      x: l.x,
      y: l.y,
      scale: l.scale,
      rotation: l.rotation,
      opacity: l.opacity,
      zIndex: l.zIndex,
      assetKey: l.assetKey,
      text: l.text,
      keyframes: keys,
      depth: l.depth,
    );
  }

  /// [built] with animated overlays (see the library comment). Returns
  /// [built] itself when the animator is switched off.
  static ReferenceSceneResult animate(ReferenceSceneResult built) {
    if (!enabled) return built;
    final assets = Map<String, SceneAssetSpec>.of(built.assets);
    final presetId = built.assets['bg:look']?.spriteKey;
    final presetOverlays = presetId == null
        ? const <MotionOverlayKind>[]
        : MotionVisualPipeline.overlaysFor(presetId);
    final allowExtra =
        extraLayerEnabled && built.project.scenes.length <= maxScenesForExtra;

    final scenes = <MotionScene>[];
    for (final scene in built.project.scenes) {
      final layers = <MotionLayer>[];
      MotionOverlayKind? mainKind;
      for (final layer in scene.layers) {
        final key = layer.assetKey;
        if (!isOverlayKey(key)) {
          layers.add(layer);
          continue;
        }
        final spec = assets[key!];
        final kind = (spec == null || spec.kind != SceneAssetKind.overlay)
            ? null
            : _kindOf(spec.spriteKey);
        if (kind == null) {
          layers.add(layer);
          continue;
        }
        if (layer.id.endsWith('_fx')) mainKind ??= kind;
        assets[key] = SceneAssetSpec(
          kind: SceneAssetKind.overlay,
          spriteKey: kind.name,
          widthFraction: MotionVfxOverlay.travelFactor(kind),
        );
        layers.add(_withKeys(layer, keysFor(kind, layer.duration, _seedOf(key))));
      }

      final hasExtra = scene.layers.any((l) => l.id.endsWith('_fx2'));
      if (allowExtra && mainKind != null && scene.duration >= 1.0 && !hasExtra) {
        final candidates = <MotionOverlayKind>[
          ...presetOverlays,
          MotionOverlayKind.dust,
          MotionOverlayKind.sparkles,
        ];
        MotionOverlayKind? extra;
        for (final candidate in candidates) {
          if (candidate != mainKind && candidate != MotionOverlayKind.shadow) {
            extra = candidate;
            break;
          }
        }
        if (extra != null) {
          final key = 'bg:fx2_${scene.id}';
          assets[key] = SceneAssetSpec(
            kind: SceneAssetKind.overlay,
            spriteKey: extra.name,
            widthFraction: MotionVfxOverlay.travelFactor(extra),
          );
          layers.add(
            MotionLayer(
              id: '${scene.id}_fx2',
              start: scene.start,
              end: scene.end,
              zIndex: 3,
              assetKey: key,
              keyframes: keysFor(extra, scene.duration, _seedOf(key) + 1),
            ),
          );
        }
      }

      scenes.add(
        MotionScene(
          id: scene.id,
          start: scene.start,
          end: scene.end,
          background: scene.background,
          transitionIn: scene.transitionIn,
          layers: layers,
          camera: scene.camera,
        ),
      );
    }

    return ReferenceSceneResult(
      project: MotionProject(
        id: built.project.id,
        width: built.project.width,
        height: built.project.height,
        frameRate: built.project.frameRate,
        duration: built.project.duration,
        scenes: scenes,
      ),
      assets: assets,
    );
  }
}
