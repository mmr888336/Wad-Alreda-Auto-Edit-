import 'package:auto_edit/camera_hint_bridge.dart';
import 'package:auto_edit/continuous_scene_generator.dart';
import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:flutter_test/flutter_test.dart';

const MotionScene _scene = MotionScene(
  id: 's',
  start: 0,
  end: 2,
  layers: <MotionLayer>[],
);

const String _sixWords = 'سر البركة والخير في حياة الناس';

SceneCamera? _camera(
  DepthCameraMove hint, {
  SceneCamera? previous,
  bool hasNext = true,
  bool isFirst = false,
}) {
  return CameraHintBridge.cameraFor(
    scene: _scene,
    hint: hint,
    mood: MotionMood.cinematic,
    previous: previous,
    hasNext: hasNext,
    isFirst: isFirst,
  );
}

void main() {
  group('filament modes', () {
    test('every move maps to a mode the native plugin accepts', () {
      for (final move in DepthCameraMove.values) {
        expect(
          CameraHintBridge.filamentModes,
          contains(CameraHintBridge.filamentMode(move)),
        );
      }
    });

    test('entry pushes in, arrival pulls out, orbit stays an orbit', () {
      expect(CameraHintBridge.filamentMode(DepthCameraMove.windowIn), 'push_in');
      expect(CameraHintBridge.filamentMode(DepthCameraMove.windowOut), 'pull_out');
      expect(CameraHintBridge.filamentMode(DepthCameraMove.craneUp), 'pull_out');
      expect(CameraHintBridge.filamentMode(DepthCameraMove.orbitLeft), 'orbit');
      expect(CameraHintBridge.filamentMode(DepthCameraMove.spiralIn), 'orbit_fast');
    });
  });

  group('hint of a time range', () {
    final beats = StoryUnderstanding.plan(const <StorySegment>[
      StorySegment(text: 'xyz', start: 0, end: 3),
      StorySegment(text: 'qwerty', start: 3, end: 6),
    ]).beats;

    test('the beat that overlaps the range gives the hint', () {
      expect(beats[0].cameraHint, DepthCameraMove.craneUp);
      expect(beats[1].cameraHint, DepthCameraMove.pullOut);
      expect(CameraHintBridge.hintFor(beats, 0.5, 2.5), DepthCameraMove.craneUp);
      expect(CameraHintBridge.hintFor(beats, 3.5, 5.5), DepthCameraMove.pullOut);
      expect(CameraHintBridge.hintFor(beats, 10, 12), isNull);
    });

    test('filamentModeFor uses the hint, else the fallback', () {
      expect(
        CameraHintBridge.filamentModeFor(beats, 0.5, 2.5, fallback: 'orbit_fast'),
        'pull_out',
      );
      expect(
        CameraHintBridge.filamentModeFor(beats, 10, 12, fallback: 'orbit_fast'),
        'orbit_fast',
      );
      expect(
        CameraHintBridge.filamentModeFor(
          const <StoryBeat>[],
          0,
          3,
          fallback: 'orbit',
        ),
        'orbit',
      );
    });

    test('the bridge can be switched off', () {
      CameraHintBridge.enabled = false;
      addTearDown(() => CameraHintBridge.enabled = true);
      expect(
        CameraHintBridge.filamentModeFor(beats, 0.5, 2.5, fallback: 'orbit_fast'),
        'orbit_fast',
      );
      expect(_camera(DepthCameraMove.pushIn), isNull);
    });
  });

  group('cameraFor', () {
    test('a plain move on the first scene is left to the director', () {
      expect(_camera(DepthCameraMove.pushIn, isFirst: true), isNull);
      expect(_camera(DepthCameraMove.craneUp, isFirst: true), isNull);
    });

    test('an entry into the window on the first scene is kept', () {
      final camera = _camera(DepthCameraMove.windowIn, isFirst: true);
      expect(camera, isNotNull);
      expect(camera!.move, DepthCameraMove.windowIn);
      expect(camera.intensity, closeTo(0.85, 1e-9));
    });

    test('an entry with no scene after it becomes a push in', () {
      final camera = _camera(DepthCameraMove.windowIn, hasNext: false);
      expect(camera!.move, DepthCameraMove.pushIn);
    });

    test('the scene after an entry is always its arrival', () {
      const entry = SceneCamera(move: DepthCameraMove.windowIn, intensity: 0.7);
      final camera = _camera(DepthCameraMove.pushIn, previous: entry);
      expect(camera!.move, DepthCameraMove.windowOut);
      expect(camera.intensity, 0.7);
    });

    test('an arrival with no entry before it becomes a pull out', () {
      final camera = _camera(DepthCameraMove.windowOut);
      expect(camera!.move, DepthCameraMove.pullOut);
    });

    test('a move is never repeated twice in a row', () {
      const before = SceneCamera(move: DepthCameraMove.pushIn, intensity: 0.85);
      final camera = _camera(DepthCameraMove.pushIn, previous: before);
      expect(camera!.move, isNot(DepthCameraMove.pushIn));
      expect(camera.move, DepthCameraMove.orbitRight);
    });

    test('no hint, no camera', () {
      expect(_camera(DepthCameraMove.none), isNull);
    });
  });

  group('ContinuousSceneGenerator with camera hints', () {
    ContinuousScenePlan build() => ContinuousSceneGenerator.build(
          id: 'cam1',
          spec: const CutawaySpec(start: 5, end: 11, text: _sixWords),
          width: 720,
          height: 1280,
        );

    test('scenes after the first get a story camera and window moves pair up', () {
      final plan = build();
      plan.result.project.validate();
      final scenes = plan.result.project.scenes;
      expect(scenes.length, greaterThan(1));

      final first = scenes.first.camera;
      expect(first == null || first.move == DepthCameraMove.windowIn, isTrue);
      for (var i = 1; i < scenes.length; i++) {
        expect(scenes[i].camera, isNotNull);
      }
      for (var i = 0; i < scenes.length; i++) {
        final move = scenes[i].camera?.move;
        if (move == DepthCameraMove.windowIn) {
          expect(i + 1 < scenes.length, isTrue);
          expect(scenes[i + 1].camera!.move, DepthCameraMove.windowOut);
        }
        if (move == DepthCameraMove.windowOut) {
          expect(i > 0, isTrue);
          expect(scenes[i - 1].camera!.move, DepthCameraMove.windowIn);
        }
      }
    });

    test('the bridge off leaves every scene without a camera', () {
      CameraHintBridge.enabled = false;
      addTearDown(() => CameraHintBridge.enabled = true);
      final plan = build();
      for (final scene in plan.result.project.scenes) {
        expect(scene.camera, isNull);
      }
    });
  });
}
