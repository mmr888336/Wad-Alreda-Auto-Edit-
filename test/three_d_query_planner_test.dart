import 'package:auto_edit/three_d_query_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThreeDQueryPlanner.localKeywords', () {
    test('maps Arabic words to English search keywords', () {
      expect(ThreeDQueryPlanner.localKeywords('المسجد الحرام'), contains('mosque'));
      expect(ThreeDQueryPlanner.localKeywords('زيارة الكعبة المشرفة'), contains('kaaba'));
    });

    test('handles diacritics, prefixes and alef variants', () {
      expect(ThreeDQueryPlanner.localKeywords('والقُرْآن'), contains('book'));
      expect(ThreeDQueryPlanner.localKeywords('بالمال والرزق'), contains('coins'));
    });

    test('returns nothing for unknown words', () {
      expect(ThreeDQueryPlanner.localKeywords('كلمات لا معنى لها هنا'), isEmpty);
    });
  });

  group('ThreeDQueryPlanner.parseKeywords', () {
    test('reads a keywords object and filters bad values', () {
      final words = ThreeDQueryPlanner.parseKeywords(
        '```json\n{"keywords":["Mosque","prayer rug","  ","123","mosque"]}\n```',
      );

      expect(words, <String>['mosque', 'prayer rug']);
    });

    test('reads a bare array', () {
      expect(
        ThreeDQueryPlanner.parseKeywords('["lamp","book"]'),
        <String>['lamp', 'book'],
      );
    });

    test('invalid replies give an empty list', () {
      expect(ThreeDQueryPlanner.parseKeywords('no json here'), isEmpty);
      expect(ThreeDQueryPlanner.parseKeywords('{"keywords": 5}'), isEmpty);
    });
  });

  group('ThreeDQueryPlanner.asciiKeywords', () {
    test('drops stop words and short words', () {
      expect(
        ThreeDQueryPlanner.asciiKeywords('the money and gold'),
        <String>['money', 'gold'],
      );
    });
  });

  test('containsArabic detects Arabic letters', () {
    expect(ThreeDQueryPlanner.containsArabic('hello مرحبا'), isTrue);
    expect(ThreeDQueryPlanner.containsArabic('hello'), isFalse);
  });
}
