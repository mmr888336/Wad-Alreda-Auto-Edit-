/// Dense motion-cutaway planner.
///
/// The old planner ([ReferenceSceneBuilder.planCutaways]) placed only 1 to 3
/// motion scenes in a whole video. This planner looks at the ENTIRE video:
/// the timeline is cut into windows (their size depends on the mood), every
/// caption span is scored by the meaning of its words, the best span of each
/// window is taken first, and the remaining spans fill the free gaps while the
/// spacing, the coverage and the total count stay under control.
///
/// Captions that are too short for a cutaway are merged with the captions
/// right next to them, so fast speech still gets scenes. Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'keyword_callout_planner.dart';
import 'motion_graphics.dart' show MotionMood;
import 'reference_scene_builder.dart';

class _Unit {
  final double start;
  final double end;
  final String text;

  const _Unit(this.start, this.end, this.text);
}

class _Scored {
  final CutawaySpec spec;
  final double score;

  const _Scored(this.spec, this.score);
}

class DenseCutawayPlanner {
  DenseCutawayPlanner._();

  /// Master switch. When false the exporter uses the old sparse planner.
  static bool enabled = true;

  /// The hook title owns the first seconds of the video.
  static const double firstAllowedStart = 3.6;

  static const double minDuration = 1.3;
  static const double maxDuration = 3.0;

  /// A cutaway must start at least this long before the end of the video and
  /// must end this long before it.
  static const double tailMargin = 2.2;
  static const double endMargin = 0.3;

  /// Cutaways may cover at most this share of the video.
  static const double maxCoverage = 0.40;

  /// Free time kept between two cutaways, so the speaker is seen again.
  static const double breathSeconds = 0.8;

  /// Captions closer than this are merged when one of them is too short.
  static const double mergeGap = 0.4;

  /// Free time kept around the ranges that must be avoided (B-roll clips).
  static const double avoidMargin = 0.3;

  /// Upper limit of cutaways in one video; every one is rendered on the phone.
  static const int hardCap = 12;

  static const double minVideoSeconds = 8;

  /// Size of one planning window: one scene is looked for in every window.
  static double windowSeconds(MotionMood mood) => switch (mood) {
        MotionMood.calm => 9.0,
        MotionMood.cinematic => 6.5,
        MotionMood.dynamic => 5.0,
      };

  /// How many cutaways a video of [duration] seconds is aimed at.
  static int targetCount({
    required double duration,
    required MotionMood mood,
  }) {
    if (!duration.isFinite) return 0;
    final span = duration - firstAllowedStart - tailMargin;
    if (span <= 0) return 0;
    final count = (span / windowSeconds(mood)).ceil();
    return math.min(hardCap, math.max(1, count));
  }

  static bool _hitsAvoid(double start, double end, List<List<double>> avoid) {
    for (final range in avoid) {
      if (range.length < 2) continue;
      if (start < range[1] + avoidMargin && end > range[0] - avoidMargin) {
        return true;
      }
    }
    return false;
  }

  /// Merges neighbouring captions until a span is long enough for a cutaway.
  static List<_Unit> _units(List<CalloutSource> captions) {
    final sorted = captions
        .where((c) => c.start.isFinite && c.end.isFinite && c.end > c.start)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final units = <_Unit>[];
    var i = 0;
    while (i < sorted.length) {
      final start = sorted[i].start;
      var end = sorted[i].end;
      var text = sorted[i].text.trim();
      var j = i + 1;
      while (j < sorted.length &&
          end - start < minDuration &&
          sorted[j].start - end <= mergeGap &&
          sorted[j].end - start <= maxDuration) {
        end = math.max(end, sorted[j].end);
        text = '$text ${sorted[j].text.trim()}';
        j++;
      }
      if (text.isNotEmpty) units.add(_Unit(start, end, text));
      i = j;
    }
    return units;
  }

  static List<_Scored> _candidates({
    required List<_Unit> units,
    required double duration,
    required List<List<double>> avoid,
  }) {
    final out = <_Scored>[];
    for (final unit in units) {
      if (unit.start < firstAllowedStart) continue;
      if (unit.start > duration - tailMargin) continue;

      final end = math.min(
        unit.end,
        math.min(unit.start + maxDuration, duration - endMargin),
      );
      if (end - unit.start < minDuration) continue;
      if (_hitsAvoid(unit.start, end, avoid)) continue;

      final words = ReferenceSceneBuilder.wordsOf(unit.text);
      if (words.length < 2) continue;

      final best = KeywordCalloutPlanner.bestWord(unit.text);
      final sprite = ReferenceSceneBuilder.spriteKeyFor(unit.text);
      final keywordScore =
          best == null ? 0.0 : math.min(best.runes.length, 9).toDouble();
      final spriteScore = sprite == null ? 0.0 : 6.0;
      final wordScore = math.min(words.length, 6) * 0.5;

      out.add(
        _Scored(
          CutawaySpec(start: unit.start, end: end, text: unit.text),
          keywordScore + spriteScore + wordScore,
        ),
      );
    }
    return out;
  }

  static int _byScore(_Scored a, _Scored b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.spec.start.compareTo(b.spec.start);
  }

  static bool _conflicts(
    CutawaySpec spec,
    List<CutawaySpec> accepted,
    double minGap,
  ) {
    for (final other in accepted) {
      if (spec.start < other.end + breathSeconds &&
          spec.end + breathSeconds > other.start) {
        return true;
      }
      if ((spec.start - other.start).abs() < minGap) return true;
    }
    return false;
  }

  /// Plans the cutaways of a whole video, sorted by start time.
  ///
  /// [maxCount] defaults to [targetCount] and never goes above [hardCap].
  /// [avoid] holds `[start, end]` ranges that stay free (B-roll clips).
  static List<CutawaySpec> plan({
    required List<CalloutSource> captions,
    required double duration,
    MotionMood mood = MotionMood.cinematic,
    int? maxCount,
    List<List<double>> avoid = const <List<double>>[],
  }) {
    if (!enabled || !duration.isFinite || duration < minVideoSeconds) {
      return const <CutawaySpec>[];
    }
    final limit = math.min(
      hardCap,
      maxCount ?? targetCount(duration: duration, mood: mood),
    );
    if (limit <= 0) return const <CutawaySpec>[];

    final candidates = _candidates(
      units: _units(captions),
      duration: duration,
      avoid: avoid,
    );
    if (candidates.isEmpty) return const <CutawaySpec>[];

    // The best span of every window comes first, so the scenes are spread over
    // the whole video; the other spans only fill the gaps that stay free.
    final window = windowSeconds(mood);
    final minGap = window * 0.6;
    final byWindow = <int, _Scored>{};
    for (final candidate in candidates) {
      final index = ((candidate.spec.start - firstAllowedStart) / window).floor();
      final current = byWindow[index];
      if (current == null || _byScore(candidate, current) < 0) {
        byWindow[index] = candidate;
      }
    }
    final winners = byWindow.values.toList()..sort(_byScore);
    final winnerSet = winners.toSet();
    final rest = candidates.where((c) => !winnerSet.contains(c)).toList()
      ..sort(_byScore);
    final ordered = <_Scored>[...winners, ...rest];

    final picked = <CutawaySpec>[];
    var covered = 0.0;
    for (final item in ordered) {
      if (picked.length >= limit) break;
      final spec = item.spec;
      if (covered + spec.duration > duration * maxCoverage) continue;
      if (_conflicts(spec, picked, minGap)) continue;
      picked.add(spec);
      covered += spec.duration;
    }

    picked.sort((a, b) => a.start.compareTo(b.start));
    return picked;
  }
}
