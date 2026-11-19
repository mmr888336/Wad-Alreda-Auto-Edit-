import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:auto_edit/scene_richness_guard.dart';
import 'package:flutter_test/flutter_test.dart';

ReferenceSceneResult _thin() {
  const scene = MotionScene(
    id: 's0',
    start: 0,
    end: 2,
    layers: <MotionLayer>[
      MotionLayer(id: 's0_bg', start: 0, end: 2, assetKey: 'bg:s0'),
      MotionLayer(id: 's0_w0', start: 0, end: 2, assetKey: 'w:s0', text: 'بنقول'),
    ],
  );
  return const ReferenceSceneResult(
    project: MotionProject(
      id: 't',
      width: 720,
      height: 1280,
      frameRate: 30,
      duration: 2,
      scenes: <MotionScene>[scene],
    ),
    assets: <String, SceneAssetSpec>{
      'bg:s0': SceneAssetSpec(kind: SceneAssetKind.background),
      'w:s0': SceneAssetSpec(kind: SceneAssetKind.word, text: 'بنقول'),
    },
  );
}

void main() {
  test('thin scene gets a ghost word and two overlays', () {
    final out = SceneRichnessGuard.enrich(_thin());
    final scene = out.project.scenes.single;
    final r = SceneRichnessGuard.measure(scene, out.assets);
    expect(r.overlays, 2);
    expect(scene.layers.any((l) => l.id.endsWith('_ghost')), isTrue);
  });

  test('enrich is idempotent', () {
    final once = SceneRichnessGuard.enrich(_thin());
    final twice = SceneRichnessGuard.enrich(once);
    expect(twice.project.scenes.single.layers.length,
        once.project.scenes.single.layers.length);
  });

  test('switched off returns the same object', () {
    final built = _thin();
    SceneRichnessGuard.enabled = false;
    expect(identical(SceneRichnessGuard.enrich(built), built), isTrue);
    SceneRichnessGuard.enabled = true;
  });
}
