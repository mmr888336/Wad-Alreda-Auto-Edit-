import 'package:auto_edit/directed_text.dart';
import 'package:auto_edit/motion_transitions.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:flutter_test/flutter_test.dart';

StoryBeat _beat(String text, double start, double end) {
  return StoryUnderstanding.plan(<StorySegment>[
    StorySegment(text: text, start: start, end: end),
  ]).beats.single;
}

void main() {
  group('cues', () {
    test('words are replaced in place: cues are contiguous and cover the beat',
        () {
      final beat = _beat('الفلوس مهمة جدا في حياتنا اليومية', 2, 5);
      final cues = DirectedText.cuesForBeat(beat, lane: CaptionLane.lower);
      expect(cues.length, 2);
      expect(cues.first.start, 2);
      expect(cues.last.end, 5);
      for (var i = 0; i < cues.length - 1; i++) {
        expect(cues[i].end, cues[i + 1].start);
      }
      final total = cues.fold<int>(0, (sum, cue) => sum + cue.words.length);
      expect(total, 6);
      for (final cue in cues) {
        expect(cue.duration, greaterThanOrEqualTo(DirectedText.minCueSeconds));
      }
    });

    test('only the effect word is accented, black and bigger', () {
      final beat = _beat('الفلوس مهمة جدا في حياتنا اليومية', 0, 3);
      final cues = DirectedText.cuesForBeat(beat, lane: CaptionLane.lower);
      final accented = <DirectedWord>[
        for (final cue in cues)
          for (final word in cue.words)
            if (word.accent) word,
      ];
      expect(accented.length, 1);
      expect(accented.first.text, 'الفلوس');
      expect(accented.first.weight, DirectedWeight.black);
      expect(accented.first.style, DirectedFontStyle.display);
      expect(accented.first.sizeFactor, greaterThan(1.2));
      expect(cues.first.motion, DirectedMotion.popScale);
    });

    test('a line mixes more than one weight and size', () {
      final beat = _beat('الفلوس مهمة جدا في حياتنا اليومية', 0, 3);
      final words = <DirectedWord>[
        for (final cue in DirectedText.cuesForBeat(beat, lane: CaptionLane.lower))
          ...cue.words,
      ];
      expect(words.map((w) => w.weight).toSet().length, greaterThan(1));
      expect(words.map((w) => w.sizeFactor).toSet().length, greaterThan(1));
    });

    test('a very short beat gets one cue, never a flicker', () {
      final beat = _beat('الفلوس مهمة جدا في حياتنا اليومية', 0, 0.5);
      final cues = DirectedText.cuesForBeat(beat, lane: CaptionLane.lower);
      expect(cues.length, 1);
      expect(cues.single.start, 0);
      expect(cues.single.end, 0.5);
    });
  });

  group('lane', () {
    const person = DirectedRect(left: 0.3, top: 0.6, right: 0.7, bottom: 1.0);

    test('stays where it is when nothing covers it', () {
      expect(
        DirectedText.chooseLane(
          previous: CaptionLane.upper,
          avoid: const <DirectedRect>[],
        ),
        CaptionLane.upper,
      );
    });

    test('moves only when the person or the mic covers the lane', () {
      expect(
        DirectedText.chooseLane(
          previous: CaptionLane.lower,
          avoid: const <DirectedRect>[person],
        ),
        CaptionLane.upper,
      );
    });

    test('takes the middle lane when upper and lower are both covered', () {
      expect(
        DirectedText.chooseLane(
          previous: CaptionLane.lower,
          avoid: const <DirectedRect>[
            person,
            DirectedRect(left: 0.3, top: 0.05, right: 0.7, bottom: 0.3),
          ],
        ),
        CaptionLane.middle,
      );
    });

    test('plan keeps the new lane after the person has moved away', () {
      final story = StoryUnderstanding.plan(const <StorySegment>[
        StorySegment(text: 'الفلوس مهمة', start: 0, end: 3),
        StorySegment(text: 'والتجارة كمان', start: 3, end: 6),
        StorySegment(text: 'والبيع كمان', start: 6, end: 9),
      ]);
      final cues = DirectedText.plan(
        story,
        avoidByBeat: const <int, List<DirectedRect>>{
          1: <DirectedRect>[person],
        },
      );
      expect(cues.where((c) => c.beatIndex == 0).first.lane, CaptionLane.lower);
      expect(cues.where((c) => c.beatIndex == 1).first.lane, CaptionLane.upper);
      expect(cues.where((c) => c.beatIndex == 2).first.lane, CaptionLane.upper);
    });
  });

  group('cuts', () {
    test('every transition is mapped into the allowed set', () {
      for (final kind in MotionTransitionKind.values) {
        expect(
          DirectedText.allowedTransitions,
          contains(DirectedText.unifyTransition(kind)),
        );
      }
      expect(
        DirectedText.unifyTransition(MotionTransitionKind.lightLeak),
        MotionTransitionKind.matchCut,
      );
      expect(
        DirectedText.unifyTransition(MotionTransitionKind.glitchSlice),
        MotionTransitionKind.whipPan,
      );
      expect(
        DirectedText.unifyTransition(MotionTransitionKind.zoomSmash),
        MotionTransitionKind.zoomSmash,
      );
    });
  });
}
