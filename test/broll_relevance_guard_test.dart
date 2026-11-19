import 'package:auto_edit/analyzer.dart';
import 'package:auto_edit/broll_relevance_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vague queries are rejected', () {
    expect(BrollRelevanceGuard.isConcrete('kitchen'), isFalse);
    expect(BrollRelevanceGuard.isConcrete('man in room'), isFalse);
  });

  test('concrete queries are kept', () {
    expect(BrollRelevanceGuard.isConcrete('dark bathroom mirror'), isTrue);
    expect(BrollRelevanceGuard.isConcrete('abandoned hospital corridor'), isTrue);
  });

  test('filter drops short and vague ideas', () {
    final out = BrollRelevanceGuard.filter(<BrollIdea>[
      BrollIdea(4, 6, 'kitchen'),
      BrollIdea(8, 8.5, 'dark bathroom mirror'),
      BrollIdea(10, 12, 'dark bathroom mirror'),
    ]);
    expect(out.length, 1);
    expect(out.single.start, 10);
  });
}
