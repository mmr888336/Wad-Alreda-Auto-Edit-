/// Directed text: animated titles, timing and consistent cuts.
///
/// For every story beat this planner produces text cues that follow these
/// rules:
///  * titles are animated (rise, pop, slide, type-on, blur-in), not static
///    boxes;
///  * words of one line have different weights, sizes and styles: normal
///    words are regular, longer words are bold, the effect word is black,
///    bigger and in the display style with the accent colour;
///  * words are REPLACED in the same place: cue n+1 starts exactly when cue
///    n ends, so text never stacks up;
///  * the caption lane (upper / middle / lower) moves only when the person
///    or the microphone would cover it, and stays where it is otherwise;
///  * transitions are limited to one small, consistent set.
///
/// Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'motion_transitions.dart' show MotionTransitionKind;
import 'story_understanding.dart';

enum DirectedWeight { light, regular, bold, black }

enum DirectedFontStyle { body, display }

enum DirectedMotion { riseIn, popScale, slideFromSide, typeOn, blurIn }

enum CaptionLane { upper, middle, lower }

/// A rectangle in normalised canvas units (0..1).
class DirectedRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const DirectedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Area shared with [other] (0 when they do not touch).
  double overlapArea(DirectedRect other) {
    final width = math.min(right, other.right) - math.max(left, other.left);
    final height = math.min(bottom, other.bottom) - math.max(top, other.top);
    if (width <= 0 || height <= 0) return 0.0;
    return width * height;
  }
}

/// One word of a cue with its own look.
class DirectedWord {
  final String text;
  final DirectedWeight weight;
  final DirectedFontStyle style;

  /// Size relative to the normal caption size (1 = normal).
  final double sizeFactor;

  /// True for the effect word (drawn in the accent colour).
  final bool accent;

  const DirectedWord({
    required this.text,
    required this.weight,
    required this.style,
    required this.sizeFactor,
    required this.accent,
  });
}

/// A piece of text shown for a time, in a lane.
class DirectedTextCue {
  final int beatIndex;
  final List<DirectedWord> words;
  final double start;
  final double end;
  final DirectedMotion motion;
  final CaptionLane lane;

  const DirectedTextCue({
    required this.beatIndex,
    required this.words,
    required this.start,
    required this.end,
    required this.motion,
    required this.lane,
  });

  String get text => words.map((word) => word.text).join(' ');

  double get duration => end - start;

  bool get hasAccent => words.any((word) => word.accent);
}

class DirectedText {
  DirectedText._();

  /// Shortest time a cue stays on screen.
  static const double minCueSeconds = 0.4;

  /// Most words in one cue.
  static const int maxWordsPerCue = 3;

  /// The horizontal band of every lane.
  static const Map<CaptionLane, DirectedRect> laneBands =
      <CaptionLane, DirectedRect>{
    CaptionLane.upper:
        DirectedRect(left: 0.05, top: 0.1, right: 0.95, bottom: 0.22),
    CaptionLane.middle:
        DirectedRect(left: 0.05, top: 0.44, right: 0.95, bottom: 0.56),
    CaptionLane.lower:
        DirectedRect(left: 0.05, top: 0.72, right: 0.95, bottom: 0.84),
  };

  // Order in which a free lane is preferred when the current one is covered.
  static const List<CaptionLane> _preference = <CaptionLane>[
    CaptionLane.lower,
    CaptionLane.upper,
    CaptionLane.middle,
  ];

  static double _overlap(CaptionLane lane, List<DirectedRect> avoid) {
    final band = laneBands[lane]!;
    var total = 0.0;
    for (final rect in avoid) {
      total += band.overlapArea(rect);
    }
    return total;
  }

  /// The lane for a cue. The [previous] lane is kept as long as nothing in
  /// [avoid] (the person, the microphone) covers it; only then the first free
  /// lane is taken. When every lane is covered, the least covered one wins.
  static CaptionLane chooseLane({
    required CaptionLane previous,
    required List<DirectedRect> avoid,
  }) {
    if (_overlap(previous, avoid) <= 1e-9) return previous;
    for (final lane in _preference) {
      if (_overlap(lane, avoid) <= 1e-9) return lane;
    }
    var best = _preference.first;
    var bestArea = _overlap(best, avoid);
    for (final lane in _preference) {
      final area = _overlap(lane, avoid);
      if (area < bestArea - 1e-9) {
        best = lane;
        bestArea = area;
      }
    }
    return best;
  }

  static DirectedWord _styleWord(String text, {required bool accent}) {
    if (accent) {
      return DirectedWord(
        text: text,
        weight: DirectedWeight.black,
        style: DirectedFontStyle.display,
        sizeFactor: 1.4,
        accent: true,
      );
    }
    if (text.length >= 6) {
      return DirectedWord(
        text: text,
        weight: DirectedWeight.bold,
        style: DirectedFontStyle.body,
        sizeFactor: 1.1,
        accent: false,
      );
    }
    return DirectedWord(
      text: text,
      weight: DirectedWeight.regular,
      style: DirectedFontStyle.body,
      sizeFactor: 1.0,
      accent: false,
    );
  }

  static DirectedMotion _motionFor(StoryShotKind shot) {
    switch (shot) {
      case StoryShotKind.establishing:
        return DirectedMotion.blurIn;
      case StoryShotKind.reveal:
        return DirectedMotion.slideFromSide;
      case StoryShotKind.closeUp:
        return DirectedMotion.popScale;
      case StoryShotKind.medium:
        return DirectedMotion.riseIn;
      case StoryShotKind.detail:
        return DirectedMotion.typeOn;
    }
  }

  /// Splits [count] words into the number of cues that fits [duration].
  static List<int> _groupSizes(int count, double duration) {
    final wanted = (count / maxWordsPerCue).ceil();
    final fits = math.max(1, (duration / minCueSeconds).floor());
    final cues = math.max(1, math.min(wanted, fits));
    final base = count ~/ cues;
    final extra = count % cues;
    return <int>[
      for (var i = 0; i < cues; i++) base + (i < extra ? 1 : 0),
    ];
  }

  /// Text cues of one beat. The cues are contiguous: each one starts when
  /// the previous one ends, so words are replaced in place and never stack.
  static List<DirectedTextCue> cuesForBeat(
    StoryBeat beat, {
    required CaptionLane lane,
  }) {
    final words = StoryUnderstanding.tokens(beat.segment.text);
    final start = beat.segment.start;
    final end = beat.segment.end;
    if (words.isEmpty || end <= start) return const <DirectedTextCue>[];

    final sizes = _groupSizes(words.length, end - start);
    final effectKey = StoryUnderstanding.normalize(beat.effectWord);

    // Time share of every cue follows the amount of text in it.
    final weights = <double>[];
    var cursor = 0;
    for (final size in sizes) {
      var chars = 0;
      for (var i = cursor; i < cursor + size; i++) {
        chars += words[i].length + 2;
      }
      weights.add(chars.toDouble());
      cursor += size;
    }
    final totalWeight = weights.fold<double>(0.0, (sum, value) => sum + value);

    final cues = <DirectedTextCue>[];
    var accentUsed = false;
    var timeCursor = start;
    cursor = 0;
    for (var c = 0; c < sizes.length; c++) {
      final styled = <DirectedWord>[];
      for (var i = cursor; i < cursor + sizes[c]; i++) {
        final isAccent = !accentUsed &&
            effectKey.isNotEmpty &&
            StoryUnderstanding.normalize(words[i]) == effectKey;
        if (isAccent) accentUsed = true;
        styled.add(_styleWord(words[i], accent: isAccent));
      }
      cursor += sizes[c];

      final cueEnd = c == sizes.length - 1
          ? end
          : timeCursor + (end - start) * weights[c] / totalWeight;
      final hasAccent = styled.any((word) => word.accent);
      cues.add(
        DirectedTextCue(
          beatIndex: beat.index,
          words: styled,
          start: timeCursor,
          end: cueEnd,
          motion: hasAccent
              ? DirectedMotion.popScale
              : (c == 0 ? _motionFor(beat.shot) : DirectedMotion.riseIn),
          lane: lane,
        ),
      );
      timeCursor = cueEnd;
    }
    return cues;
  }

  /// Text cues of the whole story. [avoidByBeat] holds, per beat index, the
  /// areas the person and the microphone cover; the lane changes only when
  /// the current one is covered.
  static List<DirectedTextCue> plan(
    StoryPlan story, {
    Map<int, List<DirectedRect>> avoidByBeat =
        const <int, List<DirectedRect>>{},
  }) {
    final cues = <DirectedTextCue>[];
    var lane = CaptionLane.lower;
    for (final beat in story.beats) {
      final avoid = avoidByBeat[beat.index] ?? const <DirectedRect>[];
      lane = chooseLane(previous: lane, avoid: avoid);
      cues.addAll(cuesForBeat(beat, lane: lane));
    }
    return cues;
  }

  /// The small set of transitions the video is allowed to use.
  static const List<MotionTransitionKind> allowedTransitions =
      <MotionTransitionKind>[
    MotionTransitionKind.hardCut,
    MotionTransitionKind.matchCut,
    MotionTransitionKind.zoomSmash,
    MotionTransitionKind.whipPan,
  ];

  /// Maps any transition to the allowed set so the cuts feel like one style:
  /// soft ones become a match cut, hard graphic ones become a whip pan.
  static MotionTransitionKind unifyTransition(MotionTransitionKind kind) {
    if (allowedTransitions.contains(kind)) return kind;
    switch (kind) {
      case MotionTransitionKind.lightLeak:
      case MotionTransitionKind.blurDissolve:
        return MotionTransitionKind.matchCut;
      case MotionTransitionKind.redFlash:
      case MotionTransitionKind.pixelBlockWipe:
      case MotionTransitionKind.glitchSlice:
      case MotionTransitionKind.rgbSplit:
        return MotionTransitionKind.whipPan;
      case MotionTransitionKind.hardCut:
      case MotionTransitionKind.matchCut:
      case MotionTransitionKind.zoomSmash:
      case MotionTransitionKind.whipPan:
        return kind;
    }
  }

  /// The transitions of [story] mapped to the allowed set.
  static List<MotionTransitionKind> unifiedTransitions(StoryPlan story) {
    return <MotionTransitionKind>[
      for (final beat in story.beats) unifyTransition(beat.transitionToNext),
    ];
  }
}
