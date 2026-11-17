import 'package:auto_edit/keyword_callout_planner.dart';
import 'package:auto_edit/motion_ffmpeg_adapter.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:flutter_test/flutter_test.dart';

int _count(String text, String char) => char.allMatches(text).length;

void main() {
  group('spriteKeyFor', () {
    test('matches the meaning of Arabic words', () {
      expect(
        ReferenceSceneBuilder.spriteKeyFor('المال والرزق'),
        'pixel_gold_coin',
      );
      expect(
        ReferenceSceneBuilder.spriteKeyFor('رحمة وقلب'),
        'pixel_red_heart',
      );
      expect(
        ReferenceSceneBuilder.spriteKeyFor('تصوير الفيديو'),
        'pixel_camera',
      );
    });

    test('matches English words and returns null for unknown text', () {
      expect(ReferenceSceneBuilder.spriteKeyFor('Play the game'),
          'pixel_game_controller');
      expect(ReferenceSceneBuilder.spriteKeyFor('xyz qwerty'), isNull);
    });
  });

  group('planCutaways', () {
    const captions = <CalloutSource>[
      CalloutSource(start: 1.0, end: 3.0, text: 'مقدمة الحلقة اليوم'),
      CalloutSource(start: 5.0, end: 7.0, text: 'نتحدث عن المال والرزق'),
      CalloutSource(start: 8.0, end: 10.0, text: 'بعد ذلك نكمل الكلام'),
      CalloutSource(start: 14.0, end: 16.0, text: 'سر البركة والخير'),
      CalloutSource(start: 22.0, end: 24.0, text: 'الخلاصة والنتيجة'),
    ];

    test('respects the hook window, spacing and the maximum count', () {
      final specs = ReferenceSceneBuilder.planCutaways(
        captions: captions,
        duration: 30,
        maxCount: 2,
      );
      expect(specs.length, lessThanOrEqualTo(2));
      expect(specs, isNotEmpty);
      for (final spec in specs) {
        expect(spec.start, greaterThanOrEqualTo(3.6));
        expect(spec.duration, greaterThanOrEqualTo(1.2));
        expect(spec.duration, lessThanOrEqualTo(2.6));
      }
      for (var i = 1; i < specs.length; i++) {
        expect(specs[i].start - specs[i - 1].start, greaterThanOrEqualTo(7.0));
      }
    });

    test('skips ranges to avoid and very short videos', () {
      final specs = ReferenceSceneBuilder.planCutaways(
        captions: captions,
        duration: 30,
        maxCount: 3,
        avoid: const <List<double>>[
          <double>[4.0, 11.0],
        ],
      );
      for (final spec in specs) {
        expect(spec.start >= 11.0 || spec.end <= 4.0, isTrue);
      }
      expect(
        ReferenceSceneBuilder.planCutaways(captions: captions, duration: 5),
        isEmpty,
      );
    });
  });

  group('buildCutaway', () {
    test('short cutaway is one valid scene with layered composition', () {
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut0',
        spec: const CutawaySpec(start: 5, end: 7, text: 'نتحدث عن المال'),
        width: 720,
        height: 1280,
      );
      result.project.validate();
      expect(result.project.scenes.length, 1);
      final layers = result.project.scenes.first.layers;
      expect(layers.where((l) => l.zIndex == 0).length, 1);
      expect(layers.any((l) => l.assetKey == 'sprite:cut0_s0'), isTrue);
      expect(layers.where((l) => l.text != null).length, greaterThan(0));
      expect(
        result.assets['sprite:cut0_s0']!.spriteKey,
        'pixel_gold_coin',
      );
      // Rotation is animated on the sprite.
      final sprite = layers.firstWhere((l) => l.id == 'cut0_s0_sprite');
      expect(sprite.keyframes.any((k) => k.rotation != 0), isTrue);
    });

    test('long cutaway becomes two scenes joined by a transition', () {
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
      expect(result.project.scenes.length, 2);
      expect(
        result.project.scenes[1].transitionIn,
        isNot(MotionTransitionKindProbe.hardCut),
      );
    });

    test('rejects cutaways that are too short', () {
      expect(
        () => ReferenceSceneBuilder.buildCutaway(
          id: 'x',
          spec: const CutawaySpec(start: 1, end: 1.5, text: 'قصير'),
          width: 720,
          height: 1280,
        ),
        throwsStateError,
      );
    });

    test('the adapter renders every layer of the built project', () {
      final result = ReferenceSceneBuilder.buildCutaway(
        id: 'cut2',
        spec: const CutawaySpec(
          start: 5,
          end: 7.6,
          text: 'سر البركة والخير في حياة الناس',
        ),
        width: 720,
        height: 1280,
      );
      final assets = <String, MotionRenderAsset>{
        for (final entry in result.assets.entries)
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
      expect(plan.filterComplex, contains('rotate=a='));
      expect(plan.filterComplex, contains('xfade='));
      expect(_count(plan.filterComplex, '('), _count(plan.filterComplex, ')'));
      expect(plan.totalDuration, closeTo(2.6, 0.05));
    });
  });
}

/// Local alias so the test reads clearly without another import line.
class MotionTransitionKindProbe {
  static const hardCut = MotionTransitionKind.hardCut;
}
