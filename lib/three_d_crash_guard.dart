import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'three_d_stage_log.dart';

/// Where the 3D pipeline was when it last wrote a note to disk.
///
/// A native crash cannot be caught from Dart, so the pipeline writes this note
/// BEFORE every risky stage, replaces it as soon as a model is finished, and
/// deletes it when the 3D phase ends normally. If the note is still there at
/// the next start, the app died in that stage.
class ThreeDBreadcrumb {
  const ThreeDBreadcrumb({
    required this.scene,
    required this.stage,
    required this.at,
    this.assetKey = '',
    this.assetTitle = '',
    this.cleared = false,
  });

  /// 1-based scene number, 0 for the whole export (tracking / compositing).
  final int scene;
  final ThreeDStage stage;
  final DateTime at;

  /// "provider:id" of the model being processed, empty when none.
  final String assetKey;
  final String assetTitle;

  /// True when the stage log proves the model finished this stage, so the note
  /// was out of date and the model is NOT to blame for the crash.
  final bool cleared;

  Map<String, Object> toJson() => <String, Object>{
        'scene': scene,
        'stage': stage.name,
        'assetKey': assetKey,
        'assetTitle': assetTitle,
        'at': at.toIso8601String(),
        'cleared': cleared,
      };

  static ThreeDBreadcrumb? fromJson(Object? value) {
    if (value is! Map) return null;

    ThreeDStage? stage;
    for (final candidate in ThreeDStage.values) {
      if (candidate.name == value['stage']) stage = candidate;
    }
    if (stage == null) return null;

    final scene = value['scene'];

    return ThreeDBreadcrumb(
      scene: scene is num ? scene.toInt() : 0,
      stage: stage,
      assetKey: '${value['assetKey'] ?? ''}',
      assetTitle: '${value['assetTitle'] ?? ''}',
      at: DateTime.tryParse('${value['at'] ?? ''}') ?? DateTime.now(),
      cleared: value['cleared'] == true,
    );
  }

  String describe() {
    final where = scene == 0 ? 'التصدير' : 'مشهد $scene';
    final model = assetTitle.isEmpty ? '' : ' — المجسم: $assetTitle';
    return '$where، مرحلة ${stage.label}$model';
  }
}

/// Crash breadcrumbs, the live export log and the list of models that crashed
/// the app before. Everything is stored in small files so it survives a crash.
class ThreeDCrashGuard {
  ThreeDCrashGuard._();

  /// Stages where a native crash is plausibly caused by the model itself.
  /// A model is blocked only when the app died inside one of these stages
  /// while that model was really being loaded, shown or captured.
  static const Set<ThreeDStage> assetStages = <ThreeDStage>{
    ThreeDStage.filamentLoad,
    ThreeDStage.camera,
    ThreeDStage.ready,
    ThreeDStage.capture,
  };

  /// Set by [recoverPreviousCrash] when the last run ended abruptly.
  static ThreeDBreadcrumb? recovered;

  static String? _directoryPath;

  /// Resolves the storage folder. Must complete once before any sync call.
  static Future<String> prepare() async {
    final cached = _directoryPath;
    if (cached != null) return cached;

    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/WadAlredaStudio/3DGuard');

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    _directoryPath = directory.path;
    return directory.path;
  }

  static File _file(String directory, String name) =>
      File('$directory/$name');

  /// Starts a fresh export log and removes any stale breadcrumb.
  static Future<void> begin() async {
    try {
      final directory = await prepare();
      await _file(directory, 'export_log.txt').writeAsString('', flush: true);

      final crumb = _file(directory, 'breadcrumb.json');
      if (await crumb.exists()) await crumb.delete();
    } catch (_) {}
  }

  static void markSync(ThreeDBreadcrumb crumb) {
    final directory = _directoryPath;
    if (directory == null) return;

    try {
      _file(directory, 'breadcrumb.json').writeAsStringSync(
        jsonEncode(crumb.toJson()),
        flush: true,
      );
    } catch (_) {}
  }

  static void clearBreadcrumbSync() {
    final directory = _directoryPath;
    if (directory == null) return;

    try {
      final file = _file(directory, 'breadcrumb.json');
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Appends one line to the export log immediately, so the log is complete
  /// up to the moment of a crash.
  static void appendLogSync(String line) {
    final directory = _directoryPath;
    if (directory == null) return;

    try {
      _file(directory, 'export_log.txt').writeAsStringSync(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  static Future<String> readLog() async {
    try {
      final directory = await prepare();
      final file = _file(directory, 'export_log.txt');
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// Call once at startup. When the previous run left a breadcrumb, the app
  /// ended abruptly in that stage.
  ///
  /// A model is blocked only when the crash happened while it was really being
  /// loaded, shown or captured: the stage must be a model stage AND the stage
  /// log must not already show that stage as finished for that model. When the
  /// compositing stage crashed, person anchoring is switched off instead.
  static Future<ThreeDBreadcrumb?> recoverPreviousCrash() async {
    try {
      final directory = await prepare();
      final file = _file(directory, 'breadcrumb.json');
      if (!await file.exists()) return null;

      final crumb = ThreeDBreadcrumb.fromJson(
        jsonDecode(await file.readAsString()),
      );

      await file.delete();

      if (crumb == null) return null;

      var result = crumb;

      if (assetStages.contains(crumb.stage) && crumb.assetKey.isNotEmpty) {
        final confirmed = ThreeDLogReader.succeeded(
          await readLog(),
          scene: crumb.scene,
          stage: crumb.stage,
          assetTitle: crumb.assetTitle,
        );

        if (confirmed) {
          // The log says this model already finished the stage, so the note
          // was stale and the model is not the cause. Do not block it.
          result = ThreeDBreadcrumb(
            scene: crumb.scene,
            stage: crumb.stage,
            at: crumb.at,
            assetKey: crumb.assetKey,
            assetTitle: crumb.assetTitle,
            cleared: true,
          );
        } else {
          final blocked = await blacklistedKeys();
          blocked.add(crumb.assetKey);
          await _file(directory, 'blacklist.json').writeAsString(
            jsonEncode(blocked.toList()),
            flush: true,
          );
        }
      }

      if (crumb.stage == ThreeDStage.composite) {
        await setAnchoringDisabled(true);
      }

      await _file(directory, 'last_crash.json').writeAsString(
        jsonEncode(result.toJson()),
        flush: true,
      );

      recovered = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<ThreeDBreadcrumb?> lastCrash() async {
    try {
      final directory = await prepare();
      final file = _file(directory, 'last_crash.json');
      if (!await file.exists()) return null;
      return ThreeDBreadcrumb.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearLastCrash() async {
    try {
      final directory = await prepare();
      final file = _file(directory, 'last_crash.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<Set<String>> blacklistedKeys() async {
    try {
      final directory = await prepare();
      final file = _file(directory, 'blacklist.json');
      if (!await file.exists()) return <String>{};

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <String>{};

      return decoded.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> clearBlacklist() async {
    try {
      final directory = await prepare();
      final file = _file(directory, 'blacklist.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<bool> isAnchoringDisabled() async {
    try {
      final directory = await prepare();
      return await _file(directory, 'anchoring_disabled.flag').exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAnchoringDisabled(bool disabled) async {
    try {
      final directory = await prepare();
      final file = _file(directory, 'anchoring_disabled.flag');

      if (disabled) {
        await file.writeAsString('1', flush: true);
      } else if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// What the app already did about a crash in [crash].
  static String adviceFor(ThreeDBreadcrumb crash) {
    if (crash.stage == ThreeDStage.composite) {
      return 'تم تعطيل ربط المجسمات بحركة الشخص تلقائياً (يُستخدم التركيب العادي) '
          'حتى تعيد تفعيله من تقرير 3D.';
    }

    if (crash.cleared) {
      return 'أنهى هذا المجسم مرحلته بنجاح حسب سجل المراحل، لذلك لم يتم حظره؛ '
          'الانهيار حدث بعد ذلك.';
    }

    if (crash.stage == ThreeDStage.rendererRelease) {
      return 'حدث الانهيار أثناء تحرير محرك العرض بعد اكتمال تصوير المشاهد؛ '
          'لم يتم حظر أي مجسم.';
    }

    if (crash.stage == ThreeDStage.search) {
      return 'حدث الانهيار أثناء البحث عن مجسم؛ لم يتم حظر أي مجسم.';
    }

    if (assetStages.contains(crash.stage) && crash.assetKey.isNotEmpty) {
      return 'تم حظر هذا المجسم تلقائياً ولن يُستخدم مرة أخرى '
          '(يمكنك مسح القائمة من تقرير 3D).';
    }

    return 'افتح تقرير 3D وانسخ التفاصيل لمعرفة المرحلة بدقة.';
  }
}
