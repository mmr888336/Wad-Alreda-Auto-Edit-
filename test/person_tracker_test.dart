import 'package:auto_edit/person_tracker.dart';
import 'package:auto_edit/person_tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

const double _fps = 8;

double _time(int frame) => frame / _fps;

PersonDetection _person(
  double centerX, {
  double confidence = 0.9,
  Map<BodyLandmark, LandmarkPoint> landmarks =
      const <BodyLandmark, LandmarkPoint>{},
}) {
  return PersonDetection(
    box: NormalizedRect(
      left: centerX - 0.15,
      top: 0.2,
      right: centerX + 0.15,
      bottom: 0.8,
    ),
    confidence: confidence,
    landmarks: landmarks,
  );
}

void main() {
  group('PersonTracker', () {
    test('follows one person moving across the frame as a single track', () {
      final tracker = PersonTracker();
      for (var i = 0; i < 20; i++) {
        tracker.update(_time(i), [_person(0.3 + i * 0.01)]);
      }

      final tracks = tracker.finish();
      expect(tracks.length, 1);
      expect(tracks.first.observations.length, 20);
    });

    test('keeps two separated people on separate tracks', () {
      final tracker = PersonTracker();
      for (var i = 0; i < 10; i++) {
        tracker.update(_time(i), [_person(0.25), _person(0.75)]);
      }

      final tracks = tracker.finish();
      expect(tracks.length, 2);
      expect(tracks[0].id, isNot(tracks[1].id));
      expect(tracks[0].observations.length, 10);
      expect(tracks[1].observations.length, 10);
      expect(
        tracks[0].observations.every((item) => item.box.centerX < 0.5),
        isTrue,
      );
      expect(
        tracks[1].observations.every((item) => item.box.centerX > 0.5),
        isTrue,
      );
    });

    test('bridges a short detection gap inside the same track', () {
      final tracker = PersonTracker();
      for (var i = 0; i < 24; i++) {
        final missing = i >= 10 && i <= 13;
        tracker.update(_time(i), missing ? <PersonDetection>[] : [_person(0.5)]);
      }

      final tracks = tracker.finish();
      expect(tracks.length, 1);
      expect(tracks.first.observations.length, 20);
    });

    test('stitches the same person after a longer gap', () {
      final tracker = PersonTracker();
      for (var i = 0; i < 34; i++) {
        final present = i < 10 || i >= 24;
        tracker.update(_time(i), present ? [_person(0.3)] : <PersonDetection>[]);
      }

      final tracks = tracker.finish();
      expect(tracks.length, 1);
      expect(tracks.first.id, 1);
      expect(tracks.first.observations.length, 20);
    });

    test('does not stitch a different person who appears far away', () {
      final tracker = PersonTracker();
      for (var i = 0; i < 34; i++) {
        if (i < 10) {
          tracker.update(_time(i), [_person(0.2)]);
        } else if (i >= 24) {
          tracker.update(_time(i), [_person(0.8)]);
        } else {
          tracker.update(_time(i), <PersonDetection>[]);
        }
      }

      expect(tracker.finish().length, 2);
    });

    test('drops very short tracks as noise', () {
      final tracker = PersonTracker();
      tracker.update(_time(0), [_person(0.5)]);
      for (var i = 1; i < 10; i++) {
        tracker.update(_time(i), <PersonDetection>[]);
      }

      expect(tracker.finish(), isEmpty);
    });

    test('ignores low-confidence detections', () {
      final tracker = PersonTracker();
      for (var i = 0; i < 10; i++) {
        tracker.update(_time(i), [_person(0.5, confidence: 0.2)]);
      }

      expect(tracker.finish(), isEmpty);
    });

    test('rejects frame times that do not increase', () {
      final tracker = PersonTracker();
      tracker.update(1, <PersonDetection>[]);

      expect(() => tracker.update(1, <PersonDetection>[]), throwsArgumentError);
      expect(() => tracker.update(0.5, <PersonDetection>[]), throwsArgumentError);
    });
  });

  group('PersonTracker smoothing', () {
    Map<BodyLandmark, LandmarkPoint> nose(double x, double confidence) {
      return <BodyLandmark, LandmarkPoint>{
        BodyLandmark.nose: LandmarkPoint(x: x, y: 0.2, confidence: confidence),
      };
    }

    test('smooths a sudden landmark jump', () {
      final tracker = PersonTracker();
      for (var i = 0; i < 6; i++) {
        final x = i == 5 ? 0.6 : 0.5;
        tracker.update(_time(i), [_person(0.5, landmarks: nose(x, 0.9))]);
      }

      final observations = tracker.finish().first.observations;
      expect(observations.length, 6);
      expect(observations[4].landmarks[BodyLandmark.nose]!.x, closeTo(0.5, 1e-9));
      expect(observations[5].landmarks[BodyLandmark.nose]!.x, closeTo(0.555, 1e-9));
    });

    test('holds the last good position for an unreliable landmark', () {
      final tracker = PersonTracker();
      for (var i = 0; i < 6; i++) {
        final landmarks = i == 5 ? nose(0.9, 0.1) : nose(0.5, 0.9);
        tracker.update(_time(i), [_person(0.5, landmarks: landmarks)]);
      }

      final last = tracker.finish().first.observations.last;
      final point = last.landmarks[BodyLandmark.nose]!;
      expect(point.x, closeTo(0.5, 1e-9));
      expect(point.confidence, closeTo(0.1, 1e-9));
    });
  });
}
