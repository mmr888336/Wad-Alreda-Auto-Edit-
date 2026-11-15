import 'package:auto_edit/person_tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

LandmarkPoint _pt(double x, double y, [double confidence = 0.9]) =>
    LandmarkPoint(x: x, y: y, confidence: confidence);

PersonObservation _observation({
  double time = 0,
  NormalizedRect box = const NormalizedRect(
    left: 0.3,
    top: 0.1,
    right: 0.7,
    bottom: 0.9,
  ),
  Map<BodyLandmark, LandmarkPoint> landmarks =
      const <BodyLandmark, LandmarkPoint>{},
}) {
  return PersonObservation(
    time: time,
    box: box,
    confidence: 0.9,
    landmarks: landmarks,
  );
}

void main() {
  group('NormalizedRect', () {
    test('iou is 1 for identical rectangles and 0 for disjoint ones', () {
      const a = NormalizedRect(left: 0.1, top: 0.1, right: 0.5, bottom: 0.6);
      const b = NormalizedRect(left: 0.6, top: 0.1, right: 0.9, bottom: 0.6);
      expect(a.iou(a), closeTo(1, 1e-9));
      expect(a.iou(b), 0);
    });

    test('iou of half-overlapping rectangles is one third', () {
      const a = NormalizedRect(left: 0, top: 0, right: 0.5, bottom: 0.5);
      const b = NormalizedRect(left: 0.25, top: 0, right: 0.75, bottom: 0.5);
      expect(a.iou(b), closeTo(1 / 3, 1e-9));
    });

    test('clampToUnit keeps the rectangle inside the frame', () {
      const rect = NormalizedRect(
        left: -0.2,
        top: -0.1,
        right: 1.3,
        bottom: 0.8,
      );
      final clamped = rect.clampToUnit();
      expect(clamped.left, 0);
      expect(clamped.top, 0);
      expect(clamped.right, 1);
      expect(clamped.bottom, 0.8);
      expect(clamped.isValid, isTrue);
    });

    test('a rectangle without width is invalid', () {
      const rect = NormalizedRect(left: 0.5, top: 0.2, right: 0.5, bottom: 0.8);
      expect(rect.isValid, isFalse);
    });
  });

  group('PersonObservation geometry', () {
    test('measures an upright torso', () {
      final observation = _observation(landmarks: {
        BodyLandmark.nose: _pt(0.5, 0.15),
        BodyLandmark.leftShoulder: _pt(0.6, 0.3),
        BodyLandmark.rightShoulder: _pt(0.4, 0.3),
        BodyLandmark.leftHip: _pt(0.58, 0.6),
        BodyLandmark.rightHip: _pt(0.42, 0.6),
      });

      expect(observation.shoulderWidth, closeTo(0.2, 1e-9));
      expect(observation.torsoHeight, closeTo(0.3, 1e-9));
      expect(observation.bodyTiltDegrees, closeTo(0, 1e-6));
      expect(observation.shoulderRollDegrees, closeTo(0, 1e-6));
    });

    test('reports a positive tilt when the torso leans to the right', () {
      final observation = _observation(landmarks: {
        BodyLandmark.leftShoulder: _pt(0.7, 0.3),
        BodyLandmark.rightShoulder: _pt(0.5, 0.3),
        BodyLandmark.leftHip: _pt(0.58, 0.6),
        BodyLandmark.rightHip: _pt(0.42, 0.6),
      });

      expect(observation.bodyTiltDegrees, closeTo(18.4349, 1e-3));
    });

    test('ignores landmarks below the confidence threshold', () {
      final observation = _observation(landmarks: {
        BodyLandmark.nose: _pt(0.5, 0.2, 0.3),
      });

      expect(observation.landmark(BodyLandmark.nose), isNull);
      expect(
        observation.landmark(BodyLandmark.nose, minConfidence: 0.2),
        isNotNull,
      );
      expect(observation.headCenter, isNull);
    });

    test('anchors use landmarks when available', () {
      final observation = _observation(landmarks: {
        BodyLandmark.nose: _pt(0.5, 0.15),
        BodyLandmark.leftShoulder: _pt(0.6, 0.3),
        BodyLandmark.rightShoulder: _pt(0.4, 0.3),
        BodyLandmark.leftHip: _pt(0.58, 0.6),
        BodyLandmark.rightHip: _pt(0.42, 0.6),
        BodyLandmark.leftWrist: _pt(0.7, 0.5),
      });

      final head = observation.anchor(PersonAnchor.head)!;
      expect(head.x, closeTo(0.5, 1e-9));
      expect(head.y, closeTo(0.15, 1e-9));

      final chest = observation.anchor(PersonAnchor.chest)!;
      expect(chest.x, closeTo(0.5, 1e-9));
      expect(chest.y, closeTo(0.405, 1e-9));

      final hand = observation.anchor(PersonAnchor.leftHand)!;
      expect(hand.x, closeTo(0.7, 1e-9));
      expect(observation.anchor(PersonAnchor.rightHand), isNull);
    });

    test('anchors fall back to the box when landmarks are missing', () {
      final observation = _observation();

      final feet = observation.anchor(PersonAnchor.feet)!;
      expect(feet.x, closeTo(0.5, 1e-9));
      expect(feet.y, closeTo(0.9, 1e-9));

      final head = observation.anchor(PersonAnchor.head)!;
      expect(head.x, closeTo(0.5, 1e-9));
      expect(head.y, closeTo(0.18, 1e-9));
    });
  });

  group('PersonTrack.sampleAt', () {
    final track = PersonTrack(id: 1, observations: [
      _observation(
        time: 0,
        box: const NormalizedRect(left: 0.1, top: 0.1, right: 0.3, bottom: 0.5),
      ),
      _observation(
        time: 0.5,
        box: const NormalizedRect(left: 0.3, top: 0.1, right: 0.5, bottom: 0.5),
      ),
    ]);

    test('returns real detections unchanged', () {
      final sample = track.sampleAt(0)!;
      expect(sample.interpolated, isFalse);
      expect(sample.box.left, closeTo(0.1, 1e-9));
    });

    test('interpolates between close detections', () {
      final sample = track.sampleAt(0.25)!;
      expect(sample.interpolated, isTrue);
      expect(sample.box.left, closeTo(0.2, 1e-9));
      expect(sample.time, closeTo(0.25, 1e-9));
    });

    test('treats a long gap as not visible', () {
      final gapped = PersonTrack(id: 2, observations: [
        _observation(time: 0),
        _observation(time: 2),
      ]);

      expect(gapped.sampleAt(1), isNull);

      final heldAfterStart = gapped.sampleAt(0.1)!;
      expect(heldAfterStart.interpolated, isTrue);
      expect(heldAfterStart.time, closeTo(0.1, 1e-9));

      expect(gapped.sampleAt(-0.1), isNotNull);
      expect(gapped.sampleAt(-0.5), isNull);
      expect(gapped.sampleAt(2.1), isNotNull);
      expect(gapped.sampleAt(2.5), isNull);
    });
  });

  group('PersonDetectionFactory', () {
    List<RawLandmark> visibleLandmarks() => const <RawLandmark>[
          RawLandmark(name: 'nose', x: 200, y: 160, likelihood: 0.9),
          RawLandmark(name: 'leftShoulder', x: 260, y: 320, likelihood: 0.9),
          RawLandmark(name: 'rightShoulder', x: 140, y: 320, likelihood: 0.9),
          RawLandmark(name: 'leftHip', x: 250, y: 560, likelihood: 0.9),
          RawLandmark(name: 'rightHip', x: 150, y: 560, likelihood: 0.9),
          RawLandmark(name: 'leftElbow', x: 300, y: 440, likelihood: 0.9),
          RawLandmark(name: 'leftAnkle', x: 260, y: 790, likelihood: 0.1),
          RawLandmark(name: 'notALandmark', x: 1, y: 1, likelihood: 0.9),
        ];

    test('normalizes landmarks and builds an expanded box', () {
      final detection = PersonDetectionFactory.fromPixelLandmarks(
        visibleLandmarks(),
        width: 400,
        height: 800,
      )!;

      expect(detection.landmarks.length, 7);
      expect(detection.landmarks[BodyLandmark.nose]!.x, closeTo(0.5, 1e-9));
      expect(detection.landmarks[BodyLandmark.nose]!.y, closeTo(0.2, 1e-9));
      expect(
        detection.landmarks[BodyLandmark.leftAnkle]!.confidence,
        closeTo(0.1, 1e-9),
      );

      expect(detection.box.left, closeTo(0.302, 1e-9));
      expect(detection.box.top, closeTo(0.1, 1e-9));
      expect(detection.box.right, closeTo(0.798, 1e-9));
      expect(detection.box.bottom, closeTo(0.725, 1e-9));
      expect(detection.confidence, closeTo(0.9, 1e-9));
    });

    test('returns null when too few landmarks are visible', () {
      final detection = PersonDetectionFactory.fromPixelLandmarks(
        const <RawLandmark>[
          RawLandmark(name: 'nose', x: 200, y: 160, likelihood: 0.9),
          RawLandmark(name: 'leftShoulder', x: 260, y: 320, likelihood: 0.9),
          RawLandmark(name: 'rightShoulder', x: 140, y: 320, likelihood: 0.9),
        ],
        width: 400,
        height: 800,
      );
      expect(detection, isNull);
    });

    test('returns null for an invalid frame size', () {
      final detection = PersonDetectionFactory.fromPixelLandmarks(
        visibleLandmarks(),
        width: 0,
        height: 800,
      );
      expect(detection, isNull);
    });
  });
}
