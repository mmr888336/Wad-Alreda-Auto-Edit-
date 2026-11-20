import 'package:auto_edit/camera_hint_bridge.dart';
import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/world_scene_camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The camera of a world scene of the 3D pipeline comes from the story hint
  // (CameraHintBridge), with the rules of the camera story.
  group('WorldSceneCamera', () {
    final wasEnabled = CameraHintBridge.enabled;

    tearDown(() {
      CameraHintBridge.enabled = wasEnabled;
    });

    // Two ideas in two different worlds (office, then room): the story enters
    // the window at the end of the first and arrives from it in the second.
    const entryAndArrival = <StorySegment>[
      StorySegment(text: 'money profit sales', start: 0, end: 3),
      StorySegment(text: 'sleep health rest', start: 3, end: 6),
    ];

    MotionScene sceneOf(double start, double end) => MotionScene(
          id: 'scene_$start',
          start: start,
          end: end,
          layers: const <MotionLayer>[],
        );

    test('an entry into the window is followed by its arrival', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);

      final entry = WorldSceneCamera.plan(
        scene: sceneOf(0, 3),
        beats: beats,
        previous: null,
        hasNext: true,
      );
      expect(entry, isNotNull);
      expect(entry!.move, DepthCameraMove.windowIn);

      final arrival = WorldSceneCamera.plan(
        scene: sceneOf(3, 6),
        beats: beats,
        previous: entry,
        hasNext: false,
      );
      expect(arrival, isNotNull);
      expect(arrival!.move, DepthCameraMove.windowOut);
      expect(arrival.intensity, entry.intensity);
    });

    test('an entry with no scene after it is a push in', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);

      final camera = WorldSceneCamera.plan(
        scene: sceneOf(0, 3),
        beats: beats,
        previous: null,
        hasNext: false,
      );

      expect(camera, isNotNull);
      expect(camera!.move, DepthCameraMove.pushIn);
    });

    test('an arrival with no entry before it is a pull out', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);

      final camera = WorldSceneCamera.plan(
        scene: sceneOf(3, 6),
        beats: beats,
        previous: null,
        hasNext: false,
      );

      expect(camera, isNotNull);
      expect(camera!.move, DepthCameraMove.pullOut);
    });

    test('the opening beat gets its crane reveal from the story', () {
      final beats = CameraHintBridge.beatsOf(const <StorySegment>[
        StorySegment(text: 'hello there', start: 0, end: 2),
      ]);

      final camera = WorldSceneCamera.plan(
        scene: sceneOf(0, 2),
        beats: beats,
        previous: null,
        hasNext: false,
      );

      expect(camera, isNotNull);
      expect(camera!.move, DepthCameraMove.craneUp);
    });

    test('a scene no beat overlaps gets no camera', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);

      expect(
        WorldSceneCamera.plan(
          scene: sceneOf(10, 12),
          beats: beats,
          previous: null,
          hasNext: false,
        ),
        isNull,
      );
      expect(
        WorldSceneCamera.plan(
          scene: sceneOf(0, 3),
          beats: const <StoryBeat>[],
          previous: null,
          hasNext: false,
        ),
        isNull,
      );
    });

    test('switching the bridge off gives no camera', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);
      CameraHintBridge.enabled = false;

      expect(
        WorldSceneCamera.plan(
          scene: sceneOf(0, 3),
          beats: beats,
          previous: null,
          hasNext: true,
        ),
        isNull,
      );
    });

    test('only scenes with almost no speaker video between them are adjacent',
        () {
      expect(WorldSceneCamera.areAdjacent(3.0, 3.0), isTrue);
      expect(WorldSceneCamera.areAdjacent(3.0, 3.5), isTrue);
      expect(WorldSceneCamera.areAdjacent(3.0, 4.0), isFalse);
    });
  });
}
