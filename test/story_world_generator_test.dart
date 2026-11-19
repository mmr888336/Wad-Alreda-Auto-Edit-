import 'package:auto_edit/continuous_scene_generator.dart';
import 'package:auto_edit/motion_ffmpeg_adapter.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/story_world_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sixWords = 'سر البركة والخير في حياة الناس';

Map<String, MotionRenderAsset> _assetsFor(ReferenceSceneResult result) {
  return <String, MotionRenderAsset>{
    for (final entry in result.assets.entries)
      entry.key: MotionRenderAsset(
        path: '/tmp/${entry.key.replaceAll(':', '_')}.png',
        aspect: entry.value.kind == SceneAssetKind.word ? 0.2 : 1.0,
        widthFraction: entry.value.widthFraction,
      ),
  };
}

void main() {
  group('StoryWorldBridge.renderingOf', () {
    test('keeps the backdrop, set pieces, character and props with art', () {
      final plan = StoryWorldBridge.plan(const <StorySegment>[
        StorySegment(text: 'الفلوس مهمة', start: 0, end: 3),
      ]);
      final rendering = StoryWorldBridge.renderingOf(
        plan.world.scenes.first,
        idPrefix: 's0',
        start: 0,
        end: 3,
      );
      expect(rendering.background, '#1E2230');
      final ids = rendering.layers.map((l) => l.id).toList();
      expect(ids, contains('s0_w0_backdrop'));
      expect(ids, contains('s0_w0_hero'));
      expect(
        ids,
        containsAll(<String>['s0_w0_set0', 's0_w0_set1', 's0_w0_set2']),
      );
      for (final layer in rendering.layers) {
        expect(rendering.assets.containsKey(layer.assetKey), isTrue);
        expect(layer.start, 0);
        expect(layer.end, 3);
      }
      final hero = rendering.layers.singleWhere((l) => l.id == 's0_w0_hero');
      expect(
        rendering.assets[hero.assetKey]!.spriteKey,
        ReferenceSceneBuilder.mascotSprite,
      );
      expect(
        rendering.assets['bg:office']!.kind,
        SceneAssetKind.background,
      );
      expect(rendering.assets['decor:desk']!.spriteKey, 'set:desk');
      final desk = rendering.layers.singleWhere((l) => l.id == 's0_w0_set0');
      expect(desk.zIndex, StoryWorldBridge.setPieceZ);
      expect(desk.scale, 1.0);
      expect(
        rendering.assets.values.any(
          (a) =>
              a.kind == SceneAssetKind.visual &&
              !(a.spriteKey ?? '').startsWith('set:'),
        ),
        isTrue,
      );
    });

    test('an invalid range throws', () {
      final plan = StoryWorldBridge.plan(const <StorySegment>[
        StorySegment(text: 'الفلوس مهمة', start: 0, end: 3),
      ]);
      expect(
        () => StoryWorldBridge.renderingOf(
          plan.world.scenes.first,
          idPrefix: 's0',
          start: 2,
          end: 2,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ContinuousSceneGenerator with the story world', () {
    test('the same character is in every scene and every layer has art', () {
      final plan = ContinuousSceneGenerator.build(
        id: 'w1',
        spec: const CutawaySpec(start: 5, end: 11, text: _sixWords),
        width: 720,
        height: 1280,
      );
      plan.result.project.validate();
      expect(plan.world, isNotNull);
      final scenes = plan.result.project.scenes;
      for (final scene in scenes) {
        final heroes =
            scene.layers.where((l) => l.id.endsWith('_hero')).toList();
        expect(heroes.length, 1);
        expect(heroes.first.assetKey, 'sprite:hero');
        expect(heroes.first.x, 0.5);
        expect(heroes.first.y, 0.62);
        expect(heroes.first.scale, 0.42);
        expect(scene.layers.any((l) => l.id.endsWith('_decor')), isFalse);
        expect(scene.layers.any((l) => l.id.contains('_set')), isTrue);
        for (final layer in scene.layers) {
          if (!layer.id.endsWith('_sprite')) continue;
          final spec = plan.result.assets[layer.assetKey];
          expect(spec?.spriteKey, isNot(ReferenceSceneBuilder.mascotSprite));
        }
      }
      final built = MotionFfmpegAdapter.build(
        project: plan.result.project,
        assets: _assetsFor(plan.result),
      );
      expect(built.skippedLayerIds, isEmpty);
    });

    test('the world can be switched off', () {
      ContinuousSceneGenerator.worldEnabled = false;
      try {
        final plan = ContinuousSceneGenerator.build(
          id: 'w2',
          spec: const CutawaySpec(start: 5, end: 11, text: _sixWords),
          width: 720,
          height: 1280,
        );
        expect(plan.world, isNull);
        for (final scene in plan.result.project.scenes) {
          expect(scene.layers.any((l) => l.id.endsWith('_hero')), isFalse);
        }
      } finally {
        ContinuousSceneGenerator.worldEnabled = true;
      }
    });
  });
}
