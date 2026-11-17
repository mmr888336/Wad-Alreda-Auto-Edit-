/// Renderer-neutral motion scene model: layers with local-time keyframes,
/// scenes with a background and an entry transition, and a validated project.
///
/// All positions are normalized to the canvas (0..1). Keyframe times are
/// local to their layer (seconds from the layer start), matching the Motion
/// Smith reference manifests.
library;

import 'dart:math' as math;

import 'motion_transitions.dart';

enum MotionEase { linear, easeOut, easeInOut, overshoot }

class MotionEasing {
  MotionEasing._();

  /// Maps progress [t] (clamped to 0..1) through the easing curve.
  static double apply(MotionEase ease, double t) {
    final x = t.isNaN ? 0.0 : t.clamp(0.0, 1.0).toDouble();
    switch (ease) {
      case MotionEase.linear:
        return x;
      case MotionEase.easeOut:
        return 1 - math.pow(1 - x, 3).toDouble();
      case MotionEase.easeInOut:
        return 0.5 - 0.5 * math.cos(math.pi * x);
      case MotionEase.overshoot:
        const c1 = 1.70158;
        const c3 = c1 + 1;
        final p = x - 1;
        return 1 + c3 * p * p * p + c1 * p * p;
    }
  }
}

class MotionKeyframe {
  /// Local time in seconds from the start of the layer.
  final double time;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final double opacity;

  /// Easing used when interpolating from the previous keyframe to this one.
  final MotionEase easing;

  const MotionKeyframe({
    required this.time,
    required this.x,
    required this.y,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.easing = MotionEase.easeInOut,
  });
}

class MotionLayerState {
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final double opacity;

  const MotionLayerState({
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.opacity,
  });
}

class MotionLayer {
  final String id;
  final double start;
  final double end;
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final double opacity;
  final int zIndex;

  /// Key of a sprite or image asset, for example `pixel_camera`.
  final String? assetKey;
  final String? text;
  final List<MotionKeyframe> keyframes;

  const MotionLayer({
    required this.id,
    required this.start,
    required this.end,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
    this.zIndex = 0,
    this.assetKey,
    this.text,
    this.keyframes = const <MotionKeyframe>[],
  });

  double get duration => end - start;

  bool isActiveAt(double seconds) => seconds >= start && seconds < end;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static MotionLayerState _fromKey(MotionKeyframe k) => MotionLayerState(
        x: k.x,
        y: k.y,
        scale: k.scale,
        rotation: k.rotation,
        opacity: k.opacity.clamp(0.0, 1.0).toDouble(),
      );

  /// Interpolated state at timeline time [seconds]. Before the first
  /// keyframe and after the last one the nearest keyframe is held.
  MotionLayerState stateAt(double seconds) {
    if (keyframes.isEmpty) {
      return MotionLayerState(
        x: x,
        y: y,
        scale: scale,
        rotation: rotation,
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
      );
    }
    final local = seconds - start;
    final first = keyframes.first;
    final last = keyframes.last;
    if (local <= first.time) return _fromKey(first);
    if (local >= last.time) return _fromKey(last);

    for (var i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (local >= a.time && local < b.time) {
        final span = b.time - a.time;
        final u = span <= 0 ? 1.0 : (local - a.time) / span;
        final e = MotionEasing.apply(b.easing, u);
        return MotionLayerState(
          x: _lerp(a.x, b.x, e),
          y: _lerp(a.y, b.y, e),
          scale: _lerp(a.scale, b.scale, e),
          rotation: _lerp(a.rotation, b.rotation, e),
          opacity: _lerp(a.opacity, b.opacity, e).clamp(0.0, 1.0).toDouble(),
        );
      }
    }
    return _fromKey(last);
  }
}

class MotionScene {
  final String id;
  final double start;
  final double end;

  /// Background colour as `#RRGGBB`.
  final String background;
  final MotionTransitionKind transitionIn;
  final List<MotionLayer> layers;

  const MotionScene({
    required this.id,
    required this.start,
    required this.end,
    required this.layers,
    this.background = '#000000',
    this.transitionIn = MotionTransitionKind.hardCut,
  });

  double get duration => end - start;

  bool isActiveAt(double seconds) => seconds >= start && seconds < end;
}

class MotionProject {
  final String id;
  final int width;
  final int height;
  final int frameRate;
  final double duration;
  final List<MotionScene> scenes;

  const MotionProject({
    required this.id,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.duration,
    required this.scenes,
  });

  /// Layers visible at [seconds], lowest zIndex first.
  List<MotionLayer> layersAt(double seconds) {
    final result = <MotionLayer>[];
    for (final scene in scenes) {
      if (!scene.isActiveAt(seconds)) continue;
      for (final layer in scene.layers) {
        if (layer.isActiveAt(seconds)) result.add(layer);
      }
    }
    result.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return result;
  }

  /// Throws [StateError] for an invalid canvas, overlapping scenes, layers
  /// outside their scene, or keyframes outside their layer.
  void validate() {
    if (width <= 0 || height <= 0 || frameRate <= 0 || duration <= 0) {
      throw StateError('Invalid canvas or project duration.');
    }
    var previousEnd = 0.0;
    for (final scene in scenes) {
      if (scene.start < 0 || scene.end <= scene.start || scene.end > duration) {
        throw StateError('Invalid scene range: ${scene.id}');
      }
      if (scene.start < previousEnd - 0.001) {
        throw StateError('Overlapping scene ranges: ${scene.id}');
      }
      previousEnd = scene.end;
      for (final layer in scene.layers) {
        if (layer.end <= layer.start ||
            layer.start < scene.start ||
            layer.end > scene.end) {
          throw StateError('Invalid layer range: ${layer.id}');
        }
        if (layer.keyframes.isNotEmpty &&
            layer.keyframes.last.time > layer.duration + 0.001) {
          throw StateError('Keyframe outside layer duration: ${layer.id}');
        }
      }
    }
  }
}
