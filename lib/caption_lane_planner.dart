import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

/// Chooses the vertical lane of the captions so they do not sit on the busiest
/// part of the picture (the microphone, the hands).
///
/// Four small frames of the video are measured; the detail (edge energy) of
/// every candidate lane is averaged and the calmest lane wins. The usual lane
/// is kept unless another one is clearly calmer, so the captions do not move
/// without a reason. Any problem returns the usual lane. [pickLane] is pure
/// Dart and testable.
class CaptionLanePlanner {
  CaptionLanePlanner._();

  static bool enabled = true;

  /// Candidate centres (share of the frame height), bottom area only.
  static const List<double> lanes = <double>[0.72, 0.80, 0.88];

  static const double usualLane = 0.80;

  /// Half height of one lane band (share of the frame height).
  static const double halfBand = 0.045;

  /// The usual lane is replaced only when its detail is this much higher.
  static const double switchRatio = 1.25;

  /// Mean absolute gradient of a grayscale image inside a horizontal band.
  static double bandDetail(
    Uint8List gray,
    int width,
    int height,
    double centerY, {
    double band = halfBand,
  }) {
    if (width < 4 || height < 4 || gray.length < width * height) return 0;
    final top = ((centerY - band) * height).round().clamp(0, height - 2);
    final bottom = ((centerY + band) * height).round().clamp(top + 1, height - 1);
    final left = (width * 0.10).round();
    final right = (width * 0.90).round().clamp(left + 2, width - 1);
    var sum = 0.0;
    var count = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final c = gray[y * width + x];
        final dx = (c - gray[y * width + x + 1]).abs();
        final dy = (c - gray[(y + 1) * width + x]).abs();
        sum += (dx + dy) / 2;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  /// The lane to use for [scores] (one detail value per entry of [lanes]).
  static double pickLane(List<double> scores) {
    if (scores.length != lanes.length) return usualLane;
    final usualIndex = lanes.indexOf(usualLane);
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] < scores[best]) best = i;
    }
    if (best == usualIndex) return usualLane;
    final usual = scores[usualIndex];
    if (usual > scores[best] * switchRatio + 1.0) return lanes[best];
    return usualLane;
  }

  static Future<Uint8List?> _grayFrame(
    String video,
    double seconds,
    String dir,
    String tag,
    List<int> size,
  ) async {
    final png = '$dir/lane_$tag.png';
    try {
      final session = await FFmpegKit.execute(
        '-y -hide_banner -ss ${seconds.toStringAsFixed(2)} -i "$video" '
        '-frames:v 1 -vf "scale=90:160:flags=bilinear,format=gray" "$png"',
      );
      if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
      final file = File(png);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width;
      final h = image.height;
      image.dispose();
      codec.dispose();
      if (data == null) return null;
      final rgba = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final gray = Uint8List(w * h);
      for (var i = 0; i < w * h; i++) {
        gray[i] = rgba[i * 4];
      }
      size
        ..clear()
        ..addAll(<int>[w, h]);
      return gray;
    } catch (_) {
      return null;
    }
  }

  /// Best caption lane for [videoPath]; [usualLane] when it cannot be told.
  static Future<double> plan({
    required String videoPath,
    required double duration,
    required String directory,
  }) async {
    if (!enabled || !duration.isFinite || duration < 2) return usualLane;
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final totals = List<double>.filled(lanes.length, 0);
      var frames = 0;
      const positions = <double>[0.15, 0.40, 0.65, 0.85];
      for (var i = 0; i < positions.length; i++) {
        final size = <int>[];
        final gray = await _grayFrame(
          videoPath,
          math.max(0.0, duration * positions[i]),
          directory,
          '${stamp}_$i',
          size,
        );
        if (gray == null || size.length != 2) continue;
        for (var l = 0; l < lanes.length; l++) {
          totals[l] += bandDetail(gray, size[0], size[1], lanes[l]);
        }
        frames++;
      }
      if (frames == 0) return usualLane;
      return pickLane(<double>[for (final t in totals) t / frames]);
    } catch (_) {
      return usualLane;
    }
  }
}
