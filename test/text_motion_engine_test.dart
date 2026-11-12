import 'package:flutter_test/flutter_test.dart';
import 'package:auto_edit/text_motion_engine.dart';

void main() {
  group('TextMotionEngine', () {
    test('calm captions use restrained movement', () {
      final preset = TextMotionEngine.presetFor(
        mood: TextMotionMood.calm,
        seed: 3,
      );
      final filter = TextMotionEngine.buildFilter(
        duration: 1.5,
        mood: TextMotionMood.calm,
        seed: 3,
      );

      expect(preset, TextMotionPreset.softSettle);
      expect(filter, contains('scale='));
      expect(filter, isNot(contains('rotate=')));
    });

    test('cinematic captions use a subtle settling tilt', () {
      final preset = TextMotionEngine.presetFor(
        mood: TextMotionMood.cinematic,
        seed: 3,
      );
      final filter = TextMotionEngine.buildFilter(
        duration: 2,
        mood: TextMotionMood.cinematic,
        seed: 3,
      );

      expect(preset, TextMotionPreset.cinematicTilt);
      expect(filter, contains('rotate='));
      expect(filter, contains('eval=frame'));
    });

    test('dynamic captions rotate through different kinetic presets', () {
      final first = TextMotionEngine.presetFor(
        mood: TextMotionMood.dynamic,
        seed: 0,
      );
      final second = TextMotionEngine.presetFor(
        mood: TextMotionMood.dynamic,
        seed: 1,
      );
      final third = TextMotionEngine.presetFor(
        mood: TextMotionMood.dynamic,
        seed: 2,
      );

      expect(first, TextMotionPreset.pop);
      expect(second, TextMotionPreset.bounce);
      expect(third, TextMotionPreset.impact);
      expect({first, second, third}.length, 3);
    });

    test('important Arabic phrases use the impact preset in dynamic mode', () {
      final preset = TextMotionEngine.presetFor(
        mood: TextMotionMood.dynamic,
        seed: 0,
        text: 'انتبه، هذه هي الحقيقة!',
      );

      expect(preset, TextMotionPreset.impact);
    });

    test('important English phrases use the impact preset in dynamic mode', () {
      final preset = TextMotionEngine.presetFor(
        mood: TextMotionMood.dynamic,
        seed: 1,
        text: 'This is important',
      );

      expect(preset, TextMotionPreset.impact);
    });

    test('filter rejects non-positive and non-finite durations', () {
      expect(
        () => TextMotionEngine.buildFilter(
          duration: 0,
          mood: TextMotionMood.calm,
          seed: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => TextMotionEngine.buildFilter(
          duration: double.infinity,
          mood: TextMotionMood.calm,
          seed: 0,
        ),
        throwsArgumentError,
      );
    });

    test('all dynamic presets produce frame-evaluated even dimensions', () {
      for (var seed = 0; seed < 3; seed++) {
        final filter = TextMotionEngine.buildFilter(
          duration: 1,
          mood: TextMotionMood.dynamic,
          seed: seed,
        );

        expect(filter, contains('eval=frame'));
        expect(filter, contains('trunc(iw*('));
        expect(filter, contains('trunc(ih*('));
      }
    });
  });
}
