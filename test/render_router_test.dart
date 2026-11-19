import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/motion_transitions.dart';
import 'package:auto_edit/render_router.dart';
import 'package:flutter_test/flutter_test.dart';

MotionScene _scene() {
  return const MotionScene(
    id: 'world_s0',
    start: 1,
    end: 4,
    background: '#1E2230',
    transitionIn: MotionTransitionKind.hardCut,
    camera: SceneCamera(move: DepthCameraMove.pushIn, intensity: 0.9),
    layers: <MotionLayer>[
      MotionLayer(id: 'bg', start: 1, end: 4, assetKey: 'bg:office'),
      MotionLayer(id: 'fx', start: 1, end: 4, assetKey: 'bg:fx_embers', zIndex: 2),
      MotionLayer(id: 'desk', start: 1, end: 4, assetKey: 'decor:desk', zIndex: 1),
      MotionLayer(id: 'hero', start: 1, end: 4, assetKey: 'sprite:hero', zIndex: 20),
      MotionLayer(id: 'title', start: 1, end: 4, assetKey: 'text:title', zIndex: 40),
      MotionLayer(id: 'plain', start: 1, end: 4),
    ],
  );
}

List<String> _ids(List<MotionLayer> layers) =>
    <String>[for (final layer in layers) layer.id];

void main() {
  setUp(() => RenderRouter.enabled = true);
  tearDown(() => RenderRouter.enabled = true);

  group('RenderRouter.engineForKey', () {
    test('the world goes to Filament', () {
      expect(RenderRouter.engineForKey('bg:office'), RenderEngine.filament3d);
      expect(RenderRouter.engineForKey('decor:desk'), RenderEngine.filament3d);
      expect(RenderRouter.engineForKey('decor:coins'), RenderEngine.filament3d);
      expect(RenderRouter.engineForKey('sprite:hero'), RenderEngine.filament3d);
    });

    test('titles, effects and unknown layers stay 2.5D', () {
      expect(RenderRouter.engineForKey('text:title'), RenderEngine.flat25d);
      expect(RenderRouter.engineForKey('bg:fx_embers'), RenderEngine.flat25d);
      expect(RenderRouter.engineForKey('weird:thing'), RenderEngine.flat25d);
      expect(RenderRouter.engineForKey(''), RenderEngine.flat25d);
      expect(RenderRouter.engineForKey(null), RenderEngine.flat25d);
    });
  });

  group('RenderRouter.route', () {
    test('splits the layers between the two engines', () {
      final routing = RenderRouter.route(_scene());
      expect(routing.fallback, isFalse);
      expect(routing.reason, isNull);
      expect(routing.usesFilament, isTrue);
      expect(_ids(routing.world), <String>['bg', 'desk', 'hero']);
      expect(_ids(routing.flat), <String>['fx', 'title', 'plain']);
      expect(routing.world.length + routing.flat.length, 6);
    });

    test('3D not ready sends the whole scene to 2.5D', () {
      final scene = _scene();
      final routing = RenderRouter.route(scene, filamentReady: false);
      expect(routing.fallback, isTrue);
      expect(routing.reason, 'filament-unavailable');
      expect(routing.usesFilament, isFalse);
      expect(routing.world, isEmpty);
      expect(_ids(routing.flat), _ids(scene.layers));
    });

    test('the master switch sends the whole scene to 2.5D', () {
      RenderRouter.enabled = false;
      final scene = _scene();
      final routing = RenderRouter.route(scene);
      expect(routing.fallback, isTrue);
      expect(routing.reason, 'disabled');
      expect(_ids(routing.flat), _ids(scene.layers));
    });

    test('a scene with no world layer stays 2.5D', () {
      const scene = MotionScene(
        id: 'flat',
        start: 0,
        end: 2,
        layers: <MotionLayer>[
          MotionLayer(id: 'a', start: 0, end: 2, assetKey: 'text:a'),
          MotionLayer(id: 'b', start: 0, end: 2, assetKey: 'bg:fx_dust'),
        ],
      );
      final routing = RenderRouter.route(scene);
      expect(routing.fallback, isTrue);
      expect(routing.reason, 'no-world-layers');
      expect(_ids(routing.flat), <String>['a', 'b']);
    });
  });

  group('RenderRouter.flatSceneOf', () {
    test('keeps timing, transition and the depth camera', () {
      final scene = _scene();
      final routing = RenderRouter.route(scene);
      final flat = RenderRouter.flatSceneOf(scene, routing);
      expect(flat.id, scene.id);
      expect(flat.start, scene.start);
      expect(flat.end, scene.end);
      expect(flat.background, scene.background);
      expect(flat.transitionIn, scene.transitionIn);
      expect(flat.camera!.move, DepthCameraMove.pushIn);
      expect(_ids(flat.layers), <String>['fx', 'title', 'plain']);
    });

    test('a fallback scene is drawn complete by the 2.5D engine', () {
      final scene = _scene();
      final routing = RenderRouter.route(scene, filamentReady: false);
      final flat = RenderRouter.flatSceneOf(scene, routing);
      expect(_ids(flat.layers), _ids(scene.layers));
    });
  });
}
