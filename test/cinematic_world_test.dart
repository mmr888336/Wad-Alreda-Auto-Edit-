import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:flutter_test/flutter_test.dart';

StoryPlan _story() {
  return StoryUnderstanding.plan(const <StorySegment>[
    StorySegment(text: 'الفلوس مهمة', start: 0, end: 3),
    StorySegment(text: 'البركة والخير', start: 3, end: 6),
    StorySegment(text: 'والتجارة كمان', start: 6, end: 9),
  ]);
}

void main() {
  test('no slot of any environment covers the speaker face', () {
    for (final layout in CinematicWorld.layouts.values) {
      for (final slot in layout.slots) {
        expect(CinematicWorld.coversFace(slot), isFalse);
      }
    }
  });

  test('every environment has a layout', () {
    for (final environment in StoryEnvironment.values) {
      expect(CinematicWorld.layouts.containsKey(environment), isTrue);
    }
  });

  test('the same character stands in every scene', () {
    final world = CinematicWorld.plan(_story());
    expect(world.scenes.length, 3);
    for (final scene in world.scenes) {
      final heroes =
          scene.layers.where((l) => l.assetKey == world.character.assetKey);
      expect(heroes.length, 1);
      expect(heroes.first.x, world.character.x);
      expect(heroes.first.y, world.character.y);
      expect(heroes.first.scale, world.character.scale);
    }
  });

  test('coming back to an environment rebuilds the same set', () {
    final world = CinematicWorld.plan(_story());
    List<String> setKeys(WorldScene scene) => <String>[
          for (final layer in scene.layers)
            if (layer.id.contains('_set') || layer.id.contains('_backdrop'))
              '${layer.assetKey}@${layer.x},${layer.y},${layer.scale},${layer.depth}',
        ];
    expect(world.scenes[0].environment, world.scenes[2].environment);
    expect(setKeys(world.scenes[0]), setKeys(world.scenes[2]));
    expect(world.scenes[1].continuesPreviousScene, isFalse);
    expect(world.scenes[2].continuesPreviousScene, isFalse);
  });

  test('same environment in a row is marked as continuing', () {
    final story = StoryUnderstanding.plan(const <StorySegment>[
      StorySegment(text: 'الفلوس مهمة', start: 0, end: 3),
      StorySegment(text: 'والتجارة كمان', start: 3, end: 6),
    ]);
    final world = CinematicWorld.plan(story);
    expect(world.scenes[0].continuesPreviousScene, isFalse);
    expect(world.scenes[1].continuesPreviousScene, isTrue);
  });

  test('props in front of the speaker are drawn above it', () {
    final world = CinematicWorld.plan(_story());
    for (final scene in world.scenes) {
      for (final layer in scene.layers) {
        if (!layer.id.contains('_prop')) continue;
        if (layer.depth > WorldCharacter.depth) {
          expect(layer.zIndex, greaterThan(20));
        } else {
          expect(layer.zIndex, lessThan(20));
        }
      }
    }
  });

  test('one palette, mood only changes the intensity and tint', () {
    final world = CinematicWorld.plan(_story());
    for (final scene in world.scenes) {
      expect(scene.look.keyAngleDegrees, world.scenes.first.look.keyAngleDegrees);
      expect(scene.look.shadowOpacity, world.scenes.first.look.shadowOpacity);
      expect(
        <String>[world.palette.red, world.palette.amber, world.palette.teal],
        contains(scene.look.tint),
      );
    }
  });
}
