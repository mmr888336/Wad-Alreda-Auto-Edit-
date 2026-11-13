import 'dart:io';

import 'package:filament_renderer/filament_renderer.dart';

import 'silence_cutter.dart';

/// Converts a captured Filament preview into MP4 and composites it over a video.
class FilamentSceneExporter {
  FilamentSceneExporter._();

  static Future<String> captureAndEncode({
    required int viewId,
    double durationSeconds = 3,
    int frameRate = 24,
    void Function(String message)? onStatus,
  }) async {
    onStatus?.call('جاري التقاط إطارات مشهد 3D...');
    final framesPath = await FilamentRenderer.captureFrames(
      viewId: viewId,
      durationSeconds: durationSeconds,
      frameRate: frameRate,
    );
    final folder = Directory(framesPath);
    if (!await folder.exists()) {
      throw FileSystemException('لم يتم العثور على مجلد إطارات 3D.', framesPath);
    }

    final scenePath = '${folder.path}/filament_3d_scene.mp4';
    final fps = frameRate.clamp(12, 30);
    final duration = durationSeconds.clamp(0.5, 8.0);
    final command =
        '-y -framerate $fps -i "${folder.path}/frame_%05d.png" '
        '-vf "scale=640:640:force_original_aspect_ratio=decrease,'
        'pad=640:640:(ow-iw)/2:(oh-ih)/2:color=0x101521,format=yuv420p" '
        '-an -c:v libx264 -preset veryfast -crf 18 -r $fps '
        '-t ${duration.toStringAsFixed(2)} -movflags +faststart "$scenePath"';

    onStatus?.call('جاري تحويل إطارات 3D إلى فيديو...');
    final encoded = await SilenceCutter.encode(command, duration, null);
    final output = File(scenePath);
    if (!encoded || !await output.exists() || await output.length() < 2048) {
      throw FileSystemException('فشل إنشاء فيديو مشهد 3D.', scenePath);
    }

    await for (final entity in folder.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    onStatus?.call('تم تجهيز فيديو مشهد 3D.');
    return scenePath;
  }

  /// Adds the 3D scene as a compact picture-in-picture layer over the source.
  static Future<String> compositeOverVideo({
    required String videoPath,
    required String scenePath,
    void Function(String message)? onStatus,
  }) async {
    final source = File(videoPath);
    final scene = File(scenePath);
    if (!await source.exists()) {
      throw FileSystemException('ملف الفيديو الأصلي غير موجود.', videoPath);
    }
    if (!await scene.exists()) {
      throw FileSystemException('ملف مشهد 3D غير موجود.', scenePath);
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${Directory.systemTemp.path}/wad_alreda_3d_$stamp.mp4';
    const boxSize = 360;
    const margin = 24;
    final command =
        '-y -i "$videoPath" -i "$scenePath" '
        '-filter_complex "'
        '[1:v]scale=$boxSize:$boxSize:force_original_aspect_ratio=decrease,'
        'pad=$boxSize:$boxSize:(ow-iw)/2:(oh-ih)/2:color=0x101521,'
        'setsar=1,drawbox=x=0:y=0:w=iw:h=ih:color=0x9A7BFF@0.95:t=4[scene];'
        '[0:v][scene]overlay=x=main_w-overlay_w-$margin:y=$margin:'
        'eof_action=pass:repeatlast=0,format=yuv420p[vout]" '
        '-map "[vout]" -map "0:a?" '
        '-c:v libx264 -preset veryfast -crf 19 -pix_fmt yuv420p '
        '-c:a aac -b:a 192k -movflags +faststart "$outputPath"';

    onStatus?.call('جاري دمج مشهد 3D فوق الفيديو الأصلي...');
    final ok = await SilenceCutter.encode(command, 0, null);
    final result = File(outputPath);
    if (!ok || !await result.exists() || await result.length() < 4096) {
      throw FileSystemException('فشل تركيب مشهد 3D على الفيديو.', outputPath);
    }
    onStatus?.call('تم تصدير الفيديو مع طبقة 3D.');
    return outputPath;
  }
}
