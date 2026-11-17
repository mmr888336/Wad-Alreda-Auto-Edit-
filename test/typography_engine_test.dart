import 'package:auto_edit/text_motion_engine.dart';
import 'package:auto_edit/typography_engine.dart';
import 'package:auto_edit/word_caption_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TypographyEngine', () {
    test('detects Arabic as right-to-left', () {
      expect(TypographyEngine.isRtlText('مرحبا بكم'), isTrue);
      expect(TypographyEngine.isRtlText('hello world'), isFalse);
    });

    test('Arabic plan has no letter spacing and covers every word', () {
      final plan = TypographyEngine.plan(
        text: 'الحقيقة عن النجاح في 2026 مهمة جدا',
        duration: 4,
        mood: TextMotionMood.cinematic,
      );
      expect(plan.rtl, isTrue);
      expect(plan.letterSpacingEm, 0.0);
      expect(plan.words.length, 7);
      final indexed = plan.lines.expand((line) => line).toList()..sort();
      expect(indexed, <int>[0, 1, 2, 3, 4, 5, 6]);
    });

    test('emphasis words and numbers become giant', () {
      final plan = TypographyEngine.plan(
        text: 'السر في 2026',
        duration: 2,
      );
      expect(plan.words[0].giant, isTrue);
      expect(plan.words[1].scale, lessThan(1.0));
      expect(plan.words[2].giant, isTrue);
    });

    test('real word timings drive the highlight', () {
      final plan = TypographyEngine.plan(
        text: 'one two three',
        duration: 3,
        wordTimings: const <WordCue>[
          WordCue(index: 0, start: 0.0, end: 0.5),
          WordCue(index: 1, start: 0.8, end: 1.2),
          WordCue(index: 2, start: 1.6, end: 2.0),
        ],
      );
      expect(plan.words[1].start, closeTo(0.8, 1e-9));
      expect(plan.words[0].end, closeTo(0.8, 1e-9));
      expect(plan.words[2].end, closeTo(3.0, 1e-9));
    });

    test('invalid timings fall back to the length based plan', () {
      final plan = TypographyEngine.plan(
        text: 'one two three',
        duration: 3,
        wordTimings: const <WordCue>[
          WordCue(index: 0, start: 1.0, end: 1.5),
          WordCue(index: 1, start: 0.5, end: 0.9),
          WordCue(index: 2, start: 1.6, end: 2.0),
        ],
      );
      expect(plan.words.last.end, closeTo(3.0, 1e-9));
    });

    test('splitPhrases keeps phrases short', () {
      final phrases = TypographyEngine.splitPhrases(
        'one two three four five six seven eight nine ten eleven twelve',
        maxWords: 5,
      );
      for (final phrase in phrases) {
        expect(phrase.split(' ').length, lessThanOrEqualTo(6));
      }
    });

    test('empty text throws', () {
      expect(
        () => TypographyEngine.plan(text: '   ', duration: 1),
        throwsArgumentError,
      );
    });
  });

  group('TypographyMotion', () {
    test('alpha filter has fade in and fade out', () {
      final filter = TypographyMotion.buildAlphaFilter(
        duration: 2,
        entrance: TypographyEntrance.zoomIn,
        exit: TypographyExit.fadeOut,
      );
      expect(filter, contains('fade=t=in'));
      expect(filter, contains('fade=t=out'));
    });

    test('cut exit has no fade out', () {
      final filter = TypographyMotion.buildAlphaFilter(
        duration: 2,
        entrance: TypographyEntrance.pop,
        exit: TypographyExit.cut,
      );
      expect(filter, isNot(contains('fade=t=out')));
    });

    test('scale filter is null for fade only pair', () {
      expect(
        TypographyMotion.buildScaleFilter(
          duration: 2,
          entrance: TypographyEntrance.fadeUp,
          exit: TypographyExit.fadeOut,
        ),
        isNull,
      );
    });

    test('scale filter rejects invalid duration', () {
      expect(
        () => TypographyMotion.buildScaleFilter(
          duration: 0,
          entrance: TypographyEntrance.pop,
          exit: TypographyExit.cut,
        ),
        throwsArgumentError,
      );
    });
  });
}
