/// Render router: decides which engine draws which layer of a motion scene.
///
///  * Filament (real 3D) owns the WORLD: the backdrop / room, the set pieces,
///    the recurring character and the props (`bg:`, `decor:`, `sprite:`).
///  * The 2.5D engine owns everything flat: titles and words (`text:`...),
///    effects and atmosphere overlays (`bg:fx`), and any layer it does not
///    know. It keeps its depth camera, so those layers still react to the
///    camera of the scene.
///
/// 2.5D is never removed. When 3D is not ready, switched off, or the scene has
/// no world layer, the whole scene is routed to the 2.5D engine exactly as it
/// was before (the fallback), so a failed 3D render never costs a scene.
/// Pure Dart, no I/O.
library;

import 'motion_scene_model.dart';

enum RenderEngine { filament3d, flat25d }

/// The layers of one scene split between the two engines.
class SceneRouting {
  final String sceneId;

  /// Layers the 3D world draws (empty on a fallback).
  final List<MotionLayer> world;

  /// Layers the 2.5D engine draws (all of them on a fallback).
  final List<MotionLayer> flat;

  /// True when the scene is drawn by the 2.5D engine alone.
  final bool fallback;

  /// Why the scene fell back (null when it did not).
  final String? reason;

  const SceneRouting({
    required this.sceneId,
    required this.world,
    required this.flat,
    required this.fallback,
    this.reason,
  });

  /// True when Filament has to render this scene.
  bool get usesFilament => !fallback && world.isNotEmpty;
}

class RenderRouter {
  RenderRouter._();

  /// Master switch. When false every scene goes to the 2.5D engine (the old
  /// behaviour).
  static bool enabled = true;

  /// The engine for a layer with asset key [key].
  static RenderEngine engineForKey(String? key) {
    if (key == null || key.isEmpty) return RenderEngine.flat25d;
    // Atmosphere overlays are flat effects, not world geometry.
    if (key.startsWith('bg:fx')) return RenderEngine.flat25d;
    if (key.startsWith('bg:') ||
        key.startsWith('decor:') ||
        key.startsWith('sprite:')) {
      return RenderEngine.filament3d;
    }
    // Titles, words, effects and anything unknown stay 2.5D.
    return RenderEngine.flat25d;
  }

  /// Splits the layers of [scene]. [filamentReady] is false when the 3D
  /// renderer is not available right now (it failed, the device cannot run
  /// it, the user turned it off): everything then goes to the 2.5D engine.
  static SceneRouting route(
    MotionScene scene, {
    bool filamentReady = true,
  }) {
    if (!enabled) {
      return SceneRouting(
        sceneId: scene.id,
        world: const <MotionLayer>[],
        flat: List<MotionLayer>.of(scene.layers),
        fallback: true,
        reason: 'disabled',
      );
    }
    if (!filamentReady) {
      return SceneRouting(
        sceneId: scene.id,
        world: const <MotionLayer>[],
        flat: List<MotionLayer>.of(scene.layers),
        fallback: true,
        reason: 'filament-unavailable',
      );
    }

    final world = <MotionLayer>[];
    final flat = <MotionLayer>[];
    for (final layer in scene.layers) {
      if (engineForKey(layer.assetKey) == RenderEngine.filament3d) {
        world.add(layer);
      } else {
        flat.add(layer);
      }
    }

    if (world.isEmpty) {
      return SceneRouting(
        sceneId: scene.id,
        world: const <MotionLayer>[],
        flat: flat,
        fallback: true,
        reason: 'no-world-layers',
      );
    }

    return SceneRouting(
      sceneId: scene.id,
      world: world,
      flat: flat,
      fallback: false,
    );
  }

  /// The routing of a scene that the 2.5D engine draws alone, with the
  /// [reason] why (for example the 3D stage that failed). Every layer goes to
  /// the 2.5D engine, in scene order.
  static SceneRouting fallbackOf(MotionScene scene, String reason) {
    return SceneRouting(
      sceneId: scene.id,
      world: const <MotionLayer>[],
      flat: List<MotionLayer>.of(scene.layers),
      fallback: true,
      reason: reason,
    );
  }

  /// Hands the world layers selected by [cannotDraw] back to the 2.5D engine
  /// (a prop the 3D world has no picture for would otherwise vanish from the
  /// final scene). The layers keep the order of [scene]. When no world layer
  /// is left the whole scene is a 2.5D fallback with [reason].
  static SceneRouting handBack(
    MotionScene scene,
    SceneRouting routing,
    bool Function(MotionLayer layer) cannotDraw, {
    String reason = 'no-world-layers',
  }) {
    if (routing.fallback) return routing;

    final world = <MotionLayer>[];
    final flat = <MotionLayer>[];
    for (final layer in scene.layers) {
      if (routing.world.contains(layer) && !cannotDraw(layer)) {
        world.add(layer);
      } else {
        flat.add(layer);
      }
    }

    if (world.isEmpty) {
      return SceneRouting(
        sceneId: routing.sceneId,
        world: const <MotionLayer>[],
        flat: flat,
        fallback: true,
        reason: reason,
      );
    }

    return SceneRouting(
      sceneId: routing.sceneId,
      world: world,
      flat: flat,
      fallback: false,
    );
  }

  /// The part of [scene] the 2.5D engine draws: same id, timing, transition
  /// and depth camera, only the flat layers.
  static MotionScene flatSceneOf(MotionScene scene, SceneRouting routing) {
    return MotionScene(
      id: scene.id,
      start: scene.start,
      end: scene.end,
      layers: routing.flat,
      background: scene.background,
      transitionIn: scene.transitionIn,
      camera: scene.camera,
    );
  }
}
