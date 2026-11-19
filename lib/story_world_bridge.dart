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
/// It only creates new objects: nothing existing is changed, so it can be
/// plugged into the scene generators one step at a time. Pure Dart, no I/O.
library;

import 'cinematic_world.dart';
import 'motion_scene_model.dart';
import 'motion_transitions.dart';
import 'story_understanding.dart';

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

class StoryWorldBridge {
  StoryWorldBridge._();

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
