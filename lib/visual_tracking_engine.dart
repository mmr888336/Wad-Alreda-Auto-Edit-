import 'dart:math' as math;

import 'person_tracker.dart';
import 'person_tracking_models.dart';

/// One sampled video frame stored on disk.
class PersonFrame {
  final int index;

  /// Time of the frame in the source video, in seconds.
  final double time;
  final String path;
  final int width;
  final int height;

  const PersonFrame({
    required this.index,
    required this.time,
    required this.path,
    required this.width,
    required this.height,
  });
}

/// Finds people in a single frame. Implementations wrap a native model; the
/// tracking engine only depends on this interface, so a multi-person detector
/// can replace the single-person one without changing the engine.
abstract class PersonDetector {
  Future<List<PersonDetection>> detect(PersonFrame frame);

  Future<void> dispose();
}

class ImageSize {
  final int width;
  final int height;

  const ImageSize(this.width, this.height);
}

class TrackingConfig {
  /// Frames analyzed per second of video.
  final double sampleFps;

  /// Width of the analysis frames in pixels.
  final int frameWidth;

  /// Only the first [maxSeconds] of the video are analyzed.
  final double maxSeconds;

  /// Hard limit on the number of analyzed frames.
  final int maxFrames;

  final PersonTrackerConfig tracker;

  const TrackingConfig({
    this.sampleFps = 8,
    this.frameWidth = 480,
    this.maxSeconds = 60,
    this.maxFrames = 600,
    this.tracker = const PersonTrackerConfig(),
  });
}

/// Visual tracking core: frame sampling commands, frame helpers and the
/// detection -> tracking -> main-subject pipeline. Pure Dart apart from the
/// injected [PersonDetector], so it can be unit tested without a device.
class VisualTrackingEngine {
  VisualTrackingEngine._();

  /// Builds an FFmpeg command that writes sampled, upright JPEG frames.
  ///
  /// [outputPattern] must contain a printf counter such as `frame_%05d.jpg`.
  static String buildFrameExtractionCommand({
    required String videoPath,
    required String outputPattern,
    double fps = 8,
    int width = 480,
    double maxSeconds = 60,
    int maxFrames = 600,
  }) {
    if (videoPath.trim().isEmpty) {
      throw ArgumentError.value(videoPath, 'videoPath', 'Path cannot be empty.');
    }
    if (outputPattern.trim().isEmpty) {
      throw ArgumentError.value(
        outputPattern,
        'outputPattern',
        'Pattern cannot be empty.',
      );
    }
    if (!fps.isFinite || fps <= 0 || fps > 30) {
      throw ArgumentError.value(fps, 'fps', 'FPS must be above 0 and at most 30.');
    }
    if (width < 64 || width > 1920) {
      throw ArgumentError.value(width, 'width', 'Width must be 64..1920.');
    }
    if (!maxSeconds.isFinite || maxSeconds <= 0) {
      throw ArgumentError.value(maxSeconds, 'maxSeconds', 'Must be positive.');
    }
    if (maxFrames < 1) {
      throw ArgumentError.value(maxFrames, 'maxFrames', 'Must be positive.');
    }

    final safeVideo = videoPath.replaceAll('"', r'\"');
    final safeOutput = outputPattern.replaceAll('"', r'\"');
    final evenWidth = width.isEven ? width : width - 1;

    return '-y -hide_banner -i "$safeVideo" -an '
        '-t ${maxSeconds.toStringAsFixed(2)} '
        '-vf "fps=${fps.toStringAsFixed(2)},'
        'scale=$evenWidth:-2:flags=bilinear" '
        '-frames:v $maxFrames -q:v 4 -start_number 0 "$safeOutput"';
  }

  /// Time of the sampled frame with zero-based [index].
  static double frameTime(int index, double fps) => index / fps;

  /// Reads the duration from FFmpeg `-i` log text, or null when unknown.
  static double? parseDurationSeconds(String logs) {
    final match = RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)')
        .firstMatch(logs);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 3600 +
        int.parse(match.group(2)!) * 60 +
        double.parse(match.group(3)!);
  }

  /// Reads the pixel size from JPEG header bytes, or null when not a JPEG.
  static ImageSize? readJpegSize(List<int> bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

    var i = 2;
    while (i + 3 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      // Markers that carry no length field.
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (marker == 0xD9) return null;

      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      if (length < 2) return null;

      final isStartOfFrame = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isStartOfFrame) {
        if (i + 8 >= bytes.length) return null;
        final height = (bytes[i + 5] << 8) | bytes[i + 6];
        final width = (bytes[i + 7] << 8) | bytes[i + 8];
        if (width <= 0 || height <= 0) return null;
        return ImageSize(width, height);
      }
      i += 2 + length;
    }
    return null;
  }

  /// Picks the main subject: the track that is present most of the time, large
  /// in the frame and close to the center.
  static PersonTrack? choosePrimaryTrack(
    List<PersonTrack> tracks, {
    required int frameCount,
  }) {
    PersonTrack? best;
    var bestScore = -1.0;
    for (final track in tracks) {
      if (track.observations.isEmpty) continue;
      final presence = frameCount <= 0
          ? 0.0
          : (track.observations.length / frameCount).clamp(0.0, 1.0).toDouble();
      final area = track.averageBoxArea.clamp(0.0, 1.0).toDouble();
      final centrality =
          (1 - math.min(1.0, track.averageCenterOffset * 2)).clamp(0.0, 1.0);
      final score = presence * 0.5 + area * 0.3 + centrality * 0.2;
      if (score > bestScore) {
        bestScore = score;
        best = track;
      }
    }
    return best;
  }

  /// Runs the detector on every frame, tracks the people and selects the main
  /// subject. A frame where the detector throws counts as "nobody found"; the
  /// run only fails when the detector fails on every frame.
  static Future<PersonTrackingResult> analyzeFrames({
    required List<PersonFrame> frames,
    required PersonDetector detector,
    TrackingConfig config = const TrackingConfig(),
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (frames.isEmpty) {
      throw ArgumentError.value(frames, 'frames', 'At least one frame is needed.');
    }

    final tracker = PersonTracker(config: config.tracker);
    var failed = 0;
    String? firstError;

    for (var i = 0; i < frames.length; i++) {
      if (isCancelled?.call() ?? false) {
        throw StateError('تم إلغاء التحليل.');
      }

      final frame = frames[i];
      var detections = const <PersonDetection>[];
      try {
        detections = await detector.detect(frame);
      } catch (error) {
        failed++;
        firstError ??= error.toString();
      }

      tracker.update(frame.time, detections);
      onProgress?.call((i + 1) / frames.length);
    }

    if (failed == frames.length) {
      throw StateError('فشل اكتشاف الأشخاص في كل الإطارات: $firstError');
    }

    final tracks = tracker.finish();
    final primary = choosePrimaryTrack(tracks, frameCount: frames.length);

    final notes = <String>[];
    if (failed > 0) {
      notes.add('تعذرت معالجة $failed إطار من ${frames.length}.');
    }
    if (primary == null) {
      notes.add('لم يتم اكتشاف أي شخص في الفيديو.');
    } else {
      final coverage = primary.observations.length / frames.length;
      if (coverage < 0.5) {
        notes.add(
          'الشخص ظاهر في أقل من نصف الإطارات؛ قد تكون الإضاءة ضعيفة أو الشخص بعيد أو مقطوع من الكادر.',
        );
      }
      if (tracks.length > 1) {
        notes.add(
          'تم اكتشاف ${tracks.length} مسارات؛ الاختيار التلقائي اعتمد المسار الأطول حضوراً والأكبر حجماً.',
        );
      }
    }

    return PersonTrackingResult(
      sampleFps: config.sampleFps,
      frameWidth: frames.first.width,
      frameHeight: frames.first.height,
      framesAnalyzed: frames.length,
      failedFrames: failed,
      tracks: tracks,
      primaryTrackId: primary?.id,
      notes: notes,
    );
  }
}
