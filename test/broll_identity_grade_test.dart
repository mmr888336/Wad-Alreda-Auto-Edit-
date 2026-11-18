import 'package:auto_edit/editing_engine.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plan = MotionGraphicsPlan.forProfile(
    EditingEngine.select(
      content: 'قصة رحلة طويلة وحكاية غريبة',
      requestedStyle: 'auto',
    ),
  );

  String filter({required bool grade}) => plan.brollInputFilter(
        width: 1080,
        height: 1920,
        start: 5.5,
        end: 7.0,
        unifiedGrade: grade,
      );

  group('stock B-roll identity grade', () {
    test('is off by default: the filter is the same as before', () {
      final plain = plan.brollInputFilter(
        width: 1080,
        height: 1920,
        start: 5.5,
        end: 7.0,
      );
      expect(plain, filter(grade: false));
      expect(plain, isNot(contains('colorchannelmixer')));
    });

    test('adds only a colour-channel mixer, never touching alpha', () {
      final graded = filter(grade: true);
      expect(graded, contains(MotionGraphicsPlan.unifiedGradeFilter));
      expect(MotionGraphicsPlan.unifiedGradeFilter, contains('colorchannelmixer'));
      expect(MotionGraphicsPlan.unifiedGradeFilter, isNot(contains('aa=')));
      expect(MotionGraphicsPlan.unifiedGradeFilter, isNot(contains('ar=')));
    });

    test('keeps the hard cut: fades first, grade after, timing last', () {
      final graded = filter(grade: true);
      final fadeOut = graded.indexOf('fade=t=out');
      final grade = graded.indexOf('colorchannelmixer');
      final timing = graded.lastIndexOf('setpts=PTS+');
      expect(fadeOut, greaterThan(0));
      expect(grade, greaterThan(fadeOut));
      expect(timing, greaterThan(grade));
    });

    test('grading removes nothing from the plain filter', () {
      final plain = filter(grade: false);
      final graded = filter(grade: true);
      expect(
        graded.replaceFirst(',${MotionGraphicsPlan.unifiedGradeFilter}', ''),
        plain,
      );
    });
  });
}
