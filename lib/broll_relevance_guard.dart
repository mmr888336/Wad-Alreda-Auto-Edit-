/// Keeps stock B-roll that has nothing to do with the speech out of the video.
///
/// The analysis can return a vague search phrase ("kitchen", "room", "man");
/// the stock library then answers with the first popular clip for it (a fried
/// egg for "kitchen"), which the viewer sees as a mistake.
///
/// Two checks work together:
///  * Story check ([filterWithStory]): every idea is compared with the story
///    beat that is spoken at the same time. The beat knows the main idea
///    (`focus`) and the objects that belong to it (`props`); an idea is kept
///    only when its query is about that idea, instead of being judged by its
///    words alone.
///  * Word check ([filter], also the fallback when a moment has no known idea):
///    at least two meaningful words, not made only of generic words.
///
/// The number of stock clips is also capped, because the dense motion cutaways
/// already carry the visual story. Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'analyzer.dart' show BrollIdea;
import 'story_understanding.dart' show StoryBeat, StoryUnderstanding;

class BrollRelevanceGuard {
  BrollRelevanceGuard._();

  static bool enabled = true;

  /// When true, [filterWithStory] judges ideas by the story beat. When false
  /// it behaves exactly like [filter].
  static bool useStory = true;

  /// When true, an idea whose moment has a known idea (focus) must be about
  /// that idea. When false, an unrelated but concrete query is still kept.
  static bool strictStory = true;

  /// Most stock clips in one video.
  static const int maxClips = 3;

  /// Shortest stock clip worth showing, in seconds.
  static const double minSeconds = 1.8;

  static const int minMeaningfulWords = 2;

  static const Set<String> generic = <String>{
    'a', 'an', 'the', 'of', 'in', 'on', 'at', 'to', 'and', 'with', 'for',
    'kitchen', 'room', 'house', 'home', 'man', 'woman', 'person', 'people',
    'guy', 'boy', 'girl', 'video', 'background', 'scene', 'shot', 'view',
    'close', 'up', 'footage', 'stock', 'generic', 'something', 'thing',
    'things', 'life', 'time', 'day', 'night', 'world', 'place', 'concept',
    'abstract', 'nature', 'city', 'business', 'hd', '4k',
  };

  static final RegExp _splitter = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static List<String> meaningfulWords(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.length >= 3 && !generic.contains(w))
        .toList();
  }

  /// True when [query] names something specific enough to search for.
  static bool isConcrete(String query) {
    return meaningfulWords(query).length >= minMeaningfulWords;
  }

  /// Normalised, singular keys of the words of [raw] (same spelling rules as
  /// the story lexicon, so Arabic and English both work).
  static List<String> _keys(String raw) {
    return <String>[
      for (final word in raw.toLowerCase().split(_splitter))
        if (word.isNotEmpty) _stem(StoryUnderstanding.normalize(word)),
    ];
  }

  static String _stem(String word) {
    if (word.length > 3 && word.endsWith('s')) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  /// The beat that overlaps [idea] the most in time, or null when none does.
  static StoryBeat? beatFor(BrollIdea idea, List<StoryBeat> beats) {
    StoryBeat? best;
    var bestOverlap = 0.0;
    for (final beat in beats) {
      final overlap = math.min(idea.end, beat.segment.end) -
          math.max(idea.start, beat.segment.start);
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        best = beat;
      }
    }
    return best;
  }

  /// Words that belong to what [beat] is about: its main idea (focus), its
  /// props, and the trigger words of that idea.
  static Set<String> beatTerms(StoryBeat beat) {
    final terms = <String>{};
    void add(String raw) {
      for (final key in _keys(raw)) {
        if (key.length >= 2 && !generic.contains(key)) terms.add(key);
      }
    }

    if (beat.focus == 'none') return terms;
    add(beat.focus);
    for (final prop in beat.props) {
      add(prop);
    }
    for (final concept in StoryUnderstanding.concepts) {
      if (concept.id != beat.focus) continue;
      for (final trigger in concept.triggers) {
        add(trigger);
      }
    }
    return terms;
  }

  /// True when [query] is about the idea of [beat] (shares a word with its
  /// focus, props or trigger words). Always false for a beat without a known
  /// idea.
  static bool isRelated(String query, StoryBeat beat) {
    if (beat.focus == 'none') return false;
    final terms = beatTerms(beat);
    for (final key in _keys(query)) {
      if (key.length < 2 || generic.contains(key)) continue;
      for (final term in terms) {
        if (key == term) return true;
        if (key.length >= 4 &&
            term.length >= 4 &&
            (key.startsWith(term) || term.startsWith(key))) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _accepts(BrollIdea idea, List<StoryBeat> beats) {
    final beat = beatFor(idea, beats);
    // No beat, or a moment without a known idea: judge by the words alone.
    if (beat == null || beat.focus == 'none') return isConcrete(idea.query);
    if (isRelated(idea.query, beat)) {
      return meaningfulWords(idea.query).isNotEmpty;
    }
    return !strictStory && isConcrete(idea.query);
  }

  /// [ideas] reduced to the concrete ones that are long enough. Always a new
  /// list (the caller may clear and refill the original).
  static List<BrollIdea> filter(List<BrollIdea> ideas) {
    if (!enabled) return List<BrollIdea>.of(ideas);
    return ideas
        .where((idea) => idea.end - idea.start >= minSeconds && isConcrete(idea.query))
        .toList();
  }

  /// Like [filter], but every idea is also compared with the story [beats]
  /// (focus and props of the beat spoken at the same time). Always a new list.
  static List<BrollIdea> filterWithStory(
    List<BrollIdea> ideas,
    List<StoryBeat> beats,
  ) {
    if (!enabled) return List<BrollIdea>.of(ideas);
    if (!useStory || beats.isEmpty) return filter(ideas);
    return ideas
        .where((idea) => idea.end - idea.start >= minSeconds && _accepts(idea, beats))
        .toList();
  }
}
