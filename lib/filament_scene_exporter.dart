import 'dart:io';

import 'package:filament_renderer/filament_renderer.dart';

import 'silence_cutter.dart';

/// Captures the live native Filament scene and places it as a full-screen 3D
/// scene at the beginning of the selected clip. The rest of the original video
/// and its audio are preserved.
class FilamentSceneExporter {
  FilamentSceneExporter._();

  static Future<String> captureAndEncode({
    required int viewId,
    double durationSeconds = 4,
    int frameRate = 24,
    void Function(String message)? onStatus,
  }) async {
    final duration = durationSeconds.clamp(0.5, 8.0).toDouble();
    final fps = frameRate.clamp(12, 30).toInt();

    onStatus?.call('جاري التقاط إطارات مشهد 3D المتحرك...');
    final framesPath = await FilamentRenderer.captureFrames(
      viewId: viewId,
      durationSeconds: duration,
      frameRate: fps,
    );

    final framesDirectory = Directory(framesPath);
    if (!await framesDirectory.exists()) {
      throw FileSystemException('مجلد إطارات 3D غير موجود.', framesPath);
    }
    final frameFiles = await framesDirectory
        .list()
        .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.png'))
        .toList();
    if (frameFiles.length < 2) {
      throw FileSystemException('لم يتم التقاط إطارات كافية من محرك 3D.', framesPath);
    }

    final scenePath = '${framesDirectory.path}/filament_3d_scene.mp4';
    final command =
        '-y -framerate $fps -start_number 0 '
        '-i "${framesDirectory.path}/frame_%05d.png" '
        '-vf "scale=1280:1280:force_original_aspect_ratio=decrease,'
        'pad=1280:1280:(ow-iw)/2:(oh-ih)/2:color=0x101521,'
        'setsar=1,format=yuv420p" '
        '-an -c:v libx264 -preset veryfast -crf 18 '
        '-r $fps -t ${duration.toStringAsFixed(2)} '
        '-movflags +faststart "$scenePath"';

    onStatus?.call('جاري ترميز مشهد 3D...');
    final encoded = await SilenceCutter.encode(command, duration, null);
    final sceneFile = File(scenePath);
    if (!encoded || !await sceneFile.exists() || await sceneFile.length() < 2048) {
      throw FileSystemException('فشل إنشاء فيديو مشهد 3D.', scenePath);
    }
    await _deletePngFrames(framesDirectory);
    onStatus?.call('تم تجهيز فيديو 3D.');
    return scenePath;
  }

  /// Replaces the opening interval with the full-frame 3D scene, then returns
  /// to the source video. The original audio remains continuous and unchanged.
  static Future<String> compositeOverVideo({
    required String videoPath,
    required String scenePath,
    void Function(String message)? onStatus,
  }) async {
    final sourceFile = File(videoPath);
    final sceneFile = File(scenePath);
    if (!await sourceFile.exists()) throw FileSystemException('الفيديو الأصلي غير موجود.', videoPath);
    if (!await sceneFile.exists() || await sceneFile.length() < 2048) {
      throw FileSystemException('فيديو مشهد 3D غير صالح.', scenePath);
    }

    final info = await SilenceCutter.probe(videoPath);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${sourceFile.parent.path}/wad_alreda_3d_scene_$stamp.mp4';
    final command =
        '-y -i "$videoPath" -i "$scenePath" '
        '-filter_complex "'
        '[1:v]scale=${info.w}:${info.h}:force_original_aspect_ratio=increase,'
        'crop=${info.w}:${info.h},setsar=1[scene];'
        '[0:v][scene]overlay=x=0:y=0:eof_action=pass:repeatlast=0,'
        'format=yuv420p[vout]" '
        '-map "[vout]" -map "0:a?" '
        '-c:v libx264 -preset veryfast -crf 19 -pix_fmt yuv420p '
        '-c:a aac -b:a 192k -movflags +faststart "$outputPath"';

    onStatus?.call('جاري تركيب المشهد ثلاثي الأبعاد بكامل الشاشة...');
    final encoded = await SilenceCutter.encode(command, 0, null);
    final outputFile = File(outputPath);
    if (!encoded || !await outputFile.exists() || await outputFile.length() < 4096) {
      throw FileSystemException('فشل دمج مشهد 3D مع الفيديو الأصلي.', outputPath);
    }
    onStatus?.call('تم دمج مشهد 3D بكامل الشاشة مع المحافظة على صوت الفيديو.');
    return outputPath;
  }

  static Future<void> _deletePngFrames(Directory directory) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
