import 'package:flutter_test/flutter_test.dart';

import 'package:wad_alreda_auto_edit/cinematic_world.dart';
import 'package:wad_alreda_auto_edit/story_understanding.dart';

void main() {
  group('StoryEnvironment layouts', () {
    test('every environment has a layout', () {
      for (final environment in StoryEnvironment.values) {
        expect(
          CinematicWorld.layouts.containsKey(environment),
          isTrue,
          reason: 'missing layout for ${environment.name}',
        );
      }
    });

    test('every layout points at its own environment', () {
      CinematicWorld.layouts.forEach((environment, layout) {
        expect(layout.environment, environment);
        expect(layout.backdropKey, isNotEmpty);
        expect(layout.backdropColor, startsWith('#'));
        expect(layout.setPieces, isNotEmpty);
        expect(layout.slots, isNotEmpty);
      });
    });

    test('CinematicWorld.plan does not throw for any environment', () {
      for (final environment in StoryEnvironment.values) {
        final story = StoryPlan(<StoryBeat>[
          StoryBeat(
            index: 0,
            segment: const StorySegment(text: 'test', start: 0, end: 2),
            focus: 'none',
            environment: environment,
            mood: StoryMood.calm,
            props: const <String>[],
            effectWord: 'test',
            shot: StoryShotKind.medium,
            cameraHint: DepthCameraMove.none,
            transitionToNext: MotionTransitionKind.hardCut,
            windowToNext: false,
          ),
        ]);
        final plan = CinematicWorld.plan(story);
        expect(plan.scenes, hasLength(1));
        expect(plan.scenes.first.environment, environment);
      }
    });
  });

  group('StoryUnderstanding environment detection', () {
    StoryEnvironment environmentOf(String text) {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        StorySegment(text: text, start: 0, end: 2),
      ]);
      return plan.beats.first.environment;
    }

    test('bathroom words pick the bathroom', () {
      expect(environmentOf('الحمامات'), StoryEnvironment.bathroom);
      expect(environmentOf('bathroom'), StoryEnvironment.bathroom);
    });

    test('kitchen words pick the kitchen', () {
      expect(environmentOf('المطبخ'), StoryEnvironment.kitchen);
      expect(environmentOf('kitchen'), StoryEnvironment.kitchen);
    });

    test('bedroom words pick the bedroom', () {
      expect(environmentOf('غرفة النوم'), StoryEnvironment.bedroom);
      expect(environmentOf('bedroom'), StoryEnvironment.bedroom);
    });

    test('living room words pick the living room', () {
      expect(environmentOf('الصالة'), StoryEnvironment.livingRoom);
      expect(environmentOf('living room'), StoryEnvironment.livingRoom);
    });

    test('hallway words pick the hallway', () {
      expect(environmentOf('الممر'), StoryEnvironment.hallway);
      expect(environmentOf('hallway'), StoryEnvironment.hallway);
    });
  });
}
