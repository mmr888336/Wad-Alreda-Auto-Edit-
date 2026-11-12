/// Lightweight scene-boundary analysis and visual pacing planner.
///
/// The FFmpeg command selects frames at visual scene changes. The parser and
/// planner are pure Dart so the detected boundaries can be validated before
/// they are connected to the export pipeline.
enum VisualPace { calm, balanced, energetic }

enum SceneTransitionType { softFade, cleanCut, subtleFlash }

class VisualShot {
  final int index;
  final double start;
  final double end;
  final VisualPace pace;

  const VisualShot({
    required this.index,
    required this.start,
    required this.end,
    required this.pace,
  });

  double get duration => end - start;
}

class SceneTransitionCue {
  final double time;
  final SceneTransitionType type;
  final double duration;

  const SceneTransitionCue({
    required this.time,
    required this.type,
    required this.duration,
  });
}

class VisualScenePlan {
  final double duration;
  final List<double> cuts;
  final List<VisualShot> shots;
  final List<SceneTransitionCue> transitions;

  const VisualScenePlan({
    required this.duration,
    required this.cuts,
    required this.shots,
    required this.transitions,
  });
}

class VisualSceneEngine {
  VisualSceneEngine._();

  static const double defaultThreshold = 0.30;
  static const double defaultMinimumGap = 0.35;
  static const int defaultMaximumCuts = 120;
  static const double _edgeGuard = 0.12;
  static const double _epsilon = 0.0001;

  /// Builds an FFmpeg command that reports timestamps of detected scene cuts.
  ///
  /// A moderate threshold avoids treating every small camera movement as a
  /// new scene. The caller is responsible for executing the command and
  /// passing the resulting FFmpeg log text to [parseDetectedTimestamps].
  static String buildDetectionCommand({
    required String videoPath,
    double threshold = defaultThreshold,
  }) {
    if (videoPath.trim().isEmpty) {
      throw ArgumentError.value(videoPath, 'videoPath', 'Path cannot be empty.');
    }
    if (!threshold.isFinite || threshold <= 0 || threshold >= 1) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'Threshold must be greater than 0 and less than 1.',
      );
    }

    final safePath = videoPath.replaceAll('"', r'\"');
    final value = threshold.toStringAsFixed(2);
    return '-hide_banner -i "$safePath" '
        '-vf "select=\'gt(scene,$value)\',showinfo" '
        '-an -vsync vfr -f null -';
  }

  /// Extracts scene timestamps from FFmpeg showinfo output.
  ///
  /// Results are sorted, clamped away from the first/last frame, deduplicated,
  /// and limited to [maximumCuts] to bound render complexity on mobile.
  static List<double> parseDetectedTimestamps(
    String logs, {
    required double duration,
    double minimumGap = defaultMinimumGap,
    int maximumCuts = defaultMaximumCuts,
  }) {
    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(duration, 'duration', 'Duration must be positive.');
    }
    if (!minimumGap.isFinite || minimumGap < 0) {
      throw ArgumentError.value(
        minimumGap,
        'minimumGap',
        'Minimum gap must be finite and non-negative.',
      );
    }
    if (maximumCuts < 1) {
      throw ArgumentError.value(maximumCuts, 'maximumCuts', 'Must be positive.');
    }

    final matches = RegExp(r'pts_time:\s*(-?\d+(?:\.\d+)?)')
        .allMatches(logs)
        .map((match) => double.tryParse(match.group(1) ?? ''))
        .whereType<double>()
        .where((time) => time.isFinite)
        .map((time) => time.clamp(0.0, duration).toDouble())
        .where((time) => time > _edgeGuard && time < duration - _edgeGuard)
        .toList()
      ..sort();

    final cuts = <double>[];
    for (final time in matches) {
      if (cuts.isEmpty || time - cuts.last >= minimumGap - _epsilon) {
        cuts.add(time);
        if (cuts.length >= maximumCuts) break;
      }
    }
    return cuts;
  }

  /// Turns detected scene changes into contiguous shot ranges and transition
  /// cues. Every output shot covers a non-empty interval; the full timeline is
  /// covered from zero through [duration] without gaps or overlaps.
  static VisualScenePlan buildPlan({
    required double duration,
    required Iterable<double> sceneTimes,
    VisualPace pace = VisualPace.balanced,
    double minimumGap = defaultMinimumGap,
    int maximumCuts = defaultMaximumCuts,
  }) {
    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(duration, 'duration', 'Duration must be positive.');
    }
    if (!minimumGap.isFinite || minimumGap < 0) {
      throw ArgumentError.value(
        minimumGap,
        'minimumGap',
        'Minimum gap must be finite and non-negative.',
      );
    }
    if (maximumCuts < 1) {
      throw ArgumentError.value(maximumCuts, 'maximumCuts', 'Must be positive.');
    }

    final candidates = sceneTimes
        .where((time) => time.isFinite)
        .map((time) => time.clamp(0.0, duration).toDouble())
        .where((time) => time > _edgeGuard && time < duration - _edgeGuard)
        .toList()
      ..sort();

    final cuts = <double>[];
    for (final time in candidates) {
      if (cuts.isEmpty || time - cuts.last >= minimumGap - _epsilon) {
        cuts.add(time);
        if (cuts.length >= maximumCuts) break;
      }
    }

    final boundaries = <double>[0, ...cuts, duration];
    final shots = <VisualShot>[];
    for (var i = 0; i < boundaries.length - 1; i++) {
      final start = boundaries[i];
      final end = boundaries[i + 1];
      if (end - start <= _epsilon) continue;
      shots.add(
        VisualShot(
          index: shots.length,
          start: start,
          end: end,
          pace: _shotPace(pace, end - start),
        ),
      );
    }

    final transition = _transitionFor(pace);
    final transitionDuration = _transitionDurationFor(pace);
    final transitions = cuts
        .map(
          (time) => SceneTransitionCue(
            time: time,
            type: transition,
            duration: transitionDuration,
          ),
        )
        .toList(growable: false);

    return VisualScenePlan(
      duration: duration,
      cuts: List<double>.unmodifiable(cuts),
      shots: List<VisualShot>.unmodifiable(shots),
      transitions: List<SceneTransitionCue>.unmodifiable(transitions),
    );
  }

  static VisualPace _shotPace(VisualPace requested, double duration) {
    switch (requested) {
      case VisualPace.calm:
        return duration < 1.0 ? VisualPace.balanced : VisualPace.calm;
      case VisualPace.balanced:
        if (duration < 0.9) return VisualPace.energetic;
        if (duration > 3.8) return VisualPace.calm;
        return VisualPace.balanced;
      case VisualPace.energetic:
        return duration > 3.0 ? VisualPace.balanced : VisualPace.energetic;
    }
  }

  static SceneTransitionType _transitionFor(VisualPace pace) {
    switch (pace) {
      case VisualPace.calm:
        return SceneTransitionType.softFade;
      case VisualPace.balanced:
        return SceneTransitionType.cleanCut;
      case VisualPace.energetic:
        return SceneTransitionType.subtleFlash;
    }
  }

  static double _transitionDurationFor(VisualPace pace) {
    switch (pace) {
      case VisualPace.calm:
        return 0.20;
      case VisualPace.balanced:
        return 0.10;
      case VisualPace.energetic:
        return 0.07;
    }
  }
}
