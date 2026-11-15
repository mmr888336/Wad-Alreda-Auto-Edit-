import 'package:auto_edit/person_tracking_models.dart';
import 'package:auto_edit/visual_tracking_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedDetector implements PersonDetector {
  _ScriptedDetector(this.script);

  final List<PersonDetection> Function(PersonFrame frame) script;
  int calls = 0;

  @override
  Future<List<PersonDetection>> detect(PersonFrame frame) async {
    calls++;
    return script(frame);
  }

  @override
  Future<void> dispose() async {}
}

List<PersonFrame> _frames(int count, {double fps = 8}) {
  return List<PersonFrame>.generate(
    count,
    (i) => PersonFrame(
      index: i,
      time: i / fps,
      path: 'frame_$i.jpg',
      width: 480,
      height: 640,
    ),
  );
}

PersonDetection _person(double centerX) {
  return PersonDetection(
    box: NormalizedRect(
      left: centerX - 0.15,
      top: 0.2,
      right: centerX + 0.15,
      bottom: 0.8,
    ),
    confidence: 0.9,
  );
}

void main() {
  group('frame extraction command', () {
    test('builds a quoted, sampled and scaled FFmpeg command', () {
      final command = VisualTrackingEngine.buildFrameExtractionCommand(
        videoPath: '/data/my "clip".mp4',
        outputPattern: '/tmp/f/frame_%05d.jpg',
        fps: 8,
        width: 481,
        maxSeconds: 60,
        maxFrames: 600,
      );

      expect(command, contains('-i "/data/my \\"clip\\".mp4"'));
      expect(command, contains('fps=8.00'));
      expect(command, contains('scale=480:-2'));
      expect(command, contains('-frames:v 600'));
      expect(command, contains('-t 60.00'));
      expect(command, contains('"/tmp/f/frame_%05d.jpg"'));
    });

    test('rejects invalid arguments', () {
      expect(
        () => VisualTrackingEngine.buildFrameExtractionCommand(
          videoPath: '',
          outputPattern: 'x_%05d.jpg',
        ),
        throwsArgumentError,
      );
      expect(
        () => VisualTrackingEngine.buildFrameExtractionCommand(
          videoPath: 'a.mp4',
          outputPattern: 'x_%05d.jpg',
          fps: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => VisualTrackingEngine.buildFrameExtractionCommand(
          videoPath: 'a.mp4',
          outputPattern: 'x_%05d.jpg',
          width: 10,
        ),
        throwsArgumentError,
      );
      expect(
        () => VisualTrackingEngine.buildFrameExtractionCommand(
          videoPath: 'a.mp4',
          outputPattern: 'x_%05d.jpg',
          maxFrames: 0,
        ),
        throwsArgumentError,
      );
    });

    test('computes the time of a sampled frame', () {
      expect(VisualTrackingEngine.frameTime(0, 8), 0);
      expect(VisualTrackingEngine.frameTime(12, 8), closeTo(1.5, 1e-9));
    });
  });

  group('media parsing', () {
    test('reads the duration from FFmpeg logs', () {
      expect(
        VisualTrackingEngine.parseDurationSeconds(
          '  Duration: 00:01:05.50, start: 0.000000, bitrate: 2000 kb/s',
        ),
        closeTo(65.5, 1e-9),
      );
      expect(
        VisualTrackingEngine.parseDurationSeconds('Duration: 01:00:00.00,'),
        closeTo(3600, 1e-9),
      );
      expect(
        VisualTrackingEngine.parseDurationSeconds('Duration: N/A, bitrate: N/A'),
        isNull,
      );
    });

    test('reads the size of a JPEG from its header', () {
      final bytes = <int>[
        0xFF, 0xD8, // start of image
        0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0 segment
        0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, length 17, 8-bit
        0x03, 0x20, // height 800
        0x01, 0x90, // width 400
        0x03,
      ];

      final size = VisualTrackingEngine.readJpegSize(bytes)!;
      expect(size.width, 400);
      expect(size.height, 800);
    });

    test('returns null for data that is not a usable JPEG', () {
      expect(VisualTrackingEngine.readJpegSize(<int>[1, 2, 3, 4, 5]), isNull);
      expect(VisualTrackingEngine.readJpegSize(<int>[0xFF, 0xD8, 0xFF]), isNull);
      expect(VisualTrackingEngine.readJpegSize(<int>[]), isNull);
    });
  });

  group('main subject selection', () {
    PersonTrack track(int id, int count, NormalizedRect box) {
      return PersonTrack(
        id: id,
        observations: [
          for (var i = 0; i < count; i++)
            PersonObservation(time: i / 8, box: box, confidence: 0.9),
        ],
      );
    }

    test('prefers the long, large, central track', () {
      final main = track(
        1,
        40,
        const NormalizedRect(left: 0.3, top: 0.1, right: 0.7, bottom: 0.9),
      );
      final background = track(
        2,
        5,
        const NormalizedRect(left: 0.05, top: 0.05, right: 0.15, bottom: 0.25),
      );

      final primary = VisualTrackingEngine.choosePrimaryTrack(
        [background, main],
        frameCount: 50,
      );
      expect(primary?.id, 1);
    });

    test('returns null when there are no tracks', () {
      expect(
        VisualTrackingEngine.choosePrimaryTrack(<PersonTrack>[], frameCount: 10),
        isNull,
      );
    });
  });

  group('analyzeFrames', () {
    test('tracks one person and reports coverage', () async {
      final detector = _ScriptedDetector(
        (frame) => frame.index == 10 ? <PersonDetection>[] : [_person(0.5)],
      );
      final progress = <double>[];

      final result = await VisualTrackingEngine.analyzeFrames(
        frames: _frames(20),
        detector: detector,
        onProgress: progress.add,
      );

      expect(result.framesAnalyzed, 20);
      expect(result.tracks.length, 1);
      expect(result.primaryTrackId, result.tracks.first.id);
      expect(result.framesWithPrimaryPerson, 19);
      expect(result.coverage, closeTo(0.95, 1e-9));
      expect(result.failedFrames, 0);

      expect(progress.length, 20);
      expect(progress.last, closeTo(1.0, 1e-9));

      final filled = result.primaryTrack!.sampleAt(10 / 8)!;
      expect(filled.interpolated, isTrue);
      expect(result.peopleAt(10 / 8).length, 1);
    });

    test('reports a note when nobody is found', () async {
      final detector = _ScriptedDetector((frame) => <PersonDetection>[]);

      final result = await VisualTrackingEngine.analyzeFrames(
        frames: _frames(12),
        detector: detector,
      );

      expect(result.primaryTrackId, isNull);
      expect(result.tracks, isEmpty);
      expect(result.coverage, 0);
      expect(result.notes, isNotEmpty);
    });

    test('survives a few failing frames and records a note', () async {
      final detector = _ScriptedDetector((frame) {
        if (frame.index == 3 || frame.index == 4) {
          throw StateError('native failure');
        }
        return [_person(0.5)];
      });

      final result = await VisualTrackingEngine.analyzeFrames(
        frames: _frames(20),
        detector: detector,
      );

      expect(result.failedFrames, 2);
      expect(result.primaryTrackId, isNotNull);
      expect(result.notes, isNotEmpty);
    });

    test('fails when the detector fails on every frame', () async {
      final detector = _ScriptedDetector((frame) {
        throw StateError('native failure');
      });

      await expectLater(
        VisualTrackingEngine.analyzeFrames(
          frames: _frames(5),
          detector: detector,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('stops when cancelled', () async {
      final detector = _ScriptedDetector((frame) => [_person(0.5)]);

      await expectLater(
        VisualTrackingEngine.analyzeFrames(
          frames: _frames(20),
          detector: detector,
          isCancelled: () => detector.calls >= 3,
        ),
        throwsA(isA<StateError>()),
      );
      expect(detector.calls, 3);
    });

    test('requires at least one frame', () async {
      final detector = _ScriptedDetector((frame) => <PersonDetection>[]);

      await expectLater(
        VisualTrackingEngine.analyzeFrames(
          frames: <PersonFrame>[],
          detector: detector,
        ),
        throwsArgumentError,
      );
    });
  });
}
