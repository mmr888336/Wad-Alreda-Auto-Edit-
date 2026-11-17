import 'package:auto_edit/continuous_scene_generator.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:auto_edit/scene_layout_memory.dart';
import 'package:flutter_test/flutter_test.dart';

const String _phrase = 'سر البركة والخير في حياة الناس';

void main() {
  setUp(SceneLayoutMemory.reset);

  group('SceneLayoutMemory', () {
    test('is empty for a new export', () {
      expect(SceneLayoutMemory.previousFor(1), isNull);
    });

    test('remembers the layout inside the same export only', () {
      SceneLayoutMemory.remember(1, SceneLayout.diagonal);
      expect(SceneLayoutMemory.previousFor(1), SceneLayout.diagonal);
      expect(SceneLayoutMemory.previousFor(2), isNull);
    });

    test('a new export starts fresh after remembering', () {
      SceneLayoutMemory.remember(1, SceneLayout.bigWord);
      SceneLayoutMemory.remember(2, SceneLayout.titleTop);
      expect(SceneLayoutMemory.previousFor(1), isNull);
      expect(SceneLayoutMemory.previousFor(2), SceneLayout.titleTop);
    });
  });

  group('a chain of cutaways in one export', () {
    test('no scene repeats the layout of the scene before it', () {
      const stamp = 77;
      SceneLayout? last;
      for (var index = 0; index < 8; index++) {
        final plan = ContinuousSceneGenerator.build(
          id: 'chain$index',
          spec: CutawaySpec(start: index * 6.0, end: index * 6.0 + 5, text: _phrase),
          width: 720,
          height: 1280,
          variant: index,
          previousLayout: SceneLayoutMemory.previousFor(stamp),
        );
        if (last != null) {
          expect(plan.layouts.first, isNot(last));
        }
        for (var i = 1; i < plan.layouts.length; i++) {
          expect(plan.layouts[i], isNot(plan.layouts[i - 1]));
        }
        last = plan.layouts.last;
        SceneLayoutMemory.remember(stamp, last);
      }
    });
  });
}
