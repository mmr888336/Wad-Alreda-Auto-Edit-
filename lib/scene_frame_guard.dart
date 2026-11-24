import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

/// What one inspected frame looks like (all shares are 0..1 of the frame).
class FrameStats {
  const FrameStats({
    required this.green,
    required this.dark,
    required this.transparent,
    required this.deviation,
  });

  /// Share of garbage green pixels.
  final double green;

  /// Share of opaque pixels that are (almost) black.
  final double dark;

  /// Share of fully or almost fully transparent pixels.
  final double transparent;

  /// Standard deviation of the luma of the opaque pixels (0 = one flat colour).
  final double deviation;

  /// True when the frame shows nothing: black, transparent or one flat colour.
  bool get isBlank =>
      transparent + dark >= SceneFrameGuard.blankShare ||
      deviation < SceneFrameGuard.flatDeviation;
}

/// What the guard decided about a whole clip.
enum SceneFrameVerdict {
  /// Safe to show.
  clean,

  /// Half-decoded green frames.
  green,

  /// Black, transparent or flat frames: nothing to see.
  blank,
}

/// Rejects rendered 3D scene clips whose frames are corrupt or empty.
///
/// An uncompleted hardware capture decodes as a flat band of bright green
/// (all-zero YUV planes), which then shows over the speaker. A clip with such
/// frames is better skipped than shown. The same goes for a scene that was
/// captured black (no light reached the model), transparent or as one flat
/// colour: it would replace the picture with nothing, so it is rejected and
/// the scene goes back to the 2.5D engine. Any problem while checking means
/// the clip is accepted (the guard never costs a good scene).
class SceneFrameGuard {
  SceneFrameGuard._();

  static bool enabled = true;

  /// Switch of the black / transparent / flat check (the green check stays).
  static bool blankDetectionEnabled = true;

  /// Seconds inside the clip that are inspected.
  static const List<double> sampleTimes = <double>[0.3, 0.9, 1.6, 2.4];

  /// One frame with at least this share of garbage green rejects the clip.
  static const double singleFrameShare = 0.10;

  /// Two frames with at least this share also reject it.
  static const double repeatedFrameShare = 0.04;

  /// Luma (0..255) at or below which an opaque pixel counts as black.
  static const double blackLuma = 14.0;

  /// A frame whose black + transparent share reaches this shows nothing.
  static const double blankShare = 0.97;

  /// A frame whose luma deviates less than this is one flat colour.
  static const double flatDeviation = 3.0;

  /// Share of the inspected frames that must be blank to reject the clip.
  static const double blankClipShare = 0.6;

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

  /// The statistics of an RGBA buffer, or null when the buffer is too small
  /// for [width] x [height].
  static FrameStats? frameStats(Uint8List rgba, int width, int height) {
    final total = width * height;
    if (width <= 0 || height <= 0 || rgba.length < total * 4) return null;

    var green = 0;
    var dark = 0;
    var transparent = 0;
    var opaque = 0;
    var sum = 0.0;
    var sumSquares = 0.0;

    for (var i = 0; i < total; i++) {
      final o = i * 4;

      if (rgba[o + 3] < 16) {
        transparent++;
        continue;
      }

      final r = rgba[o];
      final g = rgba[o + 1];
      final b = rgba[o + 2];
      opaque++;

      if (isGarbageGreen(r, g, b)) green++;

      final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      if (luma <= blackLuma) dark++;
      sum += luma;
      sumSquares += luma * luma;
    }

    var deviation = 0.0;
    if (opaque > 0) {
      final mean = sum / opaque;
      deviation = math.sqrt(math.max(0.0, sumSquares / opaque - mean * mean));
    }

    return FrameStats(
      green: green / total,
      dark: dark / total,
      transparent: transparent / total,
      deviation: deviation,
    );
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

  /// True when most of the inspected frames show nothing.
  static bool isBlankClip(List<FrameStats> frames) {
    if (frames.isEmpty) return false;
    final blank = frames.where((frame) => frame.isBlank).length;
    return blank / frames.length >= blankClipShare;
  }

  /// The decision for a clip from its inspected frames.
  static SceneFrameVerdict verdictOf(
    List<FrameStats> frames, {
    bool checkBlank = true,
  }) {
    if (frames.isEmpty) return SceneFrameVerdict.clean;
    if (isCorrupt(<double>[for (final frame in frames) frame.green])) {
      return SceneFrameVerdict.green;
    }
    if (checkBlank && isBlankClip(frames)) return SceneFrameVerdict.blank;
    return SceneFrameVerdict.clean;
  }

  static Future<FrameStats?> _statsAt(
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
      final pixels =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      return frameStats(pixels, w, h);
    } catch (_) {
      return null;
    }
  }

  /// Inspects [clipPath] and says why it is (not) safe. [directory] holds the
  /// small temp images. A problem while checking gives [SceneFrameVerdict.clean].
  static Future<SceneFrameVerdict> inspect(
    String clipPath,
    String directory,
  ) async {
    if (!enabled) return SceneFrameVerdict.clean;
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final frames = <FrameStats>[];
      for (var i = 0; i < sampleTimes.length; i++) {
        final stats =
            await _statsAt(clipPath, sampleTimes[i], directory, stamp, i);
        if (stats != null) frames.add(stats);
      }
      return verdictOf(frames, checkBlank: blankDetectionEnabled);
    } catch (_) {
      return SceneFrameVerdict.clean;
    }
  }

  /// True when [clipPath] is safe to use. [directory] holds the small temp
  /// images.
  static Future<bool> isClean(String clipPath, String directory) async {
    return await inspect(clipPath, directory) == SceneFrameVerdict.clean;
  }
}
