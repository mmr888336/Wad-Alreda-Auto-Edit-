import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/glb_inspector.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/world3d_glb_builder.dart';
import 'package:auto_edit/world3d_model.dart';
import 'package:auto_edit/world3d_planner.dart';
import 'package:auto_edit/world3d_rig.dart';
import 'package:flutter_test/flutter_test.dart';

WorldScene _scene() {
  return WorldScene(
    beatIndex: 0,
    environment: StoryEnvironment.office,
    continuesPreviousScene: false,
    look: CinematicWorld.lookFor(
      StoryEnvironment.office,
      StoryMood.calm,
      const WorldPalette(),
    ),
    layers: const <WorldLayerSpec>[
      WorldLayerSpec(
        id: 'w0_backdrop',
        assetKey: 'bg:office',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.0,
        zIndex: 0,
      ),
      WorldLayerSpec(
        id: 'w0_set0',
        assetKey: 'decor:desk',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.12,
        zIndex: 1,
      ),
      WorldLayerSpec(
        id: 'w0_set1',
        assetKey: 'decor:window',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.18,
        zIndex: 2,
      ),
      WorldLayerSpec(
        id: 'w0_hero',
        assetKey: 'sprite:hero',
        x: 0.5,
        y: 0.62,
        scale: 0.42,
        depth: 0.62,
        zIndex: 20,
      ),
      WorldLayerSpec(
        id: 'w0_prop0',
        assetKey: 'decor:coins',
        x: 0.2,
        y: 0.74,
        scale: 0.2,
        depth: 0.38,
        zIndex: 10,
      ),
    ],
  );
}

Map<String, dynamic> _json(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final length = data.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
      as Map<String, dynamic>;
}

List<double> _read(
  Uint8List bytes,
  Map<String, dynamic> json,
  int accessorIndex,
  int components,
) {
  final accessor = (json['accessors'] as List)[accessorIndex] as Map;
  final view = (json['bufferViews'] as List)[accessor['bufferView'] as int] as Map;
  final data = ByteData.sublistView(bytes);
  final jsonLength = data.getUint32(12, Endian.little);
  final offset = 28 + jsonLength + (view['byteOffset'] as int);
  final count = (accessor['count'] as int) * components;
  return <double>[
    for (var i = 0; i < count; i++) data.getFloat32(offset + 4 * i, Endian.little),
  ];
}

void _expectVec(Vec3 a, Vec3 b, [double eps = 1e-9]) {
  expect(a.x, closeTo(b.x, eps));
  expect(a.y, closeTo(b.y, eps));
  expect(a.z, closeTo(b.z, eps));
}

void main() {
  group('native camera', () {
    test('the lens of the plugin viewer gives about 46 degrees', () {
      expect(World3DNativeCamera.verticalFovDegrees, closeTo(46.4, 0.1));
    });

    test('a native stage uses that lens and keeps the aspect', () {
      final stage = World3DNativeCamera.stage();
      expect(stage.verticalFovDegrees, World3DNativeCamera.verticalFovDegrees);
      expect(stage.aspect, closeTo(9 / 16, 1e-12));
      expect(World3DNativeCamera.stage(aspect: 1).aspect, 1);
    });

    test('the unit cube scale follows the longest side', () {
      const bounds = World3DBounds(Vec3(-1, 0, -3), Vec3(3, 2, 1));
      _expectVec(bounds.center, const Vec3(1, 1, -1));
      expect(bounds.maxExtent, 4);
      expect(bounds.unitCubeScale, closeTo(0.5, 1e-12));
      // The centre of the world lands on the native target.
      _expectVec(bounds.toNative(bounds.center), World3DNativeCamera.target);
      // The nearest point of an extreme side is one unit from the target.
      expect(bounds.toNative(const Vec3(3, 1, -1)).x, closeTo(1.0, 1e-12));
    });

    test('a degenerate box keeps scale 1', () {
      const bounds = World3DBounds(Vec3(1, 1, 1), Vec3(1, 1, 1));
      expect(bounds.unitCubeScale, 1.0);
    });
  });

  group('quaternions', () {
    test('identity', () {
      final q = World3DRig.quaternionOf(
        const Vec3(1, 0, 0),
        const Vec3(0, 1, 0),
        const Vec3(0, 0, 1),
      );
      expect(q[0], closeTo(0, 1e-12));
      expect(q[1], closeTo(0, 1e-12));
      expect(q[2], closeTo(0, 1e-12));
      expect(q[3], closeTo(1, 1e-12));
    });

    test('90 degrees about y', () {
      final q = World3DRig.quaternionOf(
        const Vec3(0, 0, 1),
        const Vec3(0, 1, 0),
        const Vec3(-1, 0, 0),
      );
      _expectVec(World3DRig.rotate(q, const Vec3(1, 0, 0)), const Vec3(0, 0, -1));
      _expectVec(World3DRig.rotate(q, const Vec3(0, 0, 1)), const Vec3(1, 0, 0));
    });

    test('every branch of the conversion (half turns)', () {
      // about y: trace < 0 and the y diagonal is the largest
      final y = World3DRig.quaternionOf(
        const Vec3(-1, 0, 0),
        const Vec3(0, 1, 0),
        const Vec3(0, 0, -1),
      );
      _expectVec(World3DRig.rotate(y, const Vec3(1, 0, 0)), const Vec3(-1, 0, 0));
      _expectVec(World3DRig.rotate(y, const Vec3(0, 0, 1)), const Vec3(0, 0, -1));

      // about x: the x diagonal is the largest
      final x = World3DRig.quaternionOf(
        const Vec3(1, 0, 0),
        const Vec3(0, -1, 0),
        const Vec3(0, 0, -1),
      );
      _expectVec(World3DRig.rotate(x, const Vec3(0, 1, 0)), const Vec3(0, -1, 0));
      _expectVec(World3DRig.rotate(x, const Vec3(1, 0, 0)), const Vec3(1, 0, 0));

      // about z: the z diagonal is the largest
      final z = World3DRig.quaternionOf(
        const Vec3(-1, 0, 0),
        const Vec3(0, -1, 0),
        const Vec3(0, 0, 1),
      );
      _expectVec(World3DRig.rotate(z, const Vec3(1, 0, 0)), const Vec3(-1, 0, 0));
      _expectVec(World3DRig.rotate(z, const Vec3(0, 0, 1)), const Vec3(0, 0, 1));

      for (final q in <List<double>>[x, y, z]) {
        final length = math.sqrt(q.fold<double>(0, (s, v) => s + v * v));
        expect(length, closeTo(1, 1e-12));
      }
    });
  });

  group('rig transform', () {
    const bounds = World3DBounds(Vec3(-4, 0, -8), Vec3(4, 12, 6));

    test('the neutral pose only moves the world to the native eye', () {
      final stage = World3DNativeCamera.stage();
      final rig = World3DRig.rigFor(stage.neutralPose, bounds)!;
      expect(rig.rotation[0], closeTo(0, 1e-12));
      expect(rig.rotation[1], closeTo(0, 1e-12));
      expect(rig.rotation[2], closeTo(0, 1e-12));
      expect(rig.rotation[3], closeTo(1, 1e-12));
      final expected =
          World3DRig.nativeEyeInWorld(bounds) - stage.neutralPose.position;
      _expectVec(rig.translation, expected);
    });

    test('the native eye sits 5 / scale in front of the world centre', () {
      final eye = World3DRig.nativeEyeInWorld(bounds);
      _expectVec(eye - bounds.center, Vec3(0, 0, 5 / bounds.unitCubeScale));
    });

    test('a pose without a direction has no rig', () {
      const same = World3DCameraPose(
        position: Vec3(1, 1, 1),
        target: Vec3(1, 1, 1),
        fovDegrees: 40,
      );
      expect(World3DRig.rigFor(same, bounds), isNull);
      const up = World3DCameraPose(
        position: Vec3(0, 0, 0),
        target: Vec3(0, 5, 0),
        fovDegrees: 40,
      );
      expect(World3DRig.rigFor(up, bounds), isNull);
    });

    test('looking backwards is handled', () {
      const back = World3DCameraPose(
        position: Vec3(0, 1, 0),
        target: Vec3(0, 1, 5),
        fovDegrees: 40,
      );
      final rig = World3DRig.rigFor(back, bounds)!;
      final length =
          math.sqrt(rig.rotation.fold<double>(0, (s, v) => s + v * v));
      expect(length, closeTo(1, 1e-12));
    });
  });

  group('the fixed native camera sees the virtual camera', () {
    final stage = World3DNativeCamera.stage();

    ({double x, double y})? nativeProject(
      Vec3 point,
      List<double> rotation,
      Vec3 translation,
      World3DBounds bounds,
    ) {
      final moved = World3DRig.rotate(rotation, point) + translation;
      final native = bounds.toNative(moved);
      final depth = World3DNativeCamera.eye.z - native.z;
      if (depth <= 1e-6) return null;
      final tanHalf =
          math.tan(World3DNativeCamera.verticalFovDegrees * math.pi / 360);
      return (
        x: 0.5 + native.x / (depth * tanHalf * stage.aspect) / 2,
        y: 0.5 - native.y / (depth * tanHalf) / 2,
      );
    }

    for (final move in <DepthCameraMove>[
      DepthCameraMove.pushIn,
      DepthCameraMove.pullOut,
      DepthCameraMove.orbitLeft,
      DepthCameraMove.orbitRight,
      DepthCameraMove.parallaxLeft,
      DepthCameraMove.riseUp,
      DepthCameraMove.sinkDown,
      DepthCameraMove.spiralIn,
      DepthCameraMove.craneUp,
      DepthCameraMove.craneDown,
      DepthCameraMove.windowIn,
    ]) {
      test('$move: every sample of the animation matches', () {
        final scene = World3DPlanner.plan(
          _scene(),
          stage: stage,
          move: move,
          intensity: 1,
        );
        final bounds = World3DGlbBuilder.build(scene).bounds;
        final animation = World3DRig.build(
          path: scene.camera,
          bounds: bounds,
          duration: 3,
        );
        final points = <Vec3>[
          stage.pointAt(0.5, 0.62, 0.62),
          stage.pointAt(0.2, 0.3, 0.1),
          stage.pointAt(0.8, 0.8, 0.9),
          stage.pointAt(0.35, 0.5, 0.38),
        ];

        var checked = 0;
        for (var k = 0; k < animation.length; k++) {
          final progress = ((animation.times[k] - 0.5) / 3).clamp(0.0, 1.0);
          final pose = scene.camera.poseAt(progress);
          for (final point in points) {
            final expected = stage.project(point, pose);
            final seen = nativeProject(
              point,
              animation.rotations[k],
              animation.translations[k],
              bounds,
            );
            if (expected == null || seen == null) continue;
            expect(seen.x, closeTo(expected.x, 1e-7));
            expect(seen.y, closeTo(expected.y, 1e-7));
            checked++;
          }
        }
        expect(checked, greaterThan(animation.length));
      });
    }
  });

  group('rig animation', () {
    final stage = World3DNativeCamera.stage();
    const bounds = World3DBounds(Vec3(-4, 0, -8), Vec3(4, 12, 6));

    World3DCameraPath path(DepthCameraMove move) => World3DCameraPath(
          stage: stage,
          move: move,
          subjectDepth: 0.62,
          intensity: 1,
        );

    test('holds, samples and lengths', () {
      final animation = World3DRig.build(
        path: path(DepthCameraMove.pushIn),
        bounds: bounds,
        duration: 3,
      );
      expect(animation.times.first, 0);
      expect(animation.times[1], 0.5);
      expect(animation.times.last, closeTo(4.0, 1e-9));
      expect(animation.duration, closeTo(4.0, 1e-9));
      expect(animation.translations, hasLength(animation.length));
      expect(animation.rotations, hasLength(animation.length));
      // 2 holds + 90 motion samples + the start key.
      expect(animation.length, 2 + 90 + 1);
      for (var i = 1; i < animation.length; i++) {
        expect(animation.times[i], greaterThan(animation.times[i - 1]));
      }
    });

    test('the camera rests during the holds', () {
      final animation = World3DRig.build(
        path: path(DepthCameraMove.pushIn),
        bounds: bounds,
        duration: 3,
      );
      _expectVec(animation.translations[0], animation.translations[1]);
      _expectVec(
        animation.translations[animation.length - 1],
        animation.translations[animation.length - 2] +
            (animation.translations[animation.length - 1] -
                animation.translations[animation.length - 2]),
      );
    });

    test('quaternions are unit length and never flip the long way round', () {
      for (final move in <DepthCameraMove>[
        DepthCameraMove.orbitLeft,
        DepthCameraMove.spiralIn,
        DepthCameraMove.craneUp,
      ]) {
        final animation = World3DRig.build(
          path: path(move),
          bounds: bounds,
          duration: 2,
        );
        for (var i = 0; i < animation.length; i++) {
          final q = animation.rotations[i];
          final length = math.sqrt(q.fold<double>(0, (s, v) => s + v * v));
          expect(length, closeTo(1, 1e-9));
          if (i > 0) {
            final p = animation.rotations[i - 1];
            final dot = q[0] * p[0] + q[1] * p[1] + q[2] * p[2] + q[3] * p[3];
            expect(dot, greaterThanOrEqualTo(0));
          }
        }
      }
    });

    test('the length of the move is kept in a safe range', () {
      final short = World3DRig.build(
        path: path(DepthCameraMove.pushIn),
        bounds: bounds,
        duration: 0.01,
        holdStart: 0,
        holdEnd: 0,
      );
      expect(short.duration, closeTo(0.5, 1e-9));
      final long = World3DRig.build(
        path: path(DepthCameraMove.pushIn),
        bounds: bounds,
        duration: 9999,
        holdStart: 0,
        holdEnd: 0,
      );
      expect(long.duration, closeTo(30.0, 1e-9));
      final nan = World3DRig.build(
        path: path(DepthCameraMove.pushIn),
        bounds: bounds,
        duration: double.nan,
        holdStart: 0,
        holdEnd: 0,
      );
      expect(nan.duration, closeTo(3.0, 1e-9));
    });
  });

  group('GLB with the camera rig', () {
    final stage = World3DNativeCamera.stage();

    World3DScene plan(DepthCameraMove move) => World3DPlanner.plan(
          _scene(),
          stage: stage,
          move: move,
          intensity: 1,
        );

    test('the world hangs under one animated rig node', () {
      final glb = World3DGlbBuilder.build(
        plan(DepthCameraMove.pushIn),
        cameraSeconds: 3,
      );
      expect(glb.animated, isTrue);
      expect(glb.animationSeconds, closeTo(4.0, 1e-9));
      expect(glb.objectCount, 5);

      final report = GlbInspector.inspect(glb.bytes);
      expect(report.isSafe, isTrue, reason: report.rejection);
      expect(report.animationCount, 1);
      expect(report.vertexCount, glb.vertexCount);

      final json = _json(glb.bytes);
      final nodes = json['nodes'] as List;
      expect(nodes, hasLength(6));
      final rig = nodes.last as Map;
      expect(rig['name'], 'world_rig');
      expect(rig['children'], <int>[0, 1, 2, 3, 4]);
      expect((json['scenes'] as List).single['nodes'], <int>[5]);

      final animation = (json['animations'] as List).single as Map;
      final channels = animation['channels'] as List;
      expect(channels, hasLength(2));
      expect(channels[0]['target'], <String, dynamic>{'node': 5, 'path': 'translation'});
      expect(channels[1]['target'], <String, dynamic>{'node': 5, 'path': 'rotation'});
      final samplers = animation['samplers'] as List;
      expect(samplers[0]['interpolation'], 'LINEAR');
      expect(samplers[1]['interpolation'], 'LINEAR');
      expect(samplers[0]['input'], samplers[1]['input']);
    });

    test('the keyframes in the file are valid', () {
      final glb = World3DGlbBuilder.build(
        plan(DepthCameraMove.orbitRight),
        cameraSeconds: 3,
      );
      final json = _json(glb.bytes);
      final animation = (json['animations'] as List).single as Map;
      final samplers = animation['samplers'] as List;
      final accessors = json['accessors'] as List;

      final timeIndex = samplers[0]['input'] as int;
      final times = _read(glb.bytes, json, timeIndex, 1);
      final time = accessors[timeIndex] as Map;
      expect(time['type'], 'SCALAR');
      expect(time['min'], <double>[0.0]);
      expect(time['max'], <double>[4.0]);
      expect(times.first, 0);
      expect(times.last, closeTo(4.0, 1e-6));
      for (var i = 1; i < times.length; i++) {
        expect(times[i], greaterThan(times[i - 1]));
      }

      final translationIndex = samplers[0]['output'] as int;
      expect((accessors[translationIndex] as Map)['type'], 'VEC3');
      expect((accessors[translationIndex] as Map)['count'], times.length);

      final rotationIndex = samplers[1]['output'] as int;
      expect((accessors[rotationIndex] as Map)['type'], 'VEC4');
      final rotations = _read(glb.bytes, json, rotationIndex, 4);
      expect(rotations, hasLength(times.length * 4));
      for (var i = 0; i < times.length; i++) {
        final length = math.sqrt(
          rotations[4 * i] * rotations[4 * i] +
              rotations[4 * i + 1] * rotations[4 * i + 1] +
              rotations[4 * i + 2] * rotations[4 * i + 2] +
              rotations[4 * i + 3] * rotations[4 * i + 3],
        );
        expect(length, closeTo(1.0, 1e-5));
      }
    });

    test('without a duration the file is static', () {
      final glb = World3DGlbBuilder.build(plan(DepthCameraMove.pushIn));
      expect(glb.animated, isFalse);
      expect(glb.animationSeconds, 0);
      final json = _json(glb.bytes);
      expect(json.containsKey('animations'), isFalse);
      expect((json['nodes'] as List), hasLength(5));
      expect(GlbInspector.inspect(glb.bytes).animationCount, 0);
    });

    test('a scene without a camera move stays static', () {
      final glb = World3DGlbBuilder.build(
        plan(DepthCameraMove.none),
        cameraSeconds: 3,
      );
      expect(glb.animated, isFalse);
      expect(_json(glb.bytes).containsKey('animations'), isFalse);
    });
  });
}
