/// Real 3D world model: stage, objects and a true 3D camera.
///
/// The 2.5D engine moves flat PNG layers. The new world is a set of real 3D
/// objects (back wall, floor, set pieces, the character, props) standing at
/// real distances in front of a perspective camera, so a camera move gives
/// true parallax and perspective instead of layers sliding at different speeds.
///
/// Everything here is renderer-neutral data and pure maths (no I/O, no native
/// code): the Filament plugin, a GLB builder and the tests all read it.
///
/// Coordinates: metres, +x right, +y up, the floor is y = 0, the camera looks
/// toward -z. [World3DStage] is the bridge to the 2D layout: a layer at
/// normalised canvas position (x, y) and depth d (0 far .. 1 near) is put in
/// 3D so that the NEUTRAL camera sees it exactly at (x, y); the same world
/// then reads like the 2D layout when the camera rests, and opens into real
/// 3D when the camera moves.
library;

import 'dart:math' as math;

import 'camera_hint_bridge.dart' show CameraHintBridge;
import 'depth_camera_engine.dart';
import 'depth_camera_model.dart';

class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);

  static const Vec3 zero = Vec3(0, 0, 0);

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);

  Vec3 scaled(double factor) => Vec3(x * factor, y * factor, z * factor);

  double get length => math.sqrt(x * x + y * y + z * z);

  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

/// What a 3D object is in the story world.
enum World3DRole { backWall, floor, setPiece, character, prop }

/// How an object is built. [box], [sphere] and [cylinder] (axis y) are
/// procedural stand-ins; [character] is the one recurring hero; [billboard] is
/// a flat picture standing in the world (a prop that has no 3D model yet);
/// [model] is a real GLB model loaded from [World3DObject.modelPath].
enum World3DShape { box, sphere, cylinder, character, billboard, model }

class World3DObject {
  final String id;
  final World3DRole role;
  final World3DShape shape;

  /// Key of the 2D layer this object replaces (`decor:desk`, `sprite:hero`...).
  final String? assetKey;

  /// Centre of the object.
  final Vec3 position;

  /// Full extents along x, y and z.
  final Vec3 size;

  /// Base colour as `#RRGGBB`.
  final String color;

  /// Path of the GLB file of a [World3DShape.model] object (see
  /// [World3DGlbBuilder.readModel]). Ignored for other shapes.
  final String? modelPath;

  const World3DObject({
    required this.id,
    required this.role,
    required this.shape,
    required this.position,
    required this.size,
    required this.color,
    this.assetKey,
    this.modelPath,
  });
}

/// Where the camera is and what it looks at.
class World3DCameraPose {
  final Vec3 position;
  final Vec3 target;

  /// Vertical field of view in degrees.
  final double fovDegrees;

  const World3DCameraPose({
    required this.position,
    required this.target,
    required this.fovDegrees,
  });
}

/// The shared geometry of every 3D scene of a video.
class World3DStage {
  /// Canvas width / height (9:16 portrait by default).
  final double aspect;
  final double verticalFovDegrees;
  final double cameraHeight;
  final double cameraZ;

  /// Distance from the neutral camera to the plane of depth 1 (nearest) and
  /// of depth 0 (the back wall).
  final double nearDistance;
  final double farDistance;

  const World3DStage({
    this.aspect = 9 / 16,
    this.verticalFovDegrees = 40.0,
    this.cameraHeight = 1.5,
    this.cameraZ = 6.0,
    this.nearDistance = 4.0,
    this.farDistance = 12.0,
  });

  /// Distance from the neutral camera to the plane of [depth] (0 far .. 1 near).
  double distanceOf(double depth) {
    final d = depth.isNaN ? 0.0 : depth.clamp(0.0, 1.0).toDouble();
    return farDistance + (nearDistance - farDistance) * d;
  }

  /// The z of the plane of [depth].
  double zOf(double depth) => cameraZ - distanceOf(depth);

  /// Height of the area the camera sees at [distance].
  double frameHeightAt(double distance, {double? fovDegrees}) {
    final fov = fovDegrees ?? verticalFovDegrees;
    return 2 * distance * math.tan(fov * math.pi / 360);
  }

  double frameWidthAt(double distance, {double? fovDegrees}) =>
      frameHeightAt(distance, fovDegrees: fovDegrees) * aspect;

  /// The camera at rest: looks straight along -z.
  World3DCameraPose get neutralPose => World3DCameraPose(
        position: Vec3(0, cameraHeight, cameraZ),
        target: Vec3(0, cameraHeight, cameraZ - 1),
        fovDegrees: verticalFovDegrees,
      );

  /// The 3D point that the neutral camera sees at the normalised canvas
  /// position ([x], [y]) (y points down) on the plane of [depth].
  Vec3 pointAt(double x, double y, double depth) {
    final distance = distanceOf(depth);
    final height = frameHeightAt(distance);
    final width = height * aspect;
    return Vec3(
      (x - 0.5) * width,
      cameraHeight + (0.5 - y) * height,
      cameraZ - distance,
    );
  }

  /// Where [point] lands on the canvas (0..1, y down) seen from [pose], or
  /// null when it is behind the camera.
  ({double x, double y})? project(Vec3 point, World3DCameraPose pose) {
    final forward = pose.target - pose.position;
    final forwardLength = forward.length;
    if (forwardLength < 1e-9) return null;
    final f = forward.scaled(1 / forwardLength);

    // right = forward x worldUp(0, 1, 0)
    final rightLength = math.sqrt(f.x * f.x + f.z * f.z);
    if (rightLength < 1e-9) return null;
    final r = Vec3(-f.z / rightLength, 0, f.x / rightLength);

    // up = right x forward
    final u = Vec3(
      r.y * f.z - r.z * f.y,
      r.z * f.x - r.x * f.z,
      r.x * f.y - r.y * f.x,
    );

    final v = point - pose.position;
    final depthAlong = v.dot(f);
    if (depthAlong <= 1e-6) return null;

    final tanHalf = math.tan(pose.fovDegrees * math.pi / 360);
    final ndcX = v.dot(r) / (depthAlong * tanHalf * aspect);
    final ndcY = v.dot(u) / (depthAlong * tanHalf);
    return (x: 0.5 + ndcX / 2, y: 0.5 - ndcY / 2);
  }
}

/// A real 3D camera move of one scene.
///
/// It reuses the moves of the depth camera ([DepthCameraEngine.pathFor]), so
/// the camera hints of the story, the cinematic director and the editor keep
/// working unchanged: orbit becomes a real arc around the subject, push in /
/// pull out a real dolly, parallax a real truck, rise / sink a real pedestal,
/// the dolly zoom a real change of field of view.
class World3DCameraPath {
  final World3DStage stage;
  final DepthCameraMove move;

  /// 0..[SceneCamera.maxIntensity], like [SceneCamera.intensity].
  final double intensity;

  /// Depth of the subject the camera orbits and zooms on (the character).
  final double subjectDepth;

  const World3DCameraPath({
    required this.stage,
    required this.move,
    required this.subjectDepth,
    this.intensity = 0.8,
  });

  /// Orbit half-sweep, truck and pedestal travel at intensity 1.
  static const double orbitDegrees = 14.0;
  static const double truckMeters = 0.45;
  static const double liftMeters = 0.3;

  bool get isActive =>
      move != DepthCameraMove.none && intensity.isFinite && intensity > 0.001;

  /// The native camera mode that comes closest to this move, for the Filament
  /// plugin that can only run presets (see [CameraHintBridge.filamentMode]).
  String get filamentMode => CameraHintBridge.filamentMode(move);

  /// The camera at [progress] (0..1) of the scene.
  World3DCameraPose poseAt(double progress) {
    final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0).toDouble();
    final e = DepthCameraEngine.ease(p);
    final i = intensity.isFinite
        ? intensity.clamp(0.0, SceneCamera.maxIntensity).toDouble()
        : 0.0;
    final path = DepthCameraEngine.pathFor(move);

    double mix(double a, double b) => a + (b - a) * e;

    final zoom0 = 1 + (path.zoomStart - 1) * i;
    final zoom1 = 1 + (path.zoomEnd - 1) * i;
    final zoom = math.max(0.2, mix(zoom0, zoom1));
    final orbit = mix(path.orbitStart, path.orbitEnd) * i;
    final pan = mix(path.panStart, path.panEnd) * i;
    final lift = mix(path.liftStart, path.liftEnd) * i;

    // The camera of a 2D move that makes near layers sweep right sits to the
    // left, so the yaw has the opposite sign of the orbit value.
    final yaw = -orbit * orbitDegrees * math.pi / 180;
    final pivot = Vec3(0, stage.cameraHeight, stage.zOf(subjectDepth));
    final distance = (stage.cameraZ - pivot.z) / zoom;

    // Layers that drift up mean a camera that moves down (and the other way).
    final shift = Vec3(pan * truckMeters, -lift * liftMeters, 0);

    var fov = stage.verticalFovDegrees;
    if (path.dolly > 0) {
      // Dolly zoom: the subject keeps its size while the perspective changes.
      final tanHalf = math.tan(fov * math.pi / 360) * zoom;
      fov = 2 * math.atan(tanHalf) * 180 / math.pi;
    }

    return World3DCameraPose(
      position: Vec3(
        pivot.x + distance * math.sin(yaw) + shift.x,
        pivot.y + shift.y,
        pivot.z + distance * math.cos(yaw),
      ),
      target: pivot + shift,
      fovDegrees: fov,
    );
  }

  World3DCameraPose get startPose => poseAt(0);

  World3DCameraPose get endPose => poseAt(1);
}
