import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'smart_cut_engine.dart';

/// Controls cancellation of the active editing job.
class JobControl {
  static bool cancelled = false;

  static void reset() => cancelled = false;

  static Future<void> cancel() async {
    cancelled = true;
    await FFmpegKit.cancel();
  }
}

class CutResult {
  final String path;
  final double originalSec;
  final double newSec;
  final int segments;

  /// Start time of each retained segment on the newly joined timeline.
  final List<double> segStarts;

  CutResult(
    this.path,
    this.originalSec,
    this.newSec,
    this.segments,
    this.segStarts,
  );
}

class MediaInfo {
  final int w;
  final int h;

  MediaInfo(this.w, this.h);
}

/// Detects long silent pauses, preserves natural speech boundaries and joins
/// the retained video/audio ranges with FFmpeg.
class SilenceCutter {
  static String _f(double value) => value.toStringAsFixed(3);

  static String _tail(String value) =>
      value.length > 500 ? value.substring(value.length - 500) : value;

  /// Reads video dimensions. FFmpeg may return a non-zero code because this
  /// command intentionally has no output file.
  static Future<MediaInfo> probe(String path) async {
    final session = await FFmpegKit.execute('-hide_banner -i "$path"');
    final logs = await session.getAllLogsAsString() ?? '';
    final match = RegExp(r'Video:.*?(\d{3,5})x(\d{3,5})').firstMatch(logs);
    if (match == null) throw Exception('ما قدرت أقرأ أبعاد الفيديو.');
    return MediaInfo(int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  /// Creates a JPEG thumbnail. Kept compatible with older callers.
  static Future<String> makeThumb(String videoPath, double seconds) async {
    final file = File(videoPath);
    if (!await file.exists()) {
      throw Exception('ملف الفيديو غير موجود لإنشاء الصورة المصغرة.');
    }

    final at = seconds > 1 ? 1.0 : 0.0;
    final out =
        '${file.parent.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final command =
        '-y -ss $at -i "$videoPath" -frames:v 1 -q:v 3 "$out"';
    final session = await FFmpegKit.execute(command);
    final success = ReturnCode.isSuccess(await session.getReturnCode());

    if (!success || !await File(out).exists()) {
      throw Exception('فشل إنشاء الصورة المصغرة.');
    }
    return out;
  }

  static Future<CutResult> process(
    String input, {
    double noiseDb = -30,
    double minSilence = 0.5,
    double? maxSec,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    if (!await File(input).exists()) {
      throw Exception('ملف الفيديو المختار غير موجود.');
    }

    onStatus?.call('جاري تحليل الصوت...');
    final detect = await FFmpegKit.execute(
      '-hide_banner -i "$input" '
      '-af silencedetect=noise=${noiseDb.toStringAsFixed(0)}dB:'
      'd=${minSilence.toStringAsFixed(2)} -vn -f null -',
    );
    final logs = await detect.getAllLogsAsString() ?? '';
    final returnCode = await detect.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception(
        'فشل تحليل الصوت (قد يكون الفيديو بلا صوت).\n${_tail(logs)}',
      );
    }

    final durationMatch =
        RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)')
            .firstMatch(logs);
    if (durationMatch == null) {
      throw Exception('ما قدرت أعرف مدة الفيديو.');
    }

    final total = int.parse(durationMatch.group(1)!) * 3600 +
        int.parse(durationMatch.group(2)!) * 60 +
        double.parse(durationMatch.group(3)!);

    final starts = RegExp(r'silence_start:\s*(-?[\d.]+)')
        .allMatches(logs)
        .map((match) => double.parse(match.group(1)!))
        .toList();
    final ends = RegExp(r'silence_end:\s*(-?[\d.]+)')
        .allMatches(logs)
        .map((match) => double.parse(match.group(1)!))
        .toList();

    onStatus?.call('جاري ضبط إيقاع الكلام والحفاظ على نهايات الجمل...');
    final keep = SmartCutEngine.buildKeepSegments(
      duration: total,
      silenceStarts: starts,
      silenceEnds: ends,
    );

    if (keep.isEmpty) {
      throw Exception(
        'ما لقيت كلامًا قابلاً للاحتفاظ به. قلّل حساسية السكتة.',
      );
    }

    final newSec = keep.fold<double>(
      0,
      (sum, segment) => sum + segment.duration,
    );

    if (starts.isEmpty || (total - newSec) < 0.3) {
      throw Exception(
        'ما لقيت سكتات تستحق القص. جرّب تغيير حساسية السكتة.',
      );
    }

    if (maxSec != null && newSec > maxSec) {
      throw Exception(
        'مدة الفيديو بعد القص ${newSec.toStringAsFixed(0)} ثانية، '
        'والحد المتاح ${maxSec.toStringAsFixed(0)} ثانية.',
      );
    }

    if (JobControl.cancelled) throw Exception('تم إلغاء المونتاج.');
    onStatus?.call('جاري القص الذكي (${keep.length} مقطع)...');

    final filter = StringBuffer();
    for (var i = 0; i < keep.length; i++) {
      final segment = keep[i];
      filter.write(
        '[0:v]trim=start=${_f(segment.start)}:end=${_f(segment.end)},'
        'setpts=PTS-STARTPTS[v$i];',
      );
      filter.write(
        '[0:a]atrim=start=${_f(segment.start)}:end=${_f(segment.end)},'
        'asetpts=PTS-STARTPTS[a$i];',
      );
    }

    for (var i = 0; i < keep.length; i++) {
      filter.write('[v$i][a$i]');
    }
    filter.write('concat=n=${keep.length}:v=1:a=1[v][a]');

    final dir = (await getExternalStorageDirectory()) ??
        await getApplicationDocumentsDirectory();
    final out = '${dir.path}/cut_${DateTime.now().millisecondsSinceEpoch}.mp4';

    String command(String codec) =>
        '-y -i "$input" -filter_complex "${filter.toString()}" '
        '-map "[v]" -map "[a]" $codec -pix_fmt yuv420p '
        '-c:a aac -b:a 192k "$out"';

    var ok = await encode(
      command('-c:v libx264 -preset veryfast -crf 18'),
      newSec,
      onProgress,
    );

    if (!ok) {
      onStatus?.call('جاري المحاولة بترميز بديل...');
      ok = await encode(command('-c:v mpeg4 -q:v 2'), newSec, onProgress);
    }

    if (!ok || !await File(out).exists()) {
      throw Exception('فشل قص الفيديو ودمج المقاطع.');
    }

    final segStarts = <double>[];
    var accumulated = 0.0;
    for (final segment in keep) {
      segStarts.add(accumulated);
      accumulated += segment.duration;
    }

    return CutResult(out, total, newSec, keep.length, segStarts);
  }

  static Future<bool> encode(
    String command,
    double expectedSec,
    void Function(double)? onProgress,
  ) {
    if (JobControl.cancelled) return Future<bool>.value(false);

    final completer = Completer<bool>();
    FFmpegKit.executeAsync(command, (session) async {
      final returnCode = await session.getReturnCode();
      if (!completer.isCompleted) {
        completer.complete(ReturnCode.isSuccess(returnCode));
      }
    }, null, (stats) {
      final num time = stats.getTime();
      if (time > 0 && expectedSec > 0) {
        onProgress?.call((time / 1000 / expectedSec).clamp(0.0, 1.0));
      }
    });
    return completer.future;
  }
}
