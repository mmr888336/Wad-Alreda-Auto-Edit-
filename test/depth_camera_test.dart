import 'package:auto_edit/depth_camera_engine.dart';
import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/depth_camera_planner.dart';
import 'package:auto_edit/motion_ffmpeg_adapter.dart';
import 'package:auto_edit/motion_graphics.dart';
import 'package:auto_edit/motion_scene_editing.dart';
import 'package:auto_edit/motion_scene_json.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/reference_scene_builder.dart';
import 'package:flutter_test/flutter_test.dart';

int _count(String text, String char) => char.allMatches(text).length;

ReferenceSceneResult _built(double end, {String id = 'cam'}) {
  return ReferenceSceneBuilder.buildCutaway(
    id: id,
    spec: CutawaySpec(start: 5, end: end, text: 'سر البركة والخير في حياة الناس'),
    width: 720,
    height: 1280,
    mood: MotionMood.dynamic,
  );
}

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
  group('DepthCameraEngine', () {
    test('push in grows near layers more than far layers', () {
      const camera = SceneCamera(move: DepthCameraMove.pushIn, intensity: 1);
      final near =
          DepthCameraEngine.sample(camera: camera, depth: 1, progress: 1);
      final far =
          DepthCameraEngine.sample(camera: camera, depth: 0, progress: 1);
      expect(near.zoom, greaterThan(far.zoom));
      expect(far.zoom, greaterThan(1.0));
      final start =
          DepthCameraEngine.sample(camera: camera, depth: 1, progress: 0);
      expect(start.zoom, closeTo(1.0, 1e-9));
    });

    test('orbit sweeps near and far layers in opposite directions', () {
      const camera = SceneCamera(move: DepthCameraMove.orbitRight, intensity: 1);
      final near =
          DepthCameraEngine.sample(camera: camera, depth: 1, progress: 1);
      final far =
          DepthCameraEngine.sample(camera: camera, depth: 0, progress: 1);
      expect(near.dx, greaterThan(0));
      expect(far.dx, lessThan(0));
    });

    test('dolly zoom changes the perspective between far and near', () {
      const camera = SceneCamera(move: DepthCameraMove.dollyZoom, intensity: 1);
      final near =
          DepthCameraEngine.sample(camera: camera, depth: 1, progress: 1);
      final far =
          DepthCameraEngine.sample(camera: camera, depth: 0, progress: 1);
      expect(far.scaleMul, greaterThan(1.0));
      expect(near.scaleMul, lessThan(1.0));
    });

    test('an inactive camera leaves the layer untouched', () {
      const camera = SceneCamera(move: DepthCameraMove.none);
      expect(camera.isActive, isFalse);
      expect(
        const SceneCamera(move: DepthCameraMove.pushIn, intensity: 0).isActive,
        isFalse,
      );
    });

    test('depthOf follows the asset key, the stacking order and overrides', () {
      const layers = <MotionLayer>[
        MotionLayer(id: 'bg', start: 0, end: 2, assetKey: 'bg:s'),
        MotionLayer(id: 'sp', start: 0, end: 2, assetKey: 'sprite:s', zIndex: 10),
        MotionLayer(id: 'w', start: 0, end: 2, assetKey: 'text:w', zIndex: 20),
        MotionLayer(
          id: 'fixed',
          start: 0,
          end: 2,
          assetKey: 'text:f',
          zIndex: 21,
          depth: 0.9,
        ),
      ];
      const scene = MotionScene(id: 's', start: 0, end: 2, layers: layers);
      expect(DepthCameraEngine.depthOf(scene, layers[0]), 0.0);
      expect(DepthCameraEngine.depthOf(scene, layers[1]), lessThan(0.8));
      expect(DepthCameraEngine.depthOf(scene, layers[2]), greaterThanOrEqualTo(0.8));
      expect(DepthCameraEngine.depthOf(scene, layers[3]), 0.9);
    });

    test('coverScale keeps a background large enough but bounded', () {
      for (final move in DepthCameraMove.values) {
        final scale = DepthCameraEngine.coverScale(
          SceneCamera(move: move, intensity: 1),
          0,
        );
        expect(scale, inInclusiveRange(1.0, DepthCameraEngine.maxCoverScale));
      }
    });

    test('expressions are balanced and use the scene clock', () {
      final e = DepthCameraEngine.expressions(
        camera: const SceneCamera(move: DepthCameraMove.spiralIn),
        depth: 0.6,
        duration: 2.0,
        xExpr: '0.5',
        yExpr: '0.3',
        scaleExpr: '1.0',
      );
      for (final text in <String>[e.x, e.y, e.scale]) {
        expect(_count(text, '('), _count(text, ')'));
        expect(text, contains('cos(PI*'));
      }
    });
  });

  group('DepthCameraPlanner', () {
    test('follow never repeats the same move', () {
      for (final move in DepthCameraMove.values) {
        expect(DepthCameraPlanner.follow(move), isNot(move));
      }
    });

    test('consecutive scenes get different, active cameras', () {
      final original = _built(7.6);
      final upgraded = DepthCameraPlanner.upgrade(
        original,
        mood: MotionMood.cinematic,
      );
      final scenes = upgraded.project.scenes;
      expect(scenes.length, 2);
      expect(scenes[0].camera, isNotNull);
      expect(scenes[1].camera, isNotNull);
      expect(scenes[0].camera!.isActive, isTrue);
      expect(scenes[0].camera!.move, isNot(scenes[1].camera!.move));
      // The input is left untouched.
      expect(original.project.scenes[0].camera, isNull);
      upgraded.project.validate();
    });

    test('scenes that already have a camera keep it', () {
      final original = _built(7.6);
      const mine = SceneCamera(move: DepthCameraMove.riseUp, intensity: 0.5);
      final first = original.project.scenes.first.withCamera(mine);
      final custom = ReferenceSceneResult(
        project: MotionProject(
          id: original.project.id,
          width: original.project.width,
          height: original.project.height,
          frameRate: original.project.frameRate,
          duration: original.project.duration,
          scenes: <MotionScene>[first, ...original.project.scenes.skip(1)],
        ),
        assets: original.assets,
      );
      final upgraded =
          DepthCameraPlanner.upgrade(custom, mood: MotionMood.calm);
      expect(upgraded.project.scenes.first.camera!.move, DepthCameraMove.riseUp);
      expect(upgraded.project.scenes[1].camera!.move, DepthCameraMove.sinkDown);
    });
  });

  group('adapter with depth camera', () {
    test('a scene camera adds depth-aware expressions, flat mode does not', () {
      final base = ReferenceSceneBuilder.buildCutaway(
        id: 'cam1',
        spec: const CutawaySpec(start: 5, end: 7, text: 'نتحدث عن المال'),
        width: 720,
        height: 1280,
      );
      final withCamera = DepthCameraPlanner.upgrade(
        base,
        mood: MotionMood.cinematic,
      );
      final assets = _assetsFor(withCamera);

      final plan = MotionFfmpegAdapter.build(
        project: withCamera.project,
        assets: assets,
      );
      expect(plan.skippedLayerIds, isEmpty);
      expect(plan.filterComplex, contains('cos(PI*'));
      expect(_count(plan.filterComplex, '('), _count(plan.filterComplex, ')'));

      final flat = MotionFfmpegAdapter.build(
        project: withCamera.project,
        assets: assets,
        depthCamera: false,
      );
      expect(flat.filterComplex, isNot(contains('cos(PI*')));
      expect(flat.totalDuration, closeTo(plan.totalDuration, 1e-6));
    });

    test('a project without cameras renders exactly as before', () {
      final base = ReferenceSceneBuilder.buildCutaway(
        id: 'cam2',
        spec: const CutawaySpec(start: 5, end: 7, text: 'نتحدث عن المال'),
        width: 720,
        height: 1280,
      );
      final assets = _assetsFor(base);
      final a = MotionFfmpegAdapter.build(project: base.project, assets: assets);
      final b = MotionFfmpegAdapter.build(
        project: base.project,
        assets: assets,
        depthCamera: false,
      );
      expect(a.filterComplex, b.filterComplex);
    });
  });

  group('MotionSceneEditing camera and depth', () {
    MotionSceneDocument doc() {
      final built = _built(7.6, id: 'ed');
      return MotionSceneDocument(
        project: built.project,
        assets: built.assets,
        fontFamily: 'Roboto',
      );
    }

    test('withCamera sets, replaces and removes the camera of one scene', () {
      final d = doc();
      final sceneId = d.project.scenes.first.id;
      final set = MotionSceneEditing.withCamera(
        d,
        sceneId,
        const SceneCamera(move: DepthCameraMove.orbitLeft),
      );
      expect(set.project.scenes.first.camera!.move, DepthCameraMove.orbitLeft);
      expect(set.project.scenes[1].camera, isNull);

      final cleared = MotionSceneEditing.withCamera(
        set,
        sceneId,
        const SceneCamera(move: DepthCameraMove.none),
      );
      expect(cleared.project.scenes.first.camera, isNull);
    });

    test('camera survives layer edits', () {
      final d = MotionSceneEditing.withCamera(
        doc(),
        'ed_s0',
        const SceneCamera(move: DepthCameraMove.pushIn),
      );
      final layerId = d.project.scenes.first.layers
          .firstWhere((l) => l.assetKey == 'sprite:ed_s0')
          .id;
      final edited = MotionSceneEditing.updateLayer(
        d,
        layerId,
        (scene, layer) => MotionSceneEditing.scaledBy(layer, 1.1),
      );
      expect(edited.project.scenes.first.camera!.move, DepthCameraMove.pushIn);
    });

    test('withDepth clamps, and null returns the layer to automatic', () {
      final d = doc();
      final layerId = d.project.scenes.first.layers
          .firstWhere((l) => l.assetKey == 'sprite:ed_s0')
          .id;
      MotionLayer find(MotionSceneDocument x) => x.project.scenes.first.layers
          .firstWhere((l) => l.id == layerId);

      final far = MotionSceneEditing.withDepth(d, layerId, 3.0);
      expect(find(far).depth, 1.0);
      final mid = MotionSceneEditing.withDepth(d, layerId, 0.25);
      expect(find(mid).depth, 0.25);
      final auto = MotionSceneEditing.withDepth(mid, layerId, null);
      expect(find(auto).depth, isNull);
    });
  });
}
