import 'dart:math' as math;

/// A caption reduced to what the planner needs.
class CalloutSource {
  final double start;
  final double end;
  final String text;

  const CalloutSource({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// A key word shown big in the middle of the screen with a pop animation.
class KeywordCallout {
  final String text;
  final double start;
  final double end;

  const KeywordCallout({
    required this.text,
    required this.start,
    required this.end,
  });

  double get duration => end - start;
}

class _Candidate {
  final String word;
  final double start;
  final double end;
  final double score;

  const _Candidate(this.word, this.start, this.end, this.score);
}

/// Phase 5 (motion graphics): picks the strongest word of a few captions and
/// plans a pop-in callout for it. Pure Dart.
class KeywordCalloutPlanner {
  KeywordCalloutPlanner._();

  static bool _enabled = true;

  /// Whether a callout word may be drawn over the speaker in the exported
  /// video. It is OFF: the callout is a big word that sits above the
  /// speaker's head and repeats a word of the caption shown right below it,
  /// so the same sentence was read twice on screen. Motion Smith shows one
  /// line of text at a time; the emphasis word belongs to the full-screen
  /// motion cutaways (which already draw the key words of the phrase).
  /// The planner itself still works when this is switched on.
  static bool drawOverSpeaker = false;

  /// Master switch for keyword callouts in exported videos. It is true only
  /// when the planner is enabled AND callouts may be drawn over the speaker.
  static bool get enabled => _enabled && drawOverSpeaker;

  static set enabled(bool value) {
    _enabled = value;
  }

  /// The hook title owns the first seconds of the video.
  static const double firstAllowedStart = 3.4;
  static const double minimumGap = 4.5;
  static const double bucketSeconds = 5.0;
  static const double maximumDuration = 1.3;

  static const Set<String> _stopWords = <String>{
    'الذي', 'التي', 'الذين', 'هذا', 'هذه', 'ذلك', 'تلك', 'هناك', 'لكن',
    'لأن', 'لانه', 'حتى', 'عندما', 'بعد', 'قبل', 'عند', 'كان', 'كانت',
    'يكون', 'تكون', 'ليس', 'ليست', 'كذلك', 'أيضا', 'ايضا', 'فقط', 'جدا',
    'اللي', 'عشان', 'علشان', 'كمان', 'برضو', 'لسه', 'انتم', 'هؤلاء',
    'ماذا', 'لماذا', 'كيف', 'أنه', 'انه', 'إنه', 'عليه', 'فيه', 'منه', 'لها',
    'that', 'this', 'with', 'from', 'have', 'your', 'they', 'them', 'what',
    'when', 'there', 'which', 'would', 'could', 'about', 'because', 'just',
    'very', 'also', 'been', 'were', 'will', 'then', 'than', 'into', 'more',
  };

  static String cleanWord(String word) => word.replaceAll(
        RegExp(r'[^\p{L}\p{N}]+', unicode: true),
        '',
      );

  /// The most meaningful word of [text]: the longest non-stop word of at
  /// least four letters, or null.
  static String? bestWord(String text) {
    String? best;
    var bestLength = 0;

    for (final raw in text.split(RegExp(r'\s+'))) {
      final word = cleanWord(raw);
      final length = word.runes.length;
      if (length < 4) continue;
      if (RegExp(r'^\p{N}+$', unicode: true).hasMatch(word)) continue;
      if (_stopWords.contains(word.toLowerCase())) continue;
      if (length > bestLength) {
        best = word;
        bestLength = length;
      }
    }
    return best;
  }

  static bool _overlaps(double start, double end, List<List<double>> avoid) {
    for (final range in avoid) {
      if (range.length < 2) continue;
      if (start < range[1] && end > range[0]) return true;
    }
    return false;
  }

  /// Plans at most [maxCount] callouts, spread over the video.
  static List<KeywordCallout> plan({
    required List<CalloutSource> captions,
    required double duration,
    int maxCount = 3,
    List<List<double>> avoid = const <List<double>>[],
  }) {
    if (!_enabled || maxCount <= 0 || !duration.isFinite || duration < 6) {
      return const <KeywordCallout>[];
    }

    final candidates = <_Candidate>[];
    for (final caption in captions) {
      if (caption.end - caption.start < 0.9) continue;
      if (caption.start < firstAllowedStart) continue;
      if (caption.start > duration - 1.6) continue;

      final word = bestWord(caption.text);
      if (word == null) continue;

      final start = caption.start + 0.05;
      final end = math.min(caption.end, start + maximumDuration);
      if (end - start < 0.6) continue;
      if (_overlaps(start, end, avoid)) continue;

      candidates.add(
        _Candidate(word, start, end, word.runes.length.toDouble()),
      );
    }

    // Best word of every time bucket keeps the callouts spread out.
    final byBucket = <int, _Candidate>{};
    for (final candidate in candidates) {
      final bucket = (candidate.start / bucketSeconds).floor();
      final current = byBucket[bucket];
      if (current == null || candidate.score > current.score) {
        byBucket[bucket] = candidate;
      }
    }

    final ordered = byBucket.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final spaced = <_Candidate>[];
    final usedWords = <String>{};
    for (final candidate in ordered) {
      if (spaced.isNotEmpty && candidate.start - spaced.last.start < minimumGap) {
        continue;
      }
      if (!usedWords.add(candidate.word.toLowerCase())) continue;
      spaced.add(candidate);
    }

    var picked = spaced;
    if (picked.length > maxCount) {
      final strongest = List<_Candidate>.from(picked)
        ..sort((a, b) => b.score.compareTo(a.score));
      picked = strongest.take(maxCount).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
    }

    return <KeywordCallout>[
      for (final candidate in picked)
        KeywordCallout(
          text: candidate.word,
          start: candidate.start,
          end: candidate.end,
        ),
    ];
  }

  static String _n(double value) => value.toStringAsFixed(3);

  /// FFmpeg scale factor of `t` for the pop-in: grows from 40% to a little
  /// over 100%, settles back to 100%, then stays. [overshoot] is how far it
  /// goes past 100% (0.06 is calm, 0.18 is energetic).
  static String scaleExpression({
    required double start,
    double overshoot = 0.15,
  }) {
    final a = '(t-${_n(start)})';
    final peak = 1.0 + overshoot;
    return 'if(lt($a,0.140),0.400+${_n(peak - 0.4)}*$a/0.140,'
        'if(lt($a,0.260),${_n(peak)}-${_n(overshoot)}*($a-0.140)/0.120,1))';
  }
}
