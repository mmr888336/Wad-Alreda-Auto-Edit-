import 'package:auto_edit/cue_windows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CueWindows.freeParts', () {
    test('a window with nothing blocked is returned whole', () {
      final parts = CueWindows.freeParts(
        start: 2,
        end: 6,
        blocked: const <TimeWindow>[],
      );

      expect(parts.length, 1);
      expect(parts.first.start, 2);
      expect(parts.first.end, 6);
    });

    test('a window fully covered by B-roll has no free part', () {
      final parts = CueWindows.freeParts(
        start: 5.5,
        end: 7,
        blocked: const <TimeWindow>[(start: 5, end: 8)],
      );

      expect(parts, isEmpty);
    });

    test('B-roll in the middle splits the window in two', () {
      final parts = CueWindows.freeParts(
        start: 0,
        end: 10,
        blocked: const <TimeWindow>[(start: 4, end: 6)],
      );

      expect(parts.length, 2);
      expect(parts[0].start, 0);
      expect(parts[0].end, 4);
      expect(parts[1].start, 6);
      expect(parts[1].end, 10);
    });

    test('B-roll at the start or the end trims the window', () {
      final head = CueWindows.freeParts(
        start: 4,
        end: 9,
        blocked: const <TimeWindow>[(start: 3, end: 5.5)],
      );
      expect(head.length, 1);
      expect(head.first.start, 5.5);
      expect(head.first.end, 9);

      final tail = CueWindows.freeParts(
        start: 4,
        end: 9,
        blocked: const <TimeWindow>[(start: 7.5, end: 12)],
      );
      expect(tail.length, 1);
      expect(tail.first.start, 4);
      expect(tail.first.end, 7.5);
    });

    test('unsorted and overlapping B-roll windows are merged', () {
      final parts = CueWindows.freeParts(
        start: 0,
        end: 12,
        blocked: const <TimeWindow>[
          (start: 8, end: 9),
          (start: 2, end: 4),
          (start: 3, end: 5),
        ],
      );

      expect(parts.length, 3);
      expect(parts[0].end, 2);
      expect(parts[1].start, 5);
      expect(parts[1].end, 8);
      expect(parts[2].start, 9);
      expect(parts[2].end, 12);
    });

    test('free parts shorter than the minimum are dropped', () {
      final parts = CueWindows.freeParts(
        start: 0,
        end: 5,
        blocked: const <TimeWindow>[(start: 0.3, end: 4.8)],
      );

      expect(parts, isEmpty);
    });

    test('an invalid window gives nothing', () {
      expect(
        CueWindows.freeParts(
          start: 5,
          end: 5,
          blocked: const <TimeWindow>[],
        ),
        isEmpty,
      );
      expect(
        CueWindows.freeParts(
          start: double.nan,
          end: 5,
          blocked: const <TimeWindow>[],
        ),
        isEmpty,
      );
    });

    test('a non-finite blocked window is ignored', () {
      final parts = CueWindows.freeParts(
        start: 0,
        end: 4,
        blocked: const <TimeWindow>[(start: double.nan, end: 2)],
      );

      expect(parts.length, 1);
      expect(parts.first.end, 4);
    });
  });

  group('CueWindows.longestFreePart', () {
    test('picks the longer side of a split window', () {
      final part = CueWindows.longestFreePart(
        start: 0,
        end: 10,
        blocked: const <TimeWindow>[(start: 3, end: 4)],
      );

      expect(part, isNotNull);
      expect(part!.start, 4);
      expect(part.end, 10);
    });

    test('is null when B-roll covers the whole window', () {
      final part = CueWindows.longestFreePart(
        start: 1,
        end: 3,
        blocked: const <TimeWindow>[(start: 0, end: 5)],
      );

      expect(part, isNull);
    });
  });
}
