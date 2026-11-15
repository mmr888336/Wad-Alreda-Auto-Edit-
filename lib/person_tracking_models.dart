import 'dart:math' as math;

/// Body landmarks reported by the pose detector.
///
/// The names intentionally match ML Kit's `PoseLandmarkType` names, so the
/// native adapter can map landmarks by name while this file stays pure Dart.
enum BodyLandmark {
  nose,
  leftEyeInner,
  leftEye,
  leftEyeOuter,
  rightEyeInner,
  rightEye,
  rightEyeOuter,
  leftEar,
  rightEar,
  leftMouth,
  rightMouth,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftPinky,
  rightPinky,
  leftIndex,
  rightIndex,
  leftThumb,
  rightThumb,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftHeel,
  rightHeel,
  leftFootIndex,
  rightFootIndex;

  static BodyLandmark? fromName(String name) {
    for (final value in BodyLandmark.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Bone connections used to draw the skeleton overlay.
const List<List<BodyLandmark>> kBodySkeleton = <List<BodyLandmark>>[
  <BodyLandmark>[BodyLandmark.leftShoulder, BodyLandmark.rightShoulder],
  <BodyLandmark>[BodyLandmark.leftShoulder, BodyLandmark.leftElbow],
  <BodyLandmark>[BodyLandmark.leftElbow, BodyLandmark.leftWrist],
  <BodyLandmark>[BodyLandmark.rightShoulder, BodyLandmark.rightElbow],
  <BodyLandmark>[BodyLandmark.rightElbow, BodyLandmark.rightWrist],
  <BodyLandmark>[BodyLandmark.leftShoulder, BodyLandmark.leftHip],
  <BodyLandmark>[BodyLandmark.rightShoulder, BodyLandmark.rightHip],
  <BodyLandmark>[BodyLandmark.leftHip, BodyLandmark.rightHip],
  <BodyLandmark>[BodyLandmark.leftHip, BodyLandmark.leftKnee],
  <BodyLandmark>[BodyLandmark.leftKnee, BodyLandmark.leftAnkle],
  <BodyLandmark>[BodyLandmark.rightHip, BodyLandmark.rightKnee],
  <BodyLandmark>[BodyLandmark.rightKnee, BodyLandmark.rightAnkle],
];

/// Rectangle in normalized frame coordinates (0..1, origin top-left).
class NormalizedRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const NormalizedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get area => math.max(0.0, width) * math.max(0.0, height);
  double get diagonal => math.sqrt(width * width + height * height);

  bool get isValid =>
      left.isFinite &&
      top.isFinite &&
      right.isFinite &&
      bottom.isFinite &&
      right > left &&
      bottom > top;

  NormalizedRect clampToUnit() {
    return NormalizedRect(
      left: left.clamp(0.0, 1.0).toDouble(),
      top: top.clamp(0.0, 1.0).toDouble(),
      right: right.clamp(0.0, 1.0).toDouble(),
      bottom: bottom.clamp(0.0, 1.0).toDouble(),
    );
  }

  /// Grows the rectangle by fractions of its own width/height.
  NormalizedRect expanded({
    double sides = 0,
    double above = 0,
    double below = 0,
  }) {
    final w = width;
    final h = height;
    return NormalizedRect(
      left: left - w * sides,
      top: top - h * above,
      right: right + w * sides,
      bottom: bottom + h * below,
    );
  }

  NormalizedRect shifted(double dx, double dy) {
    return NormalizedRect(
      left: left + dx,
      top: top + dy,
      right: right + dx,
      bottom: bottom + dy,
    );
  }

  NormalizedRect lerp(NormalizedRect other, double t) {
    return NormalizedRect(
      left: left + (other.left - left) * t,
      top: top + (other.top - top) * t,
      right: right + (other.right - right) * t,
      bottom: bottom + (other.bottom - bottom) * t,
    );
  }

  double intersectionArea(NormalizedRect other) {
    final w = math.min(right, other.right) - math.max(left, other.left);
    final h = math.min(bottom, other.bottom) - math.max(top, other.top);
    if (w <= 0 || h <= 0) return 0;
    return w * h;
  }

  double iou(NormalizedRect other) {
    final intersection = intersectionArea(other);
    final union = area + other.area - intersection;
    if (union <= 0) return 0;
    return intersection / union;
  }

  double centerDistance(NormalizedRect other) {
    final dx = centerX - other.centerX;
    final dy = centerY - other.centerY;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// One body landmark in normalized frame coordinates.
class LandmarkPoint {
  final double x;
  final double y;
  final double z;
  final double confidence;

  const LandmarkPoint({
    required this.x,
    required this.y,
    this.z = 0,
    required this.confidence,
  });

  LandmarkPoint lerp(LandmarkPoint other, double t) {
    return LandmarkPoint(
      x: x + (other.x - x) * t,
      y: y + (other.y - y) * t,
      z: z + (other.z - z) * t,
      confidence: confidence + (other.confidence - confidence) * t,
    );
  }
}

/// A raw landmark in pixel coordinates, as reported by a native detector.
class RawLandmark {
  final String name;
  final double x;
  final double y;
  final double z;
  final double likelihood;

  const RawLandmark({
    required this.name,
    required this.x,
    required this.y,
    this.z = 0,
    required this.likelihood,
  });
}

/// A single-frame detection of one person.
class PersonDetection {
  final NormalizedRect box;
  final double confidence;
  final Map<BodyLandmark, LandmarkPoint> landmarks;

  const PersonDetection({
    required this.box,
    required this.confidence,
    this.landmarks = const <BodyLandmark, LandmarkPoint>{},
  });
}

/// Converts pixel landmarks from a native pose detector into a
/// [PersonDetection] with a normalized bounding box.
class PersonDetectionFactory {
  PersonDetectionFactory._();

  /// Landmarks at or above this likelihood count as visible.
  static const double visibleLikelihood = 0.5;

  /// Fewer visible landmarks than this means no reliable person.
  static const int minimumVisibleLandmarks = 5;

  /// Returns null when the frame has no reliable person.
  ///
  /// The box is built from visible landmarks only and expanded, because
  /// landmarks sit on joints and do not reach the top of the head or the
  /// body outline. For close-up videos the box covers head and shoulders.
  static PersonDetection? fromPixelLandmarks(
    Iterable<RawLandmark> raw, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) return null;

    final landmarks = <BodyLandmark, LandmarkPoint>{};
    for (final item in raw) {
      final type = BodyLandmark.fromName(item.name);
      if (type == null) continue;
      if (!item.x.isFinite || !item.y.isFinite || !item.likelihood.isFinite) {
        continue;
      }
      final z = item.z.isFinite ? item.z : 0.0;
      landmarks[type] = LandmarkPoint(
        x: item.x / width,
        y: item.y / height,
        z: z / width,
        confidence: item.likelihood.clamp(0.0, 1.0).toDouble(),
      );
    }

    final visible = landmarks.values
        .where((point) => point.confidence >= visibleLikelihood)
        .toList();
    if (visible.length < minimumVisibleLandmarks) return null;

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var confidenceSum = 0.0;
    for (final point in visible) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
      confidenceSum += point.confidence;
    }

    final box = NormalizedRect(
      left: minX,
      top: minY,
      right: maxX,
      bottom: maxY,
    ).expanded(sides: 0.12, above: 0.2, below: 0.05).clampToUnit();
    if (!box.isValid) return null;

    return PersonDetection(
      box: box,
      confidence: confidenceSum / visible.length,
      landmarks: landmarks,
    );
  }
}

/// Named attachment points on a tracked person, for placing graphics or 3D
/// models relative to the body.
enum PersonAnchor {
  center,
  head,
  aboveHead,
  chest,
  hips,
  feet,
  leftHand,
  rightHand,
}

/// A smoothed observation of one person at one moment of the video.
class PersonObservation {
  final double time;
  final NormalizedRect box;
  final double confidence;
  final Map<BodyLandmark, LandmarkPoint> landmarks;

  /// True when this observation was computed between two detections (or held
  /// briefly) rather than detected at exactly [time].
  final bool interpolated;

  const PersonObservation({
    required this.time,
    required this.box,
    required this.confidence,
    this.landmarks = const <BodyLandmark, LandmarkPoint>{},
    this.interpolated = false,
  });

  static const double defaultMinLandmarkConfidence = 0.5;

  /// Returns the landmark only when it is confident enough to use.
  LandmarkPoint? landmark(
    BodyLandmark type, {
    double minConfidence = defaultMinLandmarkConfidence,
  }) {
    final point = landmarks[type];
    if (point == null || point.confidence < minConfidence) return null;
    return point;
  }

  math.Point<double>? _point(LandmarkPoint? point) {
    if (point == null) return null;
    return math.Point<double>(point.x, point.y);
  }

  math.Point<double>? _midpoint(BodyLandmark a, BodyLandmark b) {
    final first = landmark(a);
    final second = landmark(b);
    if (first != null && second != null) {
      return math.Point<double>(
        (first.x + second.x) / 2,
        (first.y + second.y) / 2,
      );
    }
    return _point(first ?? second);
  }

  math.Point<double>? get shoulderCenter =>
      _midpoint(BodyLandmark.leftShoulder, BodyLandmark.rightShoulder);

  math.Point<double>? get hipCenter =>
      _midpoint(BodyLandmark.leftHip, BodyLandmark.rightHip);

  math.Point<double>? get headCenter {
    final nose = landmark(BodyLandmark.nose);
    if (nose != null) return math.Point<double>(nose.x, nose.y);
    return _midpoint(BodyLandmark.leftEar, BodyLandmark.rightEar);
  }

  /// Distance between the shoulders in normalized units.
  double? get shoulderWidth {
    final left = landmark(BodyLandmark.leftShoulder);
    final right = landmark(BodyLandmark.rightShoulder);
    if (left == null || right == null) return null;
    final dx = left.x - right.x;
    final dy = left.y - right.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Distance between shoulder center and hip center in normalized units.
  double? get torsoHeight {
    final shoulders = shoulderCenter;
    final hips = hipCenter;
    if (shoulders == null || hips == null) return null;
    return shoulders.distanceTo(hips);
  }

  /// Torso lean from vertical in degrees. 0 is upright; positive leans toward
  /// the right side of the screen.
  double? get bodyTiltDegrees {
    final shoulders = shoulderCenter;
    final hips = hipCenter;
    if (shoulders == null || hips == null) return null;
    final dx = shoulders.x - hips.x;
    final dy = hips.y - shoulders.y;
    if (dx == 0 && dy == 0) return null;
    return math.atan2(dx, dy) * 180 / math.pi;
  }

  /// Angle of the shoulder line in degrees, folded to -90..90. 0 means level
  /// shoulders; positive means the line tilts clockwise on screen.
  double? get shoulderRollDegrees {
    final left = landmark(BodyLandmark.leftShoulder);
    final right = landmark(BodyLandmark.rightShoulder);
    if (left == null || right == null) return null;
    var angle = math.atan2(right.y - left.y, right.x - left.x) * 180 / math.pi;
    if (angle > 90) angle -= 180;
    if (angle < -90) angle += 180;
    return angle;
  }

  math.Point<double> _headAnchor() {
    return headCenter ??
        math.Point<double>(box.centerX, box.top + box.height * 0.1);
  }

  math.Point<double> _aboveHeadAnchor() {
    final head = _headAnchor();
    return math.Point<double>(head.x, box.top - box.height * 0.06);
  }

  math.Point<double> _chestAnchor() {
    final shoulders = shoulderCenter;
    final hips = hipCenter;
    if (shoulders != null && hips != null) {
      return math.Point<double>(
        shoulders.x + (hips.x - shoulders.x) * 0.35,
        shoulders.y + (hips.y - shoulders.y) * 0.35,
      );
    }
    if (shoulders != null) {
      return math.Point<double>(shoulders.x, shoulders.y + box.height * 0.1);
    }
    return math.Point<double>(box.centerX, box.top + box.height * 0.35);
  }

  /// Position of a body anchor in normalized coordinates.
  ///
  /// Anchors fall back to box-based estimates when landmarks are missing, so
  /// only the hands can be null. `aboveHead` may lie slightly outside the
  /// frame, and `feet` is the bottom of the box when the ankles are not
  /// visible (for example when the person is cropped at the waist).
  math.Point<double>? anchor(PersonAnchor kind) {
    return switch (kind) {
      PersonAnchor.center => math.Point<double>(box.centerX, box.centerY),
      PersonAnchor.head => _headAnchor(),
      PersonAnchor.aboveHead => _aboveHeadAnchor(),
      PersonAnchor.chest => _chestAnchor(),
      PersonAnchor.hips =>
        hipCenter ??
            math.Point<double>(box.centerX, box.top + box.height * 0.6),
      PersonAnchor.feet =>
        _midpoint(BodyLandmark.leftAnkle, BodyLandmark.rightAnkle) ??
            math.Point<double>(box.centerX, box.bottom),
      PersonAnchor.leftHand => _point(landmark(BodyLandmark.leftWrist)),
      PersonAnchor.rightHand => _point(landmark(BodyLandmark.rightWrist)),
    };
  }

  PersonObservation withTime(double newTime, {bool? interpolated}) {
    return PersonObservation(
      time: newTime,
      box: box,
      confidence: confidence,
      landmarks: landmarks,
      interpolated: interpolated ?? this.interpolated,
    );
  }

  /// Blends this observation toward [other]. Landmarks present in only one of
  /// the two are kept from the nearer side.
  PersonObservation lerp(PersonObservation other, double t, {double? time}) {
    final merged = <BodyLandmark, LandmarkPoint>{};
    final keys = <BodyLandmark>{...landmarks.keys, ...other.landmarks.keys};
    for (final key in keys) {
      final a = landmarks[key];
      final b = other.landmarks[key];
      if (a != null && b != null) {
        merged[key] = a.lerp(b, t);
      } else if (a != null && t < 0.5) {
        merged[key] = a;
      } else if (b != null && t >= 0.5) {
        merged[key] = b;
      }
    }
    return PersonObservation(
      time: time ?? this.time + (other.time - this.time) * t,
      box: box.lerp(other.box, t),
      confidence: confidence + (other.confidence - confidence) * t,
      landmarks: merged,
      interpolated: true,
    );
  }
}

/// All observations of one person over time, sorted by time.
class PersonTrack {
  final int id;
  final List<PersonObservation> observations;

  PersonTrack({
    required this.id,
    required List<PersonObservation> observations,
  }) : observations = List<PersonObservation>.unmodifiable(observations);

  bool get isEmpty => observations.isEmpty;
  int get length => observations.length;
  double get startTime => observations.first.time;
  double get endTime => observations.last.time;

  double get averageConfidence {
    if (observations.isEmpty) return 0;
    var sum = 0.0;
    for (final item in observations) {
      sum += item.confidence;
    }
    return sum / observations.length;
  }

  double get averageBoxArea {
    if (observations.isEmpty) return 0;
    var sum = 0.0;
    for (final item in observations) {
      sum += item.box.area;
    }
    return sum / observations.length;
  }

  /// Mean distance of the box center from the frame center.
  double get averageCenterOffset {
    if (observations.isEmpty) return 0;
    var sum = 0.0;
    for (final item in observations) {
      final dx = item.box.centerX - 0.5;
      final dy = item.box.centerY - 0.5;
      sum += math.sqrt(dx * dx + dy * dy);
    }
    return sum / observations.length;
  }

  /// Position of the person at [time].
  ///
  /// Between two detections closer than [maxInterpolationGap] seconds the
  /// result is interpolated. Across a longer gap the person counts as not
  /// visible, except within [holdTolerance] seconds of a real detection, where
  /// the nearest detection is held. Returns null when the person is not
  /// visible at [time].
  PersonObservation? sampleAt(
    double time, {
    double maxInterpolationGap = 0.6,
    double holdTolerance = 0.15,
  }) {
    if (observations.isEmpty || !time.isFinite) return null;

    final first = observations.first;
    final last = observations.last;

    if (time < first.time) {
      return first.time - time <= holdTolerance
          ? first.withTime(time, interpolated: true)
          : null;
    }
    if (time > last.time) {
      return time - last.time <= holdTolerance
          ? last.withTime(time, interpolated: true)
          : null;
    }

    // Largest index whose time is <= [time].
    var low = 0;
    var high = observations.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (observations[mid].time <= time) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    final previous = observations[low];
    if ((time - previous.time).abs() < 1e-9) return previous;
    if (low + 1 >= observations.length) return previous;

    final next = observations[low + 1];
    final gap = next.time - previous.time;
    if (gap <= maxInterpolationGap) {
      return previous.lerp(next, (time - previous.time) / gap, time: time);
    }
    if (time - previous.time <= holdTolerance) {
      return previous.withTime(time, interpolated: true);
    }
    if (next.time - time <= holdTolerance) {
      return next.withTime(time, interpolated: true);
    }
    return null;
  }
}

/// A person visible at a given time, with the id of the track it belongs to.
class TrackedPerson {
  final int trackId;
  final PersonObservation observation;

  const TrackedPerson({required this.trackId, required this.observation});
}

/// Output of a full tracking pass over a video.
class PersonTrackingResult {
  final double sampleFps;
  final int frameWidth;
  final int frameHeight;
  final int framesAnalyzed;
  final int failedFrames;
  final List<PersonTrack> tracks;

  /// Track chosen as the main subject, or null when nobody was found.
  final int? primaryTrackId;
  final List<String> notes;

  PersonTrackingResult({
    required this.sampleFps,
    required this.frameWidth,
    required this.frameHeight,
    required this.framesAnalyzed,
    this.failedFrames = 0,
    required List<PersonTrack> tracks,
    this.primaryTrackId,
    List<String> notes = const <String>[],
  })  : tracks = List<PersonTrack>.unmodifiable(tracks),
        notes = List<String>.unmodifiable(notes);

  /// Analyzed time span in seconds.
  double get duration => sampleFps > 0 ? framesAnalyzed / sampleFps : 0;

  PersonTrack? get primaryTrack {
    final id = primaryTrackId;
    if (id == null) return null;
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  int get framesWithPrimaryPerson => primaryTrack?.observations.length ?? 0;

  /// Fraction of analyzed frames where the main person was detected.
  double get coverage {
    if (framesAnalyzed <= 0) return 0;
    return (framesWithPrimaryPerson / framesAnalyzed).clamp(0.0, 1.0).toDouble();
  }

  /// Every person visible at [time]. Works for one or many people.
  List<TrackedPerson> peopleAt(
    double time, {
    double maxInterpolationGap = 0.6,
  }) {
    final people = <TrackedPerson>[];
    for (final track in tracks) {
      final observation = track.sampleAt(
        time,
        maxInterpolationGap: maxInterpolationGap,
      );
      if (observation != null) {
        people.add(TrackedPerson(trackId: track.id, observation: observation));
      }
    }
    return people;
  }
}
