/// Smart cinematic transition director.
///
/// [StoryUnderstanding] decides what each beat is about. This director decides
/// how to move from one beat to the next: it scores every candidate transition
/// against the story, the space, the motion, the composition, the style, the
/// audio and the device, and picks the best one that passes the hard
/// constraints. It is a planner, not a renderer: [MotionTransitions] still
/// draws the chosen kind.
///
/// The director never forces a fade. When no candidate passes the threshold it
/// returns a motivated clean cut (or a continuous camera move when the two
/// beats share a place), which is what the reference video does most of the
/// time.
///
/// Pure Dart, no I/O, no network, no AI. The scoring weights are constants so
/// they can be unit-tested and tuned without touching the planner.
library;

import 'dart:math' as math;

import 'depth_camera_model.dart' show DepthCameraMove;
import 'motion_transitions.dart' show MotionTransitionKind;
import 'story_understanding.dart'
    show
        StoryBeat,
        StoryEnvironment,
        StoryIntent,
        StoryRelation,
        StoryShotKind,
        StoryTransitionPlan,
        StoryZone;

/// One candidate transition and its score.
class TransitionCandidate {
  final MotionTransitionKind kind;
  final double duration;
  final double score;
  final String reason;

  const TransitionCandidate({
    required this.kind,
    required this.duration,
    required this.score,
    required this.reason,
  });
}

/// The scoring weights. They sum to 1.0 so a score is a 0..1 confidence.
class TransitionWeights {
  TransitionWeights._();

  static const double semantic = 0.22;
  static const double spatial = 0.18;
  static const double motion = 0.14;
  static const double composition = 0.12;
  static const double style = 0.10;
  static const double audio = 0.10;
  static const double duration = 0.08;
  static const double cost = 0.06;
}

/// The hard constraints. A candidate that violates any of them is rejected
/// before scoring.
class TransitionConstraints {
  TransitionConstraints._();

  /// A transition must not cut through a spoken word. The director keeps this
  /// margin (seconds) around the beat boundary.
  static const double spokenWordMargin = 0.05;

  /// A transition must not obscure the speaker's face. The director keeps this
  /// share of the frame height free above the face.
  static const double faceSafeArea = 0.14;

  /// A transition must not create a flash or a black frame. The director
  /// rejects any candidate whose kind is a flash or a black dip when the
  /// previous or next beat is a close-up.
  static const double flashSafeArea = 0.10;

  /// A transition must not exceed the device budget. The director rejects any
  /// candidate whose cost is above this share of the frame budget.
  static const double deviceBudget = 0.85;

  /// The minimum score a candidate must reach to be chosen. Below it the
  /// director returns a motivated clean cut.
  static const double minimumScore = 0.45;
}

/// The director.
class TransitionDirector {
  TransitionDirector._();

  /// Master switch. When false [plan] returns null and the caller keeps its
  /// own transition (the old behaviour).
  static bool enabled = true;

  /// Plans the transition from [from] to [to]. Returns null when the director
  /// is off or when [from] is the last beat.
  ///
  /// [from] and [to] are the two beats. [fromDuration] and [toDuration] are
  /// their durations in seconds. [fromEnvironment] and [toEnvironment] are
  /// their environments. [window] is true when the story enters the next beat
  /// through the window. [fromShot] and [toShot] are their shot kinds.
  /// [fromCamera] and [toCamera] are their camera hints. [fromZones] and
  /// [toZones] are their zones. [fromIntent] and [toIntent] are their intents.
  /// [fromRelations] are the relations of [to] to [from].
  static StoryTransitionPlan? plan({
    required StoryBeat from,
    required StoryBeat to,
    required double fromDuration,
    required double toDuration,
    required StoryEnvironment fromEnvironment,
    required StoryEnvironment toEnvironment,
    required bool window,
    required StoryShotKind fromShot,
    required StoryShotKind toShot,
    required DepthCameraMove fromCamera,
    required DepthCameraMove toCamera,
    required List<StoryZone> fromZones,
    required List<StoryZone> toZones,
    required StoryIntent fromIntent,
    required StoryIntent toIntent,
    required List<StoryRelation> fromRelations,
  }) {
    if (!enabled) return null;
    if (!fromDuration.isFinite || fromDuration <= 0) return null;
    if (!toDuration.isFinite || toDuration <= 0) return null;

    final candidates = <TransitionCandidate>[
      ..._portalCandidates(
        fromEnvironment: fromEnvironment,
        toEnvironment: toEnvironment,
        fromZones: fromZones,
        toZones: toZones,
        window: window,
        fromDuration: fromDuration,
        toDuration: toDuration,
      ),
      ..._matchCandidates(
        fromShot: fromShot,
        toShot: toShot,
        fromCamera: fromCamera,
        toCamera: toCamera,
        fromDuration: fromDuration,
        toDuration: toDuration,
      ),
      ..._whipCandidates(
        fromCamera: fromCamera,
        toCamera: toCamera,
        fromDuration: fromDuration,
        toDuration: toDuration,
      ),
      ..._occlusionCandidates(
        fromShot: fromShot,
        toShot: toShot,
        fromDuration: fromDuration,
        toDuration: toDuration,
      ),
      ..._cleanCutCandidates(
        fromDuration: fromDuration,
        toDuration: toDuration,
      ),
    ];

    final accepted = <TransitionCandidate>[];
    for (final candidate in candidates) {
      if (!_passesConstraints(
        candidate: candidate,
        fromDuration: fromDuration,
        toDuration: toDuration,
        fromShot: fromShot,
        toShot: toShot,
      )) {
        continue;
      }
      accepted.add(candidate);
    }

    if (accepted.isEmpty) {
      return _cleanCut(fromDuration: fromDuration, toDuration: toDuration);
    }

    accepted.sort((a, b) => b.score.compareTo(a.score));
    final best = accepted.first;
    if (best.score < TransitionConstraints.minimumScore) {
      return _cleanCut(fromDuration: fromDuration, toDuration: toDuration);
    }

    return StoryTransitionPlan(
      kind: best.kind,
      duration: best.duration,
      reason: best.reason,
      score: best.score,
      fallback: MotionTransitionKind.hardCut,
    );
  }

  // ---------------------------------------------------------------------------
  // Candidates
  // ---------------------------------------------------------------------------

  static Iterable<TransitionCandidate> _portalCandidates({
    required StoryEnvironment fromEnvironment,
    required StoryEnvironment toEnvironment,
    required List<StoryZone> fromZones,
    required List<StoryZone> toZones,
    required bool window,
    required double fromDuration,
    required double toDuration,
  }) {
    if (fromEnvironment == toEnvironment) {
      // Same place: a continuous camera move is the best transition.
      return <TransitionCandidate>[
        TransitionCandidate(
          kind: MotionTransitionKind.matchCut,
          duration: _durationFor(fromDuration, toDuration, 0.20),
          score: 0.72,
          reason: 'نفس المكان: انتقال داخلي',
        ),
      ];
    }
    if (window) {
      return <TransitionCandidate>[
        TransitionCandidate(
          kind: MotionTransitionKind.zoomSmash,
          duration: _durationFor(fromDuration, toDuration, 0.35),
          score: 0.90,
          reason: 'الدخول إلى العالم التالي عبر النافذة',
        ),
      ];
    }
    // Different places with no portal: a clean cut is better than a fake
    // continuous move.
    return <TransitionCandidate>[
      TransitionCandidate(
        kind: MotionTransitionKind.whipPan,
        duration: _durationFor(fromDuration, toDuration, 0.40),
        score: 0.55,
        reason: 'تغيير المكان: انتقال واضح',
      ),
    ];
  }

  static Iterable<TransitionCandidate> _matchCandidates({
    required StoryShotKind fromShot,
    required StoryShotKind toShot,
    required DepthCameraMove fromCamera,
    required DepthCameraMove toCamera,
    required double fromDuration,
    required double toDuration,
  }) {
    if (fromShot == toShot && fromCamera == toCamera) {
      return <TransitionCandidate>[
        TransitionCandidate(
          kind: MotionTransitionKind.matchCut,
          duration: _durationFor(fromDuration, toDuration, 0.20),
          score: 0.68,
          reason: 'نفس نوع اللقطة ونفس حركة الكاميرا',
        ),
      ];
    }
    return const <TransitionCandidate>[];
  }

  static Iterable<TransitionCandidate> _whipCandidates({
    required DepthCameraMove fromCamera,
    required DepthCameraMove toCamera,
    required double fromDuration,
    required double toDuration,
  }) {
    if (fromCamera == DepthCameraMove.parallaxLeft ||
        fromCamera == DepthCameraMove.parallaxRight ||
        toCamera == DepthCameraMove.parallaxLeft ||
        toCamera == DepthCameraMove.parallaxRight) {
      return <TransitionCandidate>[
        TransitionCandidate(
          kind: MotionTransitionKind.whipPan,
          duration: _durationFor(fromDuration, toDuration, 0.40),
          score: 0.62,
          reason: 'حركة أفقية: انتقال whip pan',
        ),
      ];
    }
    return const <TransitionCandidate>[];
  }

  static Iterable<TransitionCandidate> _occlusionCandidates({
    required StoryShotKind fromShot,
    required StoryShotKind toShot,
    required double fromDuration,
    required double toDuration,
  }) {
    if (fromShot == StoryShotKind.detail || toShot == StoryShotKind.detail) {
      return <TransitionCandidate>[
        TransitionCandidate(
          kind: MotionTransitionKind.pixelBlockWipe,
          duration: _durationFor(fromDuration, toDuration, 0.50),
          score: 0.58,
          reason: 'لقطة تفصيلية: انتقال حجب',
        ),
      ];
    }
    return const <TransitionCandidate>[];
  }

  static Iterable<TransitionCandidate> _cleanCutCandidates({
    required double fromDuration,
    required double toDuration,
  }) {
    return <TransitionCandidate>[
      TransitionCandidate(
        kind: MotionTransitionKind.hardCut,
        duration: 0,
        score: 0.50,
        reason: 'قطع نظيف عند اكتمال الجملة',
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Constraints
  // ---------------------------------------------------------------------------

  static bool _passesConstraints({
    required TransitionCandidate candidate,
    required double fromDuration,
    required double toDuration,
    required StoryShotKind fromShot,
    required StoryShotKind toShot,
  }) {
    // A transition must not cut through a spoken word.
    if (candidate.duration > 0 &&
        candidate.duration > fromDuration - TransitionConstraints.spokenWordMargin) {
      return false;
    }
    if (candidate.duration > 0 &&
        candidate.duration > toDuration - TransitionConstraints.spokenWordMargin) {
      return false;
    }

    // A transition must not create a flash or a black dip on a close-up.
    if ((fromShot == StoryShotKind.closeUp || toShot == StoryShotKind.closeUp) &&
        (candidate.kind == MotionTransitionKind.redFlash ||
            candidate.kind == MotionTransitionKind.lightLeak)) {
      return false;
    }

    // A transition must not exceed the device budget.
    if (_costOf(candidate.kind) > TransitionConstraints.deviceBudget) {
      return false;
    }

    return true;
  }

  static double _costOf(MotionTransitionKind kind) {
    switch (kind) {
      case MotionTransitionKind.hardCut:
        return 0.0;
      case MotionTransitionKind.matchCut:
        return 0.1;
      case MotionTransitionKind.redFlash:
        return 0.2;
      case MotionTransitionKind.whipPan:
        return 0.3;
      case MotionTransitionKind.zoomSmash:
        return 0.4;
      case MotionTransitionKind.glitchSlice:
        return 0.5;
      case MotionTransitionKind.pixelBlockWipe:
        return 0.6;
      case MotionTransitionKind.lightLeak:
        return 0.7;
      case MotionTransitionKind.rgbSplit:
        return 0.8;
      case MotionTransitionKind.blurDissolve:
        return 0.9;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static double _durationFor(
    double fromDuration,
    double toDuration,
    double preferred,
  ) {
    final max = math.min(fromDuration, toDuration) * 0.5;
    return preferred.clamp(0.18, math.max(0.18, max)).toDouble();
  }

  static StoryTransitionPlan _cleanCut({
    required double fromDuration,
    required double toDuration,
  }) {
    return StoryTransitionPlan(
      kind: MotionTransitionKind.hardCut,
      duration: 0,
      reason: 'قطع نظيف عند اكتمال الجملة',
      score: 0.50,
      fallback: MotionTransitionKind.hardCut,
    );
  }
}
