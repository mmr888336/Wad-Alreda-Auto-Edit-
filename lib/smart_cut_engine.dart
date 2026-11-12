/// Plans clean speech cuts while retaining a small, natural pause between
/// spoken sections. This class is pure Dart so its timing rules can be tested
/// without running FFmpeg or accessing media files.
class CutRange {
  final double start;
  final double end;

  const CutRange({required this.start, required this.end});

  double get duration => end - start;
}

class SilenceRange {
  final double start;
  final double end;

  const SilenceRange({required this.start, required this.end});

  double get duration => end - start;
}

class SmartCutEngine {
  SmartCutEngine._();

  static const double _epsilon = 0.0001;
  static const double _mergeGapSeconds = 0.035;

  /// Converts detected silence intervals into source-video ranges to retain.
  ///
  /// Short pauses keep a little more breathing room so speech does not sound
  /// clipped. Long pauses are compressed more aggressively. The small lead
  /// and tail margins preserve word endings and the beginning of the next
  /// phrase. Invalid/out-of-range detections are ignored or safely clamped.
  static List<CutRange> buildKeepSegments({
    required double duration,
    required List<double> silenceStarts,
    required List<double> silenceEnds,
    double minSpeechSegment = 0.14,
  }) {
    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(duration, 'duration', 'Must be finite and positive.');
    }
    if (!minSpeechSegment.isFinite || minSpeechSegment <= 0) {
      throw ArgumentError.value(
        minSpeechSegment,
        'minSpeechSegment',
        'Must be finite and positive.',
      );
    }

    final silences = _normalizeSilences(
      duration: duration,
      starts: silenceStarts,
      ends: silenceEnds,
    );

    if (silences.isEmpty) {
      return <CutRange>[CutRange(start: 0, end: duration)];
    }

    final keep = <CutRange>[];
    var cursor = 0.0;

    for (final silence in silences) {
      final retainedPause = _retainedPause(silence.duration);
      final before = retainedPause * 0.45;
      final after = retainedPause - before;
      final previousShotEnd = silence.start + before;
      final nextShotStart = silence.end - after;

      // Do not turn a leading silence into a video segment.
      if (silence.start > cursor + _epsilon) {
        final end = previousShotEnd.clamp(cursor, duration).toDouble();
        if (end - cursor >= minSpeechSegment) {
          keep.add(CutRange(start: cursor, end: end));
        }
      }

      cursor = nextShotStart.clamp(cursor, duration).toDouble();
    }

    // Keep the final spoken section, but do not retain a tiny tail of silence.
    if (duration - cursor >= minSpeechSegment) {
      keep.add(CutRange(start: cursor, end: duration));
    }

    return keep;
  }

  static double _retainedPause(double silenceDuration) {
    // The total pause heard after concatenating the retained clips.
    // A short pause keeps more natural rhythm; a long pause is shortened more.
    if (silenceDuration <= 0.85) return 0.24;
    if (silenceDuration <= 1.60) return 0.19;
    if (silenceDuration <= 3.00) return 0.15;
    return 0.12;
  }

  static List<SilenceRange> _normalizeSilences({
    required double duration,
    required List<double> starts,
    required List<double> ends,
  }) {
    final ranges = <SilenceRange>[];

    for (var i = 0; i < starts.length; i++) {
      final rawStart = starts[i];
      final rawEnd = i < ends.length ? ends[i] : duration;
      if (!rawStart.isFinite || !rawEnd.isFinite) continue;

      final start = rawStart.clamp(0.0, duration).toDouble();
      final end = rawEnd.clamp(0.0, duration).toDouble();
      if (end - start <= _epsilon) continue;

      ranges.add(SilenceRange(start: start, end: end));
    }

    ranges.sort((a, b) => a.start.compareTo(b.start));
    if (ranges.length < 2) return ranges;

    final merged = <SilenceRange>[];
    var current = ranges.first;

    for (var i = 1; i < ranges.length; i++) {
      final next = ranges[i];
      if (next.start <= current.end + _mergeGapSeconds) {
        current = SilenceRange(
          start: current.start,
          end: next.end > current.end ? next.end : current.end,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }

    merged.add(current);
    return merged;
  }
}
