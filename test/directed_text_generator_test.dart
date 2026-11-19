import 'package:auto_edit/continuous_scene_generator.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sixWords = 'سر البركة والخير في حياة الناس';

List<String> _shownWords(ContinuousScenePlan plan) {
  return <String>[
    for (final scene in plan.result.project.scenes)
      for (final layer in scene.layers)
        if (layer.text != null) layer.text!,
  ];
}

void main() {
  group('ContinuousSceneGenerator with directed text', () {
    test('the impact word is the idea of the sentence, not the longest word',
        () {
      final plan = ContinuousSceneGenerator.build(
        id: 'd1',
        spec: const CutawaySpec(
          start: 5,
          end: 7,
          text: 'مال والتفاصيل',
        ),
        width: 720,
        height: 1280,
      );
      plan.result.project.validate();
      expect(_shownWords(plan), <String>['مال']);
      final layer = plan.result.project.scenes.first.layers
          .firstWhere((l) => l.text != null);
      expect(plan.result.assets[layer.assetKey]!.text, 'مال');
    });

    test('words come from the phrase and never repeat from scene to scene',
        () {
      final plan = ContinuousSceneGenerator.build(
        id: 'd2',
        spec: const CutawaySpec(start: 5, end: 11, text: _sixWords),
        width: 720,
        height: 1280,
      );
      final phrase = ReferenceSceneBuilder.wordsOf(_sixWords).toSet();
      final shown = _shownWords(plan);
      expect(shown, isNotEmpty);
      for (final word in shown) {
        expect(phrase, contains(word));
      }
      for (var i = 1; i < shown.length; i++) {
        expect(shown[i], isNot(shown[i - 1]));
      }
    });

    test('the switch brings back the scene builder words', () {
      ContinuousSceneGenerator.directedTextEnabled = false;
      try {
        final plan = ContinuousSceneGenerator.build(
          id: 'd3',
          spec: const CutawaySpec(
            start: 5,
            end: 7,
            text: 'مال والتفاصيل',
          ),
          width: 720,
          height: 1280,
        );
        expect(_shownWords(plan), isNot(<String>['مال']));
      } finally {
        ContinuousSceneGenerator.directedTextEnabled = true;
      }
    });
  });
}
