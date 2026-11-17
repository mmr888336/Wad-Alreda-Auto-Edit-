/// Renders a motion cutaway (see [ReferenceSceneBuilder]) to an MP4 with the
/// Motion FFmpeg adapter. The clip is then placed on the timeline like a
/// B-roll clip, so it is exported, saved and editable with the existing
/// timeline tools. Any failure returns null and the export simply continues
/// without the cutaway.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

import 'motion_ffmpeg_adapter.dart';
import 'motion_graphics.dart' show MotionMood;
import 'pixel_art_sprites.dart';
import 'reference_scene_builder.dart';
import 'text_render.dart';

class MotionCutawayClip {
  final String path;
  final double duration;

  const MotionCutawayClip({required this.path, required this.duration});
}

class MotionCutawayRenderer {
  MotionCutawayRenderer._();

  /// Master switch for motion cutaways in exported videos.
  static bool enabled = true;

  /// The motion canvas is rendered at most this many pixels on its short
  /// side (then scaled to the video size by the timeline overlay).
  static const int maxShortSide = 720;

  static int _even(double value) {
    var result = value.round();
    if (result.isOdd) result++;
    return result < 2 ? 2 : result;
  }

  static String _quote(String arg) =>
      '"${arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// Width and height of a PNG file, read from its header.
  static Future<List<int>?> _pngSize(String path) async {
    final raf = await File(path).open();
    try {
      final head = await raf.read(24);
      if (head.length < 24) return null;
      final w = (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19];
      final h = (head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23];
      if (w <= 0 || h <= 0) return null;
      return <int>[w, h];
    } finally {
      await raf.close();
    }
  }

  static int _mix(int from, int to, double t, int shift) {
    final a = (from >> shift) & 0xFF;
    final b = (to >> shift) & 0xFF;
    return (a + (b - a) * t).round();
  }

  /// Pixel-grid vertical gradient used as the scene background.
  static Uint8List _backgroundPng(int top, int bottom, int w, int h) {
    const lowW = 90;
    final lowH = math.max(8, (lowW * h / w).round());
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final ly = math.min(lowH - 1, y * lowH ~/ h);
      final t = ly / math.max(1, lowH - 1);
      final r0 = _mix(top, bottom, t, 16);
      final g0 = _mix(top, bottom, t, 8);
      final b0 = _mix(top, bottom, t, 0);
      for (var x = 0; x < w; x++) {
        final lx = math.min(lowW - 1, x * lowW ~/ w);
        final dither = ((lx + ly) & 1) == 0 ? 0 : 4;
        final grid = (lx % 10 == 0 || ly % 10 == 0) ? 8 : 0;
        final bump = dither + grid;
        final i = (y * w + x) * 4;
        rgba[i] = math.min(255, r0 + bump);
        rgba[i + 1] = math.min(255, g0 + bump);
        rgba[i + 2] = math.min(255, b0 + bump);
        rgba[i + 3] = 255;
      }
    }
    return PixelPngEncoder.encodeRgba(rgba, width: w, height: h);
  }

  /// Renders [spec] to `motion_scene_<stamp>_<index>.mp4` inside [dir].
  /// Every temporary image is added to [temps]. Returns null on failure.
  static Future<MotionCutawayClip?> render({
    required CutawaySpec spec,
    required String dir,
    required int stamp,
    required int index,
    required int outW,
    required int outH,
    required MotionMood mood,
    required String fontFamily,
    required List<String> temps,
  }) async {
    if (!enabled) return null;
    try {
      final shortSide = math.min(outW, outH);
      final factor = shortSide > maxShortSide ? maxShortSide / shortSide : 1.0;
      final mw = _even(outW * factor);
      final mh = _even(outH * factor);

      final built = ReferenceSceneBuilder.buildCutaway(
        id: 'cut$index',
        spec: spec,
        width: mw,
        height: mh,
        mood: mood,
        variant: index,
      );

      final assets = <String, MotionRenderAsset>{};
      final spritePaths = <String, String>{};
      final fontSize = math.min(mw, mh) * 0.14;
      var fontReady = false;

      for (final entry in built.assets.entries) {
        final key = entry.key;
        final asset = entry.value;
        final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');

        if (asset.kind == SceneAssetKind.background) {
          final bgPath = '$dir/mot_${stamp}_${index}_$safe.png';
          await File(bgPath).writeAsBytes(
            _backgroundPng(asset.topColor, asset.bottomColor, mw, mh),
            flush: true,
          );
          temps.add(bgPath);
          assets[key] = MotionRenderAsset(
            path: bgPath,
            aspect: mh / mw,
            widthFraction: 1.0,
          );
        } else if (asset.kind == SceneAssetKind.sprite) {
          final sprite = PixelSprites.byKey(asset.spriteKey ?? '');
          if (sprite == null) continue;
          final cached = spritePaths[sprite.key];
          final spritePath =
              cached ?? '$dir/mot_${stamp}_${index}_${sprite.key}.png';
          if (cached == null) {
            await File(spritePath).writeAsBytes(
              sprite.toPng(scale: 8),
              flush: true,
            );
            temps.add(spritePath);
            spritePaths[sprite.key] = spritePath;
          }
          assets[key] = MotionRenderAsset(
            path: spritePath,
            aspect: sprite.height / sprite.width,
            widthFraction: asset.widthFraction,
          );
        } else {
          final text = asset.text;
          if (text == null || text.trim().isEmpty) continue;
          if (!fontReady) {
            await TextRender.prepareFont(
              fontFamily: fontFamily,
              fontSize: fontSize,
              style: 'bold_center',
            );
            fontReady = true;
          }
          final wordPath = '$dir/mot_${stamp}_${index}_$safe.png';
          await TextRender.png(
            text: text,
            outPath: wordPath,
            width: mw,
            fontSize: fontSize,
            fontFamily: fontFamily,
            style: 'bold_center',
          );
          temps.add(wordPath);
          final size = await _pngSize(wordPath);
          if (size == null) continue;
          assets[key] = MotionRenderAsset(
            path: wordPath,
            aspect: size[1] / size[0],
            widthFraction: 1.0,
          );
        }
      }

      final plan = MotionFfmpegAdapter.build(
        project: built.project,
        assets: assets,
      );
      if (plan.totalDuration < 1.0) return null;

      final out = '$dir/motion_scene_${stamp}_$index.mp4';
      final command = plan.arguments(outputPath: out).map(_quote).join(' ');
      final session = await FFmpegKit.execute(command);
      final ok = ReturnCode.isSuccess(await session.getReturnCode());
      final file = File(out);
      if (!ok || !file.existsSync() || file.lengthSync() == 0) {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
        return null;
      }
      return MotionCutawayClip(
        path: out,
        duration: math.min(spec.duration, plan.totalDuration),
      );
    } catch (_) {
      return null;
    }
  }
}
