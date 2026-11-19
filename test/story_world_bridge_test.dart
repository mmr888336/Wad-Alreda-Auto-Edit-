import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/motion_transitions.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/story_world_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

StorySegment _seg(String text, double start, double end) =>
    StorySegment(text: text, start: start, end: end);

void main() {
  final segments = <StorySegment>[
    _seg('الفلوس مهمة', 0, 3),
    _seg('البركة والخير', 3, 6),
  ];

  test('plans the story and the world in one call', () {
    final plan = StoryWorldBridge.plan(segments);
    expect(plan.story.beats.length, 2);
    expect(plan.world.scenes.length, 2);
    expect(plan.world.scenes[0].environment, StoryEnvironment.office);
    expect(plan.world.scenes[1].environment, StoryEnvironment.room);
    expect(plan.worldSceneOf(1), same(plan.world.scenes[1]));
    expect(plan.worldSceneOf(9), isNull);
  });

  test('world layers become motion layers without any change', () {
    final plan = StoryWorldBridge.plan(segments);
    final scene = plan.world.scenes.first;
    final layers = StoryWorldBridge.layersOf(scene, start: 0, end: 3);
    expect(layers.length, scene.layers.length);
    final hero = layers.singleWhere((l) => l.id == 'w0_hero');
    expect(hero.assetKey, 'sprite:hero');
    expect(hero.zIndex, 20);
    expect(hero.depth, WorldCharacter.depth);
    for (final layer in layers) {
      expect(layer.start, 0);
      expect(layer.end, 3);
    }
  });

  test('the project is valid and follows the story', () {
    final plan = StoryWorldBridge.plan(segments);
    final project = StoryWorldBridge.projectFor(
      plan,
      id: 'p',
      width: 1080,
      height: 1920,
    );
    project.validate();
    expect(project.duration, 6);
    expect(project.scenes.length, 2);
    expect(project.scenes[0].background, '#1E2230');
    expect(project.scenes[0].transitionIn, MotionTransitionKind.hardCut);
    expect(
      project.scenes[1].transitionIn,
      plan.story.beats[0].transitionToNext,
    );
  });

  test('an invalid range or an empty story throws', () {
    final plan = StoryWorldBridge.plan(segments);
    expect(
      () => StoryWorldBridge.layersOf(plan.world.scenes.first,
          start: 2, end: 2),
      throwsArgumentError,
    );
    final empty = StoryWorldBridge.plan(const <StorySegment>[]);
    expect(
      () => StoryWorldBridge.projectFor(empty, id: 'p', width: 10, height: 10),
      throwsStateError,
    );
  });
}
