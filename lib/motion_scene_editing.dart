/// Pure, immutable editing operations for a [MotionSceneDocument]: move a
/// layer, change its size, trim its in/out points, reorder layers, edit a
/// word, swap a sprite, add or remove layers, and set the depth camera of a
/// scene or the depth of a layer. Every operation returns a new document and
/// leaves the original untouched.
library;

import 'dart:math' as math;

import 'depth_camera_model.dart';
import 'motion_scene_json.dart';
import 'motion_scene_model.dart';
import 'pixel_art_sprites.dart';
import 'reference_scene_builder.dart';

class MotionSceneEditing {
  MotionSceneEditing._();

  /// The shortest time a layer may stay on screen.
  static const double minLayerSeconds = 0.3;

  static const double _epsilon = 0.0001;

  /// Background layers are not edited or reordered.
  static bool isBackground(MotionLayer layer) =>
      (layer.assetKey ?? '').startsWith('bg:');

  static bool isWord(MotionSceneDocument doc, MotionLayer layer) {
    final key = layer.assetKey;
    if (key == null) return false;
    final spec = doc.assets[key];
    return spec != null && spec.kind == SceneAssetKind.word;
  }

  static bool isSprite(MotionSceneDocument doc, MotionLayer layer) {
    final key = layer.assetKey;
    if (key == null) return false;
    final spec = doc.assets[key];
    return spec != null && spec.kind == SceneAssetKind.sprite;
  }

  /// Copy of [layer] with some fields replaced. The depth is kept unless a
  /// new [depth] is given, or [clearDepth] returns it to automatic.
  static MotionLayer copyLayer(
    MotionLayer layer, {
    double? start,
    double? end,
    double? x,
    double? y,
    double? scale,
    int? zIndex,
    String? text,
    List<MotionKeyframe>? keyframes,
    double? depth,
    bool clearDepth = false,
  }) {
    return MotionLayer(
      id: layer.id,
      start: start ?? layer.start,
      end: end ?? layer.end,
      x: x ?? layer.x,
      y: y ?? layer.y,
      scale: scale ?? layer.scale,
      rotation: layer.rotation,
      opacity: layer.opacity,
      zIndex: zIndex ?? layer.zIndex,
      assetKey: layer.assetKey,
      text: text ?? layer.text,
      keyframes: keyframes ?? layer.keyframes,
      depth: clearDepth ? null : (depth ?? layer.depth),
    );
  }

  static MotionProject mapScenes(
    MotionProject project,
    MotionScene Function(MotionScene scene) edit,
  ) {
    return MotionProject(
      id: project.id,
      width: project.width,
      height: project.height,
      frameRate: project.frameRate,
      duration: project.duration,
      scenes: <MotionScene>[for (final scene in project.scenes) edit(scene)],
    );
  }

  static MotionProject mapLayers(
    MotionProject project,
    MotionLayer Function(MotionScene scene, MotionLayer layer) edit,
  ) {
    return mapScenes(project, (scene) {
      return MotionScene(
        id: scene.id,
        start: scene.start,
        end: scene.end,
        background: scene.background,
        transitionIn: scene.transitionIn,
        camera: scene.camera,
        layers: <MotionLayer>[
          for (final layer in scene.layers) edit(scene, layer),
        ],
      );
    });
  }

  static MotionSceneDocument updateLayer(
    MotionSceneDocument doc,
    String layerId,
    MotionLayer Function(MotionScene scene, MotionLayer layer) edit,
  ) {
    final next = mapLayers(
      doc.project,
      (scene, layer) => layer.id == layerId ? edit(scene, layer) : layer,
    );
    return doc.copyWith(project: next);
  }

  /// Sets the depth camera of the scene [sceneId]. A null camera, or one that
  /// does nothing (no move or zero intensity), removes the camera.
  static MotionSceneDocument withCamera(
    MotionSceneDocument doc,
    String sceneId,
    SceneCamera? camera,
  ) {
    final clean = camera != null && camera.isActive ? camera : null;
    final next = mapScenes(
      doc.project,
      (scene) => scene.id == sceneId ? scene.withCamera(clean) : scene,
    );
    return doc.copyWith(project: next);
  }

  /// Sets how near the layer [layerId] is to the depth camera (0 far, 1
  /// near). A null [depth] returns the layer to automatic depth.
  static MotionSceneDocument withDepth(
    MotionSceneDocument doc,
    String layerId,
    double? depth,
  ) {
    final value =
        depth == null || !depth.isFinite ? null : depth.clamp(0.0, 1.0);
    return updateLayer(
      doc,
      layerId,
      (scene, layer) => copyLayer(
        layer,
        depth: value?.toDouble(),
        clearDepth: value == null,
      ),
    );
  }

  /// Moves the whole animation of [layer] by a normalized offset.
  static MotionLayer translated(MotionLayer layer, double dx, double dy) {
    double clampPosition(double value) =>
        value.clamp(-0.2, 1.2).toDouble();

    return copyLayer(
      layer,
      x: clampPosition(layer.x + dx),
      y: clampPosition(layer.y + dy),
      keyframes: <MotionKeyframe>[
        for (final k in layer.keyframes)
          MotionKeyframe(
            time: k.time,
            x: clampPosition(k.x + dx),
            y: clampPosition(k.y + dy),
            scale: k.scale,
            rotation: k.rotation,
            opacity: k.opacity,
            easing: k.easing,
          ),
      ],
    );
  }

  /// Multiplies the size of [layer] (and of every keyframe) by [factor].
  static MotionLayer scaledBy(MotionLayer layer, double factor) {
    double clampScale(double value) =>
        (value * factor).clamp(0.05, 6.0).toDouble();

    return copyLayer(
      layer,
      scale: clampScale(layer.scale),
      keyframes: <MotionKeyframe>[
        for (final k in layer.keyframes)
          MotionKeyframe(
            time: k.time,
            x: k.x,
            y: k.y,
            scale: clampScale(k.scale),
            rotation: k.rotation,
            opacity: k.opacity,
            easing: k.easing,
          ),
      ],
    );
  }

  /// Changes the in/out points of [layer] inside [scene]. The animation is
  /// sampled at the new edges so the layer keeps the same motion there.
  static MotionLayer retimed(
    MotionScene scene,
    MotionLayer layer, {
    required double newStart,
    required double newEnd,
  }) {
    final start =
        newStart.clamp(scene.start, scene.end - minLayerSeconds).toDouble();
    final end = newEnd.clamp(start + minLayerSeconds, scene.end).toDouble();

    if ((start - layer.start).abs() <= _epsilon &&
        (end - layer.end).abs() <= _epsilon) {
      return layer;
    }
    if (layer.keyframes.isEmpty) {
      return copyLayer(layer, start: start, end: end);
    }

    final duration = end - start;

    MotionKeyframe boundary(double globalTime, double local) {
      final state = layer.stateAt(globalTime);
      return MotionKeyframe(
        time: local,
        x: state.x,
        y: state.y,
        scale: state.scale,
        rotation: state.rotation,
        opacity: state.opacity,
        easing: MotionEase.easeInOut,
      );
    }

    final keys = <MotionKeyframe>[boundary(start, 0)];
    for (final k in layer.keyframes) {
      final global = layer.start + k.time;
      if (global > start + 0.02 && global < end - 0.02) {
        keys.add(
          MotionKeyframe(
            time: global - start,
            x: k.x,
            y: k.y,
            scale: k.scale,
            rotation: k.rotation,
            opacity: k.opacity,
            easing: k.easing,
          ),
        );
      }
    }
    keys.add(boundary(end, duration));

    return copyLayer(layer, start: start, end: end, keyframes: keys);
  }

  /// Applies a new stacking order to one scene. [idsTopToBottom] lists the
  /// editable (non-background) layers, front-most first.
  static MotionSceneDocument reordered(
    MotionSceneDocument doc,
    String sceneId,
    List<String> idsTopToBottom,
  ) {
    final count = idsTopToBottom.length;
    final order = <String, int>{};
    for (var i = 0; i < count; i++) {
      order[idsTopToBottom[i]] = 10 + (count - 1 - i);
    }
    final next = mapLayers(doc.project, (scene, layer) {
      final value = order[layer.id];
      if (scene.id != sceneId || value == null) return layer;
      return copyLayer(layer, zIndex: value);
    });
    return doc.copyWith(project: next);
  }

  /// Changes the text of a word layer.
  static MotionSceneDocument withWordText(
    MotionSceneDocument doc,
    MotionLayer layer,
    String text,
  ) {
    final key = layer.assetKey;
    final clean = text.trim();
    if (key == null || clean.isEmpty || !isWord(doc, layer)) return doc;

    final assets = Map<String, SceneAssetSpec>.of(doc.assets);
    assets[key] = SceneAssetSpec(kind: SceneAssetKind.word, text: clean);
    final next = updateLayer(
      doc,
      layer.id,
      (scene, current) => copyLayer(current, text: clean),
    );
    return next.copyWith(assets: assets);
  }

  /// Swaps the sprite drawn by a sprite layer.
  static MotionSceneDocument withSprite(
    MotionSceneDocument doc,
    MotionLayer layer,
    String spriteKey,
  ) {
    final key = layer.assetKey;
    if (key == null || !isSprite(doc, layer)) return doc;
    if (PixelSprites.byKey(spriteKey) == null) return doc;

    final old = doc.assets[key];
    final assets = Map<String, SceneAssetSpec>.of(doc.assets);
    assets[key] = SceneAssetSpec(
      kind: SceneAssetKind.sprite,
      spriteKey: spriteKey,
      widthFraction: old == null ? 0.2 : old.widthFraction,
    );
    return doc.copyWith(assets: assets);
  }

  static List<MotionKeyframe> _popKeys(double duration, double y) {
    final t1 = math.min(0.25, duration * 0.4);
    final t2 = math.min(0.45, duration * 0.7);
    return <MotionKeyframe>[
      MotionKeyframe(
        time: 0,
        x: 0.5,
        y: y + 0.08,
        scale: 0.55,
        opacity: 0,
        easing: MotionEase.easeOut,
      ),
      MotionKeyframe(
        time: t1,
        x: 0.5,
        y: y - 0.012,
        scale: 1.12,
        easing: MotionEase.overshoot,
      ),
      MotionKeyframe(
        time: t2,
        x: 0.5,
        y: y,
        scale: 1.0,
        easing: MotionEase.easeInOut,
      ),
      MotionKeyframe(
        time: duration,
        x: 0.5,
        y: y,
        scale: 1.0,
        easing: MotionEase.easeInOut,
      ),
    ];
  }

  static String _freshId(MotionSceneDocument doc, MotionScene scene) {
    final used = <String>{};
    for (final s in doc.project.scenes) {
      for (final l in s.layers) {
        used.add(l.id);
      }
    }
    var n = 0;
    while (used.contains('${scene.id}_u$n')) {
      n++;
    }
    return '${scene.id}_u$n';
  }

  static MotionScene? _sceneById(MotionSceneDocument doc, String sceneId) {
    for (final scene in doc.project.scenes) {
      if (scene.id == sceneId) return scene;
    }
    return null;
  }

  static MotionSceneDocument _withNewLayer(
    MotionSceneDocument doc,
    MotionScene target,
    MotionLayer layer,
    String assetKey,
    SceneAssetSpec spec,
  ) {
    final next = mapScenes(doc.project, (scene) {
      if (scene.id != target.id) return scene;
      return MotionScene(
        id: scene.id,
        start: scene.start,
        end: scene.end,
        background: scene.background,
        transitionIn: scene.transitionIn,
        camera: scene.camera,
        layers: <MotionLayer>[...scene.layers, layer],
      );
    });
    final assets = Map<String, SceneAssetSpec>.of(doc.assets);
    assets[assetKey] = spec;
    return doc.copyWith(project: next, assets: assets);
  }

  static int _topZ(MotionScene scene) {
    var top = 0;
    for (final layer in scene.layers) {
      top = math.max(top, layer.zIndex);
    }
    return top + 1;
  }

  /// Adds a new word layer (pop-in animation) to the scene [sceneId].
  static MotionSceneDocument addWord(
    MotionSceneDocument doc,
    String sceneId,
    String text,
  ) {
    final clean = text.trim();
    final target = _sceneById(doc, sceneId);
    if (clean.isEmpty || target == null) return doc;

    final id = _freshId(doc, target);
    final start = math.max(
      target.start,
      math.min(target.start + 0.1, target.end - minLayerSeconds),
    );
    final layer = MotionLayer(
      id: id,
      start: start,
      end: target.end,
      zIndex: _topZ(target),
      assetKey: 'text:$id',
      text: clean,
      keyframes: _popKeys(target.end - start, 0.62),
    );
    return _withNewLayer(
      doc,
      target,
      layer,
      'text:$id',
      SceneAssetSpec(kind: SceneAssetKind.word, text: clean),
    );
  }

  /// Adds a new sprite layer (pop-in animation) to the scene [sceneId].
  static MotionSceneDocument addSprite(
    MotionSceneDocument doc,
    String sceneId,
    String spriteKey,
  ) {
    final target = _sceneById(doc, sceneId);
    if (target == null || PixelSprites.byKey(spriteKey) == null) return doc;

    final id = _freshId(doc, target);
    final start = math.max(
      target.start,
      math.min(target.start + 0.1, target.end - minLayerSeconds),
    );
    final fraction = doc.project.height >= doc.project.width ? 0.22 : 0.15;
    final layer = MotionLayer(
      id: id,
      start: start,
      end: target.end,
      zIndex: _topZ(target),
      assetKey: 'sprite:$id',
      keyframes: _popKeys(target.end - start, 0.32),
    );
    return _withNewLayer(
      doc,
      target,
      layer,
      'sprite:$id',
      SceneAssetSpec(
        kind: SceneAssetKind.sprite,
        spriteKey: spriteKey,
        widthFraction: fraction,
      ),
    );
  }

  /// Removes a layer and its asset when no other layer uses it.
  static MotionSceneDocument removeLayer(
    MotionSceneDocument doc,
    String layerId,
  ) {
    String? assetKey;
    for (final scene in doc.project.scenes) {
      for (final layer in scene.layers) {
        if (layer.id == layerId) assetKey = layer.assetKey;
      }
    }

    final next = mapScenes(doc.project, (scene) {
      return MotionScene(
        id: scene.id,
        start: scene.start,
        end: scene.end,
        background: scene.background,
        transitionIn: scene.transitionIn,
        camera: scene.camera,
        layers: <MotionLayer>[
          for (final layer in scene.layers)
            if (layer.id != layerId) layer,
        ],
      );
    });

    final assets = Map<String, SceneAssetSpec>.of(doc.assets);
    if (assetKey != null) {
      var stillUsed = false;
      for (final scene in next.scenes) {
        for (final layer in scene.layers) {
          if (layer.assetKey == assetKey) stillUsed = true;
        }
      }
      if (!stillUsed) assets.remove(assetKey);
    }
    return doc.copyWith(project: next, assets: assets);
  }
}
