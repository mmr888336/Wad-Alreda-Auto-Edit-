/// Full-background composition of the 3D world scenes.
///
/// Before this file the captured world was blended over the whole picture in
/// "screen" mode on black: only the lit objects survived and floated over the
/// footage. Here the world IS the picture: during the window of a scene its
/// clip replaces the video (cover fit, soft fade in and out). The flat layers
/// drawn by the 2.5D engine (props, particles...) sit on top of it, and a
/// scene that fell back to 2.5D comes as a ready clip of the whole scene and
/// is composed the same way. A world clip can carry the [WorldLook] of its
/// scene: it is then graded (tint, key light, vignette) before it is shown.
/// The original audio is kept. Any failure throws, so the caller can go back
/// to the previous composition.
library;

import 'dart:io';
import 'dart:math' as math;

import 'cinematic_world.dart' show WorldLook;
import 'silence_cutter.dart';
import 'world_look_grade.dart';

/// One scene of the world shown as the full picture of the video.
class WorldBackgroundClip {
  const WorldBackgroundClip({
    required this.path,
    required this.start,
    required this.end,
    this.overlayPath,
    this.look,
  });

  /// Clip that replaces the picture (the 3D world, or a whole 2.5D scene).
  final String path;

  /// Window of the scene in the video, in seconds.
  final double start;
  final double end;

  /// Optional clip of the flat 2.5D layers on black; it is screen-blended on
  /// top of the world.
  final String? overlayPath;

  /// Light and atmosphere used to grade [path]; null leaves it as it is.
  final WorldLook? look;

  double get duration => end - start;
}

/// The inputs and the filter graph of one composition (pure Dart).
class WorldBackgroundPlan {
  const WorldBackgroundPlan({
    required this.inputs,
    required this.filterComplex,
    required this.outputLabel,
  });

  final List<String> inputs;
  final String filterComplex;
  final String outputLabel;
}

class WorldBackgroundCommand {
  WorldBackgroundCommand._();

  static const String outputLabel = 'world_bg_out';

  /// Longest fade at each end of a clip, in seconds.
  static const double maxFadeSeconds = 0.35;

  static String _f(double value) => value.toStringAsFixed(3);

  /// Fade length for a clip of [clipSeconds]: never more than a third of it.
  static double fadeFor(double clipSeconds) {
    if (!clipSeconds.isFinite || clipSeconds <= 0) return 0.0;
    return math.min(maxFadeSeconds, clipSeconds / 3).toDouble();
  }

  static String _cover(int width, int height) =>
      'scale=$width:$height:force_original_aspect_ratio=increase:flags=lanczos,'
      'crop=$width:$height,'
      'setsar=1';

  /// [clips] must be sorted by start and must not overlap.
  static WorldBackgroundPlan build({
    required String videoPath,
    required int width,
    required int height,
    required List<WorldBackgroundClip> clips,
  }) {
    if (clips.isEmpty) {
      throw ArgumentError('لا توجد مشاهد عالم لتركيبها.');
    }
    if (width < 2 || height < 2) {
      throw ArgumentError('أبعاد الفيديو غير صالحة.');
    }

    final inputs = <String>['-i "$videoPath"'];
    final chains = <String>[
      '[0:v]scale=$width:$height:flags=lanczos,setsar=1,format=yuv420p'
          '[wb_base0]',
    ];

    var current = 'wb_base0';

    // 1. The world clips replace the picture inside their windows.
    for (var index = 0; index < clips.length; index++) {
      final clip = clips[index];
      final inputIndex = inputs.length;
      inputs.add('-i "${clip.path}"');

      final start = _f(clip.start);
      final end = _f(clip.end);
      final fade = fadeFor(clip.duration);
      final fadeOutStart = math.max(0.0, clip.duration - fade);
      final clipLabel = 'wb_clip_$index';
      final nextLabel = 'wb_base${index + 1}';

      // The light and the colour of the scene (see WorldLookGrade).
      final look = clip.look;
      final grade = look == null ? null : WorldLookGrade.filters(look);
      final gradePart = grade == null ? '' : '$grade,';

      chains.add(
        '[$inputIndex:v]'
        '${_cover(width, height)},'
        '$gradePart'
        'format=yuva420p,'
        'fade=t=in:st=0:d=${_f(fade)}:alpha=1,'
        'fade=t=out:st=${_f(fadeOutStart)}:d=${_f(fade)}:alpha=1,'
        'setpts=PTS-STARTPTS+$start/TB'
        '[$clipLabel]',
      );

      chains.add(
        '[$current][$clipLabel]'
        'overlay=x=0:y=0:eof_action=repeat:'
        "enable='between(t,$start,$end)'"
        '[$nextLabel]',
      );

      current = nextLabel;
    }

    // 2. The flat 2.5D layers (drawn on black) are screen-blended on top.
    final overlayClips = <WorldBackgroundClip>[
      for (final clip in clips)
        if (clip.overlayPath != null) clip,
    ];

    if (overlayClips.isNotEmpty) {
      chains.add('[$current]format=gbrp[wb_rgb0]');
      current = 'wb_rgb0';

      for (var index = 0; index < overlayClips.length; index++) {
        final clip = overlayClips[index];
        final inputIndex = inputs.length;
        inputs.add('-i "${clip.overlayPath}"');

        final start = _f(clip.start);
        final end = _f(clip.end);
        final fade = fadeFor(clip.duration);
        final fadeOutStart = math.max(0.0, clip.duration - fade);
        final overlayLabel = 'wb_ov_$index';
        final nextLabel = 'wb_rgb${index + 1}';

        chains.add(
          '[$inputIndex:v]'
          '${_cover(width, height)},'
          'format=gbrp,'
          'fade=t=in:st=0:d=${_f(fade)},'
          'fade=t=out:st=${_f(fadeOutStart)}:d=${_f(fade)},'
          'tpad=start_mode=add:start_duration=$start:color=black,'
          'setsar=1'
          '[$overlayLabel]',
        );

        chains.add(
          '[$current][$overlayLabel]'
          'blend=all_mode=screen:all_opacity=1:'
          "enable='between(t,$start,$end)'"
          '[$nextLabel]',
        );

        current = nextLabel;
      }
    }

    chains.add('[$current]format=yuv420p[$outputLabel]');

    return WorldBackgroundPlan(
      inputs: inputs,
      filterComplex: chains.join(';'),
      outputLabel: outputLabel,
    );
  }

  /// The full FFmpeg command (audio of the first input is kept).
  static String command({
    required WorldBackgroundPlan plan,
    required String outputPath,
    required double duration,
    bool maximumQuality = true,
  }) {
    final videoEncoder = maximumQuality
        ? '-c:v libx264 -preset fast -crf 17'
        : '-c:v libx264 -preset veryfast -crf 20';

    return '-y ${plan.inputs.join(' ')} '
        '-filter_complex "${plan.filterComplex}" '
        '-map "[${plan.outputLabel}]" '
        '-map "0:a?" '
        '$videoEncoder '
        '-pix_fmt yuv420p '
        '-c:a aac -b:a 192k -ar 48000 '
        '-t ${_f(duration)} '
        '-movflags +faststart "$outputPath"';
  }
}

class WorldSceneCompositor {
  WorldSceneCompositor._();

  /// Composes [clips] over [videoPath] and returns the new file (next to the
  /// source). Throws on any failure; the source is never touched.
  static Future<String> composite({
    required String videoPath,
    required List<WorldBackgroundClip> clips,
    required double duration,
    bool maximumQuality = true,
    void Function(String message)? onStatus,
    void Function(double progress)? onProgress,
  }) async {
    final sourceFile = File(videoPath);

    if (!await sourceFile.exists()) {
      throw FileSystemException('الفيديو الأصلي غير موجود.', videoPath);
    }

    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Video duration must be greater than zero.',
      );
    }

    if (clips.isEmpty) {
      throw ArgumentError('لا توجد مشاهد عالم لتركيبها.');
    }

    final info = await SilenceCutter.probe(videoPath);

    if (info.w < 2 || info.h < 2) {
      throw StateError('أبعاد الفيديو الأصلي غير صالحة.');
    }

    final valid = <WorldBackgroundClip>[];

    for (final clip in clips) {
      final file = File(clip.path);

      if (!await file.exists() || await file.length() < 2048) continue;

      final start = clip.start.clamp(0.0, duration).toDouble();
      final end = clip.end.clamp(0.0, duration).toDouble();

      if (!start.isFinite || !end.isFinite || end - start < 0.5) continue;

      String? overlay;
      final overlayPath = clip.overlayPath;

      if (overlayPath != null) {
        final overlayFile = File(overlayPath);
        if (await overlayFile.exists() && await overlayFile.length() >= 2048) {
          overlay = overlayPath;
        }
      }

      valid.add(
        WorldBackgroundClip(
          path: clip.path,
          start: start,
          end: end,
          overlayPath: overlay,
          look: clip.look,
        ),
      );
    }

    valid.sort((a, b) => a.start.compareTo(b.start));

    final ordered = <WorldBackgroundClip>[];
    var lastEnd = 0.0;

    for (final clip in valid) {
      if (clip.start < lastEnd - 0.001) continue;
      ordered.add(clip);
      lastEnd = clip.end;
    }

    if (ordered.isEmpty) {
      throw StateError('كل مشاهد العالم غير صالحة أو خارج مدة الفيديو.');
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${sourceFile.parent.path}/world_bg_composite_$stamp.mp4';

    final plan = WorldBackgroundCommand.build(
      videoPath: videoPath,
      width: info.w,
      height: info.h,
      clips: ordered,
    );

    final command = WorldBackgroundCommand.command(
      plan: plan,
      outputPath: outputPath,
      duration: duration,
      maximumQuality: maximumQuality,
    );

    onStatus?.call(
      'جاري تركيب ${ordered.length} مشاهد عالم كخلفية كاملة...',
    );

    final encoded = await SilenceCutter.encode(command, duration, onProgress);

    final outputFile = File(outputPath);

    if (!encoded ||
        !await outputFile.exists() ||
        await outputFile.length() < 4096) {
      try {
        if (await outputFile.exists()) await outputFile.delete();
      } catch (_) {}

      throw FileSystemException(
        'فشل تركيب العالم كخلفية كاملة.',
        outputPath,
      );
    }

    onStatus?.call('اكتمل تركيب العالم كخلفية كاملة.');

    return outputPath;
  }
}
