/// Camera rig: a real 3D camera move for the existing Filament plugin.
///
/// The native viewer (`ModelViewer`) owns its camera: it can only run presets
/// (orbit, push in, pull out...) and it rescales every loaded model into a unit
/// cube. A free camera path therefore cannot be sent to it. Instead the GLB of
/// the world carries ONE animation on a parent node (the "rig") that moves the
/// whole world by the INVERSE of the camera move. The fixed native camera then
/// sees exactly what the virtual camera of [World3DCameraPath] would see, and
/// the plugin already plays glTF animations, so no native code changes.
///
/// The maths, for a virtual camera at position p with basis rows (right, up,
/// back): a world point P must land on the native camera as
///
///     R(P) = eye + Rot * (P - p)        (Rot = rows right, up, back)
///
/// where `eye` is the fixed native eye expressed in world units. The native
/// model transform (`transformToUnitCube`) is
/// `native = (world - center) * scale + (0, 0, -4)`, so
/// `eye = center + (0, 0, 5 / scale)`. Both the camera space and the native
/// space differ only by that uniform scale, which a perspective projection
/// does not see.
///
/// What this needs from the device (see docs/3d_native_camera_rig_AR.md): the
/// native vertical field of view ([World3DNativeCamera.verticalFovDegrees]),
/// the unit-cube normalisation, and `setCameraMotion('manual')` before the
/// capture. The field of view of the camera path is NOT animated (the dolly
/// zoom keeps the dolly but loses the lens change).
/// Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'world3d_model.dart';

/// What the native `ModelViewer` camera is, as set up by FilamentRendererPlugin.
class World3DNativeCamera {
  World3DNativeCamera._();

  /// `ModelViewer.cameraFocalLength` (28 mm) on Filament's 24 mm sensor height.
  static const double focalLengthMm = 28.0;
  static const double sensorHeightMm = 24.0;

  /// The orbit home position and target of the plugin's manipulator.
  static const Vec3 eye = Vec3(0, 0, 1);
  static const Vec3 target = Vec3(0, 0, -4);

  /// `transformToUnitCube` scales the longest side of the model to this.
  static const double unitCubeExtent = 2.0;

  static double get verticalFovDegrees =>
      2 * math.atan(sensorHeightMm / (2 * focalLengthMm)) * 180 / math.pi;

  /// A stage whose lens equals the native camera, so a layout planned on it
  /// is seen by the native camera exactly as designed.
  static World3DStage stage({double aspect = 9 / 16}) =>
      World3DStage(aspect: aspect, verticalFovDegrees: verticalFovDegrees);
}

/// Axis-aligned bounds of the world, as the native loader sees them.
class World3DBounds {
  final Vec3 min;
  final Vec3 max;

  const World3DBounds(this.min, this.max);

  Vec3 get center => Vec3(
        (min.x + max.x) / 2,
        (min.y + max.y) / 2,
        (min.z + max.z) / 2,
      );

  double get maxExtent =>
      math.max(max.x - min.x, math.max(max.y - min.y, max.z - min.z));

  /// The scale `transformToUnitCube` applies.
  double get unitCubeScale =>
      maxExtent <= 1e-9 ? 1.0 : World3DNativeCamera.unitCubeExtent / maxExtent;

  /// Where a world point ends up inside the native viewer.
  Vec3 toNative(Vec3 point) =>
      (point - center).scaled(unitCubeScale) + World3DNativeCamera.target;
}

/// Keyframes of the rig node: translation and rotation (x, y, z, w).
class World3DRigAnimation {
  final List<double> times;
  final List<Vec3> translations;
  final List<List<double>> rotations;

  const World3DRigAnimation({
    required this.times,
    required this.translations,
    required this.rotations,
  });

  int get length => times.length;

  double get duration => times.isEmpty ? 0.0 : times.last;
}

class World3DRig {
  World3DRig._();

  /// The fixed native eye, in world units.
  static Vec3 nativeEyeInWorld(World3DBounds bounds) {
    final distance =
        (World3DNativeCamera.eye.z - World3DNativeCamera.target.z) /
            bounds.unitCubeScale;
    return bounds.center + Vec3(0, 0, distance);
  }

  /// Rotation as a quaternion (x, y, z, w) of the matrix whose rows are
  /// [right], [up] and [back].
  static List<double> quaternionOf(Vec3 right, Vec3 up, Vec3 back) {
    final m00 = right.x;
    final m01 = right.y;
    final m02 = right.z;
    final m10 = up.x;
    final m11 = up.y;
    final m12 = up.z;
    final m20 = back.x;
    final m21 = back.y;
    final m22 = back.z;
    final trace = m00 + m11 + m22;
    double x;
    double y;
    double z;
    double w;
    if (trace > 0) {
      final s = 0.5 / math.sqrt(trace + 1.0);
      w = 0.25 / s;
      x = (m21 - m12) * s;
      y = (m02 - m20) * s;
      z = (m10 - m01) * s;
    } else if (m00 > m11 && m00 > m22) {
      final s = 2.0 * math.sqrt(1.0 + m00 - m11 - m22);
      w = (m21 - m12) / s;
      x = 0.25 * s;
      y = (m01 + m10) / s;
      z = (m02 + m20) / s;
    } else if (m11 > m22) {
      final s = 2.0 * math.sqrt(1.0 + m11 - m00 - m22);
      w = (m02 - m20) / s;
      x = (m01 + m10) / s;
      y = 0.25 * s;
      z = (m12 + m21) / s;
    } else {
      final s = 2.0 * math.sqrt(1.0 + m22 - m00 - m11);
      w = (m10 - m01) / s;
      x = (m02 + m20) / s;
      y = (m12 + m21) / s;
      z = 0.25 * s;
    }
    final length = math.sqrt(x * x + y * y + z * z + w * w);
    return <double>[x / length, y / length, z / length, w / length];
  }

  /// Rotates [v] by the quaternion [q] (x, y, z, w).
  static Vec3 rotate(List<double> q, Vec3 v) {
    final qv = Vec3(q[0], q[1], q[2]);
    final w = q[3];
    final t = _cross(qv, v).scaled(2);
    return v + t.scaled(w) + _cross(qv, t);
  }

  static Vec3 _cross(Vec3 a, Vec3 b) => Vec3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
      );

  /// The transform of the rig node that makes the fixed native camera see the
  /// world the way [pose] would. Null when the pose has no usable direction.
  static ({Vec3 translation, List<double> rotation})? rigFor(
    World3DCameraPose pose,
    World3DBounds bounds,
  ) {
    final forward = pose.target - pose.position;
    final length = forward.length;
    if (length < 1e-9) return null;
    final f = forward.scaled(1 / length);

    final rightLength = math.sqrt(f.x * f.x + f.z * f.z);
    if (rightLength < 1e-9) return null;
    final right = Vec3(-f.z / rightLength, 0, f.x / rightLength);
    final up = Vec3(
      right.y * f.z - right.z * f.y,
      right.z * f.x - right.x * f.z,
      right.x * f.y - right.y * f.x,
    );
    final back = f.scaled(-1);

    final rotated = Vec3(
      right.dot(pose.position),
      up.dot(pose.position),
      back.dot(pose.position),
    );
    return (
      translation: nativeEyeInWorld(bounds) - rotated,
      rotation: quaternionOf(right, up, back),
    );
  }

  /// The rig animation of a camera path: [holdStart] seconds at the first
  /// pose (the capture needs a moment to start), the move over [duration]
  /// seconds sampled [fps] times a second, then [holdEnd] seconds at the last
  /// pose. The native player loops the animation, so the whole length should
  /// be longer than the capture.
  static World3DRigAnimation build({
    required World3DCameraPath path,
    required World3DBounds bounds,
    required double duration,
    double holdStart = 0.5,
    double holdEnd = 0.5,
    int fps = 30,
  }) {
    final span = duration.isFinite ? duration.clamp(0.5, 30.0).toDouble() : 3.0;
    final head = holdStart.isFinite ? holdStart.clamp(0.0, 5.0).toDouble() : 0.0;
    final tail = holdEnd.isFinite ? holdEnd.clamp(0.0, 5.0).toDouble() : 0.0;
    final rate = fps < 5 ? 5 : (fps > 60 ? 60 : fps);
    final steps = math.max(2, (span * rate).round());

    final times = <double>[];
    final translations = <Vec3>[];
    final rotations = <List<double>>[];

    void key(double time, double progress) {
      final rig = rigFor(path.poseAt(progress), bounds);
      if (rig == null) return;
      var q = rig.rotation;
      if (rotations.isNotEmpty) {
        final p = rotations.last;
        final dot = q[0] * p[0] + q[1] * p[1] + q[2] * p[2] + q[3] * p[3];
        if (dot < 0) q = <double>[-q[0], -q[1], -q[2], -q[3]];
      }
      times.add(time);
      translations.add(rig.translation);
      rotations.add(q);
    }

    key(0, 0);
    if (head > 0) key(head, 0);
    for (var i = 1; i <= steps; i++) {
      key(head + span * i / steps, i / steps);
    }
    if (tail > 0) key(head + span + tail, 1);

    return World3DRigAnimation(
      times: times,
      translations: translations,
      rotations: rotations,
    );
  }
}
