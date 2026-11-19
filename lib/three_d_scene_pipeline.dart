import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:filament_renderer/filament_renderer.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'camera_hint_bridge.dart';
import 'cue_windows.dart';
import 'filament_scene_exporter.dart';
import 'khronos_model_catalog.dart';
import 'person_anchored_compositor.dart';
import 'person_tracking_service.dart';
import 'scene_frame_guard.dart';
import 'settings.dart';
import 'story_understanding.dart' show StoryBeat, StorySegment;
import 'three_d_asset_service.dart';
import 'three_d_crash_guard.dart';
import 'three_d_progress.dart';
import 'three_d_query_planner.dart';
import 'three_d_stage_log.dart';
import 'timeline_engine.dart';
import 'visual_tracking_engine.dart';

class ThreeDScenePipelineResult {
  final bool applied;
  final int scenesRendered;
  final List<String> notes;

  /// Stage-by-stage log of this export (search, download, GLB inspection,
  /// Filament load, capture, compositing). Null only for results created
  /// outside the pipeline.
  final ThreeDExportSummary? summary;

  const ThreeDScenePipelineResult({
    required this.applied,
    required this.scenesRendered,
    this.notes = const <String>[],
    this.summary,
  });
}

class _ThreeDCue {
  final double start;
  final double end;
  final String query;

  const _ThreeDCue({
    required this.start,
    required this.end,
    required this.query,
  });

  double get duration => end - start;
}

/// Automatic 3D scene pipeline:
/// - Reads real caption timestamps.
/// - Creates scene windows.
/// - Turns the spoken words into English search keywords.
/// - Searches and downloads GLB assets (with a built-in safety net).
/// - Loads each asset into the native Filament renderer.
/// - Captures camera movement. The camera of each scene follows the story:
///   the captions are read as a story and the camera hint of the beat spoken
///   during the scene picks the native camera mode (see [CameraHintBridge]);
///   a scene without a hint keeps the old fixed cycle.
/// - Tracks the main person (Phase 1) and anchors each 3D scene to them
///   (Phase 2); scenes that cannot be anchored keep the old panel.
/// - Composites rendered scenes into the exported video.
///
/// Every stage of every scene is logged (see [ThreeDExportSummary]): search,
/// download, GLB inspection, Filament load, camera, readiness, capture,
/// renderer release and compositing. Both the START and the END of each stage
/// are written, so a crash shows exactly which stage was running. A failed
/// attempt is reported with the stage it failed in, so a problem is never
/// blamed on the wrong step. The log of the latest export is kept in
/// [lastExportSummary] and, line by line, on disk (see [ThreeDCrashGuard]) so
/// it survives a crash.
///
/// The crash note is replaced as soon as a model finishes capturing, so a
/// later crash (releasing the renderer, the next search, compositing) is never
/// blamed on a model that worked.
///
/// Live progress is reported through `onProgress` for the whole phase.
///
/// The native Filament view is only needed while scenes are rendered. As soon
/// as the last scene is captured the pipeline calls `onRenderingDone`, so the
/// screen can release the view (GPU memory and heat) before person tracking
/// and compositing start.
class ThreeDScenePipeline {
  ThreeDScenePipeline._();

  static const int _maximumScenesPerExport = 6;
  static const int _maximumAttemptsPerScene = 4;

  /// A transient capture failure (for example PixelCopy right after a model
  /// swap) is retried on the same model instead of throwing it away.
  static const int _maximumCaptureTries = 3;

  // The 3D card is drawn at ~46% of the video's short edge, so a ~620 px
  // square at 18 fps is plenty and captures far faster than the previous
  // full-size 24 fps render.
  static const int _captureSize = 624;
  static const int _captureFrameRate = 18;

  // Share of the 3D phase bar: scenes, then person tracking, then compositing.
  static const double _sceneShare = 0.60;
  static const double _trackingStart = 0.60;
  static const double _compositeStart = 0.72;

  /// Phase 2 switch: follow the tracked person with the 3D scenes.
  /// Any failure falls back to the previous panel compositing.
  static bool personAnchoringEnabled = true;

  /// When no library has a model for a scene, use a neutral built-in model
  /// instead of leaving the scene without 3D.
  static bool genericFallbackEnabled = true;

  /// Stage log of the most recent [apply] call (also when it ended early).
  static ThreeDExportSummary? lastExportSummary;

  /// The old fixed camera cycle. It is still the camera of a scene when the
  /// story gives no hint for it (see [CameraHintBridge.filamentModeFor]).
  static const List<String> _cameraModes = <String>[
    'orbit',
    'push_in',
    'pull_out',
    'orbit_fast',
  ];

  static String _compactQuery(String value) {
    final normalized = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.length <= 150) return normalized;
    return normalized.substring(0, 150).trim();
  }

  static String _assetKey(ThreeDAsset asset) =>
      '${asset.provider.name}:${asset.id}';

  static double _unit(double value) =>
      value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();

  /// Where each stage starts inside one scene's share of the bar.
  static double _stageStart(ThreeDStage stage) => switch (stage) {
        ThreeDStage.search => 0.00,
        ThreeDStage.download => 0.10,
        ThreeDStage.inspect => 0.35,
        ThreeDStage.filamentLoad => 0.40,
        ThreeDStage.camera => 0.50,
        ThreeDStage.ready => 0.52,
        ThreeDStage.capture => 0.60,
        ThreeDStage.rendererRelease => 1.00,
        ThreeDStage.composite => 1.00,
      };

  static double _sceneFraction(int index, int count, ThreeDStage stage) {
    if (count <= 0) return 0.0;
    return (index + _stageStart(stage)) / count * _sceneShare;
  }

  /// Test hook: the scene windows [_buildCues] derives from a timeline.
  @visibleForTesting
  static List<({double start, double end, String query})> debugCues(
    TimelineProject project,
  ) {
    return _buildCues(project)
        .map((cue) => (start: cue.start, end: cue.end, query: cue.query))
        .toList();
  }

  /// Test hook: how many query words appear in a model title.
  @visibleForTesting
  static int relevanceScore(String title, String query) =>
      _relevanceScore(title, query);

  /// The story of the video, read from the caption layers of [project]: one
  /// segment per caption, in time order. Its beats carry the camera hints
  /// that pick the camera of each 3D scene. Empty when there are no captions
  /// or the story cannot be planned (every scene then keeps the fixed cycle).
  static List<StoryBeat> _storyBeats(TimelineProject project) {
    final captions = project
        .layersOfType(TimelineLayerType.caption)
        .where(
          (layer) =>
              layer.visible &&
              layer.text != null &&
              layer.text!.trim().isNotEmpty &&
              layer.end > layer.start,
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    return CameraHintBridge.beatsOf(<StorySegment>[
      for (final layer in captions)
        StorySegment(
          text: layer.text!.trim(),
          start: layer.start,
          end: layer.end,
        ),
    ]);
  }

  /// Creates time windows using the caption layers of the existing timeline.
  ///
  /// Nearby captions are grouped together. Long groups are split into
  /// windows of at most eight seconds to match the native capture limit.
  static List<_ThreeDCue> _buildCues(TimelineProject project) {
    final captions = project
        .layersOfType(TimelineLayerType.caption)
        .where(
          (layer) =>
              layer.visible &&
              layer.text != null &&
              layer.text!.trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (captions.isEmpty) {
      return <_ThreeDCue>[];
    }

    final cues = <_ThreeDCue>[];
    final group = <TimelineLayer>[];
    var groupEnd = 0.0;

    void flushGroup() {
      if (group.isEmpty) return;

      final groupStart = group.first.start
          .clamp(0.0, project.duration)
          .toDouble();

      var lastEnd = 0.0;

      for (final layer in group) {
        if (layer.end > lastEnd) {
          lastEnd = layer.end;
        }
      }

      lastEnd = lastEnd
          .clamp(0.0, project.duration)
          .toDouble();

      var cursor = groupStart;

      while (lastEnd - cursor >= 0.5) {
        final chunkEnd =
            math.min(lastEnd, cursor + 8.0).toDouble();

        final words = group
            .where(
              (layer) =>
                  layer.start < chunkEnd && layer.end > cursor,
            )
            .map((layer) => layer.text!.trim())
            .where((text) => text.isNotEmpty)
            .join(' ');

        final query = _compactQuery(words);

        if (chunkEnd - cursor >= 0.5 && query.length >= 2) {
          cues.add(
            _ThreeDCue(
              start: cursor,
              end: chunkEnd,
              query: query,
            ),
          );
        }

        cursor = chunkEnd;
      }

      group.clear();
      groupEnd = 0.0;
    }

    for (final caption in captions) {
      final start = caption.start
          .clamp(0.0, project.duration)
          .toDouble();

      final end = caption.end
          .clamp(0.0, project.duration)
          .toDouble();

      if (end <= start) continue;

      if (group.isNotEmpty && start - groupEnd > 1.1) {
        flushGroup();
      }

      group.add(caption);

      if (end > groupEnd) {
        groupEnd = end;
      }
    }

    flushGroup();

    // A 3D scene over full-screen B-roll hides the picture and ends up as a
    // small card on top of it: keep the scenes where the speaker is on screen.
    final broll = <TimeWindow>[
      for (final layer in project.layersOfType(TimelineLayerType.broll))
        if (layer.visible && layer.end > layer.start)
          (start: layer.start, end: layer.end),
    ];
    if (broll.isNotEmpty) {
      final free = <_ThreeDCue>[];
      for (final cue in cues) {
        final part = CueWindows.longestFreePart(
          start: cue.start,
          end: cue.end,
          blocked: broll,
        );
        if (part != null) {
          free.add(
            _ThreeDCue(start: part.start, end: part.end, query: cue.query),
          );
        }
      }
      cues
        ..clear()
        ..addAll(free);
    }

    if (cues.length <= _maximumScenesPerExport) {
      return cues;
    }

    // Select windows across the whole video instead of keeping only
    // the first windows of a long project.
    final selected = <_ThreeDCue>[];

    for (var index = 0; index < _maximumScenesPerExport; index++) {
      final sourceIndex = (
        index * (cues.length - 1) /
        (_maximumScenesPerExport - 1)
      ).round();

      selected.add(cues[sourceIndex]);
    }

    return selected;
  }

  static int _relevanceScore(String title, String query) {
    final normalizedTitle = title.toLowerCase();

    final words = query
        .toLowerCase()
        .split(RegExp(r'[\s،,.;:!?؟]+'))
        .where((word) => word.length >= 2)
        .toSet();

    var score = 0;

    for (final word in words) {
      if (normalizedTitle.contains(word)) {
        score++;
      }
    }

    return score;
  }

  /// Candidate models for one scene, best first: online libraries for the
  /// first keyword that has results, then the built-in catalog. Models that
  /// crashed the app before ([blockedKeys]) are left out and counted.
  static Future<({List<ThreeDAsset> assets, int blocked})> _candidateAssets({
    required ThreeDAssetService service,
    required List<String> keywords,
    required int sceneIndex,
    required Set<String> blockedKeys,
  }) async {
    final candidates = <ThreeDAsset>[];

    for (final keyword in keywords.take(4)) {
      try {
        final found = await service.search(keyword);
        if (found.isEmpty) continue;

        final ranked = List<ThreeDAsset>.from(found)
          ..sort(
            (a, b) => _relevanceScore(b.title, keyword)
                .compareTo(_relevanceScore(a.title, keyword)),
          );

        candidates.addAll(ranked.take(3));
        break;
      } catch (_) {
        continue;
      }
    }

    candidates.addAll(
      KhronosModelCatalog.match(keywords)
          .take(2)
          .map(KhronosModelCatalog.asset),
    );

    if (candidates.isEmpty && genericFallbackEnabled) {
      candidates.add(
        KhronosModelCatalog.asset(
          KhronosModelCatalog.fallbackFor(sceneIndex),
        ),
      );
    }

    final seen = <String>{};
    final assets = <ThreeDAsset>[];
    var blocked = 0;

    for (final asset in candidates) {
      final key = _assetKey(asset);

      if (!seen.add(key)) continue;

      if (blockedKeys.contains(key)) {
        blocked++;
        continue;
      }

      assets.add(asset);
    }

    return (assets: assets, blocked: blocked);
  }

  /// Waits for the actual Android Filament SurfaceView to render the GLB.
  /// Also used by the offline self-test on the diagnostics screen.
  static Future<void> waitUntilRenderable(int viewId) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final diagnostics =
          await FilamentRenderer.getViewDiagnostics(viewId);

      final surfaceReady = diagnostics['surfaceReady'] == true;
      final modelLoaded = diagnostics['modelLoaded'] == true;

      final renderedFrames =
          (diagnostics['framesRendered'] as num?)?.toInt() ?? 0;

      if (surfaceReady && modelLoaded && renderedFrames >= 2) {
        return;
      }

      final error = diagnostics['lastError'];

      if (error != null && error.toString().trim().isNotEmpty) {
        throw StateError('Filament renderer error: $error');
      }

      await Future<void>.delayed(
        const Duration(milliseconds: 200),
      );
    }

    throw TimeoutException(
      'Filament SurfaceView did not become ready.',
      const Duration(seconds: 20),
    );
  }

  /// Captures one scene. A PixelCopy failure (the surface had no frame to
  /// copy yet, for example right after a model swap) is transient: the same
  /// model is captured again after a short wait instead of being discarded
  /// and downloading a different one.
  static Future<String> _captureWithRetry({
    required int viewId,
    required double durationSeconds,
    void Function(String message)? onStatus,
  }) async {
    var attempt = 0;

    while (true) {
      attempt++;

      try {
        return await FilamentSceneExporter.captureAndEncode(
          viewId: viewId,
          durationSeconds: durationSeconds,
          frameRate: _captureFrameRate,
          width: _captureSize,
          height: _captureSize,
          onStatus: onStatus,
        );
      } catch (error) {
        final text = '$error';

        final transient =
            text.contains('PIXEL_COPY') || text.contains('PixelCopy');

        if (!transient || attempt >= _maximumCaptureTries) {
          rethrow;
        }

        onStatus?.call(
          'تعذر التقاط الإطار؛ إعادة المحاولة ($attempt من $_maximumCaptureTries)...',
        );

        await Future<void>.delayed(
          Duration(milliseconds: 700 * attempt),
        );

        await waitUntilRenderable(viewId);
      }
    }
  }

  /// Phase 1 + 2: tracks the main person and composites the scenes around
  /// them. Returns null (and removes any partial file) when nothing could be
  /// anchored, so the caller uses the previous panel compositing.
  static Future<String?> _compositeAnchored({
    required String videoPath,
    required List<ThreeDSceneClip> scenes,
    required TimelineProject timeline,
    required AppSettings settings,
    required List<String> notes,
    void Function(String message)? onStatus,
    void Function(double fraction, String message)? onPhase,
  }) async {
    onStatus?.call('جاري تتبع الشخص لربط المجسمات به...');
    onPhase?.call(_trackingStart, 'جاري تتبع الشخص لربط المجسمات به...');

    final run = await PersonTrackingService.analyzeVideo(
      videoPath,
      config: TrackingConfig(
        sampleFps: 6,
        frameWidth: 480,
        maxSeconds: timeline.duration.clamp(1.0, 120.0).toDouble(),
        maxFrames: 720,
      ),
      onStatus: onStatus,
      onProgress: (value) => onPhase?.call(
        _trackingStart +
            (_compositeStart - _trackingStart) * _unit(value),
        'جاري تتبع الشخص لربط المجسمات به...',
      ),
    );

    final track = run.result.primaryTrack;

    if (track == null) {
      notes.add(
        'لم يتم اكتشاف شخص في الفيديو؛ استُخدم التركيب العادي للمجسمات.',
      );
      return null;
    }

    final result = await PersonAnchoredCompositor.composite(
      videoPath: videoPath,
      scenes: scenes,
      duration: timeline.duration,
      track: track,
      maximumQuality: settings.maximumQuality,
      onStatus: onStatus,
      onProgress: (value) => onPhase?.call(
        _compositeStart + (1.0 - _compositeStart) * _unit(value),
        'جاري دمج مشاهد 3D مع الفيديو...',
      ),
    );

    if (result.anchoredScenes == 0 || result.path.isEmpty) {
      notes.add(
        'الشخص غير ظاهر بما يكفي في نوافذ المشاهد؛ استُخدم التركيب العادي.',
      );
      notes.addAll(result.notes);
      return null;
    }

    notes.add(
      'تم ربط ${result.anchoredScenes} مشهد 3D بحركة الشخص'
      '${result.pipScenes > 0 ? ' (و${result.pipScenes} بالتركيب العادي)' : ''}.',
    );
    notes.addAll(result.notes);

    return result.path;
  }

  static Future<ThreeDScenePipelineResult> apply({
    required int viewId,
    required String videoPath,
    required TimelineProject timeline,
    required AppSettings settings,
    void Function(String message)? onStatus,
    void Function(ThreeDProgress progress)? onProgress,

    /// Called once every scene is rendered and the native Filament view is no
    /// longer needed (before person tracking and compositing).
    Future<void> Function()? onRenderingDone,
  }) async {
    final notes = <String>[];
    final sceneClips = <ThreeDSceneClip>[];
    final temporaryDirectories = <String>{};

    // Starts a fresh on-disk log; every stage is appended as it happens, so
    // the log is complete up to the moment of a crash.
    await ThreeDCrashGuard.begin();

    // Every stage of this export is recorded here and printed as it happens:
    // one line when a stage starts and one when it ends.
    final summary = ThreeDExportSummary(
      onEvent: (event) {
        final line = event.toLine();
        debugPrint('[3D] $line');
        ThreeDCrashGuard.appendLogSync(line);
      },
      onStart: (scene, stage, detail) {
        final line = ThreeDStageEvent.startLine(scene, stage, detail: detail);
        debugPrint('[3D] $line');
        ThreeDCrashGuard.appendLogSync(line);
      },
    );
    lastExportSummary = summary;

    String? compositePath;
    Stopwatch? compositeWatch;

    if (!settings.online3DAssetsEnabled) {
      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: const <String>[
          'مصادر المجسمات ثلاثية الأبعاد معطلة من الإعدادات.',
        ],
        summary: summary,
      );
    }

    final sourceFile = File(videoPath);

    if (!await sourceFile.exists()) {
      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: const <String>[
          'ملف الفيديو المطلوب لإضافة 3D غير موجود.',
        ],
        summary: summary,
      );
    }

    final cues = _buildCues(timeline);

    if (cues.isEmpty) {
      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: const <String>[
          'لم تتوفر توقيتات كابشن كافية لتحديد مواضع مشاهد 3D.',
        ],
        summary: summary,
      );
    }

    // The story of the video: its camera hints pick the camera of each scene.
    final storyBeats = _storyBeats(timeline);

    // Reports live progress for the whole 3D phase (0..1).
    void report(
      double fraction,
      String message, {
      ThreeDStage? stage,
      int scene = 0,
    }) {
      final callback = onProgress;
      if (callback == null) return;

      callback(
        ThreeDProgress(
          fraction: _unit(fraction),
          message: message,
          stage: stage,
          scene: scene,
          sceneCount: cues.length,
        ),
      );
    }

    final blockedKeys = await ThreeDCrashGuard.blacklistedKeys();
    final service = ThreeDAssetService(settings: settings);

    try {
      for (var index = 0; index < cues.length; index++) {
        final cue = cues[index];
        final sceneNumber = index + 1;

        // The camera of this scene: the hint of the story beat spoken during
        // it (enter the window = push in, arrive from it = pull out, orbit...).
        // Without a hint the old fixed cycle decides.
        final cameraMode = CameraHintBridge.filamentModeFor(
          storyBeats,
          cue.start,
          cue.end,
          fallback: _cameraModes[index % _cameraModes.length],
        );

        onStatus?.call(
          'جاري تجهيز مشهد 3D $sceneNumber من ${cues.length} '
          '(${cue.start.toStringAsFixed(1)}s – '
          '${cue.end.toStringAsFixed(1)}s)...',
        );

        report(
          _sceneFraction(index, cues.length, ThreeDStage.search),
          'مشهد $sceneNumber من ${cues.length} — البحث عن مجسم مناسب...',
          stage: ThreeDStage.search,
          scene: sceneNumber,
        );

        // From here on a crash belongs to THIS scene's search, never to the
        // model of the previous scene (its note is replaced right now).
        ThreeDCrashGuard.markSync(
          ThreeDBreadcrumb(
            scene: sceneNumber,
            stage: ThreeDStage.search,
            at: DateTime.now(),
          ),
        );
        summary.begin(sceneNumber, ThreeDStage.search);

        final searchWatch = Stopwatch()..start();
        var searchDone = false;

        try {
          final keywords = await ThreeDQueryPlanner.keywords(
            settings,
            cue.query,
          );

          final found = await _candidateAssets(
            service: service,
            keywords: keywords,
            sceneIndex: index,
            blockedKeys: blockedKeys,
          );

          final candidates = found.assets;
          final blockedNote = found.blocked > 0
              ? ' — ${found.blocked} محظور بعد انهيار سابق'
              : '';

          searchDone = true;

          summary.record(
            sceneNumber,
            ThreeDStage.search,
            ok: candidates.isNotEmpty,
            elapsed: searchWatch.elapsed,
            detail: candidates.isEmpty
                ? 'لا توجد مرشحات (${keywords.take(3).join('، ')})$blockedNote'
                : '${candidates.length} مرشح '
                    '(${keywords.take(3).join('، ')})$blockedNote',
          );

          if (candidates.isEmpty) {
            notes.add(
              'لم يتم العثور على مجسم GLB مناسب للمشهد $sceneNumber '
              '(${keywords.take(3).join('، ')})$blockedNote.',
            );

            if (service.warnings.isNotEmpty) {
              notes.addAll(service.warnings.take(3));
            }

            continue;
          }

          String? scenePath;
          ThreeDAsset? usedAsset;
          final attemptFailures = <String>[];

          for (final asset in candidates.take(_maximumAttemptsPerScene)) {
            // Tracks where the attempt is, so a failure is reported in the
            // stage that really failed.
            var stage = ThreeDStage.download;
            final stopwatch = Stopwatch()..start();
            final assetKey = _assetKey(asset);

            // Writes the breadcrumb BEFORE the stage starts (a native crash
            // cannot be caught, so the note says where it happened), logs the
            // start of the stage and updates the live progress.
            void announce(ThreeDStage at) {
              ThreeDCrashGuard.markSync(
                ThreeDBreadcrumb(
                  scene: sceneNumber,
                  stage: at,
                  at: DateTime.now(),
                  assetKey: assetKey,
                  assetTitle: asset.title,
                ),
              );

              summary.begin(sceneNumber, at, detail: asset.title);

              report(
                _sceneFraction(index, cues.length, at),
                'مشهد $sceneNumber من ${cues.length} — ${at.label}: ${asset.title}',
                stage: at,
                scene: sceneNumber,
              );
            }

            // Records the finished stage and moves on to the next one.
            void finish(ThreeDStage done, {ThreeDStage? next}) {
              summary.record(
                sceneNumber,
                done,
                ok: true,
                elapsed: stopwatch.elapsed,
                detail: asset.title,
              );

              if (next != null) {
                stage = next;
                announce(next);
              }

              stopwatch
                ..reset()
                ..start();
            }

            try {
              announce(ThreeDStage.download);

              onStatus?.call(
                'جاري تنزيل المجسم: ${asset.title}...',
              );

              // Download + full GLB inspection: a bad file is rejected here.
              // The service tells us when the download ends and the
              // inspection begins, so they are logged as two stages.
              final modelPath = await service.download(
                asset,
                onInspecting: () => finish(
                  ThreeDStage.download,
                  next: ThreeDStage.inspect,
                ),
              );

              finish(ThreeDStage.inspect, next: ThreeDStage.filamentLoad);

              onStatus?.call(
                'جاري تحميل المجسم داخل محرك Filament...',
              );

              await FilamentRenderer.loadModelFromFile(
                viewId: viewId,
                filePath: modelPath,
              );

              finish(ThreeDStage.filamentLoad, next: ThreeDStage.camera);

              await FilamentRenderer.setCameraMotion(
                viewId: viewId,
                mode: cameraMode,
              );

              finish(ThreeDStage.camera, next: ThreeDStage.ready);

              // Let the new model render a few frames before capturing.
              await Future<void>.delayed(
                const Duration(milliseconds: 350),
              );

              await waitUntilRenderable(viewId);

              finish(ThreeDStage.ready, next: ThreeDStage.capture);

              onStatus?.call(
                'جاري تصوير حركة الكاميرا للمشهد $sceneNumber...',
              );

              final capturedPath = await _captureWithRetry(
                viewId: viewId,
                durationSeconds: cue.duration,
                onStatus: onStatus,
              );

              final sceneFile = File(capturedPath);

              if (!await sceneFile.exists() ||
                  await sceneFile.length() < 2048) {
                throw FileSystemException(
                  '3D scene video was not created correctly.',
                  capturedPath,
                );
              }

              finish(ThreeDStage.capture);

              // The model finished everything it was asked to do. Replace its
              // crash note right away, so whatever happens next (the next
              // search, releasing the renderer) is never blamed on it.
              final lastScene = index == cues.length - 1;

              ThreeDCrashGuard.markSync(
                ThreeDBreadcrumb(
                  scene: lastScene ? 0 : sceneNumber + 1,
                  stage: lastScene
                      ? ThreeDStage.rendererRelease
                      : ThreeDStage.search,
                  at: DateTime.now(),
                ),
              );

              temporaryDirectories.add(sceneFile.parent.path);
              scenePath = capturedPath;
              usedAsset = asset;
              break;
            } catch (error) {
              summary.record(
                sceneNumber,
                stage,
                ok: false,
                elapsed: stopwatch.elapsed,
                detail: '${asset.title}: $error',
              );

              attemptFailures.add(
                '${asset.title} [مرحلة: ${stage.label}]: $error',
              );
            }
          }

          if (scenePath == null || usedAsset == null) {
            notes.add(
              'تعذر تجهيز مجسم للمشهد $sceneNumber: '
              '${attemptFailures.isEmpty ? 'غير معروف' : attemptFailures.join(' | ')}',
            );
            continue;
          }

          if (attemptFailures.isNotEmpty) {
            notes.add(
              'مشهد $sceneNumber: فشلت ${attemptFailures.length} '
              'محاولة قبل النجاح (${attemptFailures.join(' | ')}).',
            );
          }

          notes.add(
            'مشهد $sceneNumber: ${keywords.take(3).join('، ')} ← ${usedAsset.title}',
          );

          // A capture that never finished decodes as a bright green band;
          // such a scene is dropped instead of being shown over the speaker.
          final cleanFrames = await SceneFrameGuard.isClean(
            scenePath,
            File(scenePath).parent.path,
          );
          if (!cleanFrames) {
            notes.add(
              'مشهد $sceneNumber: إطارات المجسم تالفة (شاشة خضراء)؛ تم تخطيه بدل عرضه.',
            );
            try {
              File(scenePath).deleteSync();
            } catch (_) {}
            continue;
          }

          sceneClips.add(
            ThreeDSceneClip(
              path: scenePath,
              start: cue.start,
              end: cue.end,
            ),
          );
        } catch (error) {
          if (!searchDone) {
            summary.record(
              sceneNumber,
              ThreeDStage.search,
              ok: false,
              elapsed: searchWatch.elapsed,
              detail: '$error',
            );
          }

          notes.add(
            'تعذر تجهيز مشهد 3D $sceneNumber: $error',
          );
        }
      }

      notes.add(
        'ملخص 3D: تم تجهيز ${sceneClips.length} من ${cues.length} مشهد.',
      );

      if (sceneClips.isEmpty) {
        notes.add(
          'لم يتم إنشاء أي مشهد 3D؛ تم الاحتفاظ بالفيديو الأصلي دون تغييره.',
        );
        notes.add(summary.headline);

        return ThreeDScenePipelineResult(
          applied: false,
          scenesRendered: 0,
          notes: notes,
          summary: summary,
        );
      }

      // Every scene is rendered: the native Filament view is not needed any
      // more. Let the screen release it now, so its GPU memory is free (and
      // the phone cools down) before tracking and compositing start. This is
      // its own stage: a native crash while releasing the view must be
      // reported as such and never blamed on the last model.
      final releaseWatch = Stopwatch()..start();

      ThreeDCrashGuard.markSync(
        ThreeDBreadcrumb(
          scene: 0,
          stage: ThreeDStage.rendererRelease,
          at: DateTime.now(),
        ),
      );
      summary.begin(0, ThreeDStage.rendererRelease);

      report(
        _sceneShare,
        'اكتمل تجهيز المشاهد؛ جاري تحرير محرك العرض...',
        stage: ThreeDStage.rendererRelease,
      );

      try {
        await onRenderingDone?.call();

        summary.record(
          0,
          ThreeDStage.rendererRelease,
          ok: true,
          elapsed: releaseWatch.elapsed,
        );
      } catch (error) {
        // Releasing the view must never stop the export.
        summary.record(
          0,
          ThreeDStage.rendererRelease,
          ok: false,
          elapsed: releaseWatch.elapsed,
          detail: '$error',
        );
      }

      onStatus?.call(
        'جاري تركيب ${sceneClips.length} مشاهد 3D في الفيديو...',
      );

      report(
        _sceneShare,
        'اكتمل تجهيز المشاهد؛ جاري التركيب مع الفيديو...',
        stage: ThreeDStage.composite,
      );

      // From here on a crash belongs to tracking / compositing, not a model.
      ThreeDCrashGuard.markSync(
        ThreeDBreadcrumb(
          scene: 0,
          stage: ThreeDStage.composite,
          at: DateTime.now(),
        ),
      );
      summary.begin(0, ThreeDStage.composite);

      final watch = Stopwatch()..start();
      compositeWatch = watch;

      String? anchoredPath;

      if (personAnchoringEnabled && PersonTrackingService.hasDetector) {
        if (await ThreeDCrashGuard.isAnchoringDisabled()) {
          notes.add(
            'ربط المجسمات بالشخص معطّل بعد انهيار سابق؛ استُخدم التركيب العادي '
            '(يمكن إعادة تفعيله من تقرير 3D).',
          );
        } else {
          try {
            anchoredPath = await _compositeAnchored(
              videoPath: videoPath,
              scenes: sceneClips,
              timeline: timeline,
              settings: settings,
              notes: notes,
              onStatus: onStatus,
              onPhase: (fraction, message) => report(
                fraction,
                message,
                stage: ThreeDStage.composite,
              ),
            );
          } catch (error) {
            anchoredPath = null;
            notes.add(
              'تعذر ربط المجسمات بالشخص؛ تم استخدام التركيب العادي: $error',
            );
          }
        }
      }

      if (anchoredPath == null) {
        notes.add('التركيب: عادي (بدون ربط بحركة الشخص).');
      }

      compositePath = anchoredPath ??
          await FilamentSceneExporter.compositeScenesOverVideo(
            videoPath: videoPath,
            scenes: sceneClips,
            duration: timeline.duration,
            maximumQuality: settings.maximumQuality,
            onStatus: onStatus,
            onProgress: (value) => report(
              _compositeStart + (1.0 - _compositeStart) * _unit(value),
              'جاري دمج مشاهد 3D مع الفيديو...',
              stage: ThreeDStage.composite,
            ),
          );

      final compositeFile = File(compositePath);

      if (!await compositeFile.exists() ||
          await compositeFile.length() < 4096) {
        throw FileSystemException(
          'ملف الفيديو بعد دمج مشاهد 3D غير صالح.',
          compositePath,
        );
      }

      // Keep the original export path to preserve saved-project references.
      final backupPath =
          '$videoPath.before_3d_${DateTime.now().millisecondsSinceEpoch}';

      final backupFile = File(backupPath);

      await sourceFile.rename(backupPath);

      try {
        await compositeFile.rename(videoPath);

        if (await backupFile.exists()) {
          await backupFile.delete();
        }
      } catch (_) {
        if (!await sourceFile.exists() &&
            await backupFile.exists()) {
          await backupFile.rename(videoPath);
        }

        rethrow;
      }

      summary.record(
        0,
        ThreeDStage.composite,
        ok: true,
        elapsed: watch.elapsed,
        detail: anchoredPath != null
            ? '${sceneClips.length} مشهد؛ مربوط بحركة الشخص'
            : '${sceneClips.length} مشهد؛ تركيب عادي',
      );

      notes.add(summary.headline);

      report(
        1.0,
        'اكتمل دمج مشاهد 3D مع الفيديو النهائي.',
        stage: ThreeDStage.composite,
      );

      onStatus?.call(
        'اكتمل دمج مشاهد 3D مع الفيديو النهائي.',
      );

      return ThreeDScenePipelineResult(
        applied: true,
        scenesRendered: sceneClips.length,
        notes: notes,
        summary: summary,
      );
    } catch (error) {
      final failedWatch = compositeWatch;

      // Only an error after compositing started belongs to that stage; the
      // earlier stages are already logged one by one.
      if (failedWatch != null) {
        summary.record(
          0,
          ThreeDStage.composite,
          ok: false,
          elapsed: failedWatch.elapsed,
          detail: '$error',
        );
      }

      notes.add('تعذر إكمال مرحلة دمج 3D: $error');
      notes.add(summary.headline);

      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: sceneClips.length,
        notes: notes,
        summary: summary,
      );
    } finally {
      // The 3D phase ended normally (success or handled failure): there was
      // no crash, so the breadcrumb is removed and the log gets its headline.
      ThreeDCrashGuard.appendLogSync(summary.headline);
      ThreeDCrashGuard.clearBreadcrumbSync();

      service.dispose();

      for (final directoryPath in temporaryDirectories) {
        try {
          final directory = Directory(directoryPath);

          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        } catch (_) {}
      }

      if (compositePath != null) {
        try {
          final file = File(compositePath);

          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }
}
