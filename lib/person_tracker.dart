import 'dart:math' as math;

import 'person_tracking_models.dart';

/// Tuning values for [PersonTracker]. Times are in seconds; distances are in
/// normalized frame coordinates.
class PersonTrackerConfig {
  /// Detections below this confidence are ignored.
  final double minDetectionConfidence;

  /// A detection may join a track when its overlap with the predicted box is
  /// at least this high...
  final double minIou;

  /// ...or when its center is within this many box diagonals of the prediction.
  final double maxNormalizedDistance;

  /// A track that is not seen for longer than this is closed.
  final double maxMissSeconds;

  /// Weight of the new measurement when smoothing boxes (1 = no smoothing).
  final double boxSmoothing;

  /// Weight of the new measurement when smoothing landmarks.
  final double landmarkSmoothing;

  /// Landmarks below this confidence keep their previous position.
  final double minLandmarkConfidence;

  /// After a gap longer than this the new measurement is trusted fully.
  final double trustMeasurementAfterSeconds;

  /// Tracks with fewer observations are dropped as noise.
  final int minTrackObservations;

  /// Two track fragments may be joined when the gap between them is at most
  /// this long and they are close enough in space and size.
  final double stitchMaxGapSeconds;
  final double stitchMaxDistance;

  /// Limit for the estimated box speed, in frame widths per second.
  final double maxVelocity;

  const PersonTrackerConfig({
    this.minDetectionConfidence = 0.35,
    this.minIou = 0.10,
    this.maxNormalizedDistance = 0.5,
    this.maxMissSeconds = 0.9,
    this.boxSmoothing = 0.6,
    this.landmarkSmoothing = 0.55,
    this.minLandmarkConfidence = 0.3,
    this.trustMeasurementAfterSeconds = 0.5,
    this.minTrackObservations = 3,
    this.stitchMaxGapSeconds = 2.5,
    this.stitchMaxDistance = 0.3,
    this.maxVelocity = 1.5,
  });
}

class _TrackState {
  _TrackState(this.id);

  final int id;
  final List<PersonObservation> observations = <PersonObservation>[];
  double velocityX = 0;
  double velocityY = 0;

  PersonObservation get last => observations.last;
  double get lastTime => observations.last.time;

  /// Where the person is expected to be at [time], using the last velocity.
  NormalizedRect predictBox(double time, double maxSeconds) {
    final dt = (time - lastTime).clamp(0.0, maxSeconds).toDouble();
    return last.box.shifted(velocityX * dt, velocityY * dt);
  }

  void add(double time, PersonDetection detection, PersonTrackerConfig config) {
    if (observations.isEmpty) {
      observations.add(
        PersonObservation(
          time: time,
          box: detection.box,
          confidence: detection.confidence,
          landmarks: Map<BodyLandmark, LandmarkPoint>.of(detection.landmarks),
        ),
      );
      return;
    }

    final previous = observations.last;
    final dt = time - previous.time;
    final longGap = dt > config.trustMeasurementAfterSeconds;
    final boxWeight = longGap ? 1.0 : config.boxSmoothing;
    final landmarkWeight = longGap ? 1.0 : config.landmarkSmoothing;

    final box = previous.box.lerp(detection.box, boxWeight);

    final landmarks = <BodyLandmark, LandmarkPoint>{};
    detection.landmarks.forEach((type, measured) {
      final old = previous.landmarks[type];
      if (old == null) {
        landmarks[type] = measured;
        return;
      }
      if (measured.confidence < config.minLandmarkConfidence) {
        // Unreliable measurement: hold the last good position.
        landmarks[type] = LandmarkPoint(
          x: old.x,
          y: old.y,
          z: old.z,
          confidence: measured.confidence,
        );
        return;
      }
      final weight =
          old.confidence < config.minLandmarkConfidence ? 1.0 : landmarkWeight;
      landmarks[type] = old.lerp(measured, weight);
    });

    if (dt > 1e-6) {
      final vx = (box.centerX - previous.box.centerX) / dt;
      final vy = (box.centerY - previous.box.centerY) / dt;
      velocityX = (velocityX * 0.5 + vx * 0.5)
          .clamp(-config.maxVelocity, config.maxVelocity)
          .toDouble();
      velocityY = (velocityY * 0.5 + vy * 0.5)
          .clamp(-config.maxVelocity, config.maxVelocity)
          .toDouble();
    }

    observations.add(
      PersonObservation(
        time: time,
        box: box,
        confidence: detection.confidence,
        landmarks: landmarks,
      ),
    );
  }
}

class _Candidate {
  final int trackIndex;
  final int detectionIndex;
  final double score;

  const _Candidate(this.trackIndex, this.detectionIndex, this.score);
}

/// Online multi-person tracker.
///
/// Feed detections frame by frame with [update], then call [finish] to get the
/// tracks. Detections are matched to existing tracks by overlap and distance
/// from a motion-predicted box; boxes and landmarks are smoothed; short gaps
/// are bridged; and fragments of the same person separated by a longer gap
/// are stitched back together.
class PersonTracker {
  PersonTracker({this.config = const PersonTrackerConfig()});

  final PersonTrackerConfig config;
  final List<_TrackState> _active = <_TrackState>[];
  final List<_TrackState> _closed = <_TrackState>[];
  int _nextId = 1;
  double? _lastTime;

  int get activeTrackCount => _active.length;

  void update(double time, List<PersonDetection> detections) {
    if (!time.isFinite) {
      throw ArgumentError.value(time, 'time', 'Time must be finite.');
    }
    final previousTime = _lastTime;
    if (previousTime != null && time <= previousTime) {
      throw ArgumentError.value(
        time,
        'time',
        'Frame times must be strictly increasing.',
      );
    }
    _lastTime = time;

    for (final state in List<_TrackState>.of(_active)) {
      if (time - state.lastTime > config.maxMissSeconds) {
        _active.remove(state);
        _closed.add(state);
      }
    }

    final valid = detections
        .where(
          (detection) =>
              detection.confidence >= config.minDetectionConfidence &&
              detection.box.isValid,
        )
        .toList();

    final candidates = <_Candidate>[];
    for (var t = 0; t < _active.length; t++) {
      final predicted = _active[t].predictBox(time, config.maxMissSeconds);
      final diagonal = math.max(0.05, predicted.diagonal);
      for (var d = 0; d < valid.length; d++) {
        final box = valid[d].box;
        final iou = predicted.iou(box);
        final distance = predicted.centerDistance(box) / diagonal;
        if (iou < config.minIou && distance > config.maxNormalizedDistance) {
          continue;
        }
        final score = iou + 0.5 * (1 - math.min(1.0, distance));
        candidates.add(_Candidate(t, d, score));
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));

    final usedTracks = <int>{};
    final usedDetections = <int>{};
    for (final candidate in candidates) {
      if (usedTracks.contains(candidate.trackIndex) ||
          usedDetections.contains(candidate.detectionIndex)) {
        continue;
      }
      usedTracks.add(candidate.trackIndex);
      usedDetections.add(candidate.detectionIndex);
      _active[candidate.trackIndex].add(
        time,
        valid[candidate.detectionIndex],
        config,
      );
    }

    for (var d = 0; d < valid.length; d++) {
      if (usedDetections.contains(d)) continue;
      final state = _TrackState(_nextId++);
      state.add(time, valid[d], config);
      _active.add(state);
    }
  }

  /// Closes every track and returns the final, stitched tracks sorted by id.
  /// The tracker is empty afterwards.
  List<PersonTrack> finish() {
    _closed.addAll(_active);
    _active.clear();

    final fragments = _closed
        .where((state) => state.observations.length >= config.minTrackObservations)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    _closed.clear();

    final stitched = _stitch(fragments);
    stitched.sort((a, b) => a.id.compareTo(b.id));

    return stitched
        .map(
          (state) => PersonTrack(
            id: state.id,
            observations: state.observations,
          ),
        )
        .toList();
  }

  List<_TrackState> _stitch(List<_TrackState> fragments) {
    final working = List<_TrackState>.of(fragments);
    var merged = true;

    while (merged && working.length > 1) {
      merged = false;
      _TrackState? bestFirst;
      _TrackState? bestSecond;
      var bestScore = double.infinity;

      for (final first in working) {
        final firstLast = first.observations.last;
        for (final second in working) {
          if (identical(first, second)) continue;
          final secondFirst = second.observations.first;

          final gap = secondFirst.time - firstLast.time;
          if (gap <= 0 || gap > config.stitchMaxGapSeconds) continue;

          final distance = firstLast.box.centerDistance(secondFirst.box);
          if (distance > config.stitchMaxDistance) continue;

          final previousArea = math.max(firstLast.box.area, 1e-6);
          final ratio = secondFirst.box.area / previousArea;
          if (ratio < 0.4 || ratio > 2.5) continue;

          final score = gap + distance * 2;
          if (score < bestScore) {
            bestScore = score;
            bestFirst = first;
            bestSecond = second;
          }
        }
      }

      if (bestFirst != null && bestSecond != null) {
        bestFirst.observations.addAll(bestSecond.observations);
        working.remove(bestSecond);
        merged = true;
      }
    }

    return working;
  }
}
