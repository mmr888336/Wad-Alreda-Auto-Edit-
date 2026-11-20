/// World scene camera: the camera of ONE 3D world scene of the pipeline.
///
/// The story gives every beat a camera hint (see [CameraHintBridge]). The 3D
/// pipeline renders a world scene for a time window of the video, and that
/// window needs ONE camera that both engines share: the Filament camera path
/// of the 3D world and the depth camera of the 2.5D layers drawn over it (and
/// of the 2.5D fallback of the whole scene). This helper asks the bridge for
/// it, so the rules of the camera story hold here too:
///  * an entry into the window is followed by its arrival (same zoom);
///  * an arrival without an entry is a pull out;
///  * an entry with no scene after it is a push in;
///  * a move is never repeated twice in a row.
///
/// The camera story only links two scenes that are neighbours on the screen
/// ([areAdjacent]): when the speaker is shown between two 3D scenes, the
/// arrival of an entry would start zoomed in out of nowhere, so the scenes
/// are planned as separate shots.
///
/// The FIRST scene is not left to the cinematic director here: the 3D
/// pipeline has no director, so the opening beat (a crane reveal) gets its
/// camera from the story like every other scene.
///
/// Pure Dart, no I/O.
library;

import 'camera_hint_bridge.dart';
import 'depth_camera_model.dart' show SceneCamera;
import 'motion_graphics.dart' show MotionMood;
import 'motion_scene_model.dart' show MotionScene;
import 'story_understanding.dart' show StoryBeat;

class WorldSceneCamera {
  WorldSceneCamera._();

  /// The mood that sets the strength of the camera (the same default the
  /// cutaway generator uses).
  static const MotionMood mood = MotionMood.cinematic;

  /// Two 3D scenes this close (in seconds) are shown one after the other.
  static const double adjacentGapSeconds = 0.5;

  /// True when a scene that starts at [secondStart] follows a scene that ends
  /// at [firstEnd] with no (or almost no) video of the speaker in between.
  static bool areAdjacent(double firstEnd, double secondStart) {
    return secondStart - firstEnd <= adjacentGapSeconds;
  }

  /// The camera of [scene] from the story [beats], or null when the story
  /// gives it none (no beat overlaps it, the hint is "no move", or
  /// [CameraHintBridge.enabled] is false).
  ///
  /// [previous] is the camera of the scene shown right before it (null when
  /// there is none or it is not adjacent), [hasNext] tells whether a scene is
  /// shown right after it.
  static SceneCamera? plan({
    required MotionScene scene,
    required List<StoryBeat> beats,
    required SceneCamera? previous,
    required bool hasNext,
  }) {
    final hint = CameraHintBridge.hintFor(beats, scene.start, scene.end);
    if (hint == null) return null;

    return CameraHintBridge.cameraFor(
      scene: scene,
      hint: hint,
      mood: mood,
      previous: previous,
      hasNext: hasNext,
      isFirst: false,
    );
  }
}
