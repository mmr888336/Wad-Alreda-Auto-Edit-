/// Camera hint bridge: connects the camera hint of a story beat to the depth
/// camera and to the 3D (Filament) camera.
///
/// [StoryUnderstanding] decides, for every beat of the speech, a camera move
/// (`cameraHint`: crane reveal, push in, orbit, enter the window, arrive from
/// the window...). Before this bridge nobody read that hint: the depth camera
/// was chosen from a fixed cycle and the Filament camera from a fixed list,
/// both by scene number only.
///
/// Two consumers:
///  * [cameraFor] turns the hint of a beat into the [SceneCamera] of a motion
///    scene (the depth camera engine and the FFmpeg renderer then draw it).
///    The rules of a camera story are kept: an entry into the window is always
///    followed by its arrival shot (as zoomed in as the entry ended), an
///    arrival without an entry is a pull out, an entry with no scene after it
///    is a push in, and a move is never repeated twice in a row. The FIRST
///    scene of a cutaway is left to the cinematic director (it continues the
///    camera story of the whole export) unless it is an entry into the
///    window, which needs its arrival in the next scene.
///  * [filamentModeFor] turns the hint of the beat spoken during a 3D scene
///    into one of the camera modes the native Filament plugin supports.
///    Only those modes are ever returned (see [filamentModes]).
///
/// [enabled] switches the whole bridge off (the old behaviour then applies).
/// Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'cinematic_camera_director.dart' show CinematicCameraDirector;
import 'depth_camera_model.dart';
import 'depth_camera_planner.dart' show DepthCameraPlanner;
import 'motion_graphics.dart' show MotionMood;
import 'motion_scene_model.dart' show MotionScene;
import 'story_understanding.dart' show StoryBeat;

class CameraHintBridge {
  CameraHintBridge._();

  /// Master switch. When false [cameraFor] returns null and
  /// [filamentModeFor] returns its fallback.
  static bool enabled = true;

  /// The camera modes of the native Filament plugin that this bridge may
  /// return (a subset of what `setCameraMotion` accepts).
  static const Set<String> filamentModes = <String>{
    'orbit',
    'orbit_fast',
    'push_in',
    'pull_out',
  };

  /// The native camera mode that comes closest to [move]. The native camera
  /// can only orbit one way, push in and pull out, so sideways, rising and
  /// sinking moves become a slow orbit.
  static String filamentMode(DepthCameraMove move) {
    switch (move) {
      case DepthCameraMove.pushIn:
      case DepthCameraMove.craneDown:
      case DepthCameraMove.windowIn:
      case DepthCameraMove.dollyZoom:
        return 'push_in';
      case DepthCameraMove.pullOut:
      case DepthCameraMove.craneUp:
      case DepthCameraMove.windowOut:
        return 'pull_out';
      case DepthCameraMove.spiralIn:
        return 'orbit_fast';
      case DepthCameraMove.orbitLeft:
      case DepthCameraMove.orbitRight:
      case DepthCameraMove.parallaxLeft:
      case DepthCameraMove.parallaxRight:
      case DepthCameraMove.riseUp:
      case DepthCameraMove.sinkDown:
      case DepthCameraMove.none:
        return 'orbit';
    }
  }

  /// The camera hint of the beat that overlaps the time range [start]..[end]
  /// the most, or null when no beat overlaps it.
  static DepthCameraMove? hintFor(
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
    return best?.cameraHint;
  }

  /// The native Filament camera mode for a 3D scene shown from [start] to
  /// [end]. Returns [fallback] when the bridge is off or no beat gives a hint.
  static String filamentModeFor(
    List<StoryBeat> beats,
    double start,
    double end, {
    required String fallback,
  }) {
    if (!enabled) return fallback;
    final hint = hintFor(beats, start, end);
    if (hint == null || hint == DepthCameraMove.none) return fallback;
    return filamentMode(hint);
  }

  /// The depth camera of [scene] from the story hint [hint].
  ///
  /// [previous] is the camera this bridge gave to the scene before it inside
  /// the same cutaway (null when there is none), [hasNext] tells whether a
  /// scene follows, [isFirst] whether this is the first scene of the cutaway.
  /// Returns null when the scene should get no camera from the story (the
  /// director then plans it).
  static SceneCamera? cameraFor({
    required MotionScene scene,
    required DepthCameraMove hint,
    required MotionMood mood,
    required SceneCamera? previous,
    required bool hasNext,
    required bool isFirst,
  }) {
    if (!enabled || hint == DepthCameraMove.none) return null;

    final before = (previous != null && previous.isActive) ? previous : null;
    var move = hint;
    var intensity = DepthCameraPlanner.intensityFor(mood);

    if (before != null && before.move == DepthCameraMove.windowIn) {
      // The arrival always follows the entry and starts exactly as zoomed in
      // as the entry ended.
      move = DepthCameraMove.windowOut;
      intensity = before.intensity;
    } else {
      // An arrival with no entry before it would start zoomed in out of
      // nowhere; an entry with no scene after it has nothing to arrive in.
      if (move == DepthCameraMove.windowOut) move = DepthCameraMove.pullOut;
      if (move == DepthCameraMove.windowIn && !hasNext) {
        move = DepthCameraMove.pushIn;
      }
      // The first scene belongs to the camera story of the whole export.
      if (isFirst && move != DepthCameraMove.windowIn) return null;
      if (before != null && before.move == move) {
        move = DepthCameraPlanner.follow(move);
      }
    }

    final focus = CinematicCameraDirector.subjectPoint(scene);
    return SceneCamera(
      move: move,
      intensity: intensity,
      focusX: focus != null ? focus[0] : 0.5,
      focusY: focus != null ? focus[1] : 0.42,
    );
  }
}
