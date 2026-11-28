import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/three_d_asset_resolver.dart';
import 'package:auto_edit/three_d_asset_service.dart';
import 'package:auto_edit/world3d_model.dart';
import 'package:auto_edit/world3d_planner.dart';
import 'package:flutter_test/flutter_test.dart';

WorldScene _scene() {
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
        id: 'w0_backdrop',
        assetKey: 'bg:office',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.0,
        zIndex: 0,
      ),
      WorldLayerSpec(
        id: 'w0_set0',
        assetKey: 'decor:desk',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.12,
        zIndex: 1,
      ),
      WorldLayerSpec(
        id: 'w0_hero',
        assetKey: 'sprite:hero',
        x: 0.5,
        y: 0.62,
        scale: 0.42,
        depth: 0.62,
        zIndex: 20,
      ),
      WorldLayerSpec(
        id: 'w0_prop0',
        assetKey: 'decor:coins',
        x: 0.2,
        y: 0.74,
        scale: 0.2,
        depth: 0.38,
        zIndex: 10,
      ),
    ],
  );
}

ResolvedAsset _resolved(String? localPath) {
  return ResolvedAsset(
    asset: const ThreeDAsset(
      id: 'khronos_Lantern',
      title: 'Khronos Lantern',
      provider: ThreeDAssetProvider.polyHaven,
    ),
    keywords: const <String>['coins'],
    localPath: localPath,
    fromCatalog: true,
  );
}

World3DObject _prop(World3DScene plan) =>
    plan.objectsOf(World3DRole.prop).single;

void main() {
  group('World3DPlanner.plan resolved', () {
    test('a resolved prop with a local path becomes a model object', () {
      final plan = World3DPlanner.plan(
        _scene(),
        resolved: <String, ResolvedAsset>{
          'decor:coins': _resolved('/tmp/coins.glb'),
        },
      );

      final prop = _prop(plan);
      expect(prop.shape, World3DShape.model);
      expect(prop.modelPath, '/tmp/coins.glb');
      expect(prop.assetKey, 'decor:coins');
      expect(prop.role, World3DRole.prop);

      // Same place and size as the billboard it replaces.
      final plain = _prop(World3DPlanner.plan(_scene()));
      expect(prop.position, plain.position);
      expect(prop.size, plain.size);
    });

    test('a null or empty local path keeps the billboard', () {
      for (final path in <String?>[null, '']) {
        final plan = World3DPlanner.plan(
          _scene(),
          resolved: <String, ResolvedAsset>{
            'decor:coins': _resolved(path),
          },
        );
        final prop = _prop(plan);
        expect(prop.shape, World3DShape.billboard);
        expect(prop.modelPath, isNull);
        expect(prop.assetKey, 'decor:coins');
      }
    });

    test('an empty resolved map matches the call without the parameter', () {
      final withEmpty = World3DPlanner.plan(
        _scene(),
        resolved: const <String, ResolvedAsset>{},
      );
      final without = World3DPlanner.plan(_scene());

      expect(withEmpty.objects, hasLength(without.objects.length));
      for (var i = 0; i < without.objects.length; i++) {
        final a = withEmpty.objects[i];
        final b = without.objects[i];
        expect(a.id, b.id);
        expect(a.role, b.role);
        expect(a.shape, b.shape);
        expect(a.assetKey, b.assetKey);
        expect(a.position, b.position);
        expect(a.size, b.size);
        expect(a.color, b.color);
        expect(a.modelPath, b.modelPath);
      }
    });

    test('a key missing from resolved leaves the other objects untouched', () {
      final plan = World3DPlanner.plan(
        _scene(),
        resolved: <String, ResolvedAsset>{
          'decor:not_in_scene': _resolved('/tmp/other.glb'),
        },
      );
      final plain = World3DPlanner.plan(_scene());

      expect(plan.objects, hasLength(plain.objects.length));
      expect(plan.objectsOf(World3DRole.setPiece), hasLength(1));
      expect(plan.objectsOf(World3DRole.character), hasLength(1));
      expect(plan.objectsOf(World3DRole.prop), hasLength(1));

      final prop = _prop(plan);
      expect(prop.shape, World3DShape.billboard);
      expect(prop.modelPath, isNull);
      expect(prop.assetKey, 'decor:coins');
    });
  });
}
