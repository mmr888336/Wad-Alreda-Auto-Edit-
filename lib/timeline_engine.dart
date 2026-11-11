import 'dart:math' as math;

/// The semantic role of a row in the future Studio timeline.
enum TimelineTrackType { video, broll, captions, graphics, audio, effects }

/// The type of an individual editable item on a timeline track.
enum TimelineLayerType {
  sourceVideo,
  broll,
  caption,
  title,
  shape,
  icon,
  sourceAudio,
  soundEffect,
}

/// Easing applied between this keyframe and the next one.
enum KeyframeEasing { linear, easeIn, easeOut, easeInOut }

/// Transform channel that can be animated by keyframes.
enum TransformProperty { x, y, scale, rotation, opacity }

/// A normalized 2D transform. x/y are normalized center coordinates;
/// rotation is in degrees and opacity is in the range 0..1.
class LayerTransform {
  final double x;
  final double y;
  final double scale;
  final double rotation;
  final double opacity;

  const LayerTransform({
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1,
    this.rotation = 0,
    this.opacity = 1,
  });

  double valueFor(TransformProperty property) {
    switch (property) {
      case TransformProperty.x:
        return x;
      case TransformProperty.y:
        return y;
      case TransformProperty.scale:
        return scale;
      case TransformProperty.rotation:
        return rotation;
      case TransformProperty.opacity:
        return opacity;
    }
  }

  bool get isValid =>
      x.isFinite &&
      y.isFinite &&
      scale.isFinite &&
      scale > 0 &&
      scale <= 20 &&
      rotation.isFinite &&
      rotation.abs() <= 3600 &&
      opacity.isFinite &&
      opacity >= 0 &&
      opacity <= 1;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
      };

  factory LayerTransform.fromJson(Map<String, dynamic> json) {
    return LayerTransform(
      x: _readNumber(json['x'], 0.5),
      y: _readNumber(json['y'], 0.5),
      scale: _readNumber(json['scale'], 1),
      rotation: _readNumber(json['rotation'], 0),
      opacity: _readNumber(json['opacity'], 1),
    );
  }

  static double _readNumber(Object? value, double fallback) =>
      value is num && value.isFinite ? value.toDouble() : fallback;
}

/// A complete transform at one absolute point on the project timeline.
class TransformKeyframe {
  final double time;
  final LayerTransform transform;

  /// Controls interpolation from this keyframe to the next keyframe.
  final KeyframeEasing easing;

  const TransformKeyframe({
    required this.time,
    required this.transform,
    this.easing = KeyframeEasing.linear,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'transform': transform.toJson(),
        'easing': easing.name,
      };

  factory TransformKeyframe.fromJson(Map<String, dynamic> json) {
    return TransformKeyframe(
      time: _readNumber(json['time'], 0),
      transform: LayerTransform.fromJson(
        Map<String, dynamic>.from(
          (json['transform'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      easing: _readEnum(
        KeyframeEasing.values,
        json['easing'],
        KeyframeEasing.linear,
      ),
    );
  }
}

/// One real media or graphics item on the project timeline.
class TimelineLayer {
  final String id;
  final String trackId;
  final TimelineLayerType type;
  final String name;
  final double start;
  final double end;
  final int zIndex;
  final String? sourcePath;
  final String? text;
  final bool visible;
  final List<TransformKeyframe> keyframes;

  TimelineLayer({
    required this.id,
    required this.trackId,
    required this.type,
    required this.name,
    required this.start,
    required this.end,
    required this.zIndex,
    this.sourcePath,
    this.text,
    this.visible = true,
    List<TransformKeyframe> keyframes = const [],
  }) : keyframes = List.unmodifiable(keyframes);

  double get duration => end - start;

  /// Evaluates every transform channel at an absolute project time.
  LayerTransform transformAt(double time) {
    if (keyframes.isEmpty) return const LayerTransform();
    if (time <= keyframes.first.time) return keyframes.first.transform;
    if (time >= keyframes.last.time) return keyframes.last.transform;

    for (var index = 0; index < keyframes.length - 1; index++) {
      final from = keyframes[index];
      final to = keyframes[index + 1];

      if (time < to.time) {
        final span = to.time - from.time;
        if (span <= 0) return to.transform;

        final rawProgress =
            ((time - from.time) / span).clamp(0.0, 1.0).toDouble();
        final progress = _ease(rawProgress, from.easing);

        double interpolate(TransformProperty property) {
          final a = from.transform.valueFor(property);
          final b = to.transform.valueFor(property);
          return a + ((b - a) * progress);
        }

        return LayerTransform(
          x: interpolate(TransformProperty.x),
          y: interpolate(TransformProperty.y),
          scale: interpolate(TransformProperty.scale),
          rotation: interpolate(TransformProperty.rotation),
          opacity: interpolate(TransformProperty.opacity),
        );
      }
    }

    return keyframes.last.transform;
  }

  /// Builds an FFmpeg per-frame expression for one transform channel.
  /// The expression uses the main video's absolute timestamp t.
  String ffmpegExpression(
    TransformProperty property, {
    String? fallback,
  }) {
    if (keyframes.isEmpty) {
      return fallback ?? _format(const LayerTransform().valueFor(property));
    }

    final first = keyframes.first;
    var expression = _format(keyframes.last.transform.valueFor(property));

    for (var index = keyframes.length - 2; index >= 0; index--) {
      final from = keyframes[index];
      final to = keyframes[index + 1];
      final span = to.time - from.time;
      if (span <= 0) continue;

      final progress =
          'min(1,max(0,(t-${_format(from.time)})/${_format(span)}))';
      final eased = _easingExpression(from.easing, progress);
      final a = _format(from.transform.valueFor(property));
      final b = _format(to.transform.valueFor(property));
      final value = '($a+($b-$a)*($eased))';

      expression =
          'if(lt(t,${_format(to.time)}),$value,$expression)';
    }

    return 'if(lt(t,${_format(first.time)}),'
        '${_format(first.transform.valueFor(property))},$expression)';
  }

  static double _ease(double value, KeyframeEasing easing) {
    final t = value.clamp(0.0, 1.0).toDouble();
    switch (easing) {
      case KeyframeEasing.linear:
        return t;
      case KeyframeEasing.easeIn:
        return t * t * t;
      case KeyframeEasing.easeOut:
        return 1 - math.pow(1 - t, 3).toDouble();
      case KeyframeEasing.easeInOut:
        if (t < 0.5) return 4 * t * t * t;
        return 1 - (math.pow(-2 * t + 2, 3).toDouble() / 2);
    }
  }

  static String _easingExpression(KeyframeEasing easing, String t) {
    switch (easing) {
      case KeyframeEasing.linear:
        return t;
      case KeyframeEasing.easeIn:
        return 'pow($t,3)';
      case KeyframeEasing.easeOut:
        return '(1-pow(1-$t,3))';
      case KeyframeEasing.easeInOut:
        return 'if(lt($t,0.5),4*pow($t,3),'
            '(1-pow(-2*$t+2,3)/2))';
    }
  }

  static String _format(double value) => value.toStringAsFixed(6);

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'type': type.name,
        'name': name,
        'start': start,
        'end': end,
        'zIndex': zIndex,
        'sourcePath': sourcePath,
        'text': text,
        'visible': visible,
        'keyframes': keyframes.map((frame) => frame.toJson()).toList(),
      };

  factory TimelineLayer.fromJson(Map<String, dynamic> json) {
    final frames = (json['keyframes'] as List<dynamic>? ?? const [])
        .map(
          (value) => TransformKeyframe.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList();

    return TimelineLayer(
      id: json['id'] as String? ?? '',
      trackId: json['trackId'] as String? ?? '',
      type: _readEnum(
        TimelineLayerType.values,
        json['type'],
        TimelineLayerType.sourceVideo,
      ),
      name: json['name'] as String? ?? '',
      start: _readNumber(json['start'], 0),
      end: _readNumber(json['end'], 0),
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      sourcePath: json['sourcePath'] as String?,
      text: json['text'] as String?,
      visible: json['visible'] as bool? ?? true,
      keyframes: frames,
    );
  }
}

/// A named row in the Studio timeline.
class TimelineTrack {
  final String id;
  final String name;
  final TimelineTrackType type;
  final int order;
  final List<TimelineLayer> layers;

  TimelineTrack({
    required this.id,
    required this.name,
    required this.type,
    required this.order,
    List<TimelineLayer> layers = const [],
  }) : layers = List.unmodifiable(layers);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'order': order,
        'layers': layers.map((layer) => layer.toJson()).toList(),
      };

  factory TimelineTrack.fromJson(Map<String, dynamic> json) {
    final layers = (json['layers'] as List<dynamic>? ?? const [])
        .map(
          (value) => TimelineLayer.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList();

    return TimelineTrack(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: _readEnum(
        TimelineTrackType.values,
        json['type'],
        TimelineTrackType.video,
      ),
      order: (json['order'] as num?)?.toInt() ?? 0,
      layers: layers,
    );
  }
}

/// Serializable edit plan shared by the renderer and the future timeline UI.
class TimelineProject {
  final String id;
  final double duration;
  final int width;
  final int height;
  final double frameRate;
  final List<TimelineTrack> tracks;

  TimelineProject({
    required this.id,
    required this.duration,
    required this.width,
    required this.height,
    this.frameRate = 30,
    List<TimelineTrack> tracks = const [],
  }) : tracks = List.unmodifiable(tracks);

  List<TimelineLayer> get layers {
    final result = tracks.expand((track) => track.layers).toList()
      ..sort((a, b) {
        final depth = a.zIndex.compareTo(b.zIndex);
        return depth != 0 ? depth : a.start.compareTo(b.start);
      });
    return result;
  }

  List<TimelineLayer> layersOfType(TimelineLayerType type) {
    final result = layers.where((layer) => layer.type == type).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  TimelineLayer? layerById(String layerId) {
    for (final layer in layers) {
      if (layer.id == layerId) return layer;
    }
    return null;
  }

  /// Returns every structural or timing problem found in this project.
  List<String> validate() {
    final errors = <String>[];

    if (id.trim().isEmpty) errors.add('Project id is empty.');
    if (!duration.isFinite || duration <= 0) {
      errors.add('Project duration must be greater than zero.');
    }
    if (width <= 0 || height <= 0) {
      errors.add('Project dimensions must be positive.');
    }
    if (!frameRate.isFinite || frameRate <= 0 || frameRate > 240) {
      errors.add('Project frame rate is invalid.');
    }

    final trackIds = <String>{};
    final layerIds = <String>{};

    for (final track in tracks) {
      if (track.id.trim().isEmpty || !trackIds.add(track.id)) {
        errors.add('Track id is empty or duplicated: ${track.id}.');
      }

      for (final layer in track.layers) {
        if (layer.id.trim().isEmpty || !layerIds.add(layer.id)) {
          errors.add('Layer id is empty or duplicated: ${layer.id}.');
        }
        if (layer.trackId != track.id) {
          errors.add('Layer ${layer.id} points to a different track.');
        }
        if (!layer.start.isFinite ||
            !layer.end.isFinite ||
            layer.start < 0 ||
            layer.end <= layer.start ||
            layer.end > duration + 0.000001) {
          errors.add('Layer ${layer.id} has an invalid time range.');
        }

        var previousTime = double.negativeInfinity;
        for (final frame in layer.keyframes) {
          if (!frame.time.isFinite ||
              frame.time < layer.start - 0.000001 ||
              frame.time > layer.end + 0.000001 ||
              frame.time <= previousTime) {
            errors.add(
              'Layer ${layer.id} has invalid keyframe ordering/time.',
            );
            break;
          }
          if (!frame.transform.isValid) {
            errors.add('Layer ${layer.id} has an invalid transform.');
            break;
          }
          previousTime = frame.time;
        }
      }
    }

    return errors;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'duration': duration,
        'width': width,
        'height': height,
        'frameRate': frameRate,
        'tracks': tracks.map((track) => track.toJson()).toList(),
      };

  factory TimelineProject.fromJson(Map<String, dynamic> json) {
    final tracks = (json['tracks'] as List<dynamic>? ?? const [])
        .map(
          (value) => TimelineTrack.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        )
        .toList();

    return TimelineProject(
      id: json['id'] as String? ?? '',
      duration: _readNumber(json['duration'], 0),
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      frameRate: _readNumber(json['frameRate'], 30),
      tracks: tracks,
    );
  }
}

double _readNumber(Object? value, double fallback) =>
    value is num && value.isFinite ? value.toDouble() : fallback;

T _readEnum<T extends Enum>(List<T> values, Object? value, T fallback) {
  for (final option in values) {
    if (option.name == value) return option;
  }
  return fallback;
}
