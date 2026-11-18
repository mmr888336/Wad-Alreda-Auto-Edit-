import 'package:auto_edit/editing_engine.dart';
import 'package:auto_edit/motion_camera_engine.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:flutter_test/flutter_test.dart';

// The longest fade the B-roll filter applies at either end of a cutaway.
double _longestFade(String filter) {
  final matches =
      RegExp(r'fade=t=(?:in|out):st=[0-9.]+:d=([0-9.]+)').allMatches(filter);
  var longest = 0.0;
  for (final match in matches) {
    final value = double.parse(match.group(1)!);
    if (value > longest) longest = value;
  }
  return longest;
}

void main() {
  const topics = <String, String>{
    'calm': 'سيرة النبي ومواقف الصحابة والتوكل على الله',
    'dynamic': 'مراجعة منتج جديد وسعره متوفر في المتجر',
    'cinematic': 'قصة رحلة طويلة وحكاية غريبة',
  };

  group('B-roll cuts instead of dissolving', () {
    topics.forEach((name, content) {
      test('$name mood keeps the B-roll fade short', () {
        final motion = MotionGraphicsPlan.forProfile(
          EditingEngine.select(content: content, requestedStyle: 'auto'),
        );

        expect(
          motion.brollFadeSeconds,
          lessThanOrEqualTo(MotionGraphicsPlan.maxBrollFadeSeconds),
        );

        final filter = motion.brollInputFilter(
          width: 1080,
          height: 1920,
          start: 5.5,
          end: 7.0,
        );
        expect(filter, contains('fade=t=in'));
        expect(filter, contains('fade=t=out'));
        expect(
          _longestFade(filter),
          lessThanOrEqualTo(MotionGraphicsPlan.maxBrollFadeSeconds + 1e-9),
        );
      });
    });

    test('a long configured fade is still capped', () {
      const slow = MotionGraphicsPlan(
        mood: MotionMood.calm,
        label: 'slow',
        captionEnterSeconds: 0.3,
        captionFadeOutSeconds: 0.2,
        hookEnterSeconds: 0.4,
        hookDurationSeconds: 3.2,
        brollFadeSeconds: 0.9,
        captionTravel: 0.3,
        cameraStyle: CameraMotionStyle.restrained,
      );

      final filter = slow.brollInputFilter(
        width: 1080,
        height: 1920,
        start: 2,
        end: 6,
      );

      expect(
        _longestFade(filter),
        lessThanOrEqualTo(MotionGraphicsPlan.maxBrollFadeSeconds + 1e-9),
      );
    });
  });
}
