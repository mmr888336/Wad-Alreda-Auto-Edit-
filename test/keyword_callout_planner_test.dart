import 'package:auto_edit/keyword_callout_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    KeywordCalloutPlanner.enabled = true;
    KeywordCalloutPlanner.drawOverSpeaker = false;
  });

  group('KeywordCalloutPlanner.bestWord', () {
    test('picks the longest meaningful word', () {
      expect(
        KeywordCalloutPlanner.bestWord('هذا هو النجاح الحقيقي'),
        'الحقيقي',
      );
      expect(
        KeywordCalloutPlanner.bestWord('this is a wonderful idea'),
        'wonderful',
      );
    });

    test('ignores stop words, short words and numbers', () {
      expect(KeywordCalloutPlanner.bestWord('هذا ذلك هناك'), isNull);
      expect(KeywordCalloutPlanner.bestWord('a an to 12345'), isNull);
    });

    test('strips punctuation', () {
      expect(KeywordCalloutPlanner.bestWord('"Success!"'), 'Success');
    });
  });

  group('KeywordCalloutPlanner.plan', () {
    List<CalloutSource> captions() => <CalloutSource>[
          for (var i = 0; i < 12; i++)
            CalloutSource(
              start: 1.0 + i * 2.0,
              end: 2.5 + i * 2.0,
              text: 'word${'x' * i} في الحياة',
            ),
        ];

    test('keeps clear of the hook and respects the maximum', () {
      final callouts = KeywordCalloutPlanner.plan(
        captions: captions(),
        duration: 26,
        maxCount: 3,
      );

      expect(callouts.length, lessThanOrEqualTo(3));
      expect(callouts, isNotEmpty);
      for (final callout in callouts) {
        expect(callout.start, greaterThanOrEqualTo(KeywordCalloutPlanner.firstAllowedStart));
        expect(callout.duration, greaterThanOrEqualTo(0.6));
        expect(callout.duration, lessThanOrEqualTo(KeywordCalloutPlanner.maximumDuration + 1e-9));
      }
    });

    test('callouts are spaced apart and sorted', () {
      final callouts = KeywordCalloutPlanner.plan(
        captions: captions(),
        duration: 26,
        maxCount: 6,
      );

      for (var i = 1; i < callouts.length; i++) {
        expect(
          callouts[i].start - callouts[i - 1].start,
          greaterThanOrEqualTo(KeywordCalloutPlanner.minimumGap - 1e-9),
        );
      }
    });

    test('avoids the given time ranges', () {
      final all = KeywordCalloutPlanner.plan(
        captions: captions(),
        duration: 26,
        maxCount: 6,
      );
      final blocked = <List<double>>[
        <double>[0, 100],
      ];
      final none = KeywordCalloutPlanner.plan(
        captions: captions(),
        duration: 26,
        maxCount: 6,
        avoid: blocked,
      );

      expect(all, isNotEmpty);
      expect(none, isEmpty);
    });

    test('very short videos and a disabled planner give nothing', () {
      expect(
        KeywordCalloutPlanner.plan(captions: captions(), duration: 4),
        isEmpty,
      );

      KeywordCalloutPlanner.enabled = false;
      expect(
        KeywordCalloutPlanner.plan(captions: captions(), duration: 26),
        isEmpty,
      );
    });
  });

  group('KeywordCalloutPlanner export switch', () {
    test('exported videos draw no callout over the speaker by default', () {
      expect(KeywordCalloutPlanner.drawOverSpeaker, isFalse);
      expect(KeywordCalloutPlanner.enabled, isFalse);
    });

    test('switching it on restores the callouts; the planner switch still wins', () {
      KeywordCalloutPlanner.drawOverSpeaker = true;
      expect(KeywordCalloutPlanner.enabled, isTrue);

      KeywordCalloutPlanner.enabled = false;
      expect(KeywordCalloutPlanner.enabled, isFalse);
    });
  });

  group('KeywordCalloutPlanner.scaleExpression', () {
    test('pops in, settles and stays', () {
      final expression = KeywordCalloutPlanner.scaleExpression(
        start: 5,
        overshoot: 0.15,
      );

      expect(expression, contains('(t-5.000)'));
      expect(expression, contains('1.150'));
      expect(expression, endsWith(',1))'));
    });
  });
}
