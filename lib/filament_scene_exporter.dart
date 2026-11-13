import 'dart:io';

import 'package:filament_renderer/filament_renderer.dart';

import 'silence_cutter.dart';

/// Converts frames captured from the native Filament view into MP4 and
/// composites that short 3D clip over the user's selected source video.
///
/// This file belongs to the main application at lib/ because it uses the
/// application's SilenceCutter/FFmpeg pipeline. It must NOT live inside the
/// standalone packages/filament_renderer package.
class FilamentSceneExporter {
  FilamentSceneExporter._();

  /// Captures the visible native Filament surface and encodes it as a silent MP4.
  static Future<String> captureAndEncode({
    required int viewId,
    double durationSeconds = 3,
    int frameRate = 24,
    void Function(String message)? onStatus,
  }) async {
    final duration = durationSeconds.clamp(0.5, 8.0).toDouble();
    final fps = frameRate.clamp(12, 30).toInt();

    onStatus?.call('جاري التقاط إطارات مشهد 3D...');
    final framesPath = await FilamentRenderer.captureFrames(
      viewId: viewId,
      durationSeconds: duration,
      frameRate: fps,
    );

    final framesDirectory = Directory(framesPath);
    if (!await framesDirectory.exists()) {
      throw FileSystemException(
        'لم يتم العثور على مجلد إطارات 3D.',
        framesPath,
      );
    }

    final frameFiles = await framesDirectory
        .list()
        .where((entity) =>
            entity is File && entity.path.toLowerCase().endsWith('.png'))
        .toList();
    if (frameFiles.length < 2) {
      throw FileSystemException(
        'لم يتم التقاط إطارات كافية من محرك 3D.',
        framesPath,
      );
    }

    final scenePath = '${framesDirectory.path}/filament_3d_scene.mp4';
    final command =
        '-y -framerate $fps '
        '-start_number 0 '
        '-i "${framesDirectory.path}/frame_%05d.png" '
        '-vf "scale=640:640:force_original_aspect_ratio=decrease,'
        'pad=640:640:(ow-iw)/2:(oh-ih)/2:color=0x101521,'
        'setsar=1,format=yuv420p" '
        '-an -c:v libx264 -preset veryfast -crf 18 '
        '-r $fps -t ${duration.toStringAsFixed(2)} '
        '-movflags +faststart "$scenePath"';

    onStatus?.call('جاري تحويل إطارات 3D إلى فيديو...');
    final encoded = await SilenceCutter.encode(command, duration, null);
    final sceneFile = File(scenePath);
    if (!encoded ||
        !await sceneFile.exists() ||
        await sceneFile.length() < 2048) {
      throw FileSystemException(
        'فشل إنشاء فيديو مشهد 3D من الإطارات الملتقطة.',
        scenePath,
      );
    }

    // The encoded MP4 is now sufficient; remove the much larger PNG sequence.
    await _deletePngFrames(framesDirectory);
    onStatus?.call('تم تجهيز فيديو مشهد 3D.');
    return scenePath;
  }

  /// Places the 3D clip as a small framed picture-in-picture overlay.
  /// The original video and its audio remain the primary tracks.
  static Future<String> compositeOverVideo({
    required String videoPath,
    required String scenePath,
    void Function(String message)? onStatus,
  }) async {
    final sourceFile = File(videoPath);
    final sceneFile = File(scenePath);

    if (!await sourceFile.exists()) {
      throw FileSystemException(
        'ملف الفيديو الأصلي غير موجود.',
        videoPath,
      );
    }
    if (!await sceneFile.exists() || await sceneFile.length() < 2048) {
      throw FileSystemException(
        'ملف مشهد 3D غير موجود أو غير صالح.',
        scenePath,
      );
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath =
        '${sourceFile.parent.path}/wad_alreda_3d_$stamp.mp4';
    const boxSize = 360;
    const margin = 24;

    final command =
        '-y -i "$videoPath" -i "$scenePath" '
        '-filter_complex "'
        '[1:v]scale=$boxSize:$boxSize:force_original_aspect_ratio=decrease,'
        'pad=$boxSize:$boxSize:(ow-iw)/2:(oh-ih)/2:color=0x101521,'
        'setsar=1,drawbox=x=0:y=0:w=iw:h=ih:'
        'color=0x9A7BFF@0.95:t=4[scene];'
        '[0:v][scene]overlay='
        'x=main_w-overlay_w-$margin:y=$margin:'
        'eof_action=pass:repeatlast=0,format=yuv420p[vout]" '
        '-map "[vout]" -map "0:a?" '
        '-c:v libx264 -preset veryfast -crf 19 -pix_fmt yuv420p '
        '-c:a aac -b:a 192k -movflags +faststart "$outputPath"';

    onStatus?.call('جاري دمج مشهد 3D فوق الفيديو الأصلي...');
    // expectedSec=0 disables percentage reporting; FFmpeg still runs normally.
    final encoded = await SilenceCutter.encode(command, 0, null);
    final outputFile = File(outputPath);
    if (!encoded ||
        !await outputFile.exists() ||
        await outputFile.length() < 4096) {
      throw FileSystemException(
        'فشل تركيب مشهد 3D على الفيديو الأصلي.',
        outputPath,
      );
    }

    onStatus?.call('تم تصدير الفيديو مع طبقة 3D.');
    return outputPath;
  }

  static Future<void> _deletePngFrames(Directory directory) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
          try {
            await entity.delete();
          } catch (_) {
            // Keep the successful MP4 even if a temporary PNG cannot be removed.
          }
        }
      }
    } catch (_) {
      // Temporary-file cleanup must not invalidate a successfully encoded clip.
    }
  }
}
