import 'package:auto_edit/word_caption_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    WordCaptionPlanner.enabled = true;
  });

  group('WordCaptionPlanner.plan', () {
    test('splits the duration between the words without gaps', () {
      final cues = WordCaptionPlanner.plan(
        text: 'كلمة ثانية ثالثة',
        duration: 3,
      );

      expect(cues.length, 3);
      expect(cues.first.start, 0);
      expect(cues.last.end, closeTo(3, 1e-9));
      for (var i = 1; i < cues.length; i++) {
        expect(cues[i].start, closeTo(cues[i - 1].end, 1e-9));
        expect(cues[i].duration, greaterThan(0));
      }
    });

    test('longer words get more time', () {
      final cues = WordCaptionPlanner.plan(text: 'a bbbbbbbb', duration: 2);
      expect(cues[1].duration, greaterThan(cues[0].duration));
    });

    test('a single word or invalid duration has no plan', () {
      expect(WordCaptionPlanner.plan(text: 'hello', duration: 2), isEmpty);
      expect(WordCaptionPlanner.plan(text: 'hello world', duration: 0), isEmpty);
    });
  });

  group('WordCaptionPlanner filters', () {
    test('index expression switches at each word end', () {
      final cues = WordCaptionPlanner.plan(text: 'ab cd ef', duration: 3);

      expect(
        WordCaptionPlanner.indexExpression(cues),
        'if(lt(t,1.000),0,if(lt(t,2.000),1,2))',
      );
    });

    test('crop filter selects the frame of the active word', () {
      final cues = WordCaptionPlanner.plan(text: 'ab cd', duration: 2);

      expect(
        WordCaptionPlanner.cropFilter(frameHeight: 120, cues: cues),
        "crop=w=iw:h=120:x=0:y='120*(if(lt(t,1.000),0,1))'",
      );
    });
  });

  group('WordCaptionPlanner.canHighlight', () {
    test('needs two to eight words and enough time', () {
      expect(WordCaptionPlanner.canHighlight('a b c', 1.2), isTrue);
      expect(WordCaptionPlanner.canHighlight('a', 1.2), isFalse);
      expect(WordCaptionPlanner.canHighlight('a b c', 0.3), isFalse);
      expect(
        WordCaptionPlanner.canHighlight('a b c d e f g h i', 2),
        isFalse,
      );
    });

    test('can be switched off', () {
      WordCaptionPlanner.enabled = false;
      expect(WordCaptionPlanner.canHighlight('a b c', 1.2), isFalse);
    });
  });
}
