import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:filament_renderer/filament_renderer.dart';

import 'filament_scene_exporter.dart';
import 'settings.dart';
import 'three_d_asset_service.dart';
import 'timeline_engine.dart';

class ThreeDScenePipelineResult {
  final bool applied;
  final int scenesRendered;
  final List<String> notes;

  const ThreeDScenePipelineResult({
    required this.applied,
    required this.scenesRendered,
    this.notes = const <String>[],
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
/// - Searches and downloads GLB assets.
/// - Loads each asset into the native Filament renderer.
/// - Captures camera movement.
/// - Composites rendered scenes into the exported video.
class ThreeDScenePipeline {
  ThreeDScenePipeline._();

  static const int _maximumScenesPerExport = 8;

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

  static ThreeDAsset? _chooseAsset(
    List<ThreeDAsset> assets,
    String query,
  ) {
    if (assets.isEmpty) return null;

    final ranked = List<ThreeDAsset>.from(assets)
      ..sort(
        (a, b) => _relevanceScore(b.title, query)
            .compareTo(_relevanceScore(a.title, query)),
      );

    return ranked.first;
  }

  /// Waits for the actual Android Filament SurfaceView to render the GLB.
  static Future<void> _waitUntilRenderable(int viewId) async {
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

  static Future<ThreeDScenePipelineResult> apply({
    required int viewId,
    required String videoPath,
    required TimelineProject timeline,
    required AppSettings settings,
    void Function(String message)? onStatus,
  }) async {
    final notes = <String>[];
    final sceneClips = <ThreeDSceneClip>[];
    final temporaryDirectories = <String>{};

    String? compositePath;

    if (!settings.online3DAssetsEnabled) {
      return const ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: <String>[
          'مصادر المجسمات ثلاثية الأبعاد معطلة من الإعدادات.',
        ],
      );
    }

    final sourceFile = File(videoPath);

    if (!await sourceFile.exists()) {
      return const ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: <String>[
          'ملف الفيديو المطلوب لإضافة 3D غير موجود.',
        ],
      );
    }

    final cues = _buildCues(timeline);

    if (cues.isEmpty) {
      return const ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: 0,
        notes: <String>[
          'لم تتوفر توقيتات كابشن كافية لتحديد مواضع مشاهد 3D.',
        ],
      );
    }

    final service = ThreeDAssetService(settings: settings);

    try {
      for (var index = 0; index < cues.length; index++) {
        final cue = cues[index];

        onStatus?.call(
          'جاري تجهيز مشهد 3D ${index + 1} من ${cues.length} '
          '(${cue.start.toStringAsFixed(1)}s – '
          '${cue.end.toStringAsFixed(1)}s)...',
        );

        try {
          final assets = await service.search(cue.query);
          final asset = _chooseAsset(assets, cue.query);

          if (asset == null) {
            notes.add(
              'لم يتم العثور على مجسم GLB مناسب للمشهد ${index + 1}.',
            );

            if (service.warnings.isNotEmpty) {
              notes.addAll(service.warnings.take(3));
            }

            continue;
          }

          onStatus?.call(
            'جاري تنزيل المجسم: ${asset.title}...',
          );

          final modelPath = await service.download(asset);

          onStatus?.call(
            'جاري تحميل المجسم داخل محرك Filament...',
          );

          await FilamentRenderer.loadModelFromFile(
            viewId: viewId,
            filePath: modelPath,
          );

          final cameraMode =
              _cameraModes[index % _cameraModes.length];

          await FilamentRenderer.setCameraMotion(
            viewId: viewId,
            mode: cameraMode,
          );

          await _waitUntilRenderable(viewId);

          onStatus?.call(
            'جاري تصوير حركة الكاميرا للمشهد ${index + 1}...',
          );

          final scenePath =
              await FilamentSceneExporter.captureAndEncode(
            viewId: viewId,
            durationSeconds: cue.duration,
            frameRate: 24,
            width: 720,
            height: 720,
            onStatus: onStatus,
          );

          final sceneFile = File(scenePath);

          if (!await sceneFile.exists() ||
              await sceneFile.length() < 2048) {
            throw FileSystemException(
              '3D scene video was not created correctly.',
              scenePath,
            );
          }

          temporaryDirectories.add(sceneFile.parent.path);

          sceneClips.add(
            ThreeDSceneClip(
              path: scenePath,
              start: cue.start,
              end: cue.end,
            ),
          );
        } catch (error) {
          notes.add(
            'تعذر تجهيز مشهد 3D ${index + 1}: $error',
          );
        }
      }

      if (sceneClips.isEmpty) {
        notes.add(
          'لم يتم إنشاء أي مشهد 3D؛ تم الاحتفاظ بالفيديو الأصلي دون تغييره.',
        );

        return ThreeDScenePipelineResult(
          applied: false,
          scenesRendered: 0,
          notes: notes,
        );
      }

      onStatus?.call(
        'جاري تركيب ${sceneClips.length} مشاهد 3D في الفيديو...',
      );

      compositePath =
          await FilamentSceneExporter.compositeScenesOverVideo(
        videoPath: videoPath,
        scenes: sceneClips,
        duration: timeline.duration,
        maximumQuality: settings.maximumQuality,
        onStatus: onStatus,
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

      onStatus?.call(
        'اكتمل دمج مشاهد 3D مع الفيديو النهائي.',
      );

      return ThreeDScenePipelineResult(
        applied: true,
        scenesRendered: sceneClips.length,
        notes: notes,
      );
    } catch (error) {
      notes.add('تعذر إكمال مرحلة دمج 3D: $error');

      return ThreeDScenePipelineResult(
        applied: false,
        scenesRendered: sceneClips.length,
        notes: notes,
      );
    } finally {
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
