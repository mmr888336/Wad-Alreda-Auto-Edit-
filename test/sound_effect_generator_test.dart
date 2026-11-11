import 'package:auto_edit/sound_effect_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SoundEffectGenerator timeline durations', () {
    test('returns exact duration for a known preset', () {
      expect(SoundEffectGenerator.durationFor('whoosh_soft'), 0.62);
      expect(SoundEffectGenerator.durationFor('click'), 0.055);
    });

    test('returns zero when sound effects are disabled', () {
      expect(SoundEffectGenerator.durationFor('none'), 0);
    });

    test('uses the safe default duration for an unknown preset', () {
      expect(SoundEffectGenerator.durationFor('not_a_preset'), 0.62);
    });
  });
}
