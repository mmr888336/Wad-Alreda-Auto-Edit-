/// Keeps the caption off the screen while a full-screen motion cutaway is up.
///
/// A motion cutaway shows one impact word. The caption sentence drawn under
/// it at the same moment repeats that text, while the Motion Smith reference
/// shows one line of text at a time. The exporter therefore does not draw a
/// caption inside the window of a motion cutaway; outside the windows nothing
/// changes. The caption layers on the timeline are untouched (only the FFmpeg
/// `enable` expression of the overlay changes), so the editor still shows them.
/// Pure Dart, no I/O.
library;

class CaptionMotionGate {
  CaptionMotionGate._();

  /// Master switch: when false captions are drawn over cutaways as before.
  static bool enabled = true;

  static String _f(double value) => value.toStringAsFixed(2);

  /// FFmpeg `enable` expression of a caption shown from [start] to [end]
  /// that is switched off inside every window of [windows] (pairs of
  /// start and end seconds) that overlaps it. Windows that do not overlap the
  /// caption, are empty, reversed or not finite are ignored.
  static String enableExpression({
    required double start,
    required double end,
    required List<List<double>> windows,
  }) {
    final buffer = StringBuffer('between(t,${_f(start)},${_f(end)})');
    if (!enabled) return buffer.toString();
    for (final window in windows) {
      if (window.length < 2) continue;
      final from = window[0];
      final to = window[1];
      if (!from.isFinite || !to.isFinite || to <= from) continue;
      if (to <= start || from >= end) continue;
      buffer.write('*not(between(t,${_f(from)},${_f(to)}))');
    }
    return buffer.toString();
  }
}
