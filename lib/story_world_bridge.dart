/// Story-world bridge: connects the story planner and the cinematic world
/// to the motion scene model.
///
/// [StoryUnderstanding] reads what the speaker says, [CinematicWorld] turns
/// that story into one fixed world (same character, same palette, one fixed
/// layout per environment). Both produce renderer-neutral data. This bridge
/// is the missing link: it plans both in one call and converts every world
/// scene into a [MotionScene] whose layers carry the fixed character, the
/// fixed set pieces and the props chosen by the meaning of the sentence, each
/// with its own depth for the depth camera.
///
/// [StoryWorldBridge.renderingOf] goes one step further: it keeps only the
/// world layers the renderer can draw today (backdrop, the set pieces of the
/// environment, the fixed character and the props that have a library
/// picture) and creates the asset of each one, so a scene generator can merge
/// them into its own scenes. A set piece is a full-canvas picture drawn by
/// [WorldSetPieces]; its asset is a `visual` asset with the id `set:<name>`.
///
/// Pure Dart, no I/O.
library;

import 'cinematic_world.dart';
import 'motion_scene_model.dart';
import 'motion_transitions.dart';
import 'motion_visual_library.dart' show MotionVisualLibrary;
import 'reference_scene_builder.dart'
    show ReferenceSceneBuilder, SceneAssetKind, SceneAssetSpec;
import 'story_understanding.dart';
import 'world_set_pieces.dart';

/// The story of a video and the world planned from it.
class StoryWorldPlan {
  final StoryPlan story;
  final WorldPlan world;

  const StoryWorldPlan({required this.story, required this.world});

  /// The world scene of beat [beatIndex], or null when there is none.
  WorldScene? worldSceneOf(int beatIndex) {
    for (final scene in world.scenes) {
      if (scene.beatIndex == beatIndex) return scene;
    }
    return null;
  }
}

/// The drawable part of one world scene: its layers, the asset of each layer
/// and the flat background colour (`#RRGGBB`) of the environment.
class WorldRendering {
  final String background;
  final List<MotionLayer> layers;
  final Map<String, SceneAssetSpec> assets;

  const WorldRendering({
    required this.background,
    required this.layers,
    required this.assets,
  });
}

class StoryWorldBridge {
  StoryWorldBridge._();

  /// Library picture that stands for a prop of the story. A prop that is not
  /// listed has no art yet and is not drawn.
  static const Map<String, String> propVisuals = <String, String>{
    'coins': 'coins',
    'chart': 'chart_bars',
    'wallet': 'wallet',
    'books': 'book',
    'notebook': 'book',
    'lamp': 'bulb',
    'lightbulb': 'bulb',
    'laptop': 'laptop',
    'screen': 'laptop',
    'clock': 'clock',
    'calendar': 'calendar',
    'trophy': 'trophy',
    'plant': 'tree',
    'water': 'water',
    'lantern': 'crescent',
    'stars': 'moon_stars',
    'cups': 'coffee',
    'car': 'car',
    'suitcase': 'briefcase',
    'chip': 'chip',
    'phone': 'phone',
    'warning': 'warning',
  };

  /// Stacking order of the world art inside a merged scene: the set pieces
  /// sit right above the backdrop and below the atmosphere overlays (2); the
  /// props and the character are below the scene's own subject (10) and
  /// words (20+).
  static const int backdropZ = 0;
  static const int setPieceZ = 1;
  static const int propBehindZ = 6;
  static const int heroZ = 8;
  static const int propFrontZ = 9;

  /// Plans the story of [segments] (in time order) and the world of that
  /// story. The character and the palette are the same in every scene.
  static StoryWorldPlan plan(
    List<StorySegment> segments, {
    WorldCharacter character = const WorldCharacter(),
    WorldPalette palette = const WorldPalette(),
  }) {
    final story = StoryUnderstanding.plan(segments);
    final world = CinematicWorld.plan(
      story,
      character: character,
      palette: palette,
    );
    return StoryWorldPlan(story: story, world: world);
  }

  /// Background colour (`#RRGGBB`) of the environment of [scene].
  static String backgroundOf(WorldScene scene) {
    return CinematicWorld.layouts[scene.environment]?.backdropColor ??
        '#000000';
  }

  /// The layers of [scene] as motion layers visible from [start] to [end]
  /// seconds. Position, size, depth and stacking order come from the world
  /// plan untouched, so the character and the set pieces stay identical
  /// every time the same environment comes back.
  static List<MotionLayer> layersOf(
    WorldScene scene, {
    required double start,
    required double end,
  }) {
    if (!start.isFinite || !end.isFinite || end <= start) {
      throw ArgumentError('Invalid scene range: $start..$end');
    }
    return <MotionLayer>[
      for (final spec in scene.layers)
        MotionLayer(
          id: spec.id,
          start: start,
          end: end,
          x: spec.x,
          y: spec.y,
          scale: spec.scale,
          zIndex: spec.zIndex,
          assetKey: spec.assetKey,
          depth: spec.depth,
        ),
    ];
  }

  static int _argbOf(String hex) {
    if (hex.length != 7 || !hex.startsWith('#')) return 0xFF000000;
    final value = int.tryParse(hex.substring(1), radix: 16);
    return value == null ? 0xFF000000 : 0xFF000000 | value;
  }

  static int _darker(int argb, double share) {
    int channel(int shift) {
      final value = (argb >> shift) & 0xFF;
      return (value * (1 - share)).round().clamp(0, 255).toInt();
    }

    return 0xFF000000 | (channel(16) << 16) | (channel(8) << 8) | channel(0);
  }

  /// A `decor:` layer of scale 0.9 or more is a set piece (full canvas);
  /// a smaller one is a prop that sits in a slot.
  static bool _isSetPiece(WorldLayerSpec spec) =>
      spec.assetKey.startsWith('decor:') && spec.scale >= 0.9;

  /// The asset the renderer must draw for [spec], or null when there is no
  /// art for it (a set piece without art, a prop without a library picture).
  static SceneAssetSpec? _assetFor(WorldLayerSpec spec, String backdropHex) {
    final key = spec.assetKey;
    if (key.startsWith('bg:')) {
      final top = _argbOf(backdropHex);
      return SceneAssetSpec(
        kind: SceneAssetKind.background,
        topColor: top,
        bottomColor: _darker(top, 0.45),
      );
    }
    if (key.startsWith('sprite:')) {
      // The one recurring character of the video.
      return const SceneAssetSpec(
        kind: SceneAssetKind.sprite,
        spriteKey: ReferenceSceneBuilder.mascotSprite,
        widthFraction: 1.0,
      );
    }
    if (key.startsWith('decor:')) {
      final name = key.substring('decor:'.length);
      if (_isSetPiece(spec)) {
        if (!WorldSetPieces.has(name)) return null;
        return SceneAssetSpec(
          kind: SceneAssetKind.visual,
          spriteKey: WorldSetPieces.idOf(name),
          widthFraction: 1.0,
        );
      }
      final id = propVisuals[name];
      if (id == null || MotionVisualLibrary.byId(id) == null) return null;
      return SceneAssetSpec(
        kind: SceneAssetKind.visual,
        spriteKey: id,
        widthFraction: 1.0,
      );
    }
    return null;
  }

  static int _zIndexFor(WorldLayerSpec spec) {
    final key = spec.assetKey;
    if (key.startsWith('bg:')) return backdropZ;
    if (key.startsWith('sprite:')) return heroZ;
    if (_isSetPiece(spec)) return setPieceZ;
    return spec.depth > WorldCharacter.depth ? propFrontZ : propBehindZ;
  }

  /// The drawable layers of [scene] from [start] to [end] seconds, with an
  /// asset for each. Layer ids start with [idPrefix] so they stay unique when
  /// several scenes share one project. Position, size and depth come from the
  /// world plan untouched. A picture is used once per scene.
  static WorldRendering renderingOf(
    WorldScene scene, {
    required String idPrefix,
    required double start,
    required double end,
  }) {
    if (!start.isFinite || !end.isFinite || end <= start) {
      throw ArgumentError('Invalid scene range: $start..$end');
    }
    final background = backgroundOf(scene);
    final layers = <MotionLayer>[];
    final assets = <String, SceneAssetSpec>{};
    final usedVisuals = <String>{};

    for (final spec in scene.layers) {
      final asset = _assetFor(spec, background);
      if (asset == null) continue;
      if (asset.kind == SceneAssetKind.visual &&
          !usedVisuals.add(asset.spriteKey ?? '')) {
        continue;
      }
      assets[spec.assetKey] = asset;
      layers.add(
        MotionLayer(
          id: '${idPrefix}_${spec.id}',
          start: start,
          end: end,
          x: spec.x,
          y: spec.y,
          scale: spec.scale,
          zIndex: _zIndexFor(spec),
          assetKey: spec.assetKey,
          depth: spec.depth,
        ),
      );
    }
    return WorldRendering(
      background: background,
      layers: layers,
      assets: assets,
    );
  }

  /// One motion scene for [scene] from [start] to [end] seconds, entered with
  /// [transitionIn].
  static MotionScene sceneFor(
    WorldScene scene, {
    required double start,
    required double end,
    MotionTransitionKind transitionIn = MotionTransitionKind.hardCut,
  }) {
    return MotionScene(
      id: 'world_s${scene.beatIndex}',
      start: start,
      end: end,
      background: backgroundOf(scene),
      transitionIn: transitionIn,
      layers: layersOf(scene, start: start, end: end),
    );
  }

  /// The whole video as a motion project: one scene per beat, timed like the
  /// spoken segment, entered with the transition the story chose after the
  /// beat before it. Throws [StateError] when the story has no beat.
  static MotionProject projectFor(
    StoryWorldPlan plan, {
    required String id,
    required int width,
    required int height,
    int frameRate = 30,
  }) {
    final beats = plan.story.beats;
    if (beats.isEmpty) {
      throw StateError('The story has no beats.');
    }
    final scenes = <MotionScene>[];
    for (var i = 0; i < beats.length; i++) {
      final beat = beats[i];
      final worldScene = plan.worldSceneOf(beat.index);
      if (worldScene == null) continue;
      scenes.add(
        sceneFor(
          worldScene,
          start: beat.segment.start,
          end: beat.segment.end,
          transitionIn:
              i == 0 ? MotionTransitionKind.hardCut : beats[i - 1].transitionToNext,
        ),
      );
    }
    return MotionProject(
      id: id,
      width: width,
      height: height,
      frameRate: frameRate,
      duration: beats.last.segment.end,
      scenes: scenes,
    );
  }
}
