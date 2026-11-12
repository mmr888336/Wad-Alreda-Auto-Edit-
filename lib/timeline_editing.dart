import 'timeline_engine.dart';

/// Safe, immutable editing operations for the Studio timeline.
///
/// The existing TimelineProject remains the single source of truth. Every
/// operation returns a new project and leaves the original project untouched.
class TimelineEditing {
  TimelineEditing._();

  static const double _timeEpsilon = 0.0001;

  static const Set<String> _supportedBrollExtensions = {
    'mp4',
    'm4v',
    'mov',
    'mkv',
    'webm',
    'avi',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
  };

  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
  };

  /// Moves a clip while preserving its duration and shifting its keyframes.
  ///
  /// The requested start is clamped to the project boundaries. Keyframes use
  /// absolute project time, so they must move by the same delta as the clip.
  static TimelineProject moveLayer({
    required TimelineProject project,
    required String layerId,
    required double newStart,
  }) {
    if (!newStart.isFinite) {
      throw ArgumentError.value(newStart, 'newStart', 'Time must be finite.');
    }

    final layer = _requireLayer(project, layerId);
    final latestStart = project.duration - layer.duration;
    final safeStart = newStart.clamp(0.0, latestStart).toDouble();
    final delta = safeStart - layer.start;

    if (delta.abs() <= _timeEpsilon) return project;

    final movedKeyframes = layer.keyframes.map((frame) {
      return TransformKeyframe(
        time: frame.time + delta,
        transform: frame.transform,
        easing: frame.easing,
      );
    }).toList();

    return _replaceLayer(
      project,
      layerId,
      _copyLayer(
        layer,
        start: safeStart,
        end: safeStart + layer.duration,
        keyframes: movedKeyframes,
      ),
    );
  }

  /// Trims the visible in/out points of a layer without extending its source.
  ///
  /// At least one frame must remain. Existing animation is sampled at the new
  /// boundaries so the trimmed clip keeps the same motion at its new edges.
  static TimelineProject trimLayer({
    required TimelineProject project,
    required String layerId,
    double? newStart,
    double? newEnd,
  }) {
    final layer = _requireLayer(project, layerId);
    final start = newStart ?? layer.start;
    final end = newEnd ?? layer.end;

    if (!start.isFinite || !end.isFinite) {
      throw ArgumentError('Trim times must be finite.');
    }
    if (start < layer.start - _timeEpsilon ||
        end > layer.end + _timeEpsilon) {
      throw ArgumentError('Trimming cannot extend a clip beyond its source.');
    }

    final minimumDuration = 1 / project.frameRate;
    if (end - start < minimumDuration - _timeEpsilon) {
      throw ArgumentError(
        'A clip must retain at least one frame after trimming.',
      );
    }

    if ((start - layer.start).abs() <= _timeEpsilon &&
        (end - layer.end).abs() <= _timeEpsilon) {
      return project;
    }

    final adjustedStart = start.clamp(layer.start, layer.end).toDouble();
    final adjustedEnd = end.clamp(adjustedStart, layer.end).toDouble();
    final keyframes = _trimKeyframes(
      layer,
      start: adjustedStart,
      end: adjustedEnd,
    );

    return _replaceLayer(
      project,
      layerId,
      _copyLayer(
        layer,
        start: adjustedStart,
        end: adjustedEnd,
        keyframes: keyframes,
      ),
    );
  }

  /// Replaces the media used by a B-roll layer with a video or still image.
  ///
  /// This only changes the source in the edit plan. ProjectStore copies the
  /// selected asset into the saved project when the user saves their edits.
  /// The export engine will consume the replacement in the following phase.
  static TimelineProject replaceBrollSource({
    required TimelineProject project,
    required String layerId,
    required String sourcePath,
    String? displayName,
  }) {
    final layer = _requireLayer(project, layerId);
    if (layer.type != TimelineLayerType.broll) {
      throw ArgumentError.value(
        layer.type,
        'layer.type',
        'Only B-roll layers can have their media source replaced.',
      );
    }

    final path = sourcePath.trim();
    if (path.isEmpty) {
      throw ArgumentError.value(sourcePath, 'sourcePath', 'Path is empty.');
    }

    final extension = _extension(path);
    if (!_supportedBrollExtensions.contains(extension)) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'Choose a supported video or image file.',
      );
    }

    final nextName = displayName?.trim();
    return _replaceLayer(
      project,
      layerId,
      _copyLayer(
        layer,
        sourcePath: path,
        name: nextName == null || nextName.isEmpty ? layer.name : nextName,
      ),
    );
  }

  /// Adds a keyframe or replaces the keyframe nearest to the same time.
  static TimelineProject setKeyframe({
    required TimelineProject project,
    required String layerId,
    required double time,
    required LayerTransform transform,
    KeyframeEasing? easing,
  }) {
    final layer = _requireLayer(project, layerId);
    if (!time.isFinite ||
        time < layer.start - _timeEpsilon ||
        time > layer.end + _timeEpsilon) {
      throw ArgumentError.value(
        time,
        'time',
        'Keyframe time must be inside the selected layer.',
      );
    }
    if (!transform.isValid) {
      throw ArgumentError.value(
        transform,
        'transform',
        'Transform values are outside their supported ranges.',
      );
    }

    final safeTime = time.clamp(layer.start, layer.end).toDouble();
    final frames = layer.keyframes.toList();
    final existingIndex = frames.indexWhere(
      (frame) => (frame.time - safeTime).abs() <= _timeEpsilon,
    );
    final nextFrame = TransformKeyframe(
      time: existingIndex >= 0 ? frames[existingIndex].time : safeTime,
      transform: transform,
      easing: easing ??
          (existingIndex >= 0
              ? frames[existingIndex].easing
              : KeyframeEasing.linear),
    );

    if (existingIndex >= 0) {
      frames[existingIndex] = nextFrame;
    } else {
      frames.add(nextFrame);
    }
    frames.sort((a, b) => a.time.compareTo(b.time));

    return _replaceLayer(
      project,
      layerId,
      _copyLayer(layer, keyframes: frames),
    );
  }

  /// Identifies common still-image formats for the renderer and editor UI.
  static bool isImageAssetPath(String path) =>
      _imageExtensions.contains(_extension(path));

  static String _extension(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static TimelineLayer _requireLayer(
    TimelineProject project,
    String layerId,
  ) {
    final layer = project.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'Layer was not found.');
    }
    return layer;
  }

  static TimelineProject _replaceLayer(
    TimelineProject project,
    String layerId,
    TimelineLayer replacement,
  ) {
    var found = false;
    final tracks = project.tracks.map((track) {
      final layers = track.layers.map((layer) {
        if (layer.id != layerId) return layer;
        found = true;
        if (replacement.trackId != track.id) {
          throw StateError('An edit cannot move a layer to another track.');
        }
        return replacement;
      }).toList();

      return TimelineTrack(
        id: track.id,
        name: track.name,
        type: track.type,
        order: track.order,
        layers: layers,
      );
    }).toList();

    if (!found) {
      throw ArgumentError.value(layerId, 'layerId', 'Layer was not found.');
    }

    final updated = TimelineProject(
      id: project.id,
      duration: project.duration,
      width: project.width,
      height: project.height,
      frameRate: project.frameRate,
      tracks: tracks,
    );
    final errors = updated.validate();
    if (errors.isNotEmpty) {
      throw StateError('Timeline edit is invalid: ${errors.first}');
    }
    return updated;
  }

  static TimelineLayer _copyLayer(
    TimelineLayer layer, {
    double? start,
    double? end,
    String? sourcePath,
    String? name,
    List<TransformKeyframe>? keyframes,
  }) {
    return TimelineLayer(
      id: layer.id,
      trackId: layer.trackId,
      type: layer.type,
      name: name ?? layer.name,
      start: start ?? layer.start,
      end: end ?? layer.end,
      zIndex: layer.zIndex,
      sourcePath: sourcePath ?? layer.sourcePath,
      text: layer.text,
      visible: layer.visible,
      keyframes: keyframes ?? layer.keyframes,
    );
  }

  static List<TransformKeyframe> _trimKeyframes(
    TimelineLayer layer, {
    required double start,
    required double end,
  }) {
    if (layer.keyframes.isEmpty) return const [];

    TransformKeyframe boundary(double time) {
      for (final frame in layer.keyframes) {
        if ((frame.time - time).abs() <= _timeEpsilon) {
          return TransformKeyframe(
            time: time,
            transform: frame.transform,
            easing: frame.easing,
          );
        }
      }
      return TransformKeyframe(
        time: time,
        transform: layer.transformAt(time),
      );
    }

    final result = <TransformKeyframe>[boundary(start)];
    result.addAll(
      layer.keyframes.where(
        (frame) =>
            frame.time > start + _timeEpsilon &&
            frame.time < end - _timeEpsilon,
      ),
    );
    result.add(boundary(end));
    return result;
  }
}
