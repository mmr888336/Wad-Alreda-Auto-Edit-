import 'dart:math' as math;

import 'person_tracking_models.dart';

/// Where a 3D scene card sits relative to the tracked person.
enum PersonPlacement { aboveHead, behindShoulder, besideHand }

extension PersonPlacementBehavior on PersonPlacement {
  /// True when the person must be drawn over the 3D card so the card looks
  /// like it stands behind the person.
  bool get occludedByPerson => this == PersonPlacement.behindShoulder;
}

/// Center of the 3D card at one moment, normalized to the frame (0..1).
class AnchorKeyframe {
  final double time;
  final double x;
  final double y;

  const AnchorKeyframe({
    required this.time,
    required this.x,
    required this.y,
  });
}

/// Smoothed path of a 3D card that follows the main person during one scene.
class PersonAnchorPath {
  static const List<PersonPlacement> defaultCycle = <PersonPlacement>[
    PersonPlacement.behindShoulder,
    PersonPlacement.aboveHead,
    PersonPlacement.besideHand,
  ];

  /// Minimum share of the scene where the person must be visible.
  static const double minimumCoverage = 0.6;

  /// Free space kept between a card and the head, as a share of the shorter
  /// frame edge.
  static const double headClearance = 0.015;

  /// A card that cannot keep clear of the head is shrunk by this factor, up to
  /// [maximumShrinkSteps] times, before the plan is given up (null).
  static const double shrinkFactor = 0.8;
  static const int maximumShrinkSteps = 4;

  /// Smallest card side (share of the shorter frame edge) worth showing.
  static const double minimumSideFraction = 0.12;

  final PersonPlacement placement;
  final double start;
  final double end;
  final int frameWidth;
  final int frameHeight;

  /// Card side relative to the shorter frame edge.
  final double sideFraction;

  /// Share of the scene where the person was really visible.
  final double coverage;
  final List<AnchorKeyframe> keyframes;

  PersonAnchorPath({
    required this.placement,
    required this.start,
    required this.end,
    required this.frameWidth,
    required this.frameHeight,
    required this.sideFraction,
    required this.coverage,
    required List<AnchorKeyframe> keyframes,
  }) : keyframes = List<AnchorKeyframe>.unmodifiable(keyframes);

  /// Card side in pixels (always even, for video encoders).
  int get sidePixels {
    final rounded = (math.min(frameWidth, frameHeight) * sideFraction).round();
    return rounded.isEven ? rounded : rounded + 1;
  }

  /// Overlay `x` expression (top-left corner in pixels) over timeline time `t`.
  String xExpression() => piecewiseExpression(
        keyframes.map((k) => k.time).toList(),
        keyframes.map((k) => k.x * frameWidth - sidePixels / 2).toList(),
      );

  /// Overlay `y` expression (top-left corner in pixels) over timeline time `t`.
  String yExpression() => piecewiseExpression(
        keyframes.map((k) => k.time).toList(),
        keyframes.map((k) => k.y * frameHeight - sidePixels / 2).toList(),
      );

  /// Builds a piecewise-linear FFmpeg expression of `t`.
  static String piecewiseExpression(List<double> times, List<double> values) {
    if (times.isEmpty || times.length != values.length) {
      throw ArgumentError('times and values must have the same length.');
    }
    if (values.length == 1) return _n(values.first);

    var expression = _n(values.last);
    for (var i = times.length - 2; i >= 0; i--) {
      final t0 = times[i];
      final t1 = times[i + 1];
      final v0 = values[i];
      final v1 = values[i + 1];
      final dt = t1 - t0;
      final segment = dt <= 1e-6
          ? _n(v1)
          : '${_n(v0)}+(${_n(v1 - v0)})*(t-${_t(t0)})/${_t(dt)}';
      expression = 'if(lt(t,${_t(t1)}),$segment,$expression)';
    }
    return expression;
  }

  static String _n(double value) => value.toStringAsFixed(1);
  static String _t(double value) => value.toStringAsFixed(3);

  /// Plans the card path for [start]..[end]. Returns null when the person is
  /// not visible for enough of the scene, so the caller can fall back.
  static PersonAnchorPath? plan({
    required PersonTrack track,
    required double start,
    required double end,
    required PersonPlacement placement,
    required int frameWidth,
    required int frameHeight,
    double sampleFps = 5,
    double minCoverage = minimumCoverage,
  }) {
    if (frameWidth <= 0 || frameHeight <= 0 || track.isEmpty) return null;
    if (!start.isFinite || !end.isFinite || end - start < 0.4) return null;

    final fps = sampleFps.clamp(2.0, 12.0).toDouble();
    final steps = math.max(2, ((end - start) * fps).ceil());
    final w = frameWidth.toDouble();
    final h = frameHeight.toDouble();
    final shortEdge = math.min(w, h);

    final times = <double>[];
    final samples = <PersonObservation?>[];
    var found = 0;
    for (var i = 0; i <= steps; i++) {
      final time = start + (end - start) * i / steps;
      final sample = track.sampleAt(
        time,
        maxInterpolationGap: 0.8,
        holdTolerance: 0.4,
      );
      times.add(time);
      samples.add(sample);
      if (sample != null) found++;
    }

    final coverage = found / samples.length;
    if (found == 0 || coverage < minCoverage) return null;

    final sides = <double>[
      for (final sample in samples)
        if (sample != null) _sidePixels(sample, placement, w, h),
    ]..sort();
    var sideFraction =
        (sides[sides.length ~/ 2] / shortEdge).clamp(0.12, 0.6).toDouble();

    // Put the card on the side of the person that has more free room.
    var direction = 1.0;
    for (final sample in samples) {
      if (sample != null) {
        direction = sample.box.centerX <= 0.5 ? 1.0 : -1.0;
        break;
      }
    }

    // A card that is not hidden behind the person must never cover the face:
    // if it cannot be placed clear of the head, it is made smaller, and if it
    // still cannot, there is no plan (the caller keeps the plain scene).
    late List<double> smoothX;
    late List<double> smoothY;
    var shrinkSteps = 0;
    while (true) {
      final side = sideFraction * shortEdge;
      final xs = List<double?>.filled(samples.length, null);
      final ys = List<double?>.filled(samples.length, null);
      for (var i = 0; i < samples.length; i++) {
        final sample = samples[i];
        if (sample == null) continue;
        final target = _target(sample, placement, direction, w, h, side);
        xs[i] = target.x;
        ys[i] = target.y;
      }
      _fillGaps(xs);
      _fillGaps(ys);

      smoothX = _smooth(<double>[for (final v in xs) v!]);
      smoothY = _smooth(<double>[for (final v in ys) v!]);

      if (placement.occludedByPerson ||
          !_coversHead(samples, smoothX, smoothY, w, h, side)) {
        break;
      }
      final smaller = sideFraction * shrinkFactor;
      if (shrinkSteps >= maximumShrinkSteps || smaller < minimumSideFraction) {
        return null;
      }
      shrinkSteps++;
      sideFraction = smaller;
    }

    return PersonAnchorPath(
      placement: placement,
      start: start,
      end: end,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      sideFraction: sideFraction,
      coverage: coverage,
      keyframes: <AnchorKeyframe>[
        for (var i = 0; i < times.length; i++)
          AnchorKeyframe(
            time: times[i],
            x: smoothX[i] / w,
            y: smoothY[i] / h,
          ),
      ],
    );
  }

  static double _shoulderPixels(PersonObservation o, double w, double h) {
    final left = o.landmark(BodyLandmark.leftShoulder);
    final right = o.landmark(BodyLandmark.rightShoulder);
    if (left != null && right != null) {
      final dx = (left.x - right.x) * w;
      final dy = (left.y - right.y) * h;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > 4) return distance;
    }
    return o.box.width * w * 0.55;
  }

  static double _sidePixels(
    PersonObservation o,
    PersonPlacement placement,
    double w,
    double h,
  ) {
    final shoulder = _shoulderPixels(o, w, h);
    final shortEdge = math.min(w, h);
    switch (placement) {
      case PersonPlacement.aboveHead:
        return (shoulder * 1.0).clamp(shortEdge * 0.16, shortEdge * 0.38);
      case PersonPlacement.behindShoulder:
        return (shoulder * 1.5).clamp(shortEdge * 0.24, shortEdge * 0.5);
      case PersonPlacement.besideHand:
        return (shoulder * 0.85).clamp(shortEdge * 0.14, shortEdge * 0.3);
    }
  }

  static math.Point<double>? _pickHand(PersonObservation o) {
    final left = o.anchor(PersonAnchor.leftHand);
    final right = o.anchor(PersonAnchor.rightHand);
    if (left == null) return right;
    if (right == null) return left;
    return left.y <= right.y ? left : right;
  }

  static math.Point<double> _behindTarget(
    PersonObservation o,
    double direction,
    double w,
    double h,
    double side,
  ) {
    final shoulder = _shoulderPixels(o, w, h);
    final chest = o.anchor(PersonAnchor.chest)!;
    return math.Point<double>(
      chest.x * w + direction * (shoulder * 0.5 + side * 0.38),
      chest.y * h - side * 0.2,
    );
  }

  static math.Point<double> _rawTarget(
    PersonObservation o,
    PersonPlacement placement,
    double direction,
    double w,
    double h,
    double side,
  ) {
    switch (placement) {
      case PersonPlacement.aboveHead:
        final above = o.anchor(PersonAnchor.aboveHead)!;
        return math.Point<double>(above.x * w, above.y * h - side * 0.5);
      case PersonPlacement.besideHand:
        final hand = _pickHand(o);
        if (hand != null) {
          return math.Point<double>(hand.x * w, hand.y * h - side * 0.6);
        }
        return _behindTarget(o, direction, w, h, side);
      case PersonPlacement.behindShoulder:
        return _behindTarget(o, direction, w, h, side);
    }
  }

  static math.Point<double> _target(
    PersonObservation o,
    PersonPlacement placement,
    double direction,
    double w,
    double h,
    double side,
  ) {
    final raw = _rawTarget(o, placement, direction, w, h, side);
    final half = side / 2;
    final margin = math.min(w, h) * 0.02;
    final inFrame = math.Point<double>(
      _clamp(raw.x, half + margin, w - half - margin),
      _clamp(raw.y, half + margin, h - half - margin),
    );
    if (placement.occludedByPerson) return inFrame;
    return _clearOfHead(o, inFrame, direction, w, h, side);
  }

  /// Half sizes (pixels) of the area around the head that a card must not
  /// touch, for a card of [side] pixels (the card's own half side included).
  static math.Point<double> _headReach(
    PersonObservation o,
    double w,
    double h,
    double side,
  ) {
    final shoulder = _shoulderPixels(o, w, h);
    final gap = math.min(w, h) * headClearance;
    return math.Point<double>(
      shoulder * 0.28 + side / 2 + gap,
      shoulder * 0.4 + side / 2 + gap,
    );
  }

  static bool _hitsHead(
    PersonObservation o,
    math.Point<double> center,
    double w,
    double h,
    double side,
  ) {
    final head = o.anchor(PersonAnchor.head);
    if (head == null) return false;
    final reach = _headReach(o, w, h, side);
    return (center.x - head.x * w).abs() < reach.x &&
        (center.y - head.y * h).abs() < reach.y;
  }

  /// True when the smoothed card path covers the head at any sample.
  static bool _coversHead(
    List<PersonObservation?> samples,
    List<double> xs,
    List<double> ys,
    double w,
    double h,
    double side,
  ) {
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      if (sample == null) continue;
      final center = math.Point<double>(xs[i], ys[i]);
      if (_hitsHead(sample, center, w, h, side)) return true;
    }
    return false;
  }

  /// Moves a card center that would cover the head to the nearest spot beside,
  /// above or below the head that is still inside the frame. When there is no
  /// such spot the point is returned unchanged (the caller shrinks the card).
  static math.Point<double> _clearOfHead(
    PersonObservation o,
    math.Point<double> point,
    double direction,
    double w,
    double h,
    double side,
  ) {
    final head = o.anchor(PersonAnchor.head);
    if (head == null || !_hitsHead(o, point, w, h, side)) return point;

    final half = side / 2;
    final margin = math.min(w, h) * 0.02;
    final reach = _headReach(o, w, h, side);
    final hx = head.x * w;
    final hy = head.y * h;

    math.Point<double> fit(double x, double y) => math.Point<double>(
          _clamp(x, half + margin, w - half - margin),
          _clamp(y, half + margin, h - half - margin),
        );

    final options = <math.Point<double>>[
      fit(hx + direction * reach.x, point.y),
      fit(hx - direction * reach.x, point.y),
      fit(point.x, hy - reach.y),
      fit(point.x, hy + reach.y),
    ]..sort((a, b) => _distance(a, point).compareTo(_distance(b, point)));

    for (final option in options) {
      if (!_hitsHead(o, option, w, h, side)) return option;
    }
    return point;
  }

  static double _distance(math.Point<double> a, math.Point<double> b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _clamp(double value, double low, double high) {
    if (low > high) return (low + high) / 2;
    return value.clamp(low, high).toDouble();
  }

  static void _fillGaps(List<double?> values) {
    double? last;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value != null) {
        last = value;
      } else if (last != null) {
        values[i] = last;
      }
    }
    last = null;
    for (var i = values.length - 1; i >= 0; i--) {
      final value = values[i];
      if (value != null) {
        last = value;
      } else if (last != null) {
        values[i] = last;
      }
    }
  }

  /// Forward-backward exponential smoothing: no lag, no jitter.
  static List<double> _smooth(List<double> values, {double alpha = 0.45}) {
    if (values.length < 3) return values;
    final out = List<double>.from(values);
    for (var i = 1; i < out.length; i++) {
      out[i] = out[i - 1] + (out[i] - out[i - 1]) * alpha;
    }
    for (var i = out.length - 2; i >= 0; i--) {
      out[i] = out[i + 1] + (out[i] - out[i + 1]) * alpha;
    }
    return out;
  }
}
