import 'package:auto_edit/analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Analyzer.cleanCaptions', () {
    test('merges the same text repeated back to back', () {
      final cleaned = Analyzer.cleanCaptions(<Caption>[
        Caption(0, 1, 'لا إله إلا'),
        Caption(1, 2, 'لا إله إلا'),
        Caption(2, 3, 'الله أكبر'),
      ]);

      expect(cleaned.length, 2);
      expect(cleaned.first.start, 0);
      expect(cleaned.first.end, 2);
      expect(cleaned.last.text, 'الله أكبر');
    });

    test('ignores punctuation and letter case when comparing', () {
      final cleaned = Analyzer.cleanCaptions(<Caption>[
        Caption(0, 1, 'Hello, world'),
        Caption(1.2, 2, 'hello world!'),
      ]);

      expect(cleaned.length, 1);
      expect(cleaned.first.end, 2);
    });

    test('keeps a phrase that is repeated much later', () {
      final cleaned = Analyzer.cleanCaptions(<Caption>[
        Caption(0, 1, 'كلمة مهمة'),
        Caption(5, 6, 'كلمة مهمة'),
      ]);

      expect(cleaned.length, 2);
    });

    test('removes overlap so two captions are never shown together', () {
      final cleaned = Analyzer.cleanCaptions(<Caption>[
        Caption(0, 2, 'أول'),
        Caption(1, 3, 'ثاني'),
      ]);

      expect(cleaned.length, 2);
      expect(cleaned.first.end, lessThanOrEqualTo(cleaned.last.start));
    });

    test('drops empty text and sorts by start time', () {
      final cleaned = Analyzer.cleanCaptions(<Caption>[
        Caption(3, 4, 'b'),
        Caption(1, 2, '   '),
        Caption(0, 1, 'a'),
      ]);

      expect(cleaned.map((c) => c.text), <String>['a', 'b']);
    });
  });

  group('Analyzer.collapseRepeatedWords', () {
    test('collapses a phrase repeated inside one sentence', () {
      expect(
        Analyzer.collapseRepeatedWords('one two three one two three'),
        'one two three',
      );
    });

    test('keeps natural emphasis of a single word', () {
      expect(
        Analyzer.collapseRepeatedWords('لا لا لا'),
        'لا لا لا',
      );
    });

    test('collapses a word stuck in a loop', () {
      expect(
        Analyzer.collapseRepeatedWords('نعم نعم نعم نعم نعم نعم'),
        'نعم',
      );
    });

    test('leaves a normal sentence unchanged', () {
      expect(
        Analyzer.collapseRepeatedWords('هذا كلام عادي جداً'),
        'هذا كلام عادي جداً',
      );
    });
  });

  group('Analyzer.cleanSegments', () {
    test('merges the same long sentence repeated by Whisper', () {
      final cleaned = Analyzer.cleanSegments(<Caption>[
        Caption(0, 3, 'a b c d e f'),
        Caption(3, 6, 'a b c d e f'),
        Caption(6, 8, 'g h i'),
      ]);

      expect(cleaned.length, 2);
      expect(cleaned.first.start, 0);
      expect(cleaned.first.end, 6);
      expect(cleaned.last.text, 'g h i');
    });

    test('drops a segment that is part of the overlapping previous one', () {
      final cleaned = Analyzer.cleanSegments(<Caption>[
        Caption(0, 4, 'a b c d e f'),
        Caption(1, 3, 'c d e'),
      ]);

      expect(cleaned.length, 1);
      expect(cleaned.first.text, 'a b c d e f');
    });

    test('replaces the previous segment when the new one contains it', () {
      final cleaned = Analyzer.cleanSegments(<Caption>[
        Caption(0, 2, 'a b c'),
        Caption(1, 4, 'a b c d e'),
      ]);

      expect(cleaned.length, 1);
      expect(cleaned.first.text, 'a b c d e');
      expect(cleaned.first.start, 0);
      expect(cleaned.first.end, 4);
    });

    test('keeps the same sentence when it is said again much later', () {
      final cleaned = Analyzer.cleanSegments(<Caption>[
        Caption(0, 2, 'a b c'),
        Caption(10, 12, 'a b c'),
      ]);

      expect(cleaned.length, 2);
    });

    test('keeps different sentences that do not overlap', () {
      final cleaned = Analyzer.cleanSegments(<Caption>[
        Caption(0, 2, 'a b c'),
        Caption(2, 4, 'd e f'),
      ]);

      expect(cleaned.map((c) => c.text), <String>['a b c', 'd e f']);
    });
  });
}
