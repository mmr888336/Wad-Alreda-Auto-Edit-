import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'filament_scene_exporter.dart';
import 'person_anchor_path.dart';
import 'person_anchored_command.dart';
import 'person_matte_renderer.dart';
import 'person_segmentation_matte.dart';
import 'person_silhouette.dart';
import 'person_tracking_models.dart';
import 'scene_environment.dart';
import 'scene_environment_sampler.dart';
import 'scene_key_color.dart';
import 'silence_cutter.dart';

class PersonAnchoredResult {
  final String path;
  final int anchoredScenes;
  final int pipScenes;

  /// Anchored scenes that were also matched to the light, color and depth of
  /// the place (grade, haze, soft focus, grain and a cast shadow).
  final int environmentScenes;
  final List<String> notes;

  const PersonAnchoredResult({
    required this.path,
    required this.anchoredScenes,
    required this.pipScenes,
    this.environmentScenes = 0,
    this.notes = const <String>[],
  });
}

/// Phase 2: places rendered 3D scenes around the tracked person instead of a
/// fixed panel. The card follows the person, the background of the 3D render
/// is keyed out, and for "behind" placements a per-frame person matte is drawn
/// over the card so it looks like it stands behind them.
///
/// The matte comes from ML Kit Selfie Segmentation (an accurate mask of the
/// person for every sampled frame). When segmentation is not possible the
/// approximate pose-based matte is used instead.
///
/// Phase 3 (environment): every anchored card is also matched to the place it
/// stands in. The light, color cast, softness and light direction of the real
/// footage are measured during the scene, and the card gets the same
/// exposure and color cast, distance haze and soft focus by depth, the grain
/// of the camera and a soft shadow that falls away from the light. If that
/// richer composite cannot be encoded, the plain anchored composite is encoded
/// instead, so the environment match can never cost the export.
///
/// A scene whose person path cannot be planned keeps the old panel.
class PersonAnchoredCompositor {
  PersonAnchoredCompositor._();

  /// Phase 3 switch: match anchored cards to the light, color and depth of
  /// the footage. Any failure falls back to the plain anchored look.
  static bool environmentIntegrationEnabled = true;

  static Future<PersonAnchoredResult> composite({
    required String videoPath,
    required List<ThreeDSceneClip> scenes,
    required double duration,
    required PersonTrack? track,
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

    final info = await SilenceCutter.probe(videoPath);
    final width = info.w.toInt();
    final height = info.h.toInt();

    if (width < 2 || height < 2) {
      throw StateError('أبعاد الفيديو الأصلي غير صالحة.');
    }

    final valid = <ThreeDSceneClip>[];

    for (final scene in scenes) {
      final file = File(scene.path);

      if (!await file.exists() || await file.length() < 2048) continue;

      final start = scene.start.clamp(0.0, duration).toDouble();
      final end = scene.end.clamp(0.0, duration).toDouble();

      if (!start.isFinite || !end.isFinite || end - start < 0.5) continue;

      valid.add(ThreeDSceneClip(path: scene.path, start: start, end: end));
    }

    if (valid.isEmpty) {
      throw StateError('كل ملفات مشاهد 3D غير صالحة أو خارج مدة الفيديو.');
    }

    valid.sort((a, b) => a.start.compareTo(b.start));

    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final workDir = Directory('${temp.path}/person_anchor_$stamp');
    await workDir.create(recursive: true);

    final outputPath = '${sourceFile.parent.path}/3d_person_$stamp.mp4';

    final notes = <String>[];
    final specs = <AnchoredSceneSpec>[];
    var anchored = 0;
    var pip = 0;
    var environmentScenes = 0;

    try {
      for (var i = 0; i < valid.length; i++) {
        final scene = valid[i];
        final placement = PersonAnchorPath
            .defaultCycle[i % PersonAnchorPath.defaultCycle.length];

        PersonAnchorPath? path;
        if (track != null) {
          path = PersonAnchorPath.plan(
            track: track,
            start: scene.start,
            end: scene.end,
            placement: placement,
            frameWidth: width,
            frameHeight: height,
          );
        }

        if (path == null) {
          pip++;
          specs.add(
            AnchoredSceneSpec(
              scenePath: scene.path,
              start: scene.start,
              end: scene.end,
            ),
          );
          continue;
        }

        onStatus?.call('جاري ربط المجسم ${i + 1} بحركة الشخص...');

        final keyColors = await SceneKeyColor.sample(scene.path, workDir.path);

        PersonMatteSequence? matte;
        if (path.placement.occludedByPerson && track != null) {
          onStatus?.call('جاري قص الشخص بدقة للمشهد ${i + 1}...');

          // 1) Accurate matte: real segmentation of every sampled frame.
          try {
            matte = await PersonSegmentationMatte.render(
              videoPath: videoPath,
              start: scene.start,
              end: scene.end,
              directory: '${workDir.path}/matte_$i',
              frameWidth: width,
              frameHeight: height,
            );
          } catch (_) {
            matte = null;
          }

          // 2) Fallback: approximate matte drawn from the pose landmarks.
          if (matte == null) {
            try {
              matte = await PersonMatteRenderer.render(
                track: track,
                start: scene.start,
                end: scene.end,
                directory: '${workDir.path}/matte_$i',
                frameWidth: width,
                frameHeight: height,
              );
            } catch (_) {
              matte = null;
            }

            if (matte != null) {
              notes.add(
                'تعذر القص الدقيق للمشهد ${i + 1}؛ استُخدم قناع تقريبي للشخص.',
              );
            }
          }

          if (matte == null) {
            notes.add(
              'تعذر إنشاء قناع الشخص للمشهد ${i + 1}؛ سيظهر المجسم أمام الشخص.',
            );
          }
        }

        // Phase 3: read the light and color of the place during this scene.
        // Any problem here only means this scene keeps the plain look.
        SceneEnvironmentLook? environment;
        if (environmentIntegrationEnabled) {
          try {
            onStatus?.call('جاري قراءة ضوء ولون المكان للمشهد ${i + 1}...');

            final profile = await SceneEnvironmentSampler.sample(
              videoPath: videoPath,
              start: scene.start,
              end: scene.end,
              directory: '${workDir.path}/env_$i',
            );

            if (profile != null) {
              environment = SceneEnvironmentLook.plan(
                profile: profile,
                placement: path.placement,
                sidePixels: path.sidePixels,
              );
              environmentScenes++;
            }
          } catch (_) {
            environment = null;
          }
        }

        anchored++;
        specs.add(
          AnchoredSceneSpec(
            scenePath: scene.path,
            start: scene.start,
            end: scene.end,
            path: path,
            matte: matte,
            keyColors: keyColors,
            environment: environment,
          ),
        );
      }

      if (anchored == 0) {
        return PersonAnchoredResult(
          path: '',
          anchoredScenes: 0,
          pipScenes: pip,
          notes: notes,
        );
      }

      Future<bool> encode(List<AnchoredSceneSpec> list) async {
        final command = PersonAnchoredCommand.build(
          videoPath: videoPath,
          outputPath: outputPath,
          width: width,
          height: height,
          duration: duration,
          scenes: list,
          maximumQuality: maximumQuality,
        );

        final encoded =
            await SilenceCutter.encode(command, duration, onProgress);

        final outputFile = File(outputPath);

        if (encoded &&
            await outputFile.exists() &&
            await outputFile.length() >= 4096) {
          return true;
        }

        try {
          if (await outputFile.exists()) await outputFile.delete();
        } catch (_) {}

        return false;
      }

      onStatus?.call(
        'جاري دمج $anchored مشاهد 3D مرتبطة بالشخص مع الفيديو...',
      );

      var encodedOk = false;
      var environmentApplied = 0;

      if (environmentScenes > 0) {
        try {
          encodedOk = await encode(specs);
          if (encodedOk) environmentApplied = environmentScenes;
        } catch (_) {
          encodedOk = false;
        }

        if (!encodedOk) {
          notes.add(
            'تعذر دمج ضوء ولون وعمق المكان مع المجسمات؛ '
            'استُخدم الربط العادي بالشخص.',
          );
        }
      }

      if (!encodedOk) {
        // Plain anchored composite: exactly the previous behaviour.
        encodedOk = await encode(
          <AnchoredSceneSpec>[
            for (final spec in specs) spec.withoutEnvironment(),
          ],
        );
      }

      if (!encodedOk) {
        throw FileSystemException(
          'فشل دمج مشاهد 3D المرتبطة بالشخص.',
          outputPath,
        );
      }

      if (environmentApplied > 0) {
        notes.add(
          'تم دمج ضوء ولون وعمق وظل المكان مع $environmentApplied مشهد 3D.',
        );
      }

      return PersonAnchoredResult(
        path: outputPath,
        anchoredScenes: anchored,
        pipScenes: math.max(0, pip),
        environmentScenes: environmentApplied,
        notes: notes,
      );
    } finally {
      try {
        if (await workDir.exists()) {
          await workDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
