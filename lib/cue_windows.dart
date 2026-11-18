/// A time window in seconds.
typedef TimeWindow = ({double start, double end});

/// Time-window helpers for placing 3D scenes where the speaker is on screen.
/// Pure Dart, no I/O.
class CueWindows {
  CueWindows._();

  /// Shortest window (seconds) worth rendering a scene for.
  static const double minimumLength = 0.5;

  /// The parts of [start]..[end] not covered by any [blocked] window, in time
  /// order. Parts shorter than [minLength] are dropped.
  static List<TimeWindow> freeParts({
    required double start,
    required double end,
    required List<TimeWindow> blocked,
    double minLength = minimumLength,
  }) {
    if (!start.isFinite || !end.isFinite || end <= start) {
      return const <TimeWindow>[];
    }

    final ordered = List<TimeWindow>.from(blocked)
      ..sort((a, b) => a.start.compareTo(b.start));

    final parts = <TimeWindow>[];
    var cursor = start;

    for (final window in ordered) {
      if (!window.start.isFinite || !window.end.isFinite) continue;
      if (window.end <= cursor) continue;
      if (window.start >= end) break;

      if (window.start - cursor >= minLength) {
        parts.add((start: cursor, end: window.start));
      }
      if (window.end > cursor) cursor = window.end;
    }

    if (end - cursor >= minLength) {
      parts.add((start: cursor, end: end));
    }

    return parts;
  }

  /// The longest free part of [start]..[end], or null when none is left.
  static TimeWindow? longestFreePart({
    required double start,
    required double end,
    required List<TimeWindow> blocked,
    double minLength = minimumLength,
  }) {
    TimeWindow? best;
    for (final part in freeParts(
      start: start,
      end: end,
      blocked: blocked,
      minLength: minLength,
    )) {
      if (best == null || part.end - part.start > best.end - best.start) {
        best = part;
      }
    }
    return best;
  }
}
