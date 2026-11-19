import 'package:auto_edit/camera_hint_bridge.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The 3D scene pipeline reads the captions as a story (beatsOf) and asks the
  // bridge for the native Filament camera of every 3D scene (filamentModeFor).
  group('CameraHintBridge for the 3D (Filament) camera', () {
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

    test('beatsOf reads the story and returns no beats for no segments', () {
      expect(CameraHintBridge.beatsOf(const <StorySegment>[]), isEmpty);
      expect(CameraHintBridge.beatsOf(entryAndArrival), hasLength(2));
    });

    test('entering the window pushes in, arriving from it pulls out', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);

      expect(
        CameraHintBridge.filamentModeFor(beats, 0.0, 3.0, fallback: 'orbit'),
        'push_in',
      );
      expect(
        CameraHintBridge.filamentModeFor(beats, 3.0, 6.0, fallback: 'orbit'),
        'pull_out',
      );
    });

    test('the opening crane reveal pulls out', () {
      final beats = CameraHintBridge.beatsOf(const <StorySegment>[
        StorySegment(text: 'hello there', start: 0, end: 2),
      ]);

      expect(
        CameraHintBridge.filamentModeFor(beats, 0.0, 2.0, fallback: 'orbit'),
        'pull_out',
      );
    });

    test('the scene gets the beat that overlaps it the most', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);

      expect(
        CameraHintBridge.filamentModeFor(beats, 2.0, 5.5, fallback: 'orbit'),
        'pull_out',
      );
    });

    test('no beat for the scene gives the fallback', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);

      expect(
        CameraHintBridge.filamentModeFor(beats, 10.0, 12.0, fallback: 'orbit_fast'),
        'orbit_fast',
      );
      expect(
        CameraHintBridge.filamentModeFor(
          const <StoryBeat>[],
          0.0,
          3.0,
          fallback: 'push_in',
        ),
        'push_in',
      );
    });

    test('switching the bridge off gives the fallback', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);
      CameraHintBridge.enabled = false;

      expect(
        CameraHintBridge.filamentModeFor(beats, 0.0, 3.0, fallback: 'orbit'),
        'orbit',
      );
    });

    test('only modes of the native plugin are returned', () {
      final beats = CameraHintBridge.beatsOf(entryAndArrival);

      for (final beat in beats) {
        final mode = CameraHintBridge.filamentModeFor(
          beats,
          beat.segment.start,
          beat.segment.end,
          fallback: 'orbit',
        );
        expect(CameraHintBridge.filamentModes, contains(mode));
      }
    });
  });
}
