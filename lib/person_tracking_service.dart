import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'person_tracking_models.dart';
import 'visual_tracking_engine.dart';

/// Thrown when no [PersonDetector] backend is installed in this build.
class PersonDetectorUnavailable implements Exception {
  const PersonDetectorUnavailable();

  @override
  String toString() =>
      'كاشف الأشخاص غير مفعّل في هذه النسخة. تم عزل مكتبة ML Kit مؤقتاً '
      'حتى يتأكد استقرار التطبيق مع محرك Filament.';
}

/// Result of analyzing one video, plus the sampled frames when they were kept
/// for preview.
class PersonTrackingRun {
  final PersonTrackingResult result;

  /// Sampled frames. Empty unless the run was started with `keepFrames`.
  final List<PersonFrame> frames;
  final String? framesDirectory;

  const PersonTrackingRun({
    required this.result,
    this.frames = const <PersonFrame>[],
    this.framesDirectory,
  });

  /// Deletes the kept frames from disk.
  void deleteFramesSync() {
    final path = framesDirectory;
    if (path == null) return;
    try {
      final directory = Directory(path);
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Samples frames from a video with FFmpeg and runs the tracking engine.
///
/// The detector backend is injected: pass a [PersonDetector] to
/// [analyzeVideo], or register one in [detectorFactory]. No native detector
/// is bundled in the app by default.
class PersonTrackingService {
  PersonTrackingService._();

  /// Creates the default detector when [analyzeVideo] gets none. Null means
  /// that no detector backend is installed in this build.
  static PersonDetector Function()? detectorFactory;

  static bool get hasDetector => detectorFactory != null;

  static String _tail(String value) =>
      value.length > 500 ? value.substring(value.length - 500) : value;

  static Future<PersonTrackingRun> analyzeVideo(
    String videoPath, {
    TrackingConfig config = const TrackingConfig(),
    PersonDetector? detector,
    bool keepFrames = false,
    void Function(String message)? onStatus,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final factory = detectorFactory;
    if (detector == null && factory == null) {
      throw const PersonDetectorUnavailable();
    }

    if (!await File(videoPath).exists()) {
      throw FileSystemException('ملف الفيديو غير موجود.', videoPath);
    }

    final temp = await getTemporaryDirectory();
    final directory = Directory(
      '${temp.path}/person_tracking_${DateTime.now().millisecondsSinceEpoch}',
    );
    await directory.create(recursive: true);

    PersonDetector? created;
    var keep = false;

    try {
      onStatus?.call('جاري استخراج إطارات التحليل من الفيديو...');

      final command = VisualTrackingEngine.buildFrameExtractionCommand(
        videoPath: videoPath,
        outputPattern: '${directory.path}/frame_%05d.jpg',
        fps: config.sampleFps,
        width: config.frameWidth,
        maxSeconds: config.maxSeconds,
        maxFrames: config.maxFrames,
      );

      final session = await FFmpegKit.execute(command);
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code)) {
        final logs = await session.getAllLogsAsString() ?? '';
        throw Exception('فشل استخراج إطارات الفيديو.\n${_tail(logs)}');
      }

      if (isCancelled?.call() ?? false) {
        throw StateError('تم إلغاء التحليل.');
      }

      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.jpg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      if (files.isEmpty) {
        throw Exception('لم يتم استخراج أي إطار من الفيديو.');
      }

      final size = VisualTrackingEngine.readJpegSize(
        await files.first.readAsBytes(),
      );
      if (size == null) {
        throw Exception('تعذر قراءة أبعاد إطارات التحليل.');
      }

      final frames = <PersonFrame>[
        for (var i = 0; i < files.length; i++)
          PersonFrame(
            index: i,
            time: VisualTrackingEngine.frameTime(i, config.sampleFps),
            path: files[i].path,
            width: size.width,
            height: size.height,
          ),
      ];

      final PersonDetector active = detector ?? (created = factory!());

      onStatus?.call(
        'جاري اكتشاف الأشخاص وتتبعهم (${frames.length} إطار)...',
      );

      final result = await VisualTrackingEngine.analyzeFrames(
        frames: frames,
        detector: active,
        config: config,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );

      keep = keepFrames;
      return PersonTrackingRun(
        result: result,
        frames: keepFrames ? frames : const <PersonFrame>[],
        framesDirectory: keepFrames ? directory.path : null,
      );
    } finally {
      try {
        await created?.dispose();
      } catch (_) {}

      if (!keep) {
        try {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        } catch (_) {}
      }
    }
  }
}
