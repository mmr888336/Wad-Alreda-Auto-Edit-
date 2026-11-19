/// Data model of the depth camera (camera and depth motion phase).
///
/// A [SceneCamera] describes ONE virtual camera move for a whole motion
/// scene. The layers of a scene sit at different depths, so the same move
/// shifts and scales near layers more than far ones (parallax) instead of
/// just sliding every element across the screen. Pure Dart, no I/O.
library;

/// Camera moves. Names describe what the nearest layers do on screen.
enum DepthCameraMove {
  /// No camera movement.
  none,

  /// Camera moves toward the subject: near layers grow faster than far ones.
  pushIn,

  /// Camera moves away from the subject, ending on the normal framing.
  pullOut,

  /// Orbit: near layers sweep to the left while far layers sweep to the right.
  orbitLeft,

  /// Orbit: near layers sweep to the right while far layers sweep to the left.
  orbitRight,

  /// Camera trucks sideways: every layer drifts left, near layers travel more.
  parallaxLeft,

  /// Camera trucks sideways: every layer drifts right, near layers travel more.
  parallaxRight,

  /// Every layer drifts upward, near layers travel more.
  riseUp,

  /// Every layer drifts downward, near layers travel more.
  sinkDown,

  /// Perspective change: far layers grow while near layers shrink.
  dollyZoom,

  /// Push in while orbiting and rising: the strongest depth effect.
  spiralIn,

  /// Crane up: the camera rises and pulls back, so the scene opens up and
  /// settles on the normal framing. Near layers sink more than far ones.
  craneUp,

  /// Crane down: the camera descends and pushes in. Near layers rise more
  /// than far ones.
  craneDown,

  /// Enter the window: the camera dives into the subject, near layers fly
  /// past it. Meant to be followed by [windowOut] in the next scene.
  windowIn,

  /// Arrival after [windowIn]: the scene starts zoomed in, as the previous
  /// one ended, and pulls out into the new world.
  windowOut,
}

/// The camera of one motion scene.
class SceneCamera {
  final DepthCameraMove move;

  /// Strength of the move, 0..[maxIntensity]. 1 is a full move.
  final double intensity;

  /// Focus point (normalised canvas coordinates) the zoom is centred on.
  final double focusX;
  final double focusY;

  const SceneCamera({
    this.move = DepthCameraMove.none,
    this.intensity = 0.8,
    this.focusX = 0.5,
    this.focusY = 0.42,
  });

  static const double maxIntensity = 1.5;

  /// False for "no move" or a zero intensity: nothing is rendered then.
  bool get isActive =>
      move != DepthCameraMove.none && intensity.isFinite && intensity > 0.001;

  SceneCamera copyWith({
    DepthCameraMove? move,
    double? intensity,
    double? focusX,
    double? focusY,
  }) {
    return SceneCamera(
      move: move ?? this.move,
      intensity: intensity ?? this.intensity,
      focusX: focusX ?? this.focusX,
      focusY: focusY ?? this.focusY,
    );
  }
}
