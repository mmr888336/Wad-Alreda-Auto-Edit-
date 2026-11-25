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
///
/// Because the world replaces the whole picture, two things of the video would
/// disappear inside a scene window, and both are put back on top of the world:
///  * the PERSON: cut out of the original video with a per-frame matte
///    ([WorldBackgroundClip.matte]). The cut-out is made of the very pixels of
///    the video, so it matches the picture underneath during the fades;
///  * the CAPTIONS and the hook title: their PNG layers are drawn again on top
///    ([WorldTextOverlay]).
///
/// The original audio is kept. Any failure throws, so the caller can go back
/// to the previous composition.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'cinematic_world.dart' show WorldLook;
import 'person_segmentation_matte.dart';
import 'person_silhouette.dart' show PersonMatteSequence;
import 'silence_cutter.dart';
import 'timeline_engine.dart';
import 'world_look_grade.dart';

/// One scene of the world shown as the full picture of the video.
class WorldBackgroundClip {
  const WorldBackgroundClip({
    required this.path,
    required this.start,
    required this.end,
    this.overlayPath,
    this.look,
    this.matte,
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

  /// Per-frame matte of the person in the window (white = person). When set,
  /// the person of the original video is drawn on top of the world.
  final PersonMatteSequence? matte;

  double get duration => end - start;

  WorldBackgroundClip withMatte(PersonMatteSequence? value) =>
      WorldBackgroundClip(
        path: path,
        start: start,
        end: end,
        overlayPath: overlayPath,
        look: look,
        matte: value,
      );
}

/// A caption or title picture (PNG) that is drawn again on top of the world.
class WorldTextOverlay {
  const WorldTextOverlay({
    required this.path,
    required this.start,
    required this.end,
    required this.y,
  });

  final String path;

  /// Window of the layer in the video, in seconds.
  final double start;
  final double end;

  /// Vertical centre of the picture, 0..1 of the frame height.
  final double y;

  /// Most overlays one composition carries (each one is an FFmpeg input).
  static const int maxCount = 60;

  /// The caption and title layers of [project] that have a picture.
  static List<WorldTextOverlay> fromTimeline(TimelineProject project) {
    final result = <WorldTextOverlay>[];

    for (final layer in project.layers) {
      if (!layer.visible) continue;
      if (layer.type != TimelineLayerType.caption &&
          layer.type != TimelineLayerType.title) {
        continue;
      }

      final path = layer.sourcePath;
      if (path == null || path.trim().isEmpty) continue;
      if (!layer.start.isFinite ||
          !layer.end.isFinite ||
          layer.end <= layer.start) {
        continue;
      }

      final fallbackY = layer.type == TimelineLayerType.title ? 0.10 : 0.80;
      final rawY =
          layer.keyframes.isEmpty ? fallbackY : layer.transformAt(layer.end).y;
      final y = rawY.isFinite ? rawY.clamp(0.02, 0.98).toDouble() : fallbackY;

      result.add(
        WorldTextOverlay(
          path: path,
          start: layer.start,
          end: layer.end,
          y: y,
        ),
      );
    }

    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }
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
    List<WorldTextOverlay> textOverlays = const <WorldTextOverlay>[],
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

      // The light and the colour of the scene (see WorldLookGrade). The master
      // switch of the grade is honoured here too.
      final look = WorldLookGrade.enabled ? clip.look : null;
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

    final mattedClips = <int>[
      for (var index = 0; index < clips.length; index++)
        if (clips[index].matte != null) index,
    ];

    final texts = <WorldTextOverlay>[];
    for (final overlay in textOverlays) {
      if (texts.length >= WorldTextOverlay.maxCount) break;
      if (_windowsOf(overlay, clips).isNotEmpty) texts.add(overlay);
    }

    if (mattedClips.isNotEmpty || texts.isNotEmpty) {
      chains.add('[$current]format=yuv420p[wb_yuv]');
      current = 'wb_yuv';
    }

    // 3. The person of the original video, cut out, on top of the world. It
    // reads ITS OWN short window of the video (-ss/-t), so no full-size stream
    // is buffered. The cut-out is made of the pixels of the video itself, so
    // it matches the picture underneath while the world fades in and out.
    for (final index in mattedClips) {
      final clip = clips[index];
      final matte = clip.matte!;
      final start = _f(clip.start);
      final end = _f(clip.end);
      final windowSeconds = _f(math.max(0.2, clip.duration + 0.1));

      inputs.add('-ss $start -t $windowSeconds -i "$videoPath"');
      final personIndex = inputs.length - 1;
      inputs.add('-framerate ${_f(matte.fps)} -i "${matte.pattern}"');
      final matteIndex = inputs.length - 1;

      final matteLabel = 'wb_matte_$index';
      final windowLabel = 'wb_win_$index';
      final cutLabel = 'wb_cut_$index';
      final topLabel = 'wb_top_$index';

      chains.add(
        '[$matteIndex:v]setpts=PTS-STARTPTS+$start/TB,'
        'scale=$width:$height:flags=bilinear,'
        'gblur=sigma=2.5,format=gray[$matteLabel]',
      );
      chains.add(
        '[$personIndex:v]scale=$width:$height:flags=lanczos,setsar=1,'
        'format=yuv420p,setpts=PTS-STARTPTS+$start/TB[$windowLabel]',
      );
      chains.add('[$windowLabel][$matteLabel]alphamerge[$cutLabel]');
      chains.add(
        '[$current][$cutLabel]overlay=x=0:y=0:'
        "eof_action=pass:repeatlast=0:enable='between(t,$start,$end)'"
        '[$topLabel]',
      );
      current = topLabel;
    }

    // 4. The captions and the hook title, drawn again on top of everything.
    for (var index = 0; index < texts.length; index++) {
      final overlay = texts[index];
      final windows = _windowsOf(overlay, clips);
      final duration = math.max(0.1, overlay.end - overlay.start);

      inputs.add(
        '-loop 1 -framerate 30 -t ${_f(duration + 0.1)} -i "${overlay.path}"',
      );
      final inputIndex = inputs.length - 1;

      final textLabel = 'wb_txt_$index';
      final outLabel = 'wb_txtout_$index';

      chains.add(
        '[$inputIndex:v]scale=$width:-2:flags=lanczos,format=rgba,'
        'setpts=PTS-STARTPTS+${_f(overlay.start)}/TB[$textLabel]',
      );
      chains.add(
        "[$current][$textLabel]overlay=x='(main_w-overlay_w)/2':"
        "y='main_h*${_f(overlay.y)}-overlay_h/2':"
        'eof_action=pass:repeatlast=0:'
        "enable='${windows.join('+')}'"
        '[$outLabel]',
      );
      current = outLabel;
    }

    chains.add('[$current]format=yuv420p[$outputLabel]');

    return WorldBackgroundPlan(
      inputs: inputs,
      filterComplex: chains.join(';'),
      outputLabel: outputLabel,
    );
  }

  /// `between(...)` terms for the parts of [overlay] that fall inside a world
  /// clip window (empty when it never does).
  static List<String> _windowsOf(
    WorldTextOverlay overlay,
    List<WorldBackgroundClip> clips,
  ) {
    final windows = <String>[];
    for (final clip in clips) {
      final from = math.max(overlay.start, clip.start);
      final to = math.min(overlay.end, clip.end);
      if (to - from >= 0.05) {
        windows.add('between(t,${_f(from)},${_f(to)})');
      }
    }
    return windows;
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

  /// Switch: draw the person of the video on top of the world scenes. Any
  /// failure to cut the person out leaves that scene as it was (world only).
  static bool keepPersonEnabled = true;

  /// Composes [clips] over [videoPath] and returns the new file (next to the
  /// source). Throws on any failure; the source is never touched.
  static Future<String> composite({
    required String videoPath,
    required List<WorldBackgroundClip> clips,
    required double duration,
    bool maximumQuality = true,
    List<WorldTextOverlay> textOverlays = const <WorldTextOverlay>[],
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

    // The captions and the title that fall inside a world window, and whose
    // picture is still on disk.
    final texts = <WorldTextOverlay>[];
    for (final overlay in textOverlays) {
      if (texts.length >= WorldTextOverlay.maxCount) break;

      final overlaps = ordered.any(
        (clip) =>
            math.min(overlay.end, clip.end) -
                math.max(overlay.start, clip.start) >=
            0.05,
      );
      if (!overlaps) continue;
      if (!await File(overlay.path).exists()) continue;

      texts.add(overlay);
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${sourceFile.parent.path}/world_bg_composite_$stamp.mp4';

    Directory? work;

    try {
      // The person of the video, cut out for every scene window.
      var composed = ordered;

      if (keepPersonEnabled) {
        try {
          final temp = await getTemporaryDirectory();
          final created = Directory('${temp.path}/world_person_$stamp');
          await created.create(recursive: true);
          work = created;
        } catch (_) {
          work = null;
        }
      }

      final folder = work;
      if (folder != null) {
        composed = <WorldBackgroundClip>[];

        for (var index = 0; index < ordered.length; index++) {
          final clip = ordered[index];
          onStatus?.call('جاري قص الشخص للمشهد ${index + 1}...');

          PersonMatteSequence? matte;
          try {
            matte = await PersonSegmentationMatte.render(
              videoPath: videoPath,
              start: clip.start,
              end: clip.end,
              directory: '${folder.path}/matte_$index',
              frameWidth: info.w,
              frameHeight: info.h,
            );
          } catch (_) {
            matte = null;
          }

          composed.add(clip.withMatte(matte));
        }
      }

      final plan = WorldBackgroundCommand.build(
        videoPath: videoPath,
        width: info.w,
        height: info.h,
        clips: composed,
        textOverlays: texts,
      );

      final command = WorldBackgroundCommand.command(
        plan: plan,
        outputPath: outputPath,
        duration: duration,
        maximumQuality: maximumQuality,
      );

      onStatus?.call(
        'جاري تركيب ${composed.length} مشاهد عالم كخلفية كاملة...',
      );

      var encoded = await SilenceCutter.encode(command, duration, onProgress);

      var outputFile = File(outputPath);

      // The person and the captions are extras: if their graph cannot be
      // encoded, the plain world composition is encoded instead.
      final hasExtras =
          texts.isNotEmpty || composed.any((clip) => clip.matte != null);

      if ((!encoded ||
              !await outputFile.exists() ||
              await outputFile.length() < 4096) &&
          hasExtras) {
        try {
          if (await outputFile.exists()) await outputFile.delete();
        } catch (_) {}

        onStatus?.call('جاري تركيب العالم بدون الشخص والكابشن...');

        final plainPlan = WorldBackgroundCommand.build(
          videoPath: videoPath,
          width: info.w,
          height: info.h,
          clips: <WorldBackgroundClip>[
            for (final clip in composed) clip.withMatte(null),
          ],
        );

        encoded = await SilenceCutter.encode(
          WorldBackgroundCommand.command(
            plan: plainPlan,
            outputPath: outputPath,
            duration: duration,
            maximumQuality: maximumQuality,
          ),
          duration,
          onProgress,
        );
        outputFile = File(outputPath);
      }

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
    } finally {
      final folder = work;
      if (folder != null) {
        try {
          if (await folder.exists()) await folder.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
