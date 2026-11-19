/// Cinematic camera director.
///
/// The old planner picked a camera move per scene from a pool, so the camera
/// had no logic behind it. The director plans the camera of the WHOLE video
/// like a film shot list, in scene order:
///
///  * the first shot of the video is a crane reveal (the world opens up);
///  * after it the shots follow a fixed cycle: dolly in/out, orbit, crane,
///    then "enter the window" (the camera dives into the subject) followed
///    by the matching arrival shot in the next scene (it starts zoomed in
///    and pulls out into the new world);
///  * the cycle continues across cutaways of one export (see
///    [CameraDirectorMemory]), so the video keeps one camera story;
///  * inside one cutaway every shot starts where the previous one ended
///    (zoom, orbit, pan and lift are matched), so the last framing of a
///    scene is carried into the first framing of the next one;
///  * the zoom is centred on the subject (the sprite) of the scene.
///
/// Only the existing [SceneCamera] model is used, so the editor, the JSON
/// sidecar and the FFmpeg renderer work unchanged. Pure Dart, no I/O.
library;

import 'depth_camera_engine.dart';
import 'depth_camera_model.dart';
import 'depth_camera_planner.dart';
import 'motion_graphics.dart' show MotionMood;
import 'motion_scene_model.dart';
import 'reference_scene_builder.dart' show ReferenceSceneResult;

/// What a shot is for in the story of the video.
enum ShotRole { establish, dolly, orbit, crane, windowIn, windowOut }

/// Position of the camera story inside one export.
class CameraDirectorState {
  /// Number of scenes that already got a camera in this export.
  int count = 0;
}

/// Remembers the camera story of the current export, so the shot cycle goes
/// on from one cutaway to the next. A new export has a new `stamp`, which
/// starts the story again with the opening crane shot.
class CameraDirectorMemory {
  CameraDirectorMemory._();

  static int? _stamp;
  static CameraDirectorState _state = CameraDirectorState();

  /// The story state of the export [stamp] (fresh for a new export).
  static CameraDirectorState stateFor(int stamp) {
    if (_stamp != stamp) {
      _stamp = stamp;
      _state = CameraDirectorState();
    }
    return _state;
  }

  /// Forgets everything.
  static void reset() {
    _stamp = null;
    _state = CameraDirectorState();
  }
}

class CinematicCameraDirector {
  CinematicCameraDirector._();

  /// Shots after the opening one, in order. The arrival shot of a window
  /// entry is not listed: it is forced right after [ShotRole.windowIn].
  static const List<ShotRole> _cycle = <ShotRole>[
    ShotRole.dolly,
    ShotRole.orbit,
    ShotRole.crane,
    ShotRole.windowIn,
    ShotRole.orbit,
  ];

  /// The moves each role may use (the first one is the default).
  static List<DepthCameraMove> candidates(ShotRole role) {
    switch (role) {
      case ShotRole.establish:
        return const <DepthCameraMove>[
          DepthCameraMove.craneUp,
          DepthCameraMove.pullOut,
        ];
      case ShotRole.dolly:
        return const <DepthCameraMove>[
          DepthCameraMove.pushIn,
          DepthCameraMove.pullOut,
        ];
      case ShotRole.orbit:
        return const <DepthCameraMove>[
          DepthCameraMove.orbitRight,
          DepthCameraMove.orbitLeft,
        ];
      case ShotRole.crane:
        return const <DepthCameraMove>[
          DepthCameraMove.craneUp,
          DepthCameraMove.craneDown,
        ];
      case ShotRole.windowIn:
        return const <DepthCameraMove>[DepthCameraMove.windowIn];
      case ShotRole.windowOut:
        return const <DepthCameraMove>[DepthCameraMove.windowOut];
    }
  }

  /// The role of the scene number [order] of the export.
  ///
  /// [previous] is the camera of the scene before it INSIDE THE SAME
  /// cutaway (null for the first scene of a cutaway). A window entry needs a
  /// scene after it to arrive in, so [hasNext] false turns it into a dolly.
  static ShotRole roleFor({
    required int order,
    required SceneCamera? previous,
    required bool hasNext,
  }) {
    if (previous != null && previous.move == DepthCameraMove.windowIn) {
      return ShotRole.windowOut;
    }
    if (order <= 0) return ShotRole.establish;
    final role = _cycle[(order - 1) % _cycle.length];
    if (role == ShotRole.windowIn && !hasNext) return ShotRole.dolly;
    return role;
  }

  // The framing a move starts and ends on, at [intensity]:
  // zoom, orbit, pan, lift.
  static List<double> _start(DepthCameraMove move, double intensity) {
    final p = DepthCameraEngine.pathFor(move);
    return <double>[
      1 + (p.zoomStart - 1) * intensity,
      p.orbitStart,
      p.panStart,
      p.liftStart,
    ];
  }

  static List<double> _end(DepthCameraMove move, double intensity) {
    final p = DepthCameraEngine.pathFor(move);
    return <double>[
      1 + (p.zoomEnd - 1) * intensity,
      p.orbitEnd,
      p.panEnd,
      p.liftEnd,
    ];
  }

  /// How far the start of a shot is from the end of the one before it.
  /// Zoom counts most: a jump in size is what the eye notices first.
  static double _gap(List<double> end, List<double> start) {
    return 4.0 * (end[0] - start[0]).abs() +
        0.4 * ((end[1] - start[1]).abs() +
            (end[2] - start[2]).abs() +
            (end[3] - start[3]).abs());
  }

  /// The move for [role]. Without a [previous] shot it is chosen by [order]
  /// (deterministic). With one, the candidate that starts closest to where
  /// the previous shot ended wins, and a move is never repeated.
  static DepthCameraMove pickMove({
    required ShotRole role,
    required int order,
    required SceneCamera? previous,
    required double intensity,
  }) {
    final options = candidates(role);
    if (previous == null || !previous.isActive) {
      return options[order.abs() % options.length];
    }
    final end = _end(previous.move, previous.intensity);
    DepthCameraMove? best;
    var bestGap = double.infinity;
    for (final move in options) {
      if (move == previous.move && options.length > 1) continue;
      final gap = _gap(end, _start(move, intensity));
      if (gap < bestGap - 1e-9) {
        bestGap = gap;
        best = move;
      }
    }
    return best ?? options.first;
  }

  /// Where the zoom of [scene] is centred: the resting place of its sprite,
  /// or null when the scene has none.
  static List<double>? subjectPoint(MotionScene scene) {
    for (final layer in scene.layers) {
      final key = layer.assetKey ?? '';
      if (!key.startsWith('sprite:') && !layer.id.endsWith('_sprite')) {
        continue;
      }
      final s = layer.stateAt(layer.end);
      if (!s.x.isFinite || !s.y.isFinite) continue;
      return <double>[
        s.x.clamp(0.15, 0.85).toDouble(),
        s.y.clamp(0.15, 0.85).toDouble(),
      ];
    }
    return null;
  }

  /// The camera of [scene].
  static SceneCamera cameraFor({
    required MotionScene scene,
    required MotionMood mood,
    required int order,
    required SceneCamera? previous,
    required bool hasNext,
  }) {
    final role = roleFor(order: order, previous: previous, hasNext: hasNext);
    var intensity = DepthCameraPlanner.intensityFor(mood);
    if (role == ShotRole.windowOut && previous != null) {
      // The arrival starts exactly as zoomed in as the entry ended.
      intensity = previous.intensity;
    }
    final move = pickMove(
      role: role,
      order: order,
      previous: previous,
      intensity: intensity,
    );
    final focus = subjectPoint(scene);
    return SceneCamera(
      move: move,
      intensity: intensity,
      focusX: focus != null ? focus[0] : 0.5,
      focusY: focus != null ? focus[1] : 0.42,
    );
  }

  /// Same cutaway with a camera on every scene that has none, planned as one
  /// shot list. Scenes that already have a camera keep it. [state] carries
  /// the camera story from one cutaway to the next (see
  /// [CameraDirectorMemory]); without it the story starts here. The input
  /// is left untouched.
  static ReferenceSceneResult upgrade(
    ReferenceSceneResult built, {
    required MotionMood mood,
    CameraDirectorState? state,
  }) {
    final story = state ?? CameraDirectorState();
    final source = built.project;
    final scenes = <MotionScene>[];
    SceneCamera? previous;
    for (var i = 0; i < source.scenes.length; i++) {
      final scene = source.scenes[i];
      final existing = scene.camera;
      if (existing != null) {
        scenes.add(scene);
        previous = existing;
        story.count++;
        continue;
      }
      final camera = cameraFor(
        scene: scene,
        mood: mood,
        order: story.count,
        previous: previous,
        hasNext: i < source.scenes.length - 1,
      );
      previous = camera;
      story.count++;
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
