/// Makes sure no motion scene is nearly empty.
///
/// The references (Motion Smith and the pixel-art typography reel) never show
/// a bare background with one word and one small sprite. Every scene has a
/// subject, a word, moving atmosphere and depth. A scene built from a very
/// short phrase can end up with too little, so this step runs right before
/// the clip is rendered and, for a thin scene only:
///  * adds a giant, very faint copy of the scene's first word behind the
///    subject (typographic depth, slow drift, parallax via a far depth);
///  * adds moving atmosphere overlays until the scene has two of them.
///
/// Scenes that are already rich are returned untouched. It is idempotent
/// (layers it adds have fixed ids) and never throws for odd input: the
/// renderer also wraps it in a try/catch. Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'motion_scene_model.dart';
import 'motion_vfx_animator.dart';
import 'motion_vfx_overlay.dart';
import 'reference_scene_builder.dart';

/// Counts of what a scene shows.
class SceneRichness {
  final int subjects;
  final int words;
  final int overlays;

  const SceneRichness({
    required this.subjects,
    required this.words,
    required this.overlays,
  });

  int get total => subjects + words + overlays;
}

class SceneRichnessGuard {
  SceneRichnessGuard._();

  static bool enabled = true;

  /// A scene with fewer visible layers than this is enriched.
  static const int minLayers = 4;

  /// Wanted number of atmosphere overlays in an enriched scene.
  static const int wantedOverlays = 2;

  static const String ghostSuffix = '_ghost';

  static SceneRichness measure(
    MotionScene scene,
    Map<String, SceneAssetSpec> assets,
  ) {
    var subjects = 0;
    var words = 0;
    var overlays = 0;
    for (final layer in scene.layers) {
      final spec = assets[layer.assetKey];
      if (spec == null) continue;
      switch (spec.kind) {
        case SceneAssetKind.sprite:
        case SceneAssetKind.visual:
          subjects++;
        case SceneAssetKind.word:
          words++;
        case SceneAssetKind.overlay:
          overlays++;
        case SceneAssetKind.background:
        case SceneAssetKind.look:
          break;
      }
    }
    return SceneRichness(subjects: subjects, words: words, overlays: overlays);
  }

  static String? _firstWord(MotionScene scene, Map<String, SceneAssetSpec> assets) {
    for (final layer in scene.layers) {
      final spec = assets[layer.assetKey];
      if (spec == null || spec.kind != SceneAssetKind.word) continue;
      final text = (spec.text ?? layer.text ?? '').trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static int _seed(String key) =>
      key.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7FFFFFFF);

  /// [built] with every thin scene enriched.
  static ReferenceSceneResult enrich(ReferenceSceneResult built) {
    if (!enabled) return built;
    final assets = Map<String, SceneAssetSpec>.of(built.assets);
    final scenes = <MotionScene>[];
    var changed = false;

    for (final scene in built.project.scenes) {
      final richness = measure(scene, assets);
      final alreadyGhosted = scene.layers.any((l) => l.id.endsWith(ghostSuffix));
      if (richness.total >= minLayers && richness.overlays >= wantedOverlays ||
          scene.duration < 0.8 ||
          alreadyGhosted) {
        scenes.add(scene);
        continue;
      }

      final layers = List<MotionLayer>.of(scene.layers);
      final dur = scene.duration;

      // 1) Giant faint word behind everything that moves.
      final word = _firstWord(scene, assets);
      if (word != null && richness.total < minLayers) {
        final key = 'word:${scene.id}$ghostSuffix';
        assets[key] = SceneAssetSpec(
          kind: SceneAssetKind.word,
          text: word,
          widthFraction: 1.0,
        );
        final side = (_seed(key) & 1) == 0 ? 1.0 : -1.0;
        layers.add(
          MotionLayer(
            id: '${scene.id}$ghostSuffix',
            start: scene.start,
            end: scene.end,
            zIndex: 1,
            depth: 0.15,
            assetKey: key,
            keyframes: <MotionKeyframe>[
              MotionKeyframe(
                time: 0,
                x: 0.5 - 0.08 * side,
                y: 0.42,
                scale: 2.1,
                opacity: 0,
                easing: MotionEase.easeOut,
              ),
              MotionKeyframe(
                time: math.min(0.35, dur * 0.3),
                x: 0.5 - 0.05 * side,
                y: 0.42,
                scale: 2.2,
                opacity: 0.13,
              ),
              MotionKeyframe(
                time: dur,
                x: 0.5 + 0.08 * side,
                y: 0.42,
                scale: 2.35,
                opacity: 0.13,
              ),
            ],
          ),
        );
        changed = true;
      }

      // 2) Moving atmosphere until the scene has two overlays.
      var have = richness.overlays;
      const order = <MotionOverlayKind>[
        MotionOverlayKind.embers,
        MotionOverlayKind.sparkles,
        MotionOverlayKind.bokeh,
        MotionOverlayKind.dust,
      ];
      final usedKinds = <String>{
        for (final layer in scene.layers)
          if (assets[layer.assetKey]?.kind == SceneAssetKind.overlay)
            assets[layer.assetKey]!.spriteKey ?? '',
      };
      for (final kind in order) {
        if (have >= wantedOverlays) break;
        if (usedKinds.contains(kind.name)) continue;
        final key = 'bg:fx3_${scene.id}_${kind.name}';
        assets[key] = SceneAssetSpec(
          kind: SceneAssetKind.overlay,
          spriteKey: kind.name,
          widthFraction: MotionVfxOverlay.travelFactor(kind),
        );
        layers.add(
          MotionLayer(
            id: '${scene.id}_fx3_${kind.name}',
            start: scene.start,
            end: scene.end,
            zIndex: 3,
            assetKey: key,
            keyframes: MotionVfxAnimator.keysFor(kind, dur, _seed(key)),
          ),
        );
        usedKinds.add(kind.name);
        have++;
        changed = true;
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

    if (!changed) return built;
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
