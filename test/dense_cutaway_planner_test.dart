import 'package:auto_edit/dense_cutaway_planner.dart';
import 'package:auto_edit/keyword_callout_planner.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _phrases = <String>[
  'نتحدث عن المال والرزق',
  'سر البركة والخير',
  'قصة الحب والرحمة',
  'تصوير الفيديو والمحتوى',
  'الخلاصة والنتيجة النهائية',
  'بعد ذلك نكمل الكلام',
];

/// A 60 second video with a caption every 2.5 seconds.
List<CalloutSource> _longVideo() {
  return <CalloutSource>[
    for (var i = 0; i < 24; i++)
      CalloutSource(
        start: 1.0 + i * 2.5,
        end: 3.0 + i * 2.5,
        text: _phrases[i % _phrases.length],
      ),
  ];
}

void main() {
  group('DenseCutawayPlanner', () {
    test('places many more scenes than the sparse planner', () {
      final captions = _longVideo();
      final sparse = ReferenceSceneBuilder.planCutaways(
        captions: captions,
        duration: 60,
        maxCount: 3,
      );
      final dense = DenseCutawayPlanner.plan(
        captions: captions,
        duration: 60,
        mood: MotionMood.dynamic,
      );
      expect(sparse.length, lessThanOrEqualTo(3));
      expect(dense.length, greaterThanOrEqualTo(6));
      expect(dense.length, greaterThan(sparse.length));
      expect(dense.length, lessThanOrEqualTo(DenseCutawayPlanner.hardCap));
    });

    test('looks at the whole video, not only its beginning', () {
      final dense = DenseCutawayPlanner.plan(
        captions: _longVideo(),
        duration: 60,
        mood: MotionMood.cinematic,
      );
      expect(dense, isNotEmpty);
      expect(dense.first.start, lessThan(20));
      expect(dense.last.start, greaterThan(40));
    });

    test('respects the hook window, durations, spacing and coverage', () {
      final dense = DenseCutawayPlanner.plan(
        captions: _longVideo(),
        duration: 60,
        mood: MotionMood.dynamic,
      );
      var covered = 0.0;
      for (final spec in dense) {
        expect(spec.start, greaterThanOrEqualTo(3.6));
        expect(spec.duration, greaterThanOrEqualTo(1.3));
        expect(spec.duration, lessThanOrEqualTo(3.0));
        expect(spec.end, lessThanOrEqualTo(60 - 0.3 + 1e-9));
        covered += spec.duration;
      }
      for (var i = 1; i < dense.length; i++) {
        expect(
          dense[i].start,
          greaterThanOrEqualTo(dense[i - 1].end + 0.8 - 1e-9),
        );
        expect(dense[i].start - dense[i - 1].start, greaterThanOrEqualTo(2.9));
      }
      expect(covered, lessThanOrEqualTo(60 * 0.40 + 1e-9));
    });

    test('keeps away from the ranges to avoid', () {
      final dense = DenseCutawayPlanner.plan(
        captions: _longVideo(),
        duration: 60,
        mood: MotionMood.dynamic,
        avoid: const <List<double>>[
          <double>[10.0, 20.0],
        ],
      );
      expect(dense, isNotEmpty);
      for (final spec in dense) {
        expect(spec.start >= 20.3 - 1e-9 || spec.end <= 9.7 + 1e-9, isTrue);
      }
    });

    test('a calm video gets no more scenes than a dynamic one', () {
      final calm = DenseCutawayPlanner.plan(
        captions: _longVideo(),
        duration: 60,
        mood: MotionMood.calm,
      );
      final dynamic_ = DenseCutawayPlanner.plan(
        captions: _longVideo(),
        duration: 60,
        mood: MotionMood.dynamic,
      );
      expect(calm, isNotEmpty);
      expect(calm.length, lessThanOrEqualTo(dynamic_.length));
    });

    test('maxCount limits the number of scenes', () {
      final dense = DenseCutawayPlanner.plan(
        captions: _longVideo(),
        duration: 60,
        mood: MotionMood.dynamic,
        maxCount: 4,
      );
      expect(dense.length, lessThanOrEqualTo(4));
      expect(dense, isNotEmpty);
    });

    test('merges very short neighbouring captions into one scene', () {
      final captions = <CalloutSource>[
        for (var i = 0; i < 30; i++)
          CalloutSource(
            start: 4.0 + i * 0.7,
            end: 4.7 + i * 0.7,
            text: _phrases[i % _phrases.length],
          ),
      ];
      final dense = DenseCutawayPlanner.plan(
        captions: captions,
        duration: 30,
        mood: MotionMood.dynamic,
      );
      expect(dense, isNotEmpty);
      for (final spec in dense) {
        expect(spec.duration, greaterThanOrEqualTo(1.3));
      }
    });

    test('returns nothing for very short videos or when disabled', () {
      expect(
        DenseCutawayPlanner.plan(captions: _longVideo(), duration: 7.9),
        isEmpty,
      );
      DenseCutawayPlanner.enabled = false;
      try {
        expect(
          DenseCutawayPlanner.plan(captions: _longVideo(), duration: 60),
          isEmpty,
        );
      } finally {
        DenseCutawayPlanner.enabled = true;
      }
    });

    test('targetCount grows with the video length and stays capped', () {
      final short = DenseCutawayPlanner.targetCount(
        duration: 20,
        mood: MotionMood.cinematic,
      );
      final long = DenseCutawayPlanner.targetCount(
        duration: 120,
        mood: MotionMood.cinematic,
      );
      expect(short, greaterThanOrEqualTo(1));
      expect(long, greaterThan(short));
      expect(long, lessThanOrEqualTo(DenseCutawayPlanner.hardCap));
    });
  });
}
