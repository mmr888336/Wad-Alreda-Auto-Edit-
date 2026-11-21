/// Draws the 2.5D part of a world scene with the existing 2.5D engine
/// ([MotionCutawayRenderer.renderBuilt]):
///
///  * `wholeScene: false`: only the flat layers the router gave to 2.5D
///    (props...), on black. The compositor screen-blends this clip on top of
///    the 3D world.
///  * `wholeScene: true`: the whole scene (backdrop, set pieces, character,
///    props) on the colour of the environment, for a scene that fell back
///    from 3D to 2.5D.
///
/// With `withLook` the atmosphere particles of the scene's [WorldLook] (dust,
/// sparks, pollen) are added as one more overlay layer (see
/// [WorldLookGrade.particleKind]).
///
/// The depth camera of the scene is carried over, so the flat layers react to
/// the same camera as the 3D world. Any failure returns no clip.
library;

import 'cinematic_world.dart' show WorldScene;
import 'motion_cutaway_renderer.dart';
import 'motion_scene_model.dart';
import 'reference_scene_builder.dart'
    show ReferenceSceneResult, SceneAssetKind, SceneAssetSpec;
import 'render_router.dart' show SceneRouting;
import 'story_world_bridge.dart';
import 'world_look_grade.dart';

class WorldFlatOutcome {
  const WorldFlatOutcome({this.path, this.layerCount = 0, this.error});

  /// The rendered clip, or null (nothing to draw, or it failed).
  final String? path;
  final int layerCount;

  /// Why it failed; null when nothing failed.
  final String? error;
}

class WorldFlatRenderer {
  WorldFlatRenderer._();

  /// Master switch. When false no 2.5D clip is drawn for world scenes.
  static bool enabled = true;

  /// Same limit as the motion cutaways.
  static const int maxShortSide = 720;

  /// Asset key of the particle layer of the look.
  static const String particleKey = 'bg:fx_world';

  /// Even pixel size (at least 2) for an FFmpeg canvas.
  static int evenSize(double value) {
    var result = value.round();
    if (result.isOdd) result++;
    return result < 2 ? 2 : result;
  }

  /// The motion project of the 2.5D part of [motion], or null when there is
  /// nothing to draw.
  static ReferenceSceneResult? build({
    required WorldScene world,
    required MotionScene motion,
    required SceneRouting routing,
    required bool wholeScene,
    required int width,
    required int height,
    required String idPrefix,
    bool withLook = false,
  }) {
    final duration = motion.end - motion.start;
    if (!duration.isFinite || duration <= 0 || width <= 0 || height <= 0) {
      return null;
    }

    final rendering = StoryWorldBridge.renderingOf(
      world,
      idPrefix: idPrefix,
      start: 0,
      end: duration,
    );

    final flatKeys = <String>{
      for (final layer in routing.flat)
        if (layer.assetKey != null) layer.assetKey!,
    };

    final layers = <MotionLayer>[
      for (final layer in rendering.layers)
        if (wholeScene || flatKeys.contains(layer.assetKey)) layer,
    ];

    final particles = withLook ? WorldLookGrade.particleKind(world.look) : null;

    if (layers.isEmpty && particles == null) return null;

    final assets = <String, SceneAssetSpec>{};
    for (final layer in layers) {
      final key = layer.assetKey;
      if (key == null) continue;
      final spec = rendering.assets[key];
      if (spec != null) assets[key] = spec;
    }

    if (particles != null) {
      layers.add(
        MotionLayer(
          id: '${idPrefix}_fx',
          start: 0,
          end: duration,
          zIndex: 2,
          assetKey: particleKey,
          keyframes: <MotionKeyframe>[
            const MotionKeyframe(
              time: 0,
              x: 0.5,
              y: 0.515,
              scale: 1.06,
              easing: MotionEase.linear,
            ),
            MotionKeyframe(
              time: duration,
              x: 0.5,
              y: 0.485,
              scale: 1.06,
              easing: MotionEase.linear,
            ),
          ],
        ),
      );
      assets[particleKey] = SceneAssetSpec(
        kind: SceneAssetKind.overlay,
        spriteKey: particles,
        widthFraction: 1.0,
      );
    }

    final scene = MotionScene(
      id: motion.id,
      start: 0,
      end: duration,
      layers: layers,
      background: wholeScene ? rendering.background : '#000000',
      camera: motion.camera,
    );

    return ReferenceSceneResult(
      project: MotionProject(
        id: idPrefix,
        width: width,
        height: height,
        frameRate: 30,
        duration: duration,
        scenes: <MotionScene>[scene],
      ),
      assets: assets,
    );
  }

  /// Builds and renders the 2.5D part into [dir]. Never throws.
  static Future<WorldFlatOutcome> renderScene({
    required WorldScene world,
    required MotionScene motion,
    required SceneRouting routing,
    required bool wholeScene,
    required int width,
    required int height,
    required String idPrefix,
    required String dir,
    required int stamp,
    required int index,
    required String fontFamily,
    required List<String> temps,
    bool withLook = false,
  }) async {
    try {
      final built = build(
        world: world,
        motion: motion,
        routing: routing,
        wholeScene: wholeScene,
        width: width,
        height: height,
        idPrefix: idPrefix,
        withLook: withLook,
      );

      if (built == null) return const WorldFlatOutcome();

      final layerCount = built.project.scenes.first.layers.length;

      final clip = await MotionCutawayRenderer.renderBuilt(
        built: built,
        dir: dir,
        stamp: stamp,
        index: index,
        fontFamily: fontFamily,
        temps: temps,
      );

      if (clip == null) {
        return WorldFlatOutcome(
          layerCount: layerCount,
          error: 'فشل رسم المشهد بمحرك 2.5D',
        );
      }

      return WorldFlatOutcome(path: clip.path, layerCount: layerCount);
    } catch (error) {
      return WorldFlatOutcome(error: '$error');
    }
  }
}
