import 'dart:math' as math;

import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/world3d_model.dart';
import 'package:auto_edit/world3d_planner.dart';
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
        assetKey: 'decor:mystery_piece',
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

void main() {
  group('World3DStage', () {
    const stage = World3DStage();

    test('the neutral camera sees every layer where its 2D layout put it', () {
      for (final depth in <double>[0.0, 0.12, 0.38, 0.62, 0.85, 1.0]) {
        for (final x in <double>[0.1, 0.5, 0.9]) {
          for (final y in <double>[0.14, 0.5, 0.92]) {
            final point = stage.pointAt(x, y, depth);
            final seen = stage.project(point, stage.neutralPose);
            expect(seen, isNotNull);
            expect(seen!.x, closeTo(x, 1e-9));
            expect(seen.y, closeTo(y, 1e-9));
          }
        }
      }
    });

    test('nearer planes are closer to the camera', () {
      expect(stage.distanceOf(1), lessThan(stage.distanceOf(0.5)));
      expect(stage.distanceOf(0.5), lessThan(stage.distanceOf(0)));
      expect(stage.zOf(0), lessThan(stage.zOf(1)));
    });

    test('a point behind the camera is not projected', () {
      final behind = Vec3(0, stage.cameraHeight, stage.cameraZ + 3);
      expect(stage.project(behind, stage.neutralPose), isNull);
    });
  });

  group('World3DPlanner', () {
    test('builds the room, the set pieces, the hero and the props', () {
      final plan = World3DPlanner.plan(_scene());
      expect(plan.objectsOf(World3DRole.backWall), hasLength(1));
      expect(plan.objectsOf(World3DRole.floor), hasLength(1));
      expect(plan.objectsOf(World3DRole.setPiece), hasLength(2));
      expect(plan.objectsOf(World3DRole.character), hasLength(1));
      expect(plan.objectsOf(World3DRole.prop), hasLength(1));
      expect(plan.objects, hasLength(6));
      expect(plan.beatIndex, 0);
      expect(plan.environment, StoryEnvironment.office);
    });

    test('the hero lands on its 2D place with its 2D size', () {
      final plan = World3DPlanner.plan(_scene());
      final hero = plan.character!;
      final center = plan.stage.project(hero.position, plan.stage.neutralPose);
      expect(center!.x, closeTo(0.5, 1e-9));
      expect(center.y, closeTo(0.62, 1e-9));

      final left = plan.stage.project(
        Vec3(hero.position.x - hero.size.x / 2, hero.position.y, hero.position.z),
        plan.stage.neutralPose,
      );
      final right = plan.stage.project(
        Vec3(hero.position.x + hero.size.x / 2, hero.position.y, hero.position.z),
        plan.stage.neutralPose,
      );
      expect(right!.x - left!.x, closeTo(0.42, 1e-9));
    });

    test('props are pictures standing in the world at their slot', () {
      final plan = World3DPlanner.plan(_scene());
      final prop = plan.objectsOf(World3DRole.prop).single;
      expect(prop.shape, World3DShape.billboard);
      final seen = plan.stage.project(prop.position, plan.stage.neutralPose);
      expect(seen!.x, closeTo(0.2, 1e-9));
      expect(seen.y, closeTo(0.74, 1e-9));
    });

    test('set pieces use their stand-in geometry, unknown ones a neutral box',
        () {
      final plan = World3DPlanner.plan(_scene());
      final pieces = plan.objectsOf(World3DRole.setPiece);
      expect(World3DPlanner.hasPiece('desk'), isTrue);
      expect(World3DPlanner.hasPiece('mystery_piece'), isFalse);
      expect(pieces.first.assetKey, 'decor:desk');
      expect(pieces.first.color, '#6B4A2F');
      expect(pieces.last.shape, World3DShape.box);
      expect(pieces.last.color, '#555B66');
    });

    test('the wall sits behind everything and the floor is darker', () {
      final plan = World3DPlanner.plan(_scene());
      final wall = plan.objectsOf(World3DRole.backWall).single;
      final floor = plan.objectsOf(World3DRole.floor).single;
      for (final object in plan.objects) {
        if (object.role == World3DRole.backWall) continue;
        expect(object.position.z, greaterThan(wall.position.z));
      }
      expect(wall.color, '#1E2230');
      expect(floor.color, isNot(wall.color));
      expect(floor.position.y, lessThan(0));
    });

    test('the camera of the plan follows the move that was asked', () {
      final plan = World3DPlanner.plan(
        _scene(),
        move: DepthCameraMove.orbitRight,
        intensity: 1,
      );
      expect(plan.camera.move, DepthCameraMove.orbitRight);
      expect(plan.camera.isActive, isTrue);
      expect(plan.camera.subjectDepth, closeTo(0.62, 1e-9));
    });
  });

  group('World3DCameraPath', () {
    const stage = World3DStage();
    World3DCameraPath path(DepthCameraMove move, {double intensity = 1}) =>
        World3DCameraPath(
          stage: stage,
          move: move,
          intensity: intensity,
          subjectDepth: 0.62,
        );

    double distanceToTarget(World3DCameraPose pose) =>
        (pose.position - pose.target).length;

    test('no move keeps the neutral camera', () {
      final pose = path(DepthCameraMove.none).poseAt(0.5);
      expect(path(DepthCameraMove.none).isActive, isFalse);
      expect(pose.position.x, closeTo(0, 1e-9));
      expect(pose.position.y, closeTo(stage.cameraHeight, 1e-9));
      expect(pose.position.z, closeTo(stage.cameraZ, 1e-9));
      expect(pose.fovDegrees, closeTo(stage.verticalFovDegrees, 1e-9));
    });

    test('push in dollies toward the subject, pull out dollies away', () {
      final push = path(DepthCameraMove.pushIn);
      expect(distanceToTarget(push.endPose),
          lessThan(distanceToTarget(push.startPose)));
      expect(distanceToTarget(push.startPose),
          closeTo(stage.distanceOf(0.62), 1e-9));

      final pull = path(DepthCameraMove.pullOut);
      expect(distanceToTarget(pull.endPose),
          greaterThan(distanceToTarget(pull.startPose)));
    });

    test('an orbit is a real arc around the subject', () {
      final orbit = path(DepthCameraMove.orbitRight);
      expect(orbit.startPose.position.x, greaterThan(0));
      expect(orbit.endPose.position.x, lessThan(0));
      // The camera always looks at the same point of the subject plane.
      expect(orbit.startPose.target.x, closeTo(0, 1e-9));
      expect(orbit.endPose.target.x, closeTo(0, 1e-9));
      // Halfway the camera is on the axis again.
      expect(orbit.poseAt(0.5).position.x, closeTo(0, 1e-6));
    });

    test('parallax trucks the camera sideways keeping its direction', () {
      final truck = path(DepthCameraMove.parallaxLeft);
      final a = truck.startPose;
      final b = truck.endPose;
      expect(b.position.x, greaterThan(a.position.x));
      expect(b.position.x - b.target.x, closeTo(a.position.x - a.target.x, 1e-9));
      expect(b.position.z, closeTo(a.position.z, 1e-9));
    });

    test('rise and sink move the camera on the vertical axis', () {
      final rise = path(DepthCameraMove.riseUp);
      // Layers that drift up mean a camera that goes down.
      expect(rise.endPose.position.y, lessThan(rise.startPose.position.y));
      final sink = path(DepthCameraMove.sinkDown);
      expect(sink.endPose.position.y, greaterThan(sink.startPose.position.y));
    });

    test('the dolly zoom keeps the subject size while the perspective changes',
        () {
      final dolly = path(DepthCameraMove.dollyZoom);
      double subjectFrame(World3DCameraPose pose) =>
          2 * distanceToTarget(pose) * math.tan(pose.fovDegrees * math.pi / 360);
      expect(dolly.endPose.fovDegrees, greaterThan(dolly.startPose.fovDegrees));
      expect(subjectFrame(dolly.endPose),
          closeTo(subjectFrame(dolly.startPose), 1e-9));
    });

    test('intensity scales the travel and is clamped', () {
      final soft = path(DepthCameraMove.pushIn, intensity: 0.4);
      final hard = path(DepthCameraMove.pushIn, intensity: 1.0);
      expect(distanceToTarget(soft.endPose),
          greaterThan(distanceToTarget(hard.endPose)));
      final wild = path(DepthCameraMove.pushIn, intensity: 50);
      final max = path(DepthCameraMove.pushIn,
          intensity: SceneCamera.maxIntensity);
      expect(distanceToTarget(wild.endPose),
          closeTo(distanceToTarget(max.endPose), 1e-9));
    });

    test('a bad progress is treated as the start or the end', () {
      final push = path(DepthCameraMove.pushIn);
      expect(push.poseAt(double.nan).position.z,
          closeTo(push.startPose.position.z, 1e-9));
      expect(push.poseAt(-3).position.z,
          closeTo(push.startPose.position.z, 1e-9));
      expect(push.poseAt(9).position.z, closeTo(push.endPose.position.z, 1e-9));
    });

    test('the native preset camera comes closest to the same move', () {
      expect(path(DepthCameraMove.pushIn).filamentMode, 'push_in');
      expect(path(DepthCameraMove.pullOut).filamentMode, 'pull_out');
      expect(path(DepthCameraMove.orbitLeft).filamentMode, 'orbit');
      expect(path(DepthCameraMove.spiralIn).filamentMode, 'orbit_fast');
    });
  });
}
