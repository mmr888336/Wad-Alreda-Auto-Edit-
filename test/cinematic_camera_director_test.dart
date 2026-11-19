import 'package:auto_edit/cinematic_camera_director.dart';
import 'package:auto_edit/depth_camera_engine.dart';
import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:flutter_test/flutter_test.dart';

ReferenceSceneResult _built() {
  return ReferenceSceneBuilder.buildCutaway(
    id: 'dir',
    spec: const CutawaySpec(
      start: 5,
      end: 7.6,
      text: 'سر البركة والخير في حياة الناس',
    ),
    width: 720,
    height: 1280,
    mood: MotionMood.cinematic,
  );
}

void main() {
  group('shot roles follow the scene order', () {
    test('opening crane, then dolly, orbit, crane, window entry', () {
      ShotRole role(int order, {bool hasNext = true}) =>
          CinematicCameraDirector.roleFor(
            order: order,
            previous: null,
            hasNext: hasNext,
          );
      expect(role(0), ShotRole.establish);
      expect(role(1), ShotRole.dolly);
      expect(role(2), ShotRole.orbit);
      expect(role(3), ShotRole.crane);
      expect(role(4), ShotRole.windowIn);
      expect(role(5), ShotRole.orbit);
      expect(role(6), ShotRole.dolly);
    });

    test('window entry needs a next scene, and is followed by its arrival', () {
      expect(
        CinematicCameraDirector.roleFor(
          order: 4,
          previous: null,
          hasNext: false,
        ),
        ShotRole.dolly,
      );
      expect(
        CinematicCameraDirector.roleFor(
          order: 5,
          previous: const SceneCamera(move: DepthCameraMove.windowIn),
          hasNext: true,
        ),
        ShotRole.windowOut,
      );
    });
  });

  group('continuity', () {
    test('an orbit continues the way the previous orbit ended', () {
      final move = CinematicCameraDirector.pickMove(
        role: ShotRole.orbit,
        order: 2,
        previous: const SceneCamera(
          move: DepthCameraMove.orbitRight,
          intensity: 0.85,
        ),
        intensity: 0.85,
      );
      expect(move, DepthCameraMove.orbitLeft);
    });

    test('a crane starts on the lift the previous crane ended on', () {
      final move = CinematicCameraDirector.pickMove(
        role: ShotRole.crane,
        order: 3,
        previous: const SceneCamera(
          move: DepthCameraMove.craneUp,
          intensity: 0.85,
        ),
        intensity: 0.85,
      );
      expect(move, DepthCameraMove.craneDown);
    });

    test('a crane after a pull out starts on the closest framing', () {
      final move = CinematicCameraDirector.pickMove(
        role: ShotRole.crane,
        order: 3,
        previous: const SceneCamera(
          move: DepthCameraMove.pullOut,
          intensity: 0.85,
        ),
        intensity: 0.85,
      );
      expect(move, DepthCameraMove.craneDown);
    });

    test('a dolly after a push in pulls out from the same framing', () {
      final move = CinematicCameraDirector.pickMove(
        role: ShotRole.dolly,
        order: 1,
        previous: const SceneCamera(
          move: DepthCameraMove.pushIn,
          intensity: 0.85,
        ),
        intensity: 0.85,
      );
      expect(move, DepthCameraMove.pullOut);
    });

    test('the window arrival starts as zoomed in as the entry ended', () {
      const entry = SceneCamera(move: DepthCameraMove.windowIn, intensity: 1);
      const arrival = SceneCamera(move: DepthCameraMove.windowOut, intensity: 1);
      final end =
          DepthCameraEngine.sample(camera: entry, depth: 1, progress: 1);
      final start =
          DepthCameraEngine.sample(camera: arrival, depth: 1, progress: 0);
      expect(end.zoom, greaterThan(1.5));
      expect(start.zoom, closeTo(end.zoom, 1e-9));
    });
  });

  group('new crane moves', () {
    test('crane up pulls back while near layers sink more than far ones', () {
      const camera = SceneCamera(move: DepthCameraMove.craneUp, intensity: 1);
      final startNear =
          DepthCameraEngine.sample(camera: camera, depth: 1, progress: 0);
      final endNear =
          DepthCameraEngine.sample(camera: camera, depth: 1, progress: 1);
      final endFar =
          DepthCameraEngine.sample(camera: camera, depth: 0, progress: 1);
      expect(startNear.zoom, greaterThan(endNear.zoom));
      expect(endNear.zoom, closeTo(1.0, 1e-9));
      expect(endNear.dy - startNear.dy, greaterThan(0));
      expect(
        (endNear.dy - startNear.dy).abs(),
        greaterThan((endFar.dy).abs()),
      );
    });

    test('crane down pushes in while near layers rise', () {
      const camera = SceneCamera(move: DepthCameraMove.craneDown, intensity: 1);
      final start =
          DepthCameraEngine.sample(camera: camera, depth: 1, progress: 0);
      final end =
          DepthCameraEngine.sample(camera: camera, depth: 1, progress: 1);
      expect(end.zoom, greaterThan(start.zoom));
      expect(end.dy - start.dy, lessThan(0));
    });
  });

  group('upgrade', () {
    test('a fresh story opens with a crane reveal and centres on the subject',
        () {
      final original = _built();
      final upgraded = CinematicCameraDirector.upgrade(
        original,
        mood: MotionMood.cinematic,
      );
      final scenes = upgraded.project.scenes;
      expect(scenes.length, 2);
      expect(scenes[0].camera!.move, DepthCameraMove.craneUp);
      expect(scenes[1].camera, isNotNull);
      expect(scenes[1].camera!.isActive, isTrue);
      expect(scenes[0].camera!.move, isNot(scenes[1].camera!.move));
      expect(scenes[0].camera!.focusX, inInclusiveRange(0.15, 0.85));
      expect(scenes[0].camera!.focusY, inInclusiveRange(0.15, 0.85));
      // The input is left untouched.
      expect(original.project.scenes[0].camera, isNull);
      upgraded.project.validate();
    });

    test('a window entry is followed by its arrival in the next scene', () {
      final state = CameraDirectorState()..count = 4;
      final upgraded = CinematicCameraDirector.upgrade(
        _built(),
        mood: MotionMood.cinematic,
        state: state,
      );
      final scenes = upgraded.project.scenes;
      expect(scenes[0].camera!.move, DepthCameraMove.windowIn);
      expect(scenes[1].camera!.move, DepthCameraMove.windowOut);
      expect(scenes[1].camera!.intensity, scenes[0].camera!.intensity);
      expect(state.count, 6);
      upgraded.project.validate();
    });

    test('the story goes on from one cutaway to the next', () {
      final state = CameraDirectorState();
      final first = CinematicCameraDirector.upgrade(
        _built(),
        mood: MotionMood.cinematic,
        state: state,
      );
      final second = CinematicCameraDirector.upgrade(
        _built(),
        mood: MotionMood.cinematic,
        state: state,
      );
      expect(first.project.scenes.first.camera!.move, DepthCameraMove.craneUp);
      expect(
        second.project.scenes.first.camera!.move,
        isNot(DepthCameraMove.craneUp),
      );
      expect(state.count, 4);
    });

    test('memory starts a new story for a new export', () {
      CameraDirectorMemory.reset();
      final a = CameraDirectorMemory.stateFor(1)..count = 3;
      expect(CameraDirectorMemory.stateFor(1).count, 3);
      expect(identical(CameraDirectorMemory.stateFor(1), a), isTrue);
      expect(CameraDirectorMemory.stateFor(2).count, 0);
      CameraDirectorMemory.reset();
    });

    test('scenes that already have a camera keep it', () {
      final original = _built();
      const mine = SceneCamera(move: DepthCameraMove.riseUp, intensity: 0.5);
      final first = original.project.scenes.first.withCamera(mine);
      final custom = ReferenceSceneResult(
        project: MotionProject(
          id: original.project.id,
          width: original.project.width,
          height: original.project.height,
          frameRate: original.project.frameRate,
          duration: original.project.duration,
          scenes: <MotionScene>[first, ...original.project.scenes.skip(1)],
        ),
        assets: original.assets,
      );
      final upgraded = CinematicCameraDirector.upgrade(
        custom,
        mood: MotionMood.calm,
      );
      expect(upgraded.project.scenes.first.camera!.move, DepthCameraMove.riseUp);
      expect(upgraded.project.scenes[1].camera, isNotNull);
    });
  });
}
