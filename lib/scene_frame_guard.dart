import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

/// Rejects rendered 3D scene clips whose frames are corrupt.
///
/// An uncompleted hardware capture decodes as a flat band of bright green
/// (all-zero YUV planes), which then shows over the speaker. A clip with such
/// frames is better skipped than shown. Any problem while checking means the
/// clip is accepted (the guard never costs a good scene).
class SceneFrameGuard {
  SceneFrameGuard._();

  static bool enabled = true;

  /// Seconds inside the clip that are inspected.
  static const List<double> sampleTimes = <double>[0.3, 0.9, 1.6, 2.4];

  /// One frame with at least this share of garbage green rejects the clip.
  static const double singleFrameShare = 0.10;

  /// Two frames with at least this share also reject it.
  static const double repeatedFrameShare = 0.04;

  /// A pixel that is clearly green and nothing else.
  static bool isGarbageGreen(int r, int g, int b) {
    return g >= 110 && g - r >= 80 && g - b >= 80;
  }

  /// Share (0..1) of garbage green pixels in an RGBA buffer.
  static double greenShare(Uint8List rgba, int width, int height) {
    final total = width * height;
    if (total <= 0 || rgba.length < total * 4) return 0;
    var count = 0;
    for (var i = 0; i < total; i++) {
      final o = i * 4;
      if (rgba[o + 3] < 16) continue;
      if (isGarbageGreen(rgba[o], rgba[o + 1], rgba[o + 2])) count++;
    }
    return count / total;
  }

  /// True when the shares of the inspected frames mean a corrupt clip.
  static bool isCorrupt(List<double> shares) {
    var repeated = 0;
    for (final share in shares) {
      if (share >= singleFrameShare) return true;
      if (share >= repeatedFrameShare) repeated++;
    }
    return repeated >= 2;
  }

  static Future<double?> _shareAt(
    String clip,
    double seconds,
    String dir,
    int stamp,
    int index,
  ) async {
    final png = '$dir/green_guard_${stamp}_$index.png';
    try {
      final session = await FFmpegKit.execute(
        '-y -hide_banner -ss ${seconds.toStringAsFixed(2)} -i "$clip" '
        '-frames:v 1 -vf "scale=64:64:flags=bilinear" "$png"',
      );
      if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
      final file = File(png);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width;
      final h = image.height;
      image.dispose();
      codec.dispose();
      if (data == null) return null;
      final pixels = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return greenShare(pixels, w, h);
    } catch (_) {
      return null;
    }
  }

  /// True when [clipPath] is safe to use. [directory] holds the small temp
  /// images.
  static Future<bool> isClean(String clipPath, String directory) async {
    if (!enabled) return true;
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final shares = <double>[];
      for (var i = 0; i < sampleTimes.length; i++) {
        final share = await _shareAt(clipPath, sampleTimes[i], directory, stamp, i);
        if (share != null) shares.add(share);
      }
      return !isCorrupt(shares);
    } catch (_) {
      return true;
    }
  }
}
