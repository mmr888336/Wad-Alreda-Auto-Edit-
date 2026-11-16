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
}
