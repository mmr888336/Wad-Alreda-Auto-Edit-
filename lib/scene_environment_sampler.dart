import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

import 'scene_environment.dart';

/// Reads the light, color and softness of the footage during one 3D scene by
/// decoding a few tiny frames of the real video.
///
/// Any failure returns null, which means "do not match this scene to its
/// environment" (the scene keeps the plain anchored look).
class SceneEnvironmentSampler {
  SceneEnvironmentSampler._();

  /// Width of the analysis frames. Small on purpose: fast and light on memory.
  static const int _frameWidth = 96;

  static const int _maximumFrames = 3;

  /// Samples up to three frames spread over [start]..[end] of [videoPath]
  /// into [directory] (created, and removed again) and averages their profile.
  static Future<SceneEnvironmentProfile?> sample({
    required String videoPath,
    required double start,
    required double end,
    required String directory,
  }) async {
    final folder = Directory(directory);

    try {
      if (!start.isFinite || !end.isFinite) return null;

      await folder.create(recursive: true);

      final span = math.max(0.3, end - start);
      final rate = (_maximumFrames / span).clamp(0.2, 12.0).toDouble();

      final session = await FFmpegKit.execute(
        '-y -hide_banner -ss ${start.toStringAsFixed(3)} '
        '-t ${span.toStringAsFixed(3)} -i "$videoPath" '
        '-vf "fps=${rate.toStringAsFixed(4)},'
        'scale=$_frameWidth:-2:flags=bilinear" '
        '-frames:v $_maximumFrames "$directory/env_%02d.png"',
      );

      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        return null;
      }

      final profiles = <SceneEnvironmentProfile>[];

      for (var index = 1; index <= _maximumFrames; index++) {
        final name = index.toString().padLeft(2, '0');
        final file = File('$directory/env_$name.png');

        if (!await file.exists()) continue;

        final profile = await _profileOf(file);
        if (profile != null) profiles.add(profile);
      }

      return SceneEnvironmentProfile.average(profiles);
    } catch (_) {
      return null;
    } finally {
      try {
        if (await folder.exists()) {
          await folder.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<SceneEnvironmentProfile?> _profileOf(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      final width = image.width;
      final height = image.height;

      image.dispose();
      codec.dispose();

      if (data == null) return null;

      return SceneEnvironmentProfile.fromRgba(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width,
        height,
      );
    } catch (_) {
      return null;
    }
  }
}
