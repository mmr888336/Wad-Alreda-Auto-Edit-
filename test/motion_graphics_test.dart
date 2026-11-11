import 'package:auto_edit/editing_engine.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MotionGraphicsPlan topic-aware motion', () {
    test('religious content uses calm motion', () {
      final profile = EditingEngine.select(
        content: 'سيرة النبي ومواقف الصحابة والتوكل على الله',
        requestedStyle: 'auto',
      );
      final motion = MotionGraphicsPlan.forProfile(profile);

      expect(motion.mood, MotionMood.calm);
      expect(motion.captionEnterSeconds, greaterThan(0.3));

      expect(
        motion.captionXExpression(
          baseX: '(main_w-overlay_w)/2',
          start: 1,
        ),
        '(main_w-overlay_w)/2',
      );
    });

    test('product content uses dynamic motion', () {
      final profile = EditingEngine.select(
        content: 'مراجعة منتج جديد وسعره متوفر في المتجر',
        requestedStyle: 'auto',
      );
      final motion = MotionGraphicsPlan.forProfile(profile);

      expect(motion.mood, MotionMood.dynamic);

      expect(
        motion.captionXExpression(
          baseX: '(main_w-overlay_w)/2',
          start: 1,
        ),
        contains('overlay_w*0.72'),
      );

      expect(
        motion.hookXExpression(
          baseX: '(main_w-overlay_w)/2',
          start: 0.1,
        ),
        contains('overlay_w*0.85'),
      );
    });

    test('caption overlays are faded and time-shifted', () {
      final motion = MotionGraphicsPlan.forProfile(
        EditingEngine.select(
          content: 'حكاية وتجربة',
          requestedStyle: 'auto',
        ),
      );

      final filter = motion.overlayInputFilter(
        duration: 2,
        timelineStart: 4.5,
      );

      expect(filter, contains('format=rgba'));
      expect(filter, contains('fade=t=in'));
      expect(filter, contains('fade=t=out'));
      expect(filter, contains('setpts=PTS-STARTPTS+4.500/TB'));
    });

    test('B-roll is trimmed and alpha-faded', () {
      final motion = MotionGraphicsPlan.forProfile(
        EditingEngine.select(
          content: 'مراجعة منتج',
          requestedStyle: 'auto',
        ),
      );

      final filter = motion.brollInputFilter(
        width: 1080,
        height: 1920,
        start: 3,
        end: 5.5,
      );

      expect(filter, contains('trim=duration=2.500'));
      expect(filter, contains('fade=t=in'));
      expect(filter, contains('fade=t=out'));
      expect(filter, contains('setpts=PTS+3.000/TB'));
    });

    test('caption vertical movement uses eased timing', () {
      final motion = MotionGraphicsPlan.forProfile(
        EditingEngine.select(
          content: 'درس تعليمي',
          requestedStyle: 'auto',
        ),
      );

      final expression = motion.captionYExpression(
        baseY: 'main_h*0.80-overlay_h/2',
        start: 2,
        direction: 'up',
      );

      expect(expression, contains('pow(max(0,1-'));
      expect(expression, contains('overlay_h*0.340'));
      expect(expression, contains('if(lt(t,2.340)'));
    });
  });
}
