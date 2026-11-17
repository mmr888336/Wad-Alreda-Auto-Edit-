/// Puts a re-rendered motion cutaway back into an exported video.
///
/// A motion cutaway is a full-frame, opaque scene, so drawing the new clip
/// over the same time window completely replaces the old one. Audio is copied
/// untouched. No original footage is needed.
library;

import 'dart:io';

import 'silence_cutter.dart';

class MotionReexport {
  MotionReexport._();

  static String _f(double value) => value.toStringAsFixed(3);

  /// Writes `final_edit_<stamp>.mp4` next to [videoPath] and returns its path,
  /// or null when the export failed. The caller decides what to replace.
  static Future<String?> overlayClip({
    required String videoPath,
    required String clipPath,
    required double start,
    required double end,
    required double videoDuration,
    void Function(double progress)? onProgress,
  }) async {
    if (!start.isFinite || !end.isFinite || end - start < 0.2) return null;
    if (!await File(videoPath).exists()) return null;
    if (!await File(clipPath).exists()) return null;

    final info = await SilenceCutter.probe(videoPath);
    final width = info.w - (info.w % 2);
    final height = info.h - (info.h % 2);
    if (width < 2 || height < 2) return null;

    final out = '${File(videoPath).parent.path}/'
        'final_edit_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final s = _f(start);
    final e = _f(end);

    final filter =
        '[1:v]scale=$width:$height:flags=lanczos,setsar=1,format=yuv420p,'
        'setpts=PTS-STARTPTS+$s/TB[m];'
        "[0:v][m]overlay=x=0:y=0:eof_action=pass:repeatlast=0:"
        "enable='between(t,$s,$e)'[v]";

    final command = '-y -i "$videoPath" -i "$clipPath" '
        '-filter_complex "$filter" '
        '-map "[v]" -map "0:a?" '
        '-c:v libx264 -preset veryfast -crf 17 -pix_fmt yuv420p '
        '-c:a copy -movflags +faststart "$out"';

    final ok = await SilenceCutter.encode(command, videoDuration, onProgress);
    final file = File(out);

    if (!ok || !await file.exists() || await file.length() < 4096) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
    return out;
  }
}
