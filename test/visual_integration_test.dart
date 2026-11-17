import 'package:auto_edit/motion_ffmpeg_adapter.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:auto_edit/motion_scene_json.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:flutter_test/flutter_test.dart';

int _count(String text, String char) => char.allMatches(text).length;

void main() {
  tearDown(() {
    ReferenceSceneBuilder.visualLibraryEnabled = true;
    ReferenceSceneBuilder.vfxEnabled = true;
  });

  const bookSpec = CutawaySpec(
    start: 5,
    end: 7,
    text: 'الطالب يقرأ كتاباً في الجامعة',
  );

  group('visual library in the scene builder', () {
    test('uses a library asset when no pixel sprite fits the words', () {
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut0',
        spec: bookSpec,
        width: 720,
        height: 1280,
      );
      result.project.validate();
      final sprite = result.assets['sprite:cut0_s0']!;
      expect(sprite.kind, SceneAssetKind.visual);
      expect(sprite.spriteKey, anyOf('book', 'graduation'));
    });

    test('a matching pixel sprite keeps priority', () {
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut0',
        spec: const CutawaySpec(start: 5, end: 7, text: 'نتحدث عن المال'),
        width: 720,
        height: 1280,
      );
      final sprite = result.assets['sprite:cut0_s0']!;
      expect(sprite.kind, SceneAssetKind.sprite);
      expect(sprite.spriteKey, 'pixel_gold_coin');
    });

    test('the library can be switched off', () {
      ReferenceSceneBuilder.visualLibraryEnabled = false;
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut0',
        spec: bookSpec,
        width: 720,
        height: 1280,
      );
      expect(result.assets['sprite:cut0_s0']!.kind, SceneAssetKind.sprite);
    });
  });

  group('VFX overlays and cinematic look', () {
    test('every scene gets an overlay layer and the clip a look', () {
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut1',
        spec: const CutawaySpec(
          start: 5,
          end: 7.6,
          text: 'سر البركة والخير في حياة الناس',
        ),
        width: 720,
        height: 1280,
        mood: MotionMood.dynamic,
      );
      result.project.validate();
      for (final scene in result.project.scenes) {
        final fx = scene.layers.where((l) => l.id.endsWith('_fx')).toList();
        expect(fx.length, 1);
        expect(fx.first.zIndex, 2);
        expect(result.assets[fx.first.assetKey]!.kind, SceneAssetKind.overlay);
      }
      expect(result.assets['bg:look']!.kind, SceneAssetKind.look);
      expect(result.assets['bg:look']!.spriteKey, 'action');
    });

    test('VFX can be switched off', () {
      ReferenceSceneBuilder.vfxEnabled = false;
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut0',
        spec: bookSpec,
        width: 720,
        height: 1280,
      );
      expect(
        result.assets.values.where(
          (a) =>
              a.kind == SceneAssetKind.overlay || a.kind == SceneAssetKind.look,
        ),
        isEmpty,
      );
    });

    test('the adapter renders every layer of the extended project', () {
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut2',
        spec: bookSpec,
        width: 720,
        height: 1280,
      );
      final assets = <String, MotionRenderAsset>{
        for (final entry in result.assets.entries)
          if (entry.value.kind != SceneAssetKind.look)
            entry.key: MotionRenderAsset(
              path: '/tmp/${entry.key.replaceAll(':', '_')}.png',
              aspect: entry.value.kind == SceneAssetKind.word ? 0.2 : 1.0,
              widthFraction: entry.value.widthFraction,
            ),
      };
      final plan = MotionFfmpegAdapter.build(
        project: result.project,
        assets: assets,
      );
      expect(plan.skippedLayerIds, isEmpty);
      expect(_count(plan.filterComplex, '('), _count(plan.filterComplex, ')'));
    });

    test('new asset kinds survive the editable JSON round trip', () {
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut3',
        spec: bookSpec,
        width: 720,
        height: 1280,
      );
      final decoded = MotionSceneJson.decode(
        MotionSceneJson.encode(
          MotionSceneDocument(
            project: result.project,
            assets: result.assets,
            fontFamily: 'Cairo',
          ),
        ),
      );
      for (final entry in result.assets.entries) {
        final back = decoded.assets[entry.key]!;
        expect(back.kind, entry.value.kind, reason: entry.key);
        expect(back.spriteKey, entry.value.spriteKey, reason: entry.key);
      }
    });
  });
}
