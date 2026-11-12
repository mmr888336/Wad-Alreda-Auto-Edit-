import 'package:auto_edit/smart_cut_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartCutEngine', () {
    test('keeps the full video when no silence was detected', () {
      final segments = SmartCutEngine.buildKeepSegments(
        duration: 12,
        silenceStarts: const [],
        silenceEnds: const [],
      );

      expect(segments, hasLength(1));
      expect(segments.single.start, 0);
      expect(segments.single.end, 12);
    });

    test('retains a natural pause after a short silence', () {
      final segments = SmartCutEngine.buildKeepSegments(
        duration: 10,
        silenceStarts: const [2],
        silenceEnds: const [2.7],
      );

      expect(segments, hasLength(2));
      final retainedGap =
          (segments[0].end - 2.0) + (2.7 - segments[1].start);
      expect(retainedGap, closeTo(0.24, 0.0001));
    });

    test('compresses long pauses more than short pauses', () {
      final shortPause = SmartCutEngine.buildKeepSegments(
        duration: 12,
        silenceStarts: const [2],
        silenceEnds: const [2.7],
      );
      final longPause = SmartCutEngine.buildKeepSegments(
        duration: 12,
        silenceStarts: const [2],
        silenceEnds: const [5],
      );

      final shortGap =
          (shortPause[0].end - 2.0) + (2.7 - shortPause[1].start);
      final longGap =
          (longPause[0].end - 2.0) + (5.0 - longPause[1].start);
      expect(longGap, lessThan(shortGap));
      expect(longGap, closeTo(0.15, 0.0001));
    });

    test('merges overlapping and genuinely near-adjacent silence detections', () {
      // The first two intervals are separated by only 20 ms; the final
      // interval overlaps the second. They should become one silence range.
      final segments = SmartCutEngine.buildKeepSegments(
        duration: 12,
        silenceStarts: const [4, 2, 3.02],
        silenceEnds: const [5, 3, 4],
      );

      expect(segments, hasLength(2));
      expect(segments[0].end, lessThan(2.2));
      expect(segments[1].start, greaterThan(4.8));
    });

    test('keeps a spoken bridge between silences instead of merging it away', () {
      // There is 980 ms between the first and second silence detections.
      // This is not a near-adjacent silence and must remain as speech.
      final segments = SmartCutEngine.buildKeepSegments(
        duration: 12,
        silenceStarts: const [4, 2, 3.98],
        silenceEnds: const [5, 3, 4.8],
      );

      expect(segments, hasLength(3));
      expect(segments[1].start, greaterThan(2.8));
      expect(segments[1].end, lessThan(4.2));
      expect(segments[1].duration, greaterThan(0.9));
    });

    test('clamps out-of-range silence detections to video boundaries', () {
      final segments = SmartCutEngine.buildKeepSegments(
        duration: 10,
        silenceStarts: const [-2, 12],
        silenceEnds: const [1, 15],
      );

      expect(segments, isNotEmpty);
      expect(segments.every((s) => s.start >= 0 && s.end <= 10), isTrue);
      expect(segments.every((s) => s.end > s.start), isTrue);
    });

    test('ignores invalid silence timestamps', () {
      final segments = SmartCutEngine.buildKeepSegments(
        duration: 8,
        silenceStarts: const [double.nan, 3],
        silenceEnds: const [4, double.infinity],
      );

      expect(segments, hasLength(1));
      expect(segments.single.start, 0);
      expect(segments.single.end, 8);
    });

    test('rejects an invalid video duration', () {
      expect(
        () => SmartCutEngine.buildKeepSegments(
          duration: double.nan,
          silenceStarts: const [],
          silenceEnds: const [],
        ),
        throwsArgumentError,
      );
    });
  });
}
