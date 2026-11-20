import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/render_router.dart';
import 'package:flutter_test/flutter_test.dart';

const MotionScene _scene = MotionScene(
  id: 'world_s1',
  start: 0,
  end: 3,
  layers: <MotionLayer>[
    MotionLayer(id: 'bg', start: 0, end: 3, assetKey: 'bg:office'),
    MotionLayer(id: 'hero', start: 0, end: 3, assetKey: 'sprite:hero'),
    MotionLayer(id: 'coins', start: 0, end: 3, assetKey: 'decor:coins'),
    MotionLayer(id: 'title', start: 0, end: 3, assetKey: 'text:title'),
  ],
);

List<String> _ids(List<MotionLayer> layers) =>
    <String>[for (final layer in layers) layer.id];

void main() {
  setUp(() => RenderRouter.enabled = true);
  tearDown(() => RenderRouter.enabled = true);

  group('RenderRouter.fallbackOf', () {
    test('sends every layer to 2.5D with the reason', () {
      final routing = RenderRouter.fallbackOf(_scene, 'stage-capture');
      expect(routing.fallback, isTrue);
      expect(routing.reason, 'stage-capture');
      expect(routing.sceneId, 'world_s1');
      expect(routing.usesFilament, isFalse);
      expect(routing.world, isEmpty);
      expect(_ids(routing.flat), <String>['bg', 'hero', 'coins', 'title']);
    });
  });

  group('RenderRouter.handBack', () {
    test('a layer the 3D world cannot draw returns to 2.5D in scene order', () {
      final routing = RenderRouter.route(_scene);
      final result = RenderRouter.handBack(
        _scene,
        routing,
        (layer) => layer.assetKey == 'decor:coins',
      );
      expect(result.fallback, isFalse);
      expect(_ids(result.world), <String>['bg', 'hero']);
      expect(_ids(result.flat), <String>['coins', 'title']);
    });

    test('nothing to hand back keeps the routing', () {
      final routing = RenderRouter.route(_scene);
      final result = RenderRouter.handBack(_scene, routing, (layer) => false);
      expect(_ids(result.world), <String>['bg', 'hero', 'coins']);
      expect(_ids(result.flat), <String>['title']);
    });

    test('no world layer left makes the scene a 2.5D fallback', () {
      final routing = RenderRouter.route(_scene);
      final result = RenderRouter.handBack(_scene, routing, (layer) => true);
      expect(result.fallback, isTrue);
      expect(result.reason, 'no-world-layers');
      expect(result.world, isEmpty);
      expect(_ids(result.flat), <String>['bg', 'hero', 'coins', 'title']);
    });

    test('a fallback routing is returned untouched', () {
      final routing = RenderRouter.fallbackOf(_scene, 'x');
      final result = RenderRouter.handBack(_scene, routing, (layer) => true);
      expect(identical(result, routing), isTrue);
    });
  });
}
