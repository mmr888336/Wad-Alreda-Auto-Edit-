import 'package:auto_edit/continuous_scene_generator.dart';
import 'package:auto_edit/motion_ffmpeg_adapter.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/motion_transitions.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:flutter_test/flutter_test.dart';

int _count(String text, String char) => char.allMatches(text).length;

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
  group('SceneCompositionPlanner.classify', () {
    test('reads the character of a sentence', () {
      expect(
        SceneCompositionPlanner.classify('كيف تنجح في حياتك؟'),
        SentenceKind.question,
      );
      expect(
        SceneCompositionPlanner.classify('Why does it work'),
        SentenceKind.question,
      );
      expect(
        SceneCompositionPlanner.classify('ربحت 500 دولار'),
        SentenceKind.number,
      );
      expect(
        SceneCompositionPlanner.classify('هذا رائع جدا!'),
        SentenceKind.exclaim,
      );
      expect(
        SceneCompositionPlanner.classify('الصبر، والعمل، والأمل'),
        SentenceKind.list,
      );
      expect(SceneCompositionPlanner.classify('المال'), SentenceKind.short);
      expect(
        SceneCompositionPlanner.classify(
          'هذا الكلام مهم جدا لكل واحد منا في هذه الحياة',
        ),
        SentenceKind.long,
      );
      expect(SceneCompositionPlanner.classify('   '), SentenceKind.plain);
    });
  });

  group('SceneCompositionPlanner.pick', () {
    test('never repeats the previous layout, for every kind and variant', () {
      for (final kind in SentenceKind.values) {
        for (var variant = 0; variant < 8; variant++) {
          SceneLayout? previous;
          SceneLayout? before;
          for (var i = 0; i < 12; i++) {
            final layout = SceneCompositionPlanner.pick(
              kind: kind,
              sceneIndex: i,
              variant: variant,
              previous: previous,
              beforePrevious: before,
            );
            expect(layout, isNot(previous));
            before = previous;
            previous = layout;
          }
        }
      }
    });

    test('a plain sentence walks through many different layouts', () {
      final seen = <SceneLayout>{};
      SceneLayout? previous;
      SceneLayout? before;
      for (var i = 0; i < 6; i++) {
        final layout = SceneCompositionPlanner.pick(
          kind: SentenceKind.plain,
          sceneIndex: i,
          previous: previous,
          beforePrevious: before,
        );
        seen.add(layout);
        before = previous;
        previous = layout;
      }
      expect(seen.length, greaterThanOrEqualTo(4));
    });

    test('every layout keeps its words inside the safe area', () {
      for (final layout in SceneLayout.values) {
        final c = SceneComposition.of(layout);
        expect(c.layout, layout);
        expect(c.wordX, inInclusiveRange(0.3, 0.7));
        expect(c.wordX + 2 * c.wordStepX, inInclusiveRange(0.3, 0.7));
        expect(c.spriteX, inInclusiveRange(0.2, 0.8));
        expect(c.spriteY, inInclusiveRange(0.1, 0.7));
      }
    });
  });

  group('ContinuousSceneGenerator', () {
    test('a 6 second phrase becomes several scenes with changing layouts', () {
      final plan = ContinuousSceneGenerator.build(
        id: 'g1',
        spec: const CutawaySpec(start: 5, end: 11, text: _sixWords),
        width: 720,
        height: 1280,
        mood: MotionMood.dynamic,
      );
      plan.result.project.validate();
      final scenes = plan.result.project.scenes;
      expect(scenes.length, greaterThanOrEqualTo(3));
      expect(plan.layouts.length, scenes.length);
      for (var i = 1; i < plan.layouts.length; i++) {
        expect(plan.layouts[i], isNot(plan.layouts[i - 1]));
      }
      expect(plan.layouts.toSet().length, greaterThanOrEqualTo(3));
      expect(scenes.first.transitionIn, MotionTransitionKind.hardCut);
      for (var i = 1; i < scenes.length; i++) {
        expect(scenes[i].transitionIn, isNot(MotionTransitionKind.hardCut));
      }
    });

    test('the plan renders every layer and keeps the requested length', () {
      final plan = ContinuousSceneGenerator.build(
        id: 'g2',
        spec: const CutawaySpec(start: 5, end: 11, text: _sixWords),
        width: 720,
        height: 1280,
      );
      final built = MotionFfmpegAdapter.build(
        project: plan.result.project,
        assets: _assetsFor(plan.result),
      );
      expect(built.skippedLayerIds, isEmpty);
      expect(_count(built.filterComplex, '('), _count(built.filterComplex, ')'));
      expect(built.totalDuration, closeTo(6.0, 0.2));
    });

    test('a short phrase stays one scene', () {
      final plan = ContinuousSceneGenerator.build(
        id: 'g3',
        spec: const CutawaySpec(start: 5, end: 7, text: 'نتحدث عن المال'),
        width: 720,
        height: 1280,
      );
      plan.result.project.validate();
      expect(plan.result.project.scenes.length, 1);
      final sprite = plan.result.project.scenes.first.layers
          .firstWhere((l) => l.id.endsWith('_sprite'));
      expect(sprite.keyframes.any((k) => k.rotation != 0), isTrue);
    });

    test('all words of the phrase are kept', () {
      final plan = ContinuousSceneGenerator.build(
        id: 'g4',
        spec: const CutawaySpec(start: 5, end: 11, text: _sixWords),
        width: 720,
        height: 1280,
      );
      final shown = <String>{
        for (final scene in plan.result.project.scenes)
          for (final layer in scene.layers)
            if (layer.text != null) layer.text!,
      };
      for (final word in ReferenceSceneBuilder.wordsOf(_sixWords)) {
        expect(shown, contains(word));
      }
    });

    test('the first scene differs from the previous cutaway', () {
      for (final layout in SceneLayout.values) {
        final plan = ContinuousSceneGenerator.build(
          id: 'g5',
          spec: const CutawaySpec(start: 5, end: 8, text: _sixWords),
          width: 720,
          height: 1280,
          previousLayout: layout,
        );
        expect(plan.layouts.first, isNot(layout));
      }
    });

    test('tryBuild returns null for a cutaway that is too short', () {
      expect(
        ContinuousSceneGenerator.tryBuild(
          id: 'x',
          spec: const CutawaySpec(start: 1, end: 1.5, text: 'قصير'),
          width: 720,
          height: 1280,
        ),
        isNull,
      );
    });
  });
}
