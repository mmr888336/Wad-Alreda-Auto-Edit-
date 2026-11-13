import 'dart:io';
import 'dart:math' as math;

import 'package:filament_renderer/filament_renderer.dart';

import 'silence_cutter.dart';

/// One rendered 3D clip and its absolute position in the edited video.
class ThreeDSceneClip {
  final String path;
  final double start;
  final double end;

  const ThreeDSceneClip({
    required this.path,
    required this.start,
    required this.end,
  });

  double get duration => end - start;
}

/// Captures the live native Filament scene and exports it as an MP4 clip.
///
/// This exporter keeps the previous full-frame opening-scene API for the
/// manual test page, and adds multi-scene timeline compositing for AutoEdit.
class FilamentSceneExporter {
  FilamentSceneExporter._();

  static String _f(double value) => value.toStringAsFixed(3);

  static int _even(int value) =>
      value.isEven ? value : value - 1;

  static Future<String> captureAndEncode({
    required int viewId,
    double durationSeconds = 4,
    int frameRate = 24,
    int width = 720,
    int height = 720,
    void Function(String message)? onStatus,
  }) async {
    final duration =
        durationSeconds.clamp(0.5, 8.0).toDouble();

    final fps = frameRate.clamp(12, 30).toInt();

    final outWidth = _even(
      width.clamp(240, 1920).toInt(),
    );

    final outHeight = _even(
      height.clamp(240, 1920).toInt(),
    );

    onStatus?.call(
      'جاري التقاط إطارات مشهد 3D المتحرك...',
    );

    final framesPath = await FilamentRenderer.captureFrames(
      viewId: viewId,
      durationSeconds: duration,
      frameRate: fps,
    );

    final framesDirectory = Directory(framesPath);

    if (!await framesDirectory.exists()) {
      throw FileSystemException(
        'مجلد إطارات 3D غير موجود.',
        framesPath,
      );
    }

    final frameFiles = await framesDirectory
        .list()
        .where(
          (entity) =>
              entity is File &&
              entity.path.toLowerCase().endsWith('.png'),
        )
        .toList();

    if (frameFiles.length < 2) {
      throw FileSystemException(
        'لم يتم التقاط إطارات كافية من محرك 3D.',
        framesPath,
      );
    }

    final scenePath =
        '${framesDirectory.path}/filament_3d_scene.mp4';

    final command =
        '-y -framerate $fps -start_number 0 '
        '-i "${framesDirectory.path}/frame_%05d.png" '
        '-vf "'
        'scale=$outWidth:$outHeight:'
        'force_original_aspect_ratio=decrease:flags=lanczos,'
        'pad=$outWidth:$outHeight:(ow-iw)/2:(oh-ih)/2:'
        'color=0x101521,'
        'setsar=1,'
        'format=yuv420p'
        '" '
        '-an -c:v libx264 -preset veryfast -crf 18 '
        '-r $fps -t ${_f(duration)} '
        '-movflags +faststart "$scenePath"';

    onStatus?.call('جاري ترميز مشهد 3D...');

    final encoded = await SilenceCutter.encode(
      command,
      duration,
      null,
    );

    final sceneFile = File(scenePath);

    if (!encoded ||
        !await sceneFile.exists() ||
        await sceneFile.length() < 2048) {
      throw FileSystemException(
        'فشل إنشاء فيديو مشهد 3D.',
        scenePath,
      );
    }

    await _deletePngFrames(framesDirectory);

    onStatus?.call('تم تجهيز فيديو 3D.');

    return scenePath;
  }

  /// Composites each 3D scene at its actual timeline start and end.
  ///
  /// The 3D scene is presented as a picture-in-picture panel. This preserves
  /// the captions, title graphics, B-roll and original audio already rendered
  /// by Enhancer.
  static Future<String> compositeScenesOverVideo({
    required String videoPath,
    required List<ThreeDSceneClip> scenes,
    required double duration,
    bool maximumQuality = true,
    void Function(String message)? onStatus,
  }) async {
    final sourceFile = File(videoPath);

    if (!await sourceFile.exists()) {
      throw FileSystemException(
        'الفيديو الأصلي غير موجود.',
        videoPath,
      );
    }

    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Video duration must be greater than zero.',
      );
    }

    if (scenes.isEmpty) {
      throw ArgumentError(
        'لا توجد مشاهد 3D لتركيبها.',
      );
    }

    final info = await SilenceCutter.probe(videoPath);

    if (info.w < 2 || info.h < 2) {
      throw StateError(
        'أبعاد الفيديو الأصلي غير صالحة.',
      );
    }

    final shortEdge = math.min(info.w, info.h);

    final cardSide = _even(
      (shortEdge * 0.46)
          .round()
          .clamp(120, 720)
          .toInt(),
    );

    final margin = math.max(
      8,
      (info.w * 0.035).round(),
    );

    final positionX = 'main_w-overlay_w-$margin';
    const positionY = '(main_h-overlay_h)/2';

    final validScenes = <ThreeDSceneClip>[];

    for (final scene in scenes) {
      final file = File(scene.path);

      if (!await file.exists() ||
          await file.length() < 2048) {
        continue;
      }

      final start =
          scene.start.clamp(0.0, duration).toDouble();

      final end =
          scene.end.clamp(0.0, duration).toDouble();

      if (!start.isFinite ||
          !end.isFinite ||
          end - start < 0.5) {
        continue;
      }

      validScenes.add(
        ThreeDSceneClip(
          path: scene.path,
          start: start,
          end: end,
        ),
      );
    }

    if (validScenes.isEmpty) {
      throw StateError(
        'كل ملفات مشاهد 3D غير صالحة أو خارج مدة الفيديو.',
      );
    }

    validScenes.sort(
      (a, b) => a.start.compareTo(b.start),
    );

    final stamp = DateTime.now().millisecondsSinceEpoch;

    final outputPath =
        '${sourceFile.parent.path}/3d_composite_$stamp.mp4';

    final inputs = <String>[
      '-i "$videoPath"',
    ];

    final chains = <String>[
      '[0:v]scale=${info.w}:${info.h}:flags=lanczos,setsar=1[base0]',
    ];

    var current = 'base0';

    for (var index = 0;
        index < validScenes.length;
        index++) {
      final scene = validScenes[index];
      final inputIndex = index + 1;

      inputs.add('-i "${scene.path}"');

      final sceneLabel = 'three_d_scene_$index';
      final outputLabel = 'three_d_composite_$index';

      final start = _f(scene.start);
      final end = _f(scene.end);

      chains.add(
        '[$inputIndex:v]'
        'setpts=PTS-STARTPTS+$start/TB,'
        'scale=$cardSide:$cardSide:'
        'force_original_aspect_ratio=decrease:flags=lanczos,'
        'pad=$cardSide:$cardSide:'
        '(ow-iw)/2:(oh-ih)/2:color=0x101521,'
        'setsar=1,'
        'drawbox=x=0:y=0:w=iw:h=ih:'
        'color=0xB69AFF@0.95:t=3'
        '[$sceneLabel]',
      );

      chains.add(
        '[$current][$sceneLabel]'
        'overlay='
        'x=$positionX:'
        'y=$positionY:'
        'eof_action=pass:'
        'repeatlast=0:'
        "enable='between(t,$start,$end)'"
        '[$outputLabel]',
      );

      current = outputLabel;
    }

    final videoEncoder = maximumQuality
        ? '-c:v libx264 -preset slow -crf 17'
        : '-c:v libx264 -preset veryfast -crf 20';

    final command =
        '-y ${inputs.join(' ')} '
        '-filter_complex "${chains.join(';')}" '
        '-map "[$current]" '
        '-map "0:a?" '
        '$videoEncoder '
        '-pix_fmt yuv420p '
        '-c:a aac -b:a 192k -ar 48000 '
        '-t ${_f(duration)} '
        '-movflags +faststart "$outputPath"';

    onStatus?.call(
      'جاري دمج ${validScenes.length} مشاهد 3D في التوقيتات المحددة...',
    );

    final encoded = await SilenceCutter.encode(
      command,
      duration,
      null,
    );

    final outputFile = File(outputPath);

    if (!encoded ||
        !await outputFile.exists() ||
        await outputFile.length() < 4096) {
      throw FileSystemException(
        'فشل دمج مشاهد 3D مع الفيديو الأصلي.',
        outputPath,
      );
    }

    onStatus?.call(
      'اكتمل تركيب مشاهد 3D داخل الفيديو.',
    );

    return outputPath;
  }

  /// Legacy full-frame opening-scene method retained for FilamentTestPage.
  static Future<String> compositeOverVideo({
    required String videoPath,
    required String scenePath,
    void Function(String message)? onStatus,
  }) async {
    final sourceFile = File(videoPath);
    final sceneFile = File(scenePath);

    if (!await sourceFile.exists()) {
      throw FileSystemException(
        'الفيديو الأصلي غير موجود.',
        videoPath,
      );
    }

    if (!await sceneFile.exists() ||
        await sceneFile.length() < 2048) {
      throw FileSystemException(
        'فيديو مشهد 3D غير صالح.',
        scenePath,
      );
    }

    final info = await SilenceCutter.probe(videoPath);

    final stamp = DateTime.now().millisecondsSinceEpoch;

    final outputPath =
        '${sourceFile.parent.path}/wad_alreda_3d_scene_$stamp.mp4';

    final command =
        '-y -i "$videoPath" -i "$scenePath" '
        '-filter_complex "'
        '[1:v]scale=${info.w}:${info.h}:'
        'force_original_aspect_ratio=increase,'
        'crop=${info.w}:${info.h},setsar=1[scene];'
        '[0:v][scene]'
        'overlay=x=0:y=0:'
        'eof_action=pass:repeatlast=0,'
        'format=yuv420p[vout]'
        '" '
        '-map "[vout]" '
        '-map "0:a?" '
        '-c:v libx264 -preset veryfast -crf 19 '
        '-pix_fmt yuv420p '
        '-c:a aac -b:a 192k '
        '-movflags +faststart "$outputPath"';

    onStatus?.call(
      'جاري تركيب مشهد 3D بكامل الشاشة...',
    );

    final encoded = await SilenceCutter.encode(
      command,
      0,
      null,
    );

    final outputFile = File(outputPath);

    if (!encoded ||
        !await outputFile.exists() ||
        await outputFile.length() < 4096) {
      throw FileSystemException(
        'فشل دمج مشهد 3D مع الفيديو الأصلي.',
        outputPath,
      );
    }

    onStatus?.call(
      'تم دمج مشهد 3D مع المحافظة على صوت الفيديو.',
    );

    return outputPath;
  }

  static Future<void> _deletePngFrames(
    Directory directory,
  ) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File &&
            entity.path.toLowerCase().endsWith('.png')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
