/// Keeps stock B-roll that has nothing to do with the speech out of the video.
///
/// The analysis can return a vague search phrase ("kitchen", "room", "man");
/// the stock library then answers with the first popular clip for it (a fried
/// egg for "kitchen"), which the viewer sees as a mistake. This guard keeps
/// only ideas whose query names something concrete: at least two meaningful
/// words, not made only of generic words. The number of stock clips is also
/// capped, because the dense motion cutaways already carry the visual story.
/// Pure Dart, no I/O.
library;

import 'analyzer.dart' show BrollIdea;

class BrollRelevanceGuard {
  BrollRelevanceGuard._();

  static bool enabled = true;

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

  /// [ideas] reduced to the concrete ones that are long enough. Always a new
  /// list (the caller may clear and refill the original).
  static List<BrollIdea> filter(List<BrollIdea> ideas) {
    if (!enabled) return List<BrollIdea>.of(ideas);
    return ideas
        .where((idea) => idea.end - idea.start >= minSeconds && isConcrete(idea.query))
        .toList();
  }
}
