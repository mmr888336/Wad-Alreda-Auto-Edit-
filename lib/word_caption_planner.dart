import 'dart:math' as math;

/// Timing of one word inside a caption, in seconds from the caption start.
class WordCue {
  final int index;
  final double start;
  final double end;

  const WordCue({
    required this.index,
    required this.start,
    required this.end,
  });

  double get duration => end - start;
}

/// Plans the active-word highlight of a caption (the word that is being
/// spoken is drawn in an accent color). Pure Dart.
///
/// The caption is rendered once as a vertical "film strip" PNG that holds one
/// frame per word. FFmpeg then crops the frame of the active word over time,
/// so a caption still costs one input and keeps all of its motion filters.
class WordCaptionPlanner {
  WordCaptionPlanner._();

  /// Master switch for the active-word highlight in exported videos.
  static bool enabled = true;

  static const int maximumWords = 8;
  static const double minimumDuration = 0.5;

  static List<String> splitWords(String text) => text
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  static bool canHighlight(String text, double duration) {
    if (!enabled || !duration.isFinite) return false;
    final count = splitWords(text).length;
    return count >= 2 && count <= maximumWords && duration >= minimumDuration;
  }

  /// Splits [duration] between the words by their length (spoken time is
  /// roughly proportional to the number of letters, plus a small pause).
  static List<WordCue> plan({
    required String text,
    required double duration,
  }) {
    final words = splitWords(text);
    if (words.length < 2 || !duration.isFinite || duration <= 0) {
      return const <WordCue>[];
    }

    final weights = <double>[
      for (final word in words) math.max(2, word.runes.length) + 1.0,
    ];
    final total = weights.fold<double>(0, (a, b) => a + b);

    final cues = <WordCue>[];
    var cursor = 0.0;
    for (var i = 0; i < words.length; i++) {
      final end =
          i == words.length - 1 ? duration : cursor + duration * weights[i] / total;
      cues.add(WordCue(index: i, start: cursor, end: end));
      cursor = end;
    }
    return cues;
  }

  /// FFmpeg expression of `t` (seconds from the caption start) that returns
  /// the index of the active word.
  static String indexExpression(List<WordCue> cues) {
    if (cues.isEmpty) return '0';
    var expression = '${cues.last.index}';
    for (var i = cues.length - 2; i >= 0; i--) {
      expression =
          'if(lt(t,${cues[i].end.toStringAsFixed(3)}),${cues[i].index},$expression)';
    }
    return expression;
  }

  /// Crop filter that picks the film-strip frame of the active word.
  static String cropFilter({
    required int frameHeight,
    required List<WordCue> cues,
  }) {
    return "crop=w=iw:h=$frameHeight:x=0:"
        "y='$frameHeight*(${indexExpression(cues)})'";
  }
}
