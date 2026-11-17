/// Depth camera engine: camera and depth motion for motion scenes.
///
/// Instead of sliding every element across the screen, a [SceneCamera] moves
/// ONE virtual camera and every layer reacts according to its depth
/// (0 = far background, 1 = nearest foreground):
///  * zoom: near layers grow faster than far ones (push in / pull out);
///  * orbit: near layers sweep one way while far layers sweep the other way
///    around the focus plane (depth 0.5);
///  * parallax: the camera trucks sideways, near layers travel farther;
///  * rise / sink: the same idea on the vertical axis;
///  * dolly zoom: the perspective changes (far layers grow, near ones shrink).
///
/// The same maths drives the FFmpeg renderer ([expressions]) and the editor
/// preview ([transformState]), so the preview matches the export.
/// Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'depth_camera_model.dart';
import 'motion_scene_model.dart';

/// Normalised path of a move. Zoom values are factors (1 = none); the other
/// values are -1..1 and are scaled by the camera intensity.
class DepthCameraPath {
  final double zoomStart;
  final double zoomEnd;
  final double orbitStart;
  final double orbitEnd;
  final double panStart;
  final double panEnd;
  final double liftStart;
  final double liftEnd;

  /// Perspective change strength (far layers grow, near layers shrink).
  final double dolly;

  const DepthCameraPath({
    this.zoomStart = 1,
    this.zoomEnd = 1,
    this.orbitStart = 0,
    this.orbitEnd = 0,
    this.panStart = 0,
    this.panEnd = 0,
    this.liftStart = 0,
    this.liftEnd = 0,
    this.dolly = 0,
  });
}

/// The camera effect on one layer at one moment.
class CameraSample {
  /// Zoom about the focus point, applied to the layer position offset.
  final double zoom;

  /// Extra offset (normalised canvas units) from orbit, parallax and lift.
  final double dx;
  final double dy;

  /// Extra size factor from the perspective change.
  final double scaleMul;

  const CameraSample({
    required this.zoom,
    required this.dx,
    required this.dy,
    required this.scaleMul,
  });

  /// Total size factor of the layer.
  double get layerScale => zoom * scaleMul;
}

/// FFmpeg expressions for one layer under a scene camera. `t` inside them is
/// the scene-local time in seconds.
class LayerCameraExpressions {
  final String x;
  final String y;
  final String scale;

  const LayerCameraExpressions({
    required this.x,
    required this.y,
    required this.scale,
  });
}

class _Coeffs {
  // zoom = 1 + zk0 + zk1 * e
  final double zk0;
  final double zk1;
  // dx = dx0 + dx1 * e, dy = dy0 + dy1 * e
  final double dx0;
  final double dx1;
  final double dy0;
  final double dy1;
  // scaleMul = 1 + m1 * e
  final double m1;

  const _Coeffs({
    required this.zk0,
    required this.zk1,
    required this.dx0,
    required this.dx1,
    required this.dy0,
    required this.dy1,
    required this.m1,
  });
}

class DepthCameraEngine {
  DepthCameraEngine._();

  // Far layers follow the zoom by _zoomBase, the nearest by _zoomBase +
  // _zoomGain (1.0): that difference is the depth impression.
  static const double _zoomBase = 0.55;
  static const double _zoomGain = 0.45;
  static const double _orbitAmp = 0.07;
  static const double _orbitLift = 0.3;
  static const double _panAmp = 0.06;
  static const double _liftAmp = 0.05;
  static const double _depthFloor = 0.2;

  /// Largest overscan given to a full-canvas background layer.
  static const double maxCoverScale = 1.8;

  static String _n(double value) => value.toStringAsFixed(3);

  /// Number for use inside an FFmpeg expression (negatives are wrapped, and
  /// values that round to zero are written as plain 0).
  static String _num(double value) {
    final safe = value.isFinite && value.abs() >= 0.00005 ? value : 0.0;
    final text = safe.toStringAsFixed(4);
    return safe < 0 ? '($text)' : text;
  }

  static double _focus(double value, double fallback) =>
      value.isFinite ? value.clamp(0.0, 1.0).toDouble() : fallback;

  /// The path of [move] at full intensity.
  static DepthCameraPath pathFor(DepthCameraMove move) {
    switch (move) {
      case DepthCameraMove.none:
        return const DepthCameraPath();
      case DepthCameraMove.pushIn:
        return const DepthCameraPath(zoomEnd: 1.22);
      case DepthCameraMove.pullOut:
        return const DepthCameraPath(zoomStart: 1.22);
      case DepthCameraMove.orbitLeft:
        return const DepthCameraPath(
          zoomEnd: 1.06,
          orbitStart: 1,
          orbitEnd: -1,
        );
      case DepthCameraMove.orbitRight:
        return const DepthCameraPath(
          zoomEnd: 1.06,
          orbitStart: -1,
          orbitEnd: 1,
        );
      case DepthCameraMove.parallaxLeft:
        return const DepthCameraPath(panStart: -1, panEnd: 1);
      case DepthCameraMove.parallaxRight:
        return const DepthCameraPath(panStart: 1, panEnd: -1);
      case DepthCameraMove.riseUp:
        return const DepthCameraPath(
          zoomEnd: 1.04,
          liftStart: -1,
          liftEnd: 1,
        );
      case DepthCameraMove.sinkDown:
        return const DepthCameraPath(
          zoomEnd: 1.04,
          liftStart: 1,
          liftEnd: -1,
        );
      case DepthCameraMove.dollyZoom:
        return const DepthCameraPath(zoomEnd: 1.15, dolly: 0.15);
      case DepthCameraMove.spiralIn:
        return const DepthCameraPath(
          zoomEnd: 1.2,
          orbitStart: -1,
          orbitEnd: 1,
          liftStart: 0.5,
          liftEnd: -0.5,
        );
    }
  }

  /// Smooth ease-in-out of a 0..1 progress.
  static double ease(double progress) {
    final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0).toDouble();
    return 0.5 - 0.5 * math.cos(math.pi * p);
  }

  static _Coeffs _coeffs(SceneCamera camera, double depth) {
    final i = camera.intensity.isFinite
        ? camera.intensity.clamp(0.0, SceneCamera.maxIntensity).toDouble()
        : 0.0;
    final d = depth.isFinite ? depth.clamp(0.0, 1.0).toDouble() : 0.5;
    final path = pathFor(camera.move);

    final zoomFactor = _zoomBase + _zoomGain * d;
    final z0 = 1 + (path.zoomStart - 1) * i;
    final z1 = 1 + (path.zoomEnd - 1) * i;
    final depthFactor = _depthFloor + (1 - _depthFloor) * d;
    final orbitK = _orbitAmp * i * (2 * d - 1);
    final panK = -_panAmp * i * depthFactor;
    final liftK = -_liftAmp * i * depthFactor;
    final orbitSpan = path.orbitEnd - path.orbitStart;

    return _Coeffs(
      zk0: zoomFactor * (z0 - 1),
      zk1: zoomFactor * (z1 - z0),
      dx0: orbitK * path.orbitStart + panK * path.panStart,
      dx1: orbitK * orbitSpan + panK * (path.panEnd - path.panStart),
      dy0: orbitK * _orbitLift * path.orbitStart + liftK * path.liftStart,
      dy1: orbitK * _orbitLift * orbitSpan +
          liftK * (path.liftEnd - path.liftStart),
      m1: path.dolly * i * (1 - 2 * d),
    );
  }

  /// The camera effect on a layer at [depth] (0 far .. 1 near) when the move
  /// is [progress] (0..1) complete.
  static CameraSample sample({
    required SceneCamera camera,
    required double depth,
    required double progress,
  }) {
    final c = _coeffs(camera, depth);
    final e = ease(progress);
    return CameraSample(
      zoom: 1 + c.zk0 + c.zk1 * e,
      dx: c.dx0 + c.dx1 * e,
      dy: c.dy0 + c.dy1 * e,
      scaleMul: 1 + c.m1 * e,
    );
  }

  /// Depth of [layer] inside [scene]: 0 far .. 1 near.
  ///
  /// An explicit [MotionLayer.depth] wins. Otherwise the depth follows the
  /// asset key convention of the scene builder (`bg:` far, `decor:` and
  /// `sprite:` in the middle, `text:` in front) and, for any other layer, its
  /// stacking order.
  static double depthOf(MotionScene scene, MotionLayer layer) {
    final explicit = layer.depth;
    if (explicit != null && explicit.isFinite) {
      return explicit.clamp(0.0, 1.0).toDouble();
    }
    final key = layer.assetKey ?? '';
    if (key.startsWith('bg:fx')) return 0.12;
    if (key.startsWith('bg:')) return 0.0;
    if (key.startsWith('decor:')) return 0.38;
    if (key.startsWith('sprite:')) return 0.62;

    final ranked = <MotionLayer>[
      for (final other in scene.layers)
        if (!(other.assetKey ?? '').startsWith('bg:')) other,
    ];
    ranked.sort((a, b) {
      final byZ = a.zIndex.compareTo(b.zIndex);
      return byZ != 0 ? byZ : a.id.compareTo(b.id);
    });
    var rankDepth = 0.7;
    if (ranked.length > 1) {
      var index = ranked.indexWhere((other) => other.id == layer.id);
      if (index < 0) index = 0;
      rankDepth = 0.3 + 0.7 * index / (ranked.length - 1);
    }
    if (key.startsWith('text:') && rankDepth < 0.8) return 0.8;
    return rankDepth;
  }

  /// Layer state after the scene camera, for the editor preview.
  static MotionLayerState transformState({
    required SceneCamera camera,
    required double depth,
    required double progress,
    required MotionLayerState state,
  }) {
    final s = sample(camera: camera, depth: depth, progress: progress);
    final fx = _focus(camera.focusX, 0.5);
    final fy = _focus(camera.focusY, 0.42);
    return MotionLayerState(
      x: fx + (state.x - fx) * s.zoom + s.dx,
      y: fy + (state.y - fy) * s.zoom + s.dy,
      scale: state.scale * s.layerScale,
      rotation: state.rotation,
      opacity: state.opacity,
    );
  }

  /// [state] of [layer] at timeline time [time] with the camera of [scene]
  /// applied. Scenes without an active camera return [state] unchanged.
  static MotionLayerState applyToLayer({
    required MotionScene scene,
    required MotionLayer layer,
    required MotionLayerState state,
    required double time,
  }) {
    final camera = scene.camera;
    if (camera == null || !camera.isActive) return state;
    final span = scene.duration;
    final progress = span <= 0 ? 0.0 : (time - scene.start) / span;
    return transformState(
      camera: camera,
      depth: depthOf(scene, layer),
      progress: progress,
      state: state,
    );
  }

  /// Size factor that keeps a full-canvas background layer covering the whole
  /// canvas for the entire move, so its edges never show.
  static double coverScale(SceneCamera camera, double depth) {
    if (!camera.isActive) return 1.0;
    final fx = _focus(camera.focusX, 0.5);
    final fy = _focus(camera.focusY, 0.42);
    var worst = 1.0;
    for (var i = 0; i <= 20; i++) {
      final s = sample(camera: camera, depth: depth, progress: i / 20);
      final cx = fx + (0.5 - fx) * s.zoom + s.dx;
      final cy = fy + (0.5 - fy) * s.zoom + s.dy;
      final shift = math.max((cx - 0.5).abs(), (cy - 0.5).abs());
      final size = s.layerScale <= 0.05 ? 0.05 : s.layerScale;
      final need = (1 + 2 * shift) / size;
      if (need > worst) worst = need;
    }
    return (worst + 0.02).clamp(1.0, maxCoverScale).toDouble();
  }

  /// FFmpeg expressions that apply the scene camera to one layer.
  ///
  /// [xExpr], [yExpr] and [scaleExpr] are the layer's own animated position
  /// (normalised) and size expressions; [duration] is the scene length. Set
  /// [fullBleed] for a full-canvas background so it is enlarged enough to
  /// cover the canvas during the move.
  static LayerCameraExpressions expressions({
    required SceneCamera camera,
    required double depth,
    required double duration,
    required String xExpr,
    required String yExpr,
    required String scaleExpr,
    bool fullBleed = false,
  }) {
    final c = _coeffs(camera, depth);
    final span =
        duration.isFinite ? duration.clamp(0.12, 600.0).toDouble() : 0.12;
    final progress = 'min(1,max(0,t/${_n(span)}))';
    final e = '(0.5-0.5*cos(PI*$progress))';
    final zoom = '(1+${_num(c.zk0)}+${_num(c.zk1)}*$e)';
    final fx = _num(_focus(camera.focusX, 0.5));
    final fy = _num(_focus(camera.focusY, 0.42));
    final x =
        '($fx+(($xExpr)-$fx)*$zoom+(${_num(c.dx0)}+${_num(c.dx1)}*$e))';
    final y =
        '($fy+(($yExpr)-$fy)*$zoom+(${_num(c.dy0)}+${_num(c.dy1)}*$e))';
    final cover = fullBleed ? '*${_num(coverScale(camera, depth))}' : '';
    final scale = '(($scaleExpr)*$zoom*(1+${_num(c.m1)}*$e)$cover)';
    return LayerCameraExpressions(x: x, y: y, scale: scale);
  }
}
