import 'dart:io';
import 'dart:math' as math;
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'analyzer.dart';
import 'broll.dart';
import 'settings.dart';
import 'editing_engine.dart';
import 'motion_graphics.dart';
import 'timeline_engine.dart';
import 'sound_effect_generator.dart';
import 'silence_cutter.dart';
import 'text_render.dart';

class EnhanceResult {
  final String videoPath;
  final String? coverPath;
  final String title;
  final String description;
  final List<String> hashtags;
  final List<String> notes;
  final double sizeMb;
  final int outW;
  final int outH;

  /// The exact layer manifest used by the renderer for this export.
  /// It is passed to the next Studio/timeline stage as structured data.
  final TimelineProject timelineProject;

  EnhanceResult({
    required this.videoPath,
    required this.coverPath,
    required this.title,
    required this.description,
    required this.hashtags,
    required this.notes,
    required this.sizeMb,
    required this.outW,
    required this.outH,
    required this.timelineProject,
  });
}

class _Broll {
  final String path;
  final double start;
  final double end;
  _Broll(this.path, this.start, this.end);
}

/// After silence cutting: captions, hook, B-roll, effects, audio cleanup,
/// cover generation and final export.
class Enhancer {
  static String _f(double v) => v.toStringAsFixed(2);

  static void _checkCancel() {
    if (JobControl.cancelled) throw Exception('تم إلغاء المونتاج.');
  }

  static Future<bool> _run(String cmd) async {
    final session = await FFmpegKit.execute(cmd);
    return ReturnCode.isSuccess(await session.getReturnCode());
  }

  static String _styleFilter(String style) {
    switch (style) {
      case 'clean':
        return ',eq=contrast=1.05:saturation=1.08,unsharp=5:5:0.4:3:3:0.0';
      case 'vivid':
        return ',eq=contrast=1.08:saturation=1.30:brightness=0.01,unsharp=5:5:0.45:3:3:0.0';
      case 'cinematic':
      default:
        return ',colorbalance=rs=-0.04:bs=0.05:rh=0.05:bh=-0.04,eq=contrast=1.10:saturation=1.05:brightness=-0.01,unsharp=5:5:0.35:3:3:0.0,vignette=angle=PI/5';
    }
  }

  /// Turns the actual assets produced by this editing job into a structured
  /// multi-track project. The renderer and the future Studio UI share this
  /// exact project object rather than rebuilding a decorative timeline.
  static TimelineProject _createTimelineProject({
    required String projectId,
    required String sourcePath,
    required double duration,
    required int width,
    required int height,
    required List<_Broll> brolls,
    required List<Caption> captions,
    required List<String> captionFiles,
    required String? hookPath,
    required String hookText,
    required String? effectPath,
    required String effectStyle,
    required MotionGraphicsPlan motionPlan,
    required AppSettings settings,
  }) {
    const videoTrackId = 'track_video';
    const brollTrackId = 'track_broll';
    const captionTrackId = 'track_captions';
    const graphicsTrackId = 'track_graphics';
    const audioTrackId = 'track_audio';
    const effectsTrackId = 'track_effects';

    final videoLayers = <TimelineLayer>[
      TimelineLayer(
        id: 'source_video',
        trackId: videoTrackId,
        type: TimelineLayerType.sourceVideo,
        name: 'الفيديو الأصلي',
        start: 0,
        end: duration,
        zIndex: 0,
        sourcePath: sourcePath,
      ),
    ];

    final brollLayers = <TimelineLayer>[];
    for (var i = 0; i < brolls.length; i++) {
      final item = brolls[i];
      final start = item.start.clamp(0.0, duration).toDouble();
      final end = item.end.clamp(0.0, duration).toDouble();
      if (end <= start + 0.001) continue;

      brollLayers.add(
        TimelineLayer(
          id: 'broll_$i',
          trackId: brollTrackId,
          type: TimelineLayerType.broll,
          name: 'لقطة إضافية ${brollLayers.length + 1}',
          start: start,
          end: end,
          zIndex: 10,
          sourcePath: item.path,
        ),
      );
    }

    final captionLayers = <TimelineLayer>[];
    final captionCount = math.min(captions.length, captionFiles.length);
    final baseY = settings.captionPosition == 'middle' ? 0.5 : 0.80;
    final travel = 0.04 * (motionPlan.captionTravel / 0.48);
    final dynamicMotion = motionPlan.mood == MotionMood.dynamic;

    for (var i = 0; i < captionCount; i++) {
      final caption = captions[i];
      final start = caption.start.clamp(0.0, duration).toDouble();
      final end = caption.end.clamp(0.0, duration).toDouble();
      if (end <= start + 0.001) continue;

      var initialY = baseY;
      if (settings.captionAnimation == 'slideUp') {
        initialY = baseY + travel;
      } else if (settings.captionAnimation == 'slideDown') {
        initialY = baseY - travel;
      }

      final enterEnd = math.min(
        end,
        start + motionPlan.captionEnterSeconds,
      ).toDouble();
      final hasEntrance = enterEnd > start + 0.001;

      captionLayers.add(
        TimelineLayer(
          id: 'caption_$i',
          trackId: captionTrackId,
          type: TimelineLayerType.caption,
          name: 'كابشن ${captionLayers.length + 1}',
          start: start,
          end: end,
          zIndex: 20,
          sourcePath: captionFiles[i],
          text: caption.text,
          keyframes: [
            TransformKeyframe(
              time: start,
              transform: LayerTransform(
                x: hasEntrance && dynamicMotion ? 0.98 : 0.5,
                y: hasEntrance ? initialY : baseY,
                opacity: hasEntrance ? 0 : 1,
              ),
              easing: KeyframeEasing.easeOut,
            ),
            if (hasEntrance)
              TransformKeyframe(
                time: enterEnd,
                transform: LayerTransform(x: 0.5, y: baseY, opacity: 1),
              ),
          ],
        ),
      );
    }

    final titleLayers = <TimelineLayer>[];
    if (hookPath != null && hookText.trim().isNotEmpty && duration > 0.05) {
      final start = math.min(0.1, duration * 0.1).toDouble();
      final end = math.min(
        duration,
        start + motionPlan.hookDurationSeconds,
      ).toDouble();
      if (end > start + 0.001) {
        final enterEnd = math.min(
          end,
          start + motionPlan.hookEnterSeconds,
        ).toDouble();
        final hasEntrance = enterEnd > start + 0.001;
        final initialY = motionPlan.mood == MotionMood.dynamic ? 0.10 : 0.02;

        titleLayers.add(
          TimelineLayer(
            id: 'title_main',
            trackId: graphicsTrackId,
            type: TimelineLayerType.title,
            name: 'عنوان البداية',
            start: start,
            end: end,
            zIndex: 30,
            sourcePath: hookPath,
            text: hookText,
            keyframes: [
              TransformKeyframe(
                time: start,
                transform: LayerTransform(
                  x: hasEntrance && dynamicMotion ? 0.98 : 0.5,
                  y: hasEntrance ? initialY : 0.10,
                  opacity: hasEntrance ? 0 : 1,
                ),
                easing: KeyframeEasing.easeOut,
              ),
              if (hasEntrance)
                TransformKeyframe(
                  time: enterEnd,
                  transform: const LayerTransform(x: 0.5, y: 0.10),
                ),
            ],
          ),
        );
      }
    }

    final audioLayers = <TimelineLayer>[
      TimelineLayer(
        id: 'source_audio',
        trackId: audioTrackId,
        type: TimelineLayerType.sourceAudio,
        name: 'الصوت الأصلي',
        start: 0,
        end: duration,
        zIndex: 0,
        sourcePath: sourcePath,
      ),
    ];

    final effectLayers = <TimelineLayer>[];
    if (effectPath != null && effectStyle != 'none') {
      final effectDuration = SoundEffectGenerator.durationFor(effectStyle);
      final triggerTimes = <double>[
        ...brollLayers.map((layer) => layer.start),
        ...titleLayers.map((layer) => layer.start),
      ].toSet().toList()
        ..sort();

      for (var i = 0; i < triggerTimes.length && i < 6; i++) {
        final start = triggerTimes[i];
        final end = math.min(duration, start + effectDuration).toDouble();
        if (end <= start + 0.001) continue;

        effectLayers.add(
          TimelineLayer(
            id: 'sound_effect_$i',
            trackId: effectsTrackId,
            type: TimelineLayerType.soundEffect,
            name: 'مؤثر صوتي ${i + 1}',
            start: start,
            end: end,
            zIndex: 40,
            sourcePath: effectPath,
          ),
        );
      }
    }

    return TimelineProject(
      id: projectId,
      duration: duration,
      width: width,
      height: height,
      frameRate: 30,
      tracks: [
        TimelineTrack(
          id: videoTrackId,
          name: 'الفيديو',
          type: TimelineTrackType.video,
          order: 0,
          layers: videoLayers,
        ),
        TimelineTrack(
          id: brollTrackId,
          name: 'B-roll',
          type: TimelineTrackType.broll,
          order: 1,
          layers: brollLayers,
        ),
        TimelineTrack(
          id: captionTrackId,
          name: 'الكابشن',
          type: TimelineTrackType.captions,
          order: 2,
          layers: captionLayers,
        ),
        TimelineTrack(
          id: graphicsTrackId,
          name: 'العناوين والجرافيك',
          type: TimelineTrackType.graphics,
          order: 3,
          layers: titleLayers,
        ),
        TimelineTrack(
          id: audioTrackId,
          name: 'الصوت',
          type: TimelineTrackType.audio,
          order: 4,
          layers: audioLayers,
        ),
        TimelineTrack(
          id: effectsTrackId,
          name: 'المؤثرات',
          type: TimelineTrackType.effects,
          order: 5,
          layers: effectLayers,
        ),
      ],
    );
  }

  /// Checks a B-roll frame visually: true means it passed the configured filter.
  static Future<bool> _clipIsSafe(
    AppSettings s,
    String clip,
    String dir,
    int stamp,
    String tag,
    List<String> temps,
  ) async {
    try {
      final jpg = '$dir/chk_${stamp}_$tag.jpg';
      temps.add(jpg);
      final ok = await _run(
        '-y -ss 1 -i "$clip" -frames:v 1 -vf scale=320:-2 -q:v 5 "$jpg"',
      );
      if (!ok || !File(jpg).existsSync()) return false;
      final woman = await Analyzer.containsWoman(s, jpg);
      return !woman;
    } catch (_) {
      return false;
    }
  }

  static Future<EnhanceResult> run({
    required String cutPath,
    required double cutSec,
    required AppSettings s,
    List<double> cutTimes = const [],
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    final notes = <String>[];
    final temps = <String>[];
    final dir = File(cutPath).parent.path;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    onStatus?.call('جاري فحص الفيديو...');
    final info = await SilenceCutter.probe(cutPath);
    final short = math.min(info.w, info.h);
    final targetShort = s.upscale2k ? 1440 : math.min(short, 1440);
    final factor = targetShort / short;

    int even(double value) {
      var result = value.round();
      if (result.isOdd) result++;
      return result;
    }

    final outW = even(info.w * factor);
    final outH = even(info.h * factor);
    final portrait = outH >= outW;

    // 1) Analyse the audio with the configured AI providers.
    Analysis? an;
    if (!s.hasAnyAiKey) {
      notes.add(
        'ما في مفتاح ذكاء اصطناعي؛ لم تتم إضافة الكابشن أو العنوان أو B-roll.',
      );
    } else if (cutSec > 300) {
      notes.add('الفيديو أطول من 5 دقائق؛ تم تخطي التحليل بالذكاء الاصطناعي.');
    } else {
      try {
        _checkCancel();
        onStatus?.call('جاري تفريغ الصوت وتحليله بالذكاء الاصطناعي...');
        final wav = '$dir/audio_$stamp.wav';
        temps.add(wav);
        final ok = await _run(
          '-y -i "$cutPath" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$wav"',
        );
        if (!ok) throw Exception('تعذر استخراج الصوت من الفيديو.');
        final res = await Analyzer.run(
          s,
          wav,
          cutSec,
          cutTimes: cutTimes,
          onStatus: onStatus,
        );
        an = res;
        notes.addAll(res.notes);
      } catch (e) {
        if (JobControl.cancelled) rethrow;
        notes.add('تعذر التحليل: $e');
      }
    }
    final analysis = an;

    // 2) Select a topic-aware editing profile and motion plan.
    // This is local and makes no additional AI/API request.
    final profileText = [
      analysis?.title ?? '',
      analysis?.description ?? '',
      if (analysis != null) ...analysis.captions.map((caption) => caption.text),
      if (analysis != null) ...analysis.broll.map((idea) => idea.query),
    ].join(' ').trim();
    final editingProfile = EditingEngine.select(
      content: profileText,
      requestedStyle: s.visualStyle,
    );
    final motionPlan = MotionGraphicsPlan.forProfile(editingProfile);
    final captionStyle = editingProfile.isAutomatic
        ? editingProfile.captionStyle
        : s.captionStyle;
    final punchZoom = editingProfile.isAutomatic
        ? editingProfile.punchZoom
        : s.punchZoom;
    final flashTransitions = editingProfile.isAutomatic
        ? editingProfile.flashTransitions
        : s.flashTransitions;
    if (editingProfile.isAutomatic && profileText.isNotEmpty) {
      notes.add('المحرك التلقائي اختار أسلوب: ${editingProfile.label}.');
    }

    // 3) Render caption and hook images.
    final caps = <Caption>[];
    final capFiles = <String>[];
    String? hookFile;
    if (analysis != null) {
      try {
        if (s.captions) {
          onStatus?.call('جاري تجهيز الكابشن...');
          for (var i = 0; i < analysis.captions.length; i++) {
            final path = '$dir/cap_${stamp}_$i.png';
            await TextRender.png(
              text: analysis.captions[i].text,
              outPath: path,
              width: outW,
              fontSize: outW * 0.062,
              fill: Colors.white,
              fontFamily: s.captionFont,
              style: captionStyle,
            );
            temps.add(path);
            caps.add(analysis.captions[i]);
            capFiles.add(path);
          }
          if (caps.isEmpty) {
            notes.add('لم يتم التعرف على كلام مناسب للكابشن.');
          }
        }
        if (s.hook && analysis.title.isNotEmpty) {
          final path = await TextRender.png(
            text: analysis.title,
            outPath: '$dir/hook_$stamp.png',
            width: outW,
            fontSize: outW * 0.085,
            fill: const Color(0xFFFFD400),
            box: true,
            fontFamily: s.captionFont,
            style: 'boxed',
          );
          temps.add(path);
          hookFile = path;
        }
      } catch (e) {
        notes.add('تعذر رسم النصوص: $e');
      }
    }
    // 4) Fetch topic-related B-roll, subject to the existing safety check.
    final brolls = <_Broll>[];
    if (s.broll && analysis != null && analysis.broll.isNotEmpty) {
      final hasKey = s.brollProvider == 'pixabay'
          ? s.pixabayKey.trim().isNotEmpty
          : s.pexelsKey.trim().isNotEmpty;
      if (!hasKey) {
        notes.add(
          'لا يوجد مفتاح ${s.brollProvider} للـ B-roll. أضفه من الإعدادات.',
        );
      } else {
        try {
          final ideas = analysis.broll
              .where((b) =>
                  b.start >= 3.5 &&
                  b.end <= cutSec - 0.3 &&
                  b.end - b.start >= 1.5)
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
          var lastEnd = 0.0;
          var index = 0;
          for (final idea in ideas) {
            if (brolls.length >= editingProfile.maxBroll) break;
            if (idea.start < lastEnd + 1.0) continue;
            _checkCancel();
            onStatus?.call(
              'جاري تحميل وفحص B-roll (${brolls.length + 1})...',
            );
            String? got;
            for (var attempt = 0; attempt < 3 && got == null; attempt++) {
              // Last attempt: 2D animation through Pixabay if enabled.
              final animation = attempt == 2;
              final out = '$dir/broll_${stamp}_${index}_$attempt.mp4';
              final file = await BrollFetcher.fetch(
                s,
                idea.query,
                portrait,
                out,
                index + attempt,
                animation: animation,
              );
              if (file == null) continue;
              temps.add(file);
              final safe = await _clipIsSafe(
                s,
                file,
                dir,
                stamp,
                '${index}_$attempt',
                temps,
              );
              if (safe) {
                got = file;
              } else {
                try {
                  File(file).deleteSync();
                } catch (_) {}
              }
            }
            index++;
            if (got != null) {
              brolls.add(_Broll(got, idea.start, idea.end));
              lastEnd = idea.end;
            }
          }
          if (brolls.isEmpty) {
            notes.add('لم أجد مقاطع B-roll مناسبة وآمنة؛ بقي الفيديو الأصلي.');
          }
        } catch (e) {
          if (JobControl.cancelled) rethrow;
          notes.add('تعذر تحميل B-roll: $e');
        }
      }
    }

    // 5) Generate the selected non-musical effect locally using FFmpeg.
    String? whoosh;
    if (s.sfx && s.soundEffectStyle != 'none') {
      final path = '$dir/sfx_$stamp.wav';
      try {
        final ok = await SoundEffectGenerator.render(
          style: s.soundEffectStyle,
          outputPath: path,
          execute: _run,
        );
        if (ok && File(path).existsSync()) {
          whoosh = path;
          temps.add(path);
        } else {
          notes.add(
            'تعذر توليد المؤثر الصوتي المختار؛ سيستمر التصدير بدونه.',
          );
        }
      } catch (e) {
        notes.add('تعذر توليد المؤثر الصوتي: $e');
      }
    }

    // 6) Build the real timeline project before rendering. The same layer
    // data drives FFmpeg now and will drive the interactive Studio later.
    onStatus?.call('جاري بناء طبقات المونتاج والحركات...');
    final timelineProject = _createTimelineProject(
      projectId: 'job_$stamp',
      sourcePath: cutPath,
      duration: cutSec,
      width: outW,
      height: outH,
      brolls: brolls,
      captions: caps,
      captionFiles: capFiles,
      hookPath: hookFile,
      hookText: analysis?.title ?? '',
      effectPath: whoosh,
      effectStyle: s.soundEffectStyle,
      motionPlan: motionPlan,
      settings: s,
    );
    final timelineErrors = timelineProject.validate();
    if (timelineErrors.isNotEmpty) {
      notes.add(
        'تم رصد مشكلة في بيانات بعض الطبقات: ${timelineErrors.first}',
      );
    }

    final totalKbps = s.targetMb * 279.6;
    final vK = (totalKbps - 128).clamp(800.0, 14000.0).round();
    final out = '$dir/final_$stamp.mp4';

    String buildCommand({required bool audioFx, required bool visFx}) {
      final inputs = <String>['-i "$cutPath"'];
      final style = (visFx && s.visualEffects)
          ? _styleFilter(editingProfile.visualStyle)
          : '';
      final chains = <String>[
        '[0:v]scale=$outW:$outH:flags=lanczos,setsar=1$style[base]'
      ];
      var cur = 'base';
      var n = 0;
      String next() => 'v${n++}';
      final flashTimes = <double>[];
      final sfxTimes = timelineProject
          .layersOfType(TimelineLayerType.soundEffect)
          .where((layer) => layer.visible)
          .map((layer) => layer.start)
          .toList();

      // Punch-in crop around selected edit points.
      if (visFx && s.visualEffects && punchZoom && cutTimes.length >= 3) {
        final wins = <String>[];
        for (var i = 1; i < cutTimes.length; i += 2) {
          final st = cutTimes[i];
          final en = (i + 1 < cutTimes.length) ? cutTimes[i + 1] : cutSec;
          if (en - st > 0.3) {
            wins.add('between(t,${_f(st)},${_f(en)})');
          }
        }
        if (wins.isNotEmpty) {
          final o = next();
          chains.add('[$cur]split[za][zb]');
          chains.add(
            '[zb]crop=w=iw/1.12:h=ih/1.12:x=(iw-ow)/2:y=(ih-oh)/2,scale=$outW:$outH:flags=bicubic[zc]',
          );
          chains.add(
            "[za][zc]overlay=x=0:y=0:enable='${wins.take(60).join('+')}'[$o]",
          );
          cur = o;
        }
      }

      // B-roll sources are read from the project layers, not from a second
      // independently maintained list.
      final brollLayers = timelineProject
          .layersOfType(TimelineLayerType.broll)
          .where((layer) => layer.visible && layer.sourcePath != null);
      for (final layer in brollLayers) {
        final idx = inputs.length;
        inputs.add('-i "${layer.sourcePath}"');
        chains.add(
          '[$idx:v]${motionPlan.brollInputFilter(width: outW, height: outH, start: layer.start, end: layer.end)}[bv$idx]',
        );
        final o = next();
        chains.add(
          "[$cur][bv$idx]overlay=x=0:y=0:enable='between(t,${_f(layer.start)},${_f(layer.end)})'[$o]",
        );
        cur = o;
        flashTimes.add(layer.start);
      }

      // Brief flash transitions at B-roll boundaries.
      if (visFx && s.visualEffects && flashTransitions && flashTimes.isNotEmpty) {
        final en = flashTimes
            .map((t) => 'between(t,${_f(t)},${_f(t + 0.07)})')
            .join('+');
        final o = next();
        chains.add(
          "[$cur]drawbox=x=0:y=0:w=iw:h=ih:color=white@0.5:t=fill:enable='$en'[$o]",
        );
        cur = o;
      }

      // Keyframed captions: FFmpeg evaluates the layer's normalized X/Y
      // transform against the main frame at each output frame.
      final captionLayers = timelineProject
          .layersOfType(TimelineLayerType.caption)
          .where((layer) => layer.visible && layer.sourcePath != null);
      var captionIndex = 0;
      for (final layer in captionLayers) {
        final idx = inputs.length;
        final duration = math.max(0.1, layer.duration).toDouble();
        inputs.add(
          '-loop 1 -framerate 30 -t ${_f(duration)} -i "${layer.sourcePath}"',
        );

        final label = 'caption_motion_$captionIndex';
        final motionFilter = motionPlan.overlayInputFilter(
          duration: duration,
          timelineStart: layer.start,
        );
        final scaleValue =
            layer.ffmpegExpression(TransformProperty.scale, fallback: '1');
        chains.add(
          "[$idx:v]$motionFilter,scale=w='max(2,iw*($scaleValue))':h='max(2,ih*($scaleValue))':eval=frame[$label]",
        );

        final xValue =
            layer.ffmpegExpression(TransformProperty.x, fallback: '0.5');
        final yValue =
            layer.ffmpegExpression(TransformProperty.y, fallback: '0.8');
        final x = 'main_w*($xValue)-overlay_w/2';
        final y = 'main_h*($yValue)-overlay_h/2';
        final o = next();
        chains.add(
          "[$cur][$label]overlay=x='$x':y='$y':enable='between(t,${_f(layer.start)},${_f(layer.end)})'[$o]",
        );
        cur = o;
        captionIndex++;
      }

      // Keyframed opening title uses the same transform system as captions.
      final titleLayers = timelineProject
          .layersOfType(TimelineLayerType.title)
          .where((layer) => layer.visible && layer.sourcePath != null);
      var titleIndex = 0;
      for (final layer in titleLayers) {
        final idx = inputs.length;
        final duration = math.max(0.1, layer.duration).toDouble();
        inputs.add(
          '-loop 1 -framerate 30 -t ${_f(duration)} -i "${layer.sourcePath}"',
        );

        final label = 'title_motion_$titleIndex';
        final motionFilter = motionPlan.overlayInputFilter(
          duration: duration,
          timelineStart: layer.start,
          fadeInSeconds: motionPlan.hookEnterSeconds,
          fadeOutSeconds: 0.24,
        );
        final scaleValue =
            layer.ffmpegExpression(TransformProperty.scale, fallback: '1');
        chains.add(
          "[$idx:v]$motionFilter,scale=w='max(2,iw*($scaleValue))':h='max(2,ih*($scaleValue))':eval=frame[$label]",
        );

        final xValue =
            layer.ffmpegExpression(TransformProperty.x, fallback: '0.5');
        final yValue =
            layer.ffmpegExpression(TransformProperty.y, fallback: '0.1');
        final x = 'main_w*($xValue)-overlay_w/2';
        final y = 'main_h*($yValue)-overlay_h/2';
        final o = next();
        chains.add(
          "[$cur][$label]overlay=x='$x':y='$y':enable='between(t,${_f(layer.start)},${_f(layer.end)})'[$o]",
        );
        cur = o;
        titleIndex++;
      }

      // Progress bar.
      if (visFx && s.visualEffects && s.progressBar) {
        final idx = inputs.length;
        inputs.add(
          '-f lavfi -i "color=c=0xFFD400:s=${outW}x14:r=30:d=${_f(cutSec + 1)}"',
        );
        final o = next();
        chains.add(
          '[$cur][$idx:v]overlay=x=-overlay_w+main_w*t/${_f(cutSec)}:y=main_h-14[$o]',
        );
        cur = o;
      }

      // Audio cleanup and non-musical sound effects.
      var aLabel = '0:a';
      if (audioFx && s.enhanceAudio) {
        chains.add(
          '[0:a]highpass=f=80,afftdn=nf=-25,acompressor=threshold=0.1:ratio=3:attack=20:release=250,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[clean]',
        );
        aLabel = 'clean';
      }
      var audioMap = aLabel == '0:a' ? '0:a' : '"[clean]"';
      if (whoosh != null && sfxTimes.isNotEmpty) {
        final times = sfxTimes.take(6).toList();
        final mix = StringBuffer();
        for (var k = 0; k < times.length; k++) {
          final idx = inputs.length;
          inputs.add('-i "$whoosh"');
          final ms = (times[k] * 1000).round();
          chains.add('[$idx:a]adelay=$ms|$ms,apad,volume=0.45[sf$k]');
          mix.write('[sf$k]');
        }
        final count = times.length + 1;
        chains.add(
          '[$aLabel]${mix.toString()}amix=inputs=$count:duration=first:dropout_transition=0,volume=$count,alimiter=limit=0.95[aout]',
        );
        audioMap = '"[aout]"';
      }

      final videoEncoder = s.maximumQuality
          ? '-c:v libx264 -preset slow -crf 17'
          : '-c:v libx264 -preset veryfast -crf 21 -maxrate ${vK}k -bufsize ${vK * 2}k';
      final audioEncoder = s.maximumQuality
          ? '-c:a aac -b:a 192k -ar 48000'
          : '-c:a aac -b:a 128k -ar 48000';
      final tail =
          '$videoEncoder -pix_fmt yuv420p $audioEncoder -movflags +faststart -t ${_f(cutSec + 0.2)} "$out"';
      return '-y ${inputs.join(' ')} -filter_complex "${chains.join(';')}" -map "[$cur]" -map $audioMap $tail';
    }

    onStatus?.call(
      s.maximumQuality
          ? 'جاري التصدير بأعلى جودة ${outW}×${outH} — قد يستغرق وقتاً أطول...'
          : 'جاري التصدير ${outW}×${outH} مع التحسينات...',
    );
    var ok = await SilenceCutter.encode(
      buildCommand(audioFx: true, visFx: true),
      cutSec,
      onProgress,
    );

    if (!ok) {
      _checkCancel();
      notes.add(
        'بعض الفلاتر المتقدمة ما اشتغلت؛ صدّرت بدونها مع الكابشن والـ B-roll.',
      );
      onStatus?.call('جاري التصدير بدون الفلاتر المتقدمة...');
      ok = await SilenceCutter.encode(
        buildCommand(audioFx: false, visFx: false),
        cutSec,
        onProgress,
      );
    }
    if (!ok) {
      _checkCancel();
      notes.add('فشل التركيب؛ صدّرت نسخة بسيطة.');
      onStatus?.call('جاري التصدير البسيط...');
      final fallbackVideoEncoder = s.maximumQuality
          ? '-c:v libx264 -preset slow -crf 18'
          : '-c:v libx264 -preset veryfast -crf 21 -maxrate ${vK}k -bufsize ${vK * 2}k';
      final fallbackAudioEncoder = s.maximumQuality
          ? '-c:a aac -b:a 192k'
          : '-c:a aac -b:a 128k';
      final simple =
          '-y -i "$cutPath" -vf "scale=$outW:$outH:flags=lanczos" $fallbackVideoEncoder -pix_fmt yuv420p $fallbackAudioEncoder -movflags +faststart "$out"';
      ok = await SilenceCutter.encode(simple, cutSec, onProgress);
      if (!ok) {
        _checkCancel();
        final simple2 = s.maximumQuality
            ? '-y -i "$cutPath" -vf "scale=$outW:$outH" -c:v mpeg4 -q:v 2 -c:a aac -b:a 192k "$out"'
            : '-y -i "$cutPath" -vf "scale=$outW:$outH" -c:v mpeg4 -b:v ${vK}k -c:a aac -b:a 128k "$out"';
        ok = await SilenceCutter.encode(simple2, cutSec, onProgress);
      }
    }
    _checkCancel();

    final finalPath = (ok && File(out).existsSync()) ? out : cutPath;
    if (finalPath == cutPath) {
      notes.add('فشل التصدير المحسّن؛ هذه نسخة القص فقط.');
    }

    // 7) Create a cover image from the edited source frame and AI title.
    String? coverPath;
    try {
      onStatus?.call('جاري تجهيز الغلاف...');
      final at = cutSec > 2 ? 1.0 : 0.0;
      final cover = '$dir/cover_$stamp.jpg';
      bool coverOk;
      if (analysis != null && analysis.title.isNotEmpty) {
        final titlePath = await TextRender.png(
          text: analysis.title,
          outPath: '$dir/covtitle_$stamp.png',
          width: outW,
          fontSize: outW * 0.105,
          fill: const Color(0xFFFFD400),
          box: true,
          fontFamily: s.captionFont,
          style: 'boxed',
        );
        temps.add(titlePath);
        coverOk = await _run(
          '-y -ss ${_f(at)} -i "$cutPath" -i "$titlePath" -filter_complex "[0:v]scale=$outW:$outH:flags=lanczos,setsar=1[b];[b][1:v]overlay=x=0:y=(main_h-overlay_h)/2[o]" -map "[o]" -frames:v 1 -q:v 2 "$cover"',
        );
      } else {
        coverOk = await _run(
          '-y -ss ${_f(at)} -i "$cutPath" -vf "scale=$outW:$outH:flags=lanczos" -frames:v 1 -q:v 2 "$cover"',
        );
      }
      if (coverOk && File(cover).existsSync()) coverPath = cover;
    } catch (e) {
      notes.add('تعذر تجهيز الغلاف: $e');
    }

    for (final path in temps) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    if (finalPath != cutPath) {
      try {
        File(cutPath).deleteSync();
      } catch (_) {}
    }

    final sizeMb = File(finalPath).lengthSync() / (1024 * 1024);
    return EnhanceResult(
      videoPath: finalPath,
      coverPath: coverPath,
      title: analysis?.title ?? '',
      description: analysis?.description ?? '',
      hashtags: analysis?.hashtags ?? <String>[],
      notes: notes,
      sizeMb: sizeMb,
      outW: outW,
      outH: outH,
      timelineProject: timelineProject,
    );
  }
}