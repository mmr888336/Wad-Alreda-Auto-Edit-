import 'package:auto_edit/person_tracking_codec.dart';
import 'package:auto_edit/person_tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

PersonTrackingResult _sampleResult() {
  return PersonTrackingResult(
    sampleFps: 8,
    frameWidth: 480,
    frameHeight: 640,
    framesAnalyzed: 2,
    failedFrames: 1,
    primaryTrackId: 3,
    notes: const <String>['ملاحظة'],
    tracks: <PersonTrack>[
      PersonTrack(
        id: 3,
        observations: <PersonObservation>[
          const PersonObservation(
            time: 0.125,
            box: NormalizedRect(
              left: 0.30123456,
              top: 0.1,
              right: 0.7,
              bottom: 0.9,
            ),
            confidence: 0.87654,
            landmarks: <BodyLandmark, LandmarkPoint>{
              BodyLandmark.nose: LandmarkPoint(
                x: 0.5,
                y: 0.2,
                z: -0.01,
                confidence: 0.9,
              ),
            },
          ),
          const PersonObservation(
            time: 0.25,
            box: NormalizedRect(left: 0.3, top: 0.1, right: 0.7, bottom: 0.9),
            confidence: 0.8,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('PersonTrackingCodec', () {
    test('round-trips a result through a JSON string', () {
      final text = PersonTrackingCodec.encodeToString(_sampleResult());
      final loaded = PersonTrackingCodec.decodeFromString(text);

      expect(loaded.sampleFps, 8);
      expect(loaded.frameWidth, 480);
      expect(loaded.frameHeight, 640);
      expect(loaded.framesAnalyzed, 2);
      expect(loaded.failedFrames, 1);
      expect(loaded.primaryTrackId, 3);
      expect(loaded.notes, <String>['ملاحظة']);
      expect(loaded.tracks.length, 1);

      final track = loaded.tracks.first;
      expect(track.id, 3);
      expect(track.observations.length, 2);

      final first = track.observations.first;
      expect(first.time, closeTo(0.125, 1e-4));
      expect(first.box.left, closeTo(0.30123456, 1e-4));
      expect(first.box.bottom, closeTo(0.9, 1e-4));
      expect(first.confidence, closeTo(0.87654, 1e-4));
      expect(first.landmarks[BodyLandmark.nose]!.z, closeTo(-0.01, 1e-4));
      expect(first.landmarks[BodyLandmark.nose]!.confidence, closeTo(0.9, 1e-4));

      expect(track.observations.last.landmarks, isEmpty);
    });

    test('keeps a result without a main person', () {
      final empty = PersonTrackingResult(
        sampleFps: 8,
        frameWidth: 480,
        frameHeight: 640,
        framesAnalyzed: 10,
        tracks: const <PersonTrack>[],
      );

      final loaded = PersonTrackingCodec.decodeFromString(
        PersonTrackingCodec.encodeToString(empty),
      );
      expect(loaded.primaryTrackId, isNull);
      expect(loaded.tracks, isEmpty);
      expect(loaded.framesAnalyzed, 10);
    });

    test('skips unknown landmark names', () {
      final data = PersonTrackingCodec.encode(_sampleResult());
      final tracks = data['tracks']! as List<Object?>;
      final track = tracks.first! as Map<String, Object?>;
      final observations = track['obs']! as List<Object?>;
      final observation = observations.first! as Map<String, Object?>;
      final landmarks = observation['lm']! as Map<String, Object?>;
      landmarks['notALandmark'] = <double>[0.1, 0.1, 0, 0.9];

      final loaded = PersonTrackingCodec.decode(data);
      expect(
        loaded.tracks.first.observations.first.landmarks.length,
        1,
      );
    });

    test('rejects an unsupported version', () {
      final data = PersonTrackingCodec.encode(_sampleResult());
      data['v'] = 99;
      expect(() => PersonTrackingCodec.decode(data), throwsFormatException);
    });

    test('rejects malformed data', () {
      expect(
        () => PersonTrackingCodec.decode(<String, Object?>{'v': 1}),
        throwsFormatException,
      );
      expect(
        () => PersonTrackingCodec.decodeFromString('not json'),
        throwsFormatException,
      );
      expect(
        () => PersonTrackingCodec.decodeFromString('[1, 2]'),
        throwsFormatException,
      );
    });
  });
}
