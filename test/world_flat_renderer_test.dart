import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/render_router.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/story_world_bridge.dart';
import 'package:auto_edit/world_flat_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plan = StoryWorldBridge.plan(<StorySegment>[
    StorySegment(text: 'الفلوس مهمة', start: 0, end: 3),
  ]);
  final world = plan.worldSceneOf(0)!;
  final motion = StoryWorldBridge.sceneFor(world, start: 4, end: 7);

  group('WorldFlatRenderer.build', () {
    test('a whole scene keeps every drawable layer on the environment colour',
        () {
      final built = WorldFlatRenderer.build(
        world: world,
        motion: motion,
        routing: RenderRouter.fallbackOf(motion, 'test'),
        wholeScene: true,
        width: 540,
        height: 960,
        idPrefix: 't',
      );

      expect(built, isNotNull);
      final scene = built!.project.scenes.single;
      final rendering = StoryWorldBridge.renderingOf(
        world,
        idPrefix: 't',
        start: 0,
        end: motion.duration,
      );

      expect(scene.start, 0);
      expect(scene.end, closeTo(3, 1e-9));
      expect(scene.background, rendering.background);
      expect(scene.layers.length, rendering.layers.length);
      expect(built.project.width, 540);
      expect(built.project.height, 960);
      built.project.validate();

      for (final layer in scene.layers) {
        expect(built.assets.containsKey(layer.assetKey), isTrue);
      }
    });

    test('the flat part keeps only the flat layers on black', () {
      final hero =
          motion.layers.singleWhere((layer) => layer.assetKey == 'sprite:hero');
      final routing = SceneRouting(
        sceneId: motion.id,
        world: <MotionLayer>[
          for (final layer in motion.layers)
            if (layer != hero) layer,
        ],
        flat: <MotionLayer>[hero],
        fallback: false,
      );

      final built = WorldFlatRenderer.build(
        world: world,
        motion: motion,
        routing: routing,
        wholeScene: false,
        width: 540,
        height: 960,
        idPrefix: 't',
      );

      expect(built, isNotNull);
      final scene = built!.project.scenes.single;

      expect(scene.background, '#000000');
      expect(
        scene.layers.map((layer) => layer.assetKey).toList(),
        equals(<String?>['sprite:hero']),
      );
      expect(built.assets.keys.toList(), equals(<String>['sprite:hero']));
      built.project.validate();
    });

    test('no flat layers means no 2.5D clip', () {
      final built = WorldFlatRenderer.build(
        world: world,
        motion: motion,
        routing: RenderRouter.route(motion),
        wholeScene: false,
        width: 540,
        height: 960,
        idPrefix: 't',
      );

      expect(built, isNull);
    });
  });

  test('evenSize gives an even size of at least 2', () {
    expect(WorldFlatRenderer.evenSize(539.4), 540);
    expect(WorldFlatRenderer.evenSize(720), 720);
    expect(WorldFlatRenderer.evenSize(0.2), 2);
  });
}
