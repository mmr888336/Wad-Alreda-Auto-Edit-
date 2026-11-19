/// Chooses the depth camera of every scene of a motion cutaway.
///
/// The first scene gets a move that fits the mood of the video; every next
/// scene gets the complementary move (push in is followed by an orbit, an
/// orbit by the opposite orbit, a spiral by a pull out...), so the
/// perspective changes between scenes instead of repeating. Pure Dart.
///
/// The renderer plans the camera with the cinematic director (see
/// CinematicCameraDirector), which follows the scene order of the whole
/// video; this planner stays as its fallback.
library;

import 'depth_camera_model.dart';
import 'motion_graphics.dart' show MotionMood;
import 'motion_scene_model.dart';
import 'reference_scene_builder.dart' show ReferenceSceneResult;

class DepthCameraPlanner {
  DepthCameraPlanner._();

  static const List<DepthCameraMove> _calmPool = <DepthCameraMove>[
    DepthCameraMove.pushIn,
    DepthCameraMove.orbitRight,
    DepthCameraMove.parallaxLeft,
    DepthCameraMove.riseUp,
    DepthCameraMove.orbitLeft,
  ];

  static const List<DepthCameraMove> _cinematicPool = <DepthCameraMove>[
    DepthCameraMove.spiralIn,
    DepthCameraMove.orbitLeft,
    DepthCameraMove.dollyZoom,
    DepthCameraMove.pushIn,
    DepthCameraMove.sinkDown,
    DepthCameraMove.parallaxRight,
  ];

  static const List<DepthCameraMove> _dynamicPool = <DepthCameraMove>[
    DepthCameraMove.spiralIn,
    DepthCameraMove.orbitRight,
    DepthCameraMove.dollyZoom,
    DepthCameraMove.pullOut,
    DepthCameraMove.parallaxLeft,
    DepthCameraMove.riseUp,
  ];

  static List<DepthCameraMove> _pool(MotionMood mood) {
    switch (mood) {
      case MotionMood.calm:
        return _calmPool;
      case MotionMood.cinematic:
        return _cinematicPool;
      case MotionMood.dynamic:
        return _dynamicPool;
    }
  }

  /// Strength of the camera for a mood: calm videos move gently.
  static double intensityFor(MotionMood mood) {
    switch (mood) {
      case MotionMood.calm:
        return 0.6;
      case MotionMood.cinematic:
        return 0.85;
      case MotionMood.dynamic:
        return 1.0;
    }
  }

  /// The move that follows [previous] in the next scene. It is never the
  /// same move, so consecutive scenes always change perspective.
  static DepthCameraMove follow(DepthCameraMove previous) {
    switch (previous) {
      case DepthCameraMove.none:
        return DepthCameraMove.pushIn;
      case DepthCameraMove.pushIn:
        return DepthCameraMove.orbitRight;
      case DepthCameraMove.pullOut:
        return DepthCameraMove.pushIn;
      case DepthCameraMove.orbitLeft:
        return DepthCameraMove.orbitRight;
      case DepthCameraMove.orbitRight:
        return DepthCameraMove.orbitLeft;
      case DepthCameraMove.parallaxLeft:
        return DepthCameraMove.parallaxRight;
      case DepthCameraMove.parallaxRight:
        return DepthCameraMove.parallaxLeft;
      case DepthCameraMove.riseUp:
        return DepthCameraMove.sinkDown;
      case DepthCameraMove.sinkDown:
        return DepthCameraMove.riseUp;
      case DepthCameraMove.dollyZoom:
        return DepthCameraMove.pullOut;
      case DepthCameraMove.spiralIn:
        return DepthCameraMove.pullOut;
      case DepthCameraMove.craneUp:
        return DepthCameraMove.craneDown;
      case DepthCameraMove.craneDown:
        return DepthCameraMove.craneUp;
      case DepthCameraMove.windowIn:
        return DepthCameraMove.windowOut;
      case DepthCameraMove.windowOut:
        return DepthCameraMove.pushIn;
    }
  }

  /// Camera of scene number [sceneIndex]. [previous] is the camera of the
  /// scene before it (null for the first scene). Deterministic for the same
  /// [variant].
  static SceneCamera forScene({
    required MotionMood mood,
    required int sceneIndex,
    int variant = 0,
    SceneCamera? previous,
  }) {
    final before = previous;
    final DepthCameraMove move;
    if (before == null || !before.isActive) {
      final pool = _pool(mood);
      move = pool[(variant.abs() + sceneIndex.abs()) % pool.length];
    } else {
      move = follow(before.move);
    }
    return SceneCamera(move: move, intensity: intensityFor(mood));
  }

  /// Same cutaway with a camera on every scene that has none. Scenes that
  /// already have a camera keep it. The input is left untouched.
  static ReferenceSceneResult upgrade(
    ReferenceSceneResult built, {
    required MotionMood mood,
    int variant = 0,
  }) {
    final source = built.project;
    final scenes = <MotionScene>[];
    SceneCamera? previous;
    for (var i = 0; i < source.scenes.length; i++) {
      final scene = source.scenes[i];
      final existing = scene.camera;
      if (existing != null) {
        scenes.add(scene);
        previous = existing;
        continue;
      }
      final camera = forScene(
        mood: mood,
        sceneIndex: i,
        variant: variant,
        previous: previous,
      );
      previous = camera;
      scenes.add(scene.withCamera(camera));
    }
    return ReferenceSceneResult(
      project: MotionProject(
        id: source.id,
        width: source.width,
        height: source.height,
        frameRate: source.frameRate,
        duration: source.duration,
        scenes: scenes,
      ),
      assets: built.assets,
    );
  }
}
