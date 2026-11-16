import 'dart:math' as math;

import 'person_tracking_models.dart';

/// One capsule-shaped stroke of the approximate body matte, in mask pixels.
/// A stroke whose two ends coincide is a filled circle.
class SilhouetteStroke {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double thickness;

  const SilhouetteStroke({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.thickness,
  });

  bool get isCircle => x1 == x2 && y1 == y2;
}

/// A rendered black/white person matte stored as a PNG image sequence.
class PersonMatteSequence {
  final String directory;
  final double fps;
  final int width;
  final int height;
  final int frameCount;

  const PersonMatteSequence({
    required this.directory,
    required this.fps,
    required this.width,
    required this.height,
    required this.frameCount,
  });

  /// printf-style pattern understood by FFmpeg.
  String get pattern => '$directory/matte_%05d.png';
}

/// Builds an approximate body silhouette from pose landmarks. It is a matte
/// good enough to make a 3D card pass behind the person; it is not a real
/// segmentation mask.
class PersonSilhouette {
  PersonSilhouette._();

  static const double minimumConfidence = 0.4;

  static List<SilhouetteStroke> build(
    PersonObservation observation, {
    required int width,
    required int height,
  }) {
    final w = width.toDouble();
    final h = height.toDouble();
    final strokes = <SilhouetteStroke>[];

    math.Point<double>? point(BodyLandmark type) {
      final landmark = observation.landmark(
        type,
        minConfidence: minimumConfidence,
      );
      if (landmark == null) return null;
      return math.Point<double>(landmark.x * w, landmark.y * h);
    }

    math.Point<double>? middle(
      math.Point<double>? a,
      math.Point<double>? b,
    ) {
      if (a != null && b != null) {
        return math.Point<double>((a.x + b.x) / 2, (a.y + b.y) / 2);
      }
      return a ?? b;
    }

    void add(math.Point<double> a, math.Point<double> b, double thickness) {
      strokes.add(
        SilhouetteStroke(
          x1: a.x,
          y1: a.y,
          x2: b.x,
          y2: b.y,
          thickness: math.max(1.0, thickness),
        ),
      );
    }

    void limb(
      math.Point<double>? a,
      math.Point<double>? b,
      math.Point<double>? c,
      double first,
      double second,
    ) {
      if (a != null && b != null) add(a, b, first);
      if (b != null && c != null) add(b, c, second);
    }

    final box = observation.box;
    final leftShoulder = point(BodyLandmark.leftShoulder);
    final rightShoulder = point(BodyLandmark.rightShoulder);
    final leftHip = point(BodyLandmark.leftHip);
    final rightHip = point(BodyLandmark.rightHip);

    final shoulderPx = math.max(
      4.0,
      leftShoulder != null && rightShoulder != null
          ? leftShoulder.distanceTo(rightShoulder)
          : box.width * w * 0.55,
    );

    // Head.
    final headPoint = point(BodyLandmark.nose) ??
        middle(point(BodyLandmark.leftEar), point(BodyLandmark.rightEar)) ??
        math.Point<double>(box.centerX * w, box.top * h + shoulderPx * 0.5);
    final radius = shoulderPx * 0.42;
    final headCenter = math.Point<double>(
      headPoint.x,
      headPoint.y - radius * 0.25,
    );
    add(headCenter, headCenter, radius * 2);

    // Neck and torso.
    final shoulderCenter = middle(leftShoulder, rightShoulder) ??
        math.Point<double>(
          box.centerX * w,
          math.min(box.top * h + shoulderPx * 1.3, h),
        );
    add(headCenter, shoulderCenter, shoulderPx * 0.32);

    if (leftShoulder != null && rightShoulder != null) {
      add(leftShoulder, rightShoulder, shoulderPx * 0.3);
    }

    final bottom = middle(leftHip, rightHip) ??
        math.Point<double>(shoulderCenter.x, box.bottom * h);
    add(shoulderCenter, bottom, shoulderPx * 0.92);

    if (leftHip != null && rightHip != null) {
      add(leftHip, rightHip, shoulderPx * 0.5);
    }

    // Arms and legs.
    limb(
      leftShoulder,
      point(BodyLandmark.leftElbow),
      point(BodyLandmark.leftWrist),
      shoulderPx * 0.3,
      shoulderPx * 0.27,
    );
    limb(
      rightShoulder,
      point(BodyLandmark.rightElbow),
      point(BodyLandmark.rightWrist),
      shoulderPx * 0.3,
      shoulderPx * 0.27,
    );
    limb(
      leftHip,
      point(BodyLandmark.leftKnee),
      point(BodyLandmark.leftAnkle),
      shoulderPx * 0.4,
      shoulderPx * 0.34,
    );
    limb(
      rightHip,
      point(BodyLandmark.rightKnee),
      point(BodyLandmark.rightAnkle),
      shoulderPx * 0.4,
      shoulderPx * 0.34,
    );

    return strokes;
  }
}
