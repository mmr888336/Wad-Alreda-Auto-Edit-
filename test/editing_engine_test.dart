
import 'package:auto_edit/editing_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditingEngine automatic topic profiles', () {
    test('chooses a calm treatment for Seerah and religious content', () {
      final profile = EditingEngine.select(
        content: 'سيرة النبي ومواقف الصحابة والتوكل على الله',
        requestedStyle: 'auto',
      );

      expect(profile.topic, EditTopic.religious);
      expect(profile.visualStyle, 'clean');
      expect(profile.punchZoom, isFalse);
      expect(profile.flashTransitions, isFalse);
    });

    test('chooses a more energetic treatment for product reviews', () {
      final profile = EditingEngine.select(
        content: 'مراجعة منتج جديد وسعره متوفر في المتجر',
        requestedStyle: 'auto',
      );

      expect(profile.topic, EditTopic.product);
      expect(profile.visualStyle, 'vivid');
      expect(profile.punchZoom, isTrue);
      expect(profile.flashTransitions, isTrue);
      expect(profile.maxBroll, 5);
    });

    test('preserves a manual visual style override', () {
      final profile = EditingEngine.select(
        content: 'سيرة النبي',
        requestedStyle: 'clean',
      );

      expect(profile.isAutomatic, isFalse);
      expect(profile.visualStyle, 'clean');
    });

    test('uses a balanced profile when the topic is unclear', () {
      final profile = EditingEngine.select(
        content: 'A quiet moment with no clear subject',
        requestedStyle: 'auto',
      );

      expect(profile.topic, EditTopic.general);
      expect(profile.visualStyle, 'cinematic');
    });
  });
}