import 'dart:io';

import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/render_router.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/three_d_stage_log.dart';
import 'package:auto_edit/world3d_scene_runner.dart';
import 'package:flutter_test/flutter_test.dart';

const MotionScene _motion = MotionScene(
  id: 'world_s0',
  start: 0,
  end: 3,
  background: '#1E2230',
  layers: <MotionLayer>[
    MotionLayer(id: 'bg', start: 0, end: 3, assetKey: 'bg:office'),
    MotionLayer(
      id: 'desk',
      start: 0,
      end: 3,
      assetKey: 'decor:desk',
      zIndex: 1,
    ),
    MotionLayer(
      id: 'coins',
      start: 0,
      end: 3,
      assetKey: 'decor:coins',
      scale: 0.2,
      zIndex: 10,
    ),
    MotionLayer(
      id: 'hero',
      start: 0,
      end: 3,
      assetKey: 'sprite:hero',
      scale: 0.42,
      zIndex: 20,
    ),
    MotionLayer(
      id: 'title',
      start: 0,
      end: 3,
      assetKey: 'text:title',
      zIndex: 40,
    ),
  ],
);

WorldScene _world() {
  return WorldScene(
    beatIndex: 0,
    environment: StoryEnvironment.office,
    continuesPreviousScene: false,
    look: CinematicWorld.lookFor(
      StoryEnvironment.office,
      StoryMood.calm,
      const WorldPalette(),
    ),
    layers: const <WorldLayerSpec>[
      WorldLayerSpec(
        id: 'bg',
        assetKey: 'bg:office',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.0,
        zIndex: 0,
      ),
      WorldLayerSpec(
        id: 'desk',
        assetKey: 'decor:desk',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.12,
        zIndex: 1,
      ),
      WorldLayerSpec(
        id: 'coins',
        assetKey: 'decor:coins',
        x: 0.2,
        y: 0.74,
        scale: 0.2,
        depth: 0.38,
        zIndex: 10,
      ),
      WorldLayerSpec(
        id: 'hero',
        assetKey: 'sprite:hero',
        x: 0.5,
        y: 0.62,
        scale: 0.42,
        depth: 0.62,
        zIndex: 20,
      ),
    ],
  );
}

List<String> _ids(List<MotionLayer> layers) =>
    <String>[for (final layer in layers) layer.id];

World3DNativeOps _ops(
  List<String> calls,
  String clipPath, {
  String? failAt,
  Future<bool> Function(String clipPath)? verify,
}) {
  Future<void> step(String name) async {
    calls.add(name);
    if (failAt == name) throw StateError('boom $name');
  }

  return World3DNativeOps(
    loadModel: (path) => step('load'),
    setManualCamera: () => step('manual'),
    waitUntilRenderable: () => step('ready'),
    capture: (seconds) async {
      await step('capture');
      return clipPath;
    },
    verifyClip: verify,
  );
}

void main() {
  late Directory temp;
  late String clipPath;

  setUp(() async {
    RenderRouter.enabled = true;
    temp = await Directory.systemTemp.createTemp('runner_test_');
    final clip = File('${temp.path}/clip.mp4')
      ..writeAsBytesSync(List<int>.filled(4096, 1));
    clipPath = clip.path;
  });

  tearDown(() async {
    RenderRouter.enabled = true;
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  Future<World3DSceneResult> runScene(
    World3DNativeOps ops,
    ThreeDExportSummary summary, {
    bool filamentReady = true,
  }) {
    return World3DSceneRunner.run(
      motion: _motion,
      world: _world(),
      sceneNumber: 1,
      ops: ops,
      summary: summary,
      move: DepthCameraMove.pushIn,
      filamentReady: filamentReady,
      settle: Duration.zero,
    );
  }

  test('a good scene passes every stage in order and uses Filament', () async {
    final calls = <String>[];
    final summary = ThreeDExportSummary();
    final started = <ThreeDStage>[];

    final result = await World3DSceneRunner.run(
      motion: _motion,
      world: _world(),
      sceneNumber: 1,
      ops: _ops(calls, clipPath),
      summary: summary,
      move: DepthCameraMove.pushIn,
      settle: Duration.zero,
      onStage: started.add,
    );

    const expected = <ThreeDStage>[
      ThreeDStage.worldPlan,
      ThreeDStage.worldGlb,
      ThreeDStage.inspect,
      ThreeDStage.filamentLoad,
      ThreeDStage.manualCamera,
      ThreeDStage.ready,
      ThreeDStage.capture,
    ];

    expect(result.rendered, isTrue);
    expect(result.fellBack, isFalse);
    expect(result.clipPath, clipPath);
    expect(result.failedStage, isNull);
    expect(started, expected);
    expect(<ThreeDStage>[for (final e in summary.events) e.stage], expected);
    expect(summary.failures, isEmpty);
    expect(calls, <String>['load', 'manual', 'ready', 'capture']);
  });

  test('props without a picture go back to 2.5D, the world stays 3D', () async {
    final result = await runScene(
      _ops(<String>[], clipPath),
      ThreeDExportSummary(),
    );

    expect(result.rendered, isTrue);
    expect(_ids(result.routing.world), <String>['bg', 'desk', 'hero']);
    expect(_ids(result.routing.flat), <String>['coins', 'title']);
  });

  test('a Filament load failure returns the whole scene to 2.5D', () async {
    final calls = <String>[];
    final summary = ThreeDExportSummary();

    final result = await runScene(
      _ops(calls, clipPath, failAt: 'load'),
      summary,
    );

    expect(result.rendered, isFalse);
    expect(result.fellBack, isTrue);
    expect(result.clipPath, isNull);
    expect(result.failedStage, ThreeDStage.filamentLoad);
    expect(result.routing.reason, contains(ThreeDStage.filamentLoad.label));
    expect(_ids(result.routing.flat), _ids(_motion.layers));
    expect(result.routing.world, isEmpty);
    expect(calls, <String>['load']);
    expect(summary.failures.single.stage, ThreeDStage.filamentLoad);
    expect(summary.mostFailedStage, ThreeDStage.filamentLoad);
  });

  test('a capture failure is blamed on the capture stage', () async {
    final summary = ThreeDExportSummary();

    final result = await runScene(
      _ops(<String>[], clipPath, failAt: 'capture'),
      summary,
    );

    expect(result.fellBack, isTrue);
    expect(result.failedStage, ThreeDStage.capture);
    expect(summary.failures.single.stage, ThreeDStage.capture);
  });

  test('a manual camera failure is blamed on the manual stage', () async {
    final result = await runScene(
      _ops(<String>[], clipPath, failAt: 'manual'),
      ThreeDExportSummary(),
    );

    expect(result.fellBack, isTrue);
    expect(result.failedStage, ThreeDStage.manualCamera);
  });

  test('a green-frame clip is rejected and the scene falls back', () async {
    final result = await runScene(
      _ops(
        <String>[],
        clipPath,
        verify: (path) async => false,
      ),
      ThreeDExportSummary(),
    );

    expect(result.fellBack, isTrue);
    expect(result.failedStage, ThreeDStage.capture);
    expect(result.clipPath, isNull);
  });

  test('a missing clip file is a capture failure', () async {
    final result = await runScene(
      _ops(<String>[], '${temp.path}/missing.mp4'),
      ThreeDExportSummary(),
    );

    expect(result.fellBack, isTrue);
    expect(result.failedStage, ThreeDStage.capture);
  });

  test('Filament not ready runs no stage at all', () async {
    final calls = <String>[];
    final summary = ThreeDExportSummary();

    final result = await runScene(
      _ops(calls, clipPath),
      summary,
      filamentReady: false,
    );

    expect(result.fellBack, isTrue);
    expect(result.failedStage, isNull);
    expect(result.routing.reason, 'filament-unavailable');
    expect(summary.events, isEmpty);
    expect(calls, isEmpty);
  });

  test('the new stages are part of the ordered stage list', () {
    final order = ThreeDStage.values;
    expect(
      order.indexOf(ThreeDStage.worldPlan) <
          order.indexOf(ThreeDStage.worldGlb),
      isTrue,
    );
    expect(
      order.indexOf(ThreeDStage.camera) <
          order.indexOf(ThreeDStage.manualCamera),
      isTrue,
    );
    expect(
      order.indexOf(ThreeDStage.manualCamera) <
          order.indexOf(ThreeDStage.ready),
      isTrue,
    );
  });
}
