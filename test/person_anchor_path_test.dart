import 'package:auto_edit/person_anchor_path.dart';
import 'package:auto_edit/person_tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

LandmarkPoint _pt(double x, double y) =>
    LandmarkPoint(x: x, y: y, confidence: 0.9);

PersonObservation _observation(double time, {double cx = 0.4}) {
  return PersonObservation(
    time: time,
    box: NormalizedRect(
      left: cx - 0.15,
      top: 0.2,
      right: cx + 0.15,
      bottom: 0.9,
    ),
    confidence: 0.9,
    landmarks: <BodyLandmark, LandmarkPoint>{
      BodyLandmark.nose: _pt(cx, 0.3),
      BodyLandmark.leftShoulder: _pt(cx + 0.1, 0.45),
      BodyLandmark.rightShoulder: _pt(cx - 0.1, 0.45),
      BodyLandmark.leftHip: _pt(cx + 0.08, 0.7),
      BodyLandmark.rightHip: _pt(cx - 0.08, 0.7),
    },
  );
}

PersonTrack _track(double until) {
  final observations = <PersonObservation>[];
  for (var i = 0; i * 0.2 <= until + 1e-9; i++) {
    observations.add(_observation(i * 0.2));
  }
  return PersonTrack(id: 1, observations: observations);
}

void main() {
  group('PersonAnchorPath.plan', () {
    test('places a behind card beside the person inside the frame', () {
      final path = PersonAnchorPath.plan(
        track: _track(4),
        start: 1,
        end: 3,
        placement: PersonPlacement.behindShoulder,
        frameWidth: 1080,
        frameHeight: 1920,
      )!;

      expect(path.keyframes.length, 11);
      expect(path.keyframes.first.time, closeTo(1, 1e-9));
      expect(path.keyframes.last.time, closeTo(3, 1e-9));
      expect(path.sidePixels.isEven, isTrue);
      expect(path.coverage, closeTo(1, 1e-9));
      expect(path.placement.occludedByPerson, isTrue);

      // The person is left of center, so the card goes to the right of them.
      expect(path.keyframes.first.x, greaterThan(0.4));

      for (final key in path.keyframes) {
        expect(key.x * 1080 - path.sidePixels / 2, greaterThanOrEqualTo(-0.5));
        expect(
          key.x * 1080 + path.sidePixels / 2,
          lessThanOrEqualTo(1080.5),
        );
        expect(key.y * 1920 - path.sidePixels / 2, greaterThanOrEqualTo(-0.5));
        expect(
          key.y * 1920 + path.sidePixels / 2,
          lessThanOrEqualTo(1920.5),
        );
      }
    });

    test('places a floating card above the head', () {
      final path = PersonAnchorPath.plan(
        track: _track(4),
        start: 1,
        end: 3,
        placement: PersonPlacement.aboveHead,
        frameWidth: 1080,
        frameHeight: 1920,
      )!;

      expect(path.placement.occludedByPerson, isFalse);
      for (final key in path.keyframes) {
        expect(key.y, lessThan(0.3));
      }
    });

    test('returns null when the person is missing for most of the scene', () {
      final path = PersonAnchorPath.plan(
        track: _track(1),
        start: 0,
        end: 4,
        placement: PersonPlacement.behindShoulder,
        frameWidth: 1080,
        frameHeight: 1920,
      );

      expect(path, isNull);
    });

    test('returns null for a too short scene', () {
      final path = PersonAnchorPath.plan(
        track: _track(4),
        start: 1,
        end: 1.2,
        placement: PersonPlacement.behindShoulder,
        frameWidth: 1080,
        frameHeight: 1920,
      );

      expect(path, isNull);
    });
  });

  group('piecewiseExpression', () {
    test('builds nested linear segments', () {
      final expression = PersonAnchorPath.piecewiseExpression(
        <double>[0, 1, 2],
        <double>[10, 20, 40],
      );

      expect(
        expression,
        'if(lt(t,1.000),10.0+(10.0)*(t-0.000)/1.000,'
        'if(lt(t,2.000),20.0+(20.0)*(t-1.000)/1.000,40.0))',
      );
    });

    test('a single value is a constant', () {
      expect(
        PersonAnchorPath.piecewiseExpression(<double>[0], <double>[12.34]),
        '12.3',
      );
    });

    test('rejects mismatched input', () {
      expect(
        () => PersonAnchorPath.piecewiseExpression(
          <double>[0, 1],
          <double>[1],
        ),
        throwsArgumentError,
      );
    });
  });
}
