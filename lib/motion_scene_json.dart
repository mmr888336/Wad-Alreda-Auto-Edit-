/// Saves and loads an editable motion cutaway.
///
/// A rendered cutaway is only an MP4. Next to it the app keeps a small JSON
/// file (`<clip>.motion.json`) that describes the scenes, layers, keyframes,
/// depth cameras and assets, so the layers can be edited later and the clip
/// re-rendered by the Motion engine.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'depth_camera_model.dart';
import 'motion_scene_model.dart';
import 'motion_transitions.dart';
import 'reference_scene_builder.dart';

/// Everything needed to edit and re-render one motion cutaway.
class MotionSceneDocument {
  final MotionProject project;

  /// Asset key (as used by [MotionLayer.assetKey]) -> what to render.
  final Map<String, SceneAssetSpec> assets;

  /// Font used for the word layers.
  final String fontFamily;

  const MotionSceneDocument({
    required this.project,
    required this.assets,
    required this.fontFamily,
  });

  MotionSceneDocument copyWith({
    MotionProject? project,
    Map<String, SceneAssetSpec>? assets,
    String? fontFamily,
  }) {
    return MotionSceneDocument(
      project: project ?? this.project,
      assets: assets ?? this.assets,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

class MotionSceneJson {
  MotionSceneJson._();

  static const int schemaVersion = 1;

  /// `dir/motion_scene_1_0.mp4` becomes `dir/motion_scene_1_0.motion.json`.
  /// ProjectStore uses the same naming when it copies a clip into a project.
  static String sidecarPathFor(String clipPath) {
    final dot = clipPath.lastIndexOf('.');
    final slash = math.max(
      clipPath.lastIndexOf('/'),
      clipPath.lastIndexOf('\\'),
    );
    final base = dot > slash ? clipPath.substring(0, dot) : clipPath;
    return '$base.motion.json';
  }

  // ---------------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _keyToJson(MotionKeyframe k) =>
      <String, dynamic>{
        't': k.time,
        'x': k.x,
        'y': k.y,
        's': k.scale,
        'r': k.rotation,
        'o': k.opacity,
        'e': k.easing.name,
      };

  static Map<String, dynamic> _layerToJson(MotionLayer l) {
    final depth = l.depth;
    return <String, dynamic>{
      'id': l.id,
      'start': l.start,
      'end': l.end,
      'x': l.x,
      'y': l.y,
      'scale': l.scale,
      'rotation': l.rotation,
      'opacity': l.opacity,
      'z': l.zIndex,
      'asset': l.assetKey,
      'text': l.text,
      'keys': l.keyframes.map(_keyToJson).toList(),
      if (depth != null) 'd': depth,
    };
  }

  static Map<String, dynamic> _cameraToJson(SceneCamera c) =>
      <String, dynamic>{
        'm': c.move.name,
        'i': c.intensity,
        'fx': c.focusX,
        'fy': c.focusY,
      };

  static Map<String, dynamic> _sceneToJson(MotionScene s) {
    final camera = s.camera;
    return <String, dynamic>{
      'id': s.id,
      'start': s.start,
      'end': s.end,
      'bg': s.background,
      'transition': s.transitionIn.name,
      'layers': s.layers.map(_layerToJson).toList(),
      if (camera != null) 'cam': _cameraToJson(camera),
    };
  }

  static Map<String, dynamic> _projectToJson(MotionProject p) =>
      <String, dynamic>{
        'id': p.id,
        'width': p.width,
        'height': p.height,
        'fps': p.frameRate,
        'duration': p.duration,
        'scenes': p.scenes.map(_sceneToJson).toList(),
      };

  static Map<String, dynamic> _assetToJson(SceneAssetSpec a) =>
      <String, dynamic>{
        'kind': a.kind.name,
        'sprite': a.spriteKey,
        'text': a.text,
        'w': a.widthFraction,
        'top': a.topColor,
        'bottom': a.bottomColor,
      };

  static String encode(MotionSceneDocument doc) {
    final assets = <String, dynamic>{};
    for (final entry in doc.assets.entries) {
      assets[entry.key] = _assetToJson(entry.value);
    }
    return jsonEncode(<String, dynamic>{
      'schema': schemaVersion,
      'fontFamily': doc.fontFamily,
      'project': _projectToJson(doc.project),
      'assets': assets,
    });
  }

  // ---------------------------------------------------------------------------
  // Decoding
  // ---------------------------------------------------------------------------

  static double _num(Object? value, double fallback) =>
      value is num && value.isFinite ? value.toDouble() : fallback;

  static int _int(Object? value, int fallback) =>
      value is num && value.isFinite ? value.toInt() : fallback;

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  static List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : <Object?>[];

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final option in values) {
      if (option.name == name) return option;
    }
    return fallback;
  }

  static MotionKeyframe _keyFromJson(Map<String, dynamic> j) {
    return MotionKeyframe(
      time: _num(j['t'], 0),
      x: _num(j['x'], 0.5),
      y: _num(j['y'], 0.5),
      scale: _num(j['s'], 1),
      rotation: _num(j['r'], 0),
      opacity: _num(j['o'], 1),
      easing: _enum(MotionEase.values, j['e'], MotionEase.easeInOut),
    );
  }

  static MotionLayer _layerFromJson(Map<String, dynamic> j) {
    final keys = <MotionKeyframe>[];
    for (final item in _list(j['keys'])) {
      keys.add(_keyFromJson(_map(item)));
    }
    final id = j['id'];
    final asset = j['asset'];
    final text = j['text'];
    final depth = j['d'];
    return MotionLayer(
      id: id is String ? id : '',
      start: _num(j['start'], 0),
      end: _num(j['end'], 0),
      x: _num(j['x'], 0.5),
      y: _num(j['y'], 0.5),
      scale: _num(j['scale'], 1),
      rotation: _num(j['rotation'], 0),
      opacity: _num(j['opacity'], 1),
      zIndex: _int(j['z'], 0),
      assetKey: asset is String ? asset : null,
      text: text is String ? text : null,
      keyframes: keys,
      depth: depth is num && depth.isFinite
          ? depth.toDouble().clamp(0.0, 1.0).toDouble()
          : null,
    );
  }

  /// A camera stored by this version, or null when there is none (clips made
  /// by older versions) or when it does nothing.
  static SceneCamera? _cameraFromJson(Object? value) {
    if (value is! Map) return null;
    final j = Map<String, dynamic>.from(value);
    final move = _enum(DepthCameraMove.values, j['m'], DepthCameraMove.none);
    if (move == DepthCameraMove.none) return null;
    return SceneCamera(
      move: move,
      intensity: _num(j['i'], 0.8)
          .clamp(0.0, SceneCamera.maxIntensity)
          .toDouble(),
      focusX: _num(j['fx'], 0.5).clamp(0.0, 1.0).toDouble(),
      focusY: _num(j['fy'], 0.42).clamp(0.0, 1.0).toDouble(),
    );
  }

  static MotionScene _sceneFromJson(Map<String, dynamic> j) {
    final layers = <MotionLayer>[];
    for (final item in _list(j['layers'])) {
      layers.add(_layerFromJson(_map(item)));
    }
    final id = j['id'];
    final bg = j['bg'];
    return MotionScene(
      id: id is String ? id : '',
      start: _num(j['start'], 0),
      end: _num(j['end'], 0),
      background: bg is String ? bg : '#000000',
      transitionIn: _enum(
        MotionTransitionKind.values,
        j['transition'],
        MotionTransitionKind.hardCut,
      ),
      layers: layers,
      camera: _cameraFromJson(j['cam']),
    );
  }

  static MotionProject _projectFromJson(Map<String, dynamic> j) {
    final scenes = <MotionScene>[];
    for (final item in _list(j['scenes'])) {
      scenes.add(_sceneFromJson(_map(item)));
    }
    final id = j['id'];
    return MotionProject(
      id: id is String ? id : 'motion',
      width: _int(j['width'], 0),
      height: _int(j['height'], 0),
      frameRate: _int(j['fps'], 30),
      duration: _num(j['duration'], 0),
      scenes: scenes,
    );
  }

  static SceneAssetSpec _assetFromJson(Map<String, dynamic> j) {
    final sprite = j['sprite'];
    final text = j['text'];
    return SceneAssetSpec(
      kind: _enum(SceneAssetKind.values, j['kind'], SceneAssetKind.sprite),
      spriteKey: sprite is String ? sprite : null,
      text: text is String ? text : null,
      widthFraction: _num(j['w'], 1.0),
      topColor: _int(j['top'], 0xFF000000),
      bottomColor: _int(j['bottom'], 0xFF000000),
    );
  }

  /// Throws when the text is not a valid document or its project is invalid.
  static MotionSceneDocument decode(String source) {
    final root = _map(jsonDecode(source));
    final project = _projectFromJson(_map(root['project']));
    project.validate();

    final assets = <String, SceneAssetSpec>{};
    final assetsJson = _map(root['assets']);
    for (final entry in assetsJson.entries) {
      assets[entry.key] = _assetFromJson(_map(entry.value));
    }

    final font = root['fontFamily'];
    return MotionSceneDocument(
      project: project,
      assets: assets,
      fontFamily: font is String && font.isNotEmpty ? font : 'Cairo',
    );
  }

  // ---------------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------------

  /// Reads the document stored next to [clipPath]. Returns null when there is
  /// none (clips made by older versions) or when it cannot be read.
  static Future<MotionSceneDocument?> readFor(String clipPath) async {
    try {
      final file = File(sidecarPathFor(clipPath));
      if (!await file.exists()) return null;
      return decode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeFor(
    String clipPath,
    MotionSceneDocument doc,
  ) async {
    await File(sidecarPathFor(clipPath)).writeAsString(
      encode(doc),
      flush: true,
    );
  }
}
