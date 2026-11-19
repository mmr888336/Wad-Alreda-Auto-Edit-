import 'package:auto_edit/analyzer.dart';
import 'package:auto_edit/broll_relevance_guard.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:flutter_test/flutter_test.dart';

List<StoryBeat> _beats(List<StorySegment> segments) =>
    StoryUnderstanding.plan(segments).beats;

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

  group('story beats', () {
    final money = StorySegment(text: 'making money from sales', start: 4, end: 9);
    final unknown = StorySegment(text: 'xyz qwerty', start: 9, end: 14);

    test('beatFor picks the beat with the largest overlap', () {
      final beats = _beats(<StorySegment>[
        StorySegment(text: 'making money from sales', start: 0, end: 4),
        unknown,
      ]);
      expect(beats.first.focus, 'money');
      final beat = BrollRelevanceGuard.beatFor(BrollIdea(3, 8, 'coins'), beats);
      expect(beat, isNotNull);
      expect(beat!.segment.start, 4 > 3 ? 0 : 0);
      expect(BrollRelevanceGuard.beatFor(BrollIdea(20, 22, 'coins'), beats), isNull);
    });

    test('an idea about the focus or props of the beat is kept', () {
      final beats = _beats(<StorySegment>[money]);
      expect(beats.single.focus, 'money');
      final out = BrollRelevanceGuard.filterWithStory(
        <BrollIdea>[BrollIdea(4, 7, 'coins')],
        beats,
      );
      expect(out.length, 1);
    });

    test('a concrete idea about something else is rejected', () {
      final beats = _beats(<StorySegment>[money]);
      final idea = BrollIdea(4, 7, 'fried egg pan');
      expect(BrollRelevanceGuard.isConcrete(idea.query), isTrue);
      expect(BrollRelevanceGuard.filterWithStory(<BrollIdea>[idea], beats), isEmpty);
      expect(BrollRelevanceGuard.filter(<BrollIdea>[idea]).length, 1);
    });

    test('a moment without a known idea falls back to the word check', () {
      final beats = _beats(<StorySegment>[unknown]);
      expect(beats.single.focus, 'none');
      final out = BrollRelevanceGuard.filterWithStory(
        <BrollIdea>[
          BrollIdea(9, 12, 'kitchen'),
          BrollIdea(9, 12, 'dark bathroom mirror'),
        ],
        beats,
      );
      expect(out.length, 1);
      expect(out.single.query, 'dark bathroom mirror');
    });

    test('strictStory false keeps unrelated concrete ideas', () {
      final beats = _beats(<StorySegment>[money]);
      BrollRelevanceGuard.strictStory = false;
      addTearDown(() => BrollRelevanceGuard.strictStory = true);
      final out = BrollRelevanceGuard.filterWithStory(
        <BrollIdea>[BrollIdea(4, 7, 'fried egg pan')],
        beats,
      );
      expect(out.length, 1);
    });

    test('short ideas are dropped and an empty beat list behaves like filter', () {
      final beats = _beats(<StorySegment>[money]);
      expect(
        BrollRelevanceGuard.filterWithStory(<BrollIdea>[BrollIdea(4, 5, 'coins')], beats),
        isEmpty,
      );
      final out = BrollRelevanceGuard.filterWithStory(
        <BrollIdea>[BrollIdea(4, 7, 'dark bathroom mirror')],
        const <StoryBeat>[],
      );
      expect(out.length, 1);
    });
  });
}
