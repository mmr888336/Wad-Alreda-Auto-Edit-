import 'package:auto_edit/person_anchor_path.dart';
import 'package:auto_edit/person_tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

LandmarkPoint _pt(double x, double y) =>
    LandmarkPoint(x: x, y: y, confidence: 0.9);

// A tight talking-head crop: the head is big and a hand is raised right under
// the chin, which used to drop the card onto the mouth.
PersonObservation _tight(double time) => PersonObservation(
      time: time,
      box: const NormalizedRect(left: 0.05, top: 0.1, right: 0.95, bottom: 1.0),
      confidence: 0.9,
      landmarks: <BodyLandmark, LandmarkPoint>{
        BodyLandmark.nose: _pt(0.5, 0.3),
        BodyLandmark.leftShoulder: _pt(0.8, 0.52),
        BodyLandmark.rightShoulder: _pt(0.2, 0.52),
        BodyLandmark.leftHip: _pt(0.7, 0.95),
        BodyLandmark.rightHip: _pt(0.3, 0.95),
        BodyLandmark.rightWrist: _pt(0.5, 0.42),
      },
    );

PersonTrack _tightTrack() => PersonTrack(
      id: 1,
      observations: <PersonObservation>[
        for (var i = 0; i <= 20; i++) _tight(i * 0.2),
      ],
    );

// True when the card overlaps a face box drawn around the nose.
bool _coversFace(PersonAnchorPath path, double w, double h) {
  const faceLeft = 0.5 - 0.12;
  const faceRight = 0.5 + 0.12;
  const faceTop = 0.3 - 0.08;
  const faceBottom = 0.3 + 0.1;
  final half = path.sidePixels / 2;
  for (final key in path.keyframes) {
    final left = (key.x * w - half) / w;
    final right = (key.x * w + half) / w;
    final top = (key.y * h - half) / h;
    final bottom = (key.y * h + half) / h;
    final overlaps = left < faceRight &&
        right > faceLeft &&
        top < faceBottom &&
        bottom > faceTop;
    if (overlaps) return true;
  }
  return false;
}

PersonAnchorPath? _plan(PersonPlacement placement) => PersonAnchorPath.plan(
      track: _tightTrack(),
      start: 0.5,
      end: 3.5,
      placement: placement,
      frameWidth: 1080,
      frameHeight: 1920,
    );

void main() {
  group('PersonAnchorPath keeps the face free', () {
    test('a hand card never lands on the face', () {
      final path = _plan(PersonPlacement.besideHand);

      // Either a plan that keeps clear of the face, or no plan at all.
      if (path != null) {
        expect(_coversFace(path, 1080, 1920), isFalse);
      }
    });

    test('an above-head card never lands on the face', () {
      final path = _plan(PersonPlacement.aboveHead);

      if (path != null) {
        expect(_coversFace(path, 1080, 1920), isFalse);
      }
    });

    test('a card behind the shoulder is left as it was', () {
      final path = _plan(PersonPlacement.behindShoulder);

      expect(path, isNotNull);
      expect(path!.placement.occludedByPerson, isTrue);
    });
  });
}
