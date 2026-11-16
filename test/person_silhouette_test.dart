import 'package:auto_edit/person_silhouette.dart';
import 'package:auto_edit/person_tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

LandmarkPoint _pt(double x, double y) =>
    LandmarkPoint(x: x, y: y, confidence: 0.9);

void main() {
  group('PersonSilhouette', () {
    test('builds head, torso, hips and arms from landmarks', () {
      final observation = PersonObservation(
        time: 0,
        box: const NormalizedRect(
          left: 0.25,
          top: 0.1,
          right: 0.75,
          bottom: 0.9,
        ),
        confidence: 0.9,
        landmarks: <BodyLandmark, LandmarkPoint>{
          BodyLandmark.nose: _pt(0.5, 0.2),
          BodyLandmark.leftShoulder: _pt(0.6, 0.35),
          BodyLandmark.rightShoulder: _pt(0.4, 0.35),
          BodyLandmark.leftHip: _pt(0.58, 0.65),
          BodyLandmark.rightHip: _pt(0.42, 0.65),
          BodyLandmark.leftElbow: _pt(0.65, 0.5),
          BodyLandmark.rightElbow: _pt(0.35, 0.5),
          BodyLandmark.leftWrist: _pt(0.66, 0.62),
          BodyLandmark.rightWrist: _pt(0.34, 0.62),
        },
      );

      final strokes =
          PersonSilhouette.build(observation, width: 240, height: 426);

      // head + neck + shoulder line + torso + hip line + 4 arm segments
      expect(strokes.length, 9);
      expect(strokes.first.isCircle, isTrue);
      expect(strokes.every((s) => s.thickness >= 1), isTrue);
    });

    test('falls back to the bounding box without landmarks', () {
      final observation = PersonObservation(
        time: 0,
        box: const NormalizedRect(
          left: 0.25,
          top: 0.1,
          right: 0.75,
          bottom: 0.9,
        ),
        confidence: 0.9,
      );

      final strokes =
          PersonSilhouette.build(observation, width: 240, height: 426);

      // head + neck + torso
      expect(strokes.length, 3);
      expect(strokes.every((s) => s.thickness > 0), isTrue);
    });
  });

  group('PersonMatteSequence', () {
    test('exposes an FFmpeg image sequence pattern', () {
      const sequence = PersonMatteSequence(
        directory: '/tmp/m',
        fps: 12,
        width: 240,
        height: 426,
        frameCount: 25,
      );

      expect(sequence.pattern, '/tmp/m/matte_%05d.png');
    });
  });
}
