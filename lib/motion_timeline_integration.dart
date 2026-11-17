/// Pure helpers that connect the motion scene editor to the Studio timeline.
///
/// When the user edits a motion cutaway, the re-rendered clip is drawn over the
/// same time window of the exported video and the matching timeline layer is
/// updated. This file only decides *where* the clip goes and *what the new
/// timeline looks like*; it does no file or FFmpeg work, so it is easy to test.
library;

import 'dart:math' as math;

import 'timeline_editing.dart';
import 'timeline_engine.dart';

/// The part of the exported video that an edited motion cutaway replaces.
class MotionOverlayWindow {
  final double start;
  final double end;

  const MotionOverlayWindow(this.start, this.end);

  double get duration => end - start;
}

class MotionTimelineIntegration {
  MotionTimelineIntegration._();

  /// MotionReexport refuses windows shorter than this.
  static const double minimumWindow = 0.2;

  static const double _epsilon = 0.0001;

  /// Window of the exported video that a re-rendered clip of [clipDuration]
  /// seconds replaces. The clip is drawn starting at the layer's start, never
  /// past the layer's end. Returns null when the clip is unusable (not finite,
  /// zero length, or shorter than [minimumWindow]).
  static MotionOverlayWindow? overlayWindow(
    TimelineLayer layer,
    double clipDuration,
  ) {
    if (!clipDuration.isFinite || clipDuration <= 0) return null;
    final end = math.min(layer.end, layer.start + clipDuration).toDouble();
    if (end - layer.start < minimumWindow) return null;
    return MotionOverlayWindow(layer.start, end);
  }

  /// Returns [project] with layer [layerId] now pointing at the re-rendered
  /// clip at [clipPath]. When the new clip is shorter than the layer, the layer
  /// is trimmed to match so the timeline shows what the video really contains.
  ///
  /// Throws [ArgumentError] when the layer does not exist, is not a B-roll
  /// layer, or the clip is too short to use.
  static TimelineProject applyEditedClip({
    required TimelineProject project,
    required String layerId,
    required String clipPath,
    required double clipDuration,
  }) {
    final layer = project.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'Layer was not found.');
    }

    final window = overlayWindow(layer, clipDuration);
    if (window == null) {
      throw ArgumentError.value(
        clipDuration,
        'clipDuration',
        'The edited clip is too short or invalid.',
      );
    }

    var next = TimelineEditing.replaceBrollSource(
      project: project,
      layerId: layerId,
      sourcePath: clipPath,
    );

    if (window.end < layer.end - _epsilon) {
      next = TimelineEditing.trimLayer(
        project: next,
        layerId: layerId,
        newEnd: window.end,
      );
    }
    return next;
  }
}
