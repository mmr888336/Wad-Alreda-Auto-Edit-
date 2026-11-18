import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

import 'scene_key_quality.dart';

class _ColorCluster {
  int red;
  int green;
  int blue;
  int count;

  _ColorCluster(this.red, this.green, this.blue) : count = 1;

  int get averageRed => (red / count).round();
  int get averageGreen => (green / count).round();
  int get averageBlue => (blue / count).round();
}

/// Finds the flat background color of a rendered 3D scene clip so it can be
/// removed with a color key and the model can float over the video.
class SceneKeyColor {
  SceneKeyColor._();

  static const int _tolerance = 28;

  static String _hex(int value) =>
      value.clamp(0, 255).toInt().toRadixString(16).padLeft(2, '0').toUpperCase();

  /// Returns up to two background colors (as `0xRRGGBB`) that appear on the
  /// edges of an RGBA image. Returns an empty list when no color dominates.
  static List<String> dominantEdgeColors(
    Uint8List rgba,
    int width,
    int height,
  ) {
    if (width < 4 || height < 4 || rgba.length < width * height * 4) {
      return const <String>[];
    }

    final points = <List<int>>[
      <int>[1, 1],
      <int>[width - 2, 1],
      <int>[1, height - 2],
      <int>[width - 2, height - 2],
      <int>[width ~/ 2, 1],
      <int>[width ~/ 2, height - 2],
      <int>[1, height ~/ 2],
      <int>[width - 2, height ~/ 2],
    ];

    final clusters = <_ColorCluster>[];

    for (final point in points) {
      final offset = (point[1] * width + point[0]) * 4;
      final r = rgba[offset];
      final g = rgba[offset + 1];
      final b = rgba[offset + 2];

      _ColorCluster? match;
      for (final cluster in clusters) {
        if ((cluster.averageRed - r).abs() <= _tolerance &&
            (cluster.averageGreen - g).abs() <= _tolerance &&
            (cluster.averageBlue - b).abs() <= _tolerance) {
          match = cluster;
          break;
        }
      }

      if (match == null) {
        clusters.add(_ColorCluster(r, g, b));
      } else {
        match.red += r;
        match.green += g;
        match.blue += b;
        match.count++;
      }
    }

    final strong = clusters.where((cluster) => cluster.count >= 2).toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return strong
        .take(2)
        .map(
          (cluster) =>
              '0x${_hex(cluster.averageRed)}${_hex(cluster.averageGreen)}${_hex(cluster.averageBlue)}',
        )
        .toList();
  }

  /// Extracts the first frame of [scenePath] and reads its background colors.
  /// Any failure returns an empty list, which means "do not key".
  static Future<List<String>> sample(
    String scenePath,
    String tempDirectory,
  ) async {
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final pngPath = '$tempDirectory/key_$stamp.png';

      final session = await FFmpegKit.execute(
        '-y -hide_banner -i "$scenePath" -frames:v 1 '
        '-vf "scale=64:64:flags=bilinear" "$pngPath"',
      );

      if (!ReturnCode.isSuccess(await session.getReturnCode())) {
        return const <String>[];
      }

      final file = File(pngPath);
      if (!await file.exists()) return const <String>[];

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

      try {
        await file.delete();
      } catch (_) {}

      if (data == null) return const <String>[];

      final pixels = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final colors = dominantEdgeColors(pixels, width, height);

      // A background that cannot be keyed cleanly would leave fragments of the
      // model floating over the speaker: such a scene is not keyed at all.
      return SceneKeyQuality.keepIfClean(pixels, width, height, colors);
    } catch (_) {
      return const <String>[];
    }
  }
}
