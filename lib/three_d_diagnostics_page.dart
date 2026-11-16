import 'dart:async';
import 'dart:io';

import 'package:filament_renderer/filament_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'filament_scene_exporter.dart';
import 'three_d_crash_guard.dart';
import 'three_d_render_surface.dart';
import 'three_d_scene_pipeline.dart';
import 'three_d_stage_log.dart';

/// 3D diagnostics: why each model failed in the last export, what crashed the
/// app last time, and an offline Filament self-test that uses the model
/// bundled in the app (no internet, no downloads) to tell an engine problem
/// apart from a model problem.
class ThreeDDiagnosticsPage extends StatefulWidget {
  const ThreeDDiagnosticsPage({super.key});

  @override
  State<ThreeDDiagnosticsPage> createState() =>
      _ThreeDDiagnosticsPageState();
}

class _ThreeDDiagnosticsPageState extends State<ThreeDDiagnosticsPage> {
  String _log = '';
  ThreeDBreadcrumb? _lastCrash;
  Set<String> _blocked = <String>{};
  bool _anchoringDisabled = false;

  int? _viewId;
  bool _testing = false;
  String _selfTest = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final log = await ThreeDCrashGuard.readLog();
    final crash = await ThreeDCrashGuard.lastCrash();
    final blocked = await ThreeDCrashGuard.blacklistedKeys();
    final disabled = await ThreeDCrashGuard.isAnchoringDisabled();

    if (!mounted) return;

    setState(() {
      _log = log;
      _lastCrash = crash;
      _blocked = blocked;
      _anchoringDisabled = disabled;
    });
  }

  String get _reportText {
    final buffer = StringBuffer('تقرير تشخيص 3D — Wad Alreda Studio\n');
    final crash = _lastCrash;

    buffer.writeln(
      crash == null
          ? 'آخر انهيار: لا يوجد.'
          : 'آخر انهيار: ${crash.describe()} (${crash.at.toIso8601String()})',
    );
    buffer.writeln(
      'مجسمات محظورة: ${_blocked.isEmpty ? 'لا يوجد' : _blocked.join('، ')}',
    );
    buffer.writeln(
      'ربط المجسمات بالشخص: ${_anchoringDisabled ? 'معطّل بعد انهيار' : 'مفعّل'}',
    );
    buffer.writeln();
    buffer.writeln('— سجل آخر تصدير 3D —');
    buffer.writeln(_log.trim().isEmpty ? 'لا يوجد سجل بعد.' : _log.trim());

    if (_selfTest.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('— اختبار Filament بدون إنترنت —');
      buffer.writeln(_selfTest.trim());
    }

    return buffer.toString();
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _reportText));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ تفاصيل التشخيص.')),
    );
  }

  Future<void> _clearBlocked() async {
    await ThreeDCrashGuard.clearBlacklist();
    await _reload();
  }

  Future<void> _clearCrash() async {
    await ThreeDCrashGuard.clearLastCrash();
    await _reload();
  }

  Future<void> _enableAnchoring() async {
    await ThreeDCrashGuard.setAnchoringDisabled(false);
    await _reload();
  }

  /// Loads the bundled GLB, renders it, moves the camera and captures a short
  /// clip. Every step is logged on its own, so a failure names its stage.
  Future<void> _runSelfTest() async {
    final id = _viewId;
    if (id == null || _testing) return;

    setState(() {
      _testing = true;
      _selfTest = 'جاري اختبار Filament بالمجسم المدمج (بدون إنترنت)...';
    });

    final summary = ThreeDExportSummary();
    final watch = Stopwatch()..start();
    var stage = ThreeDStage.filamentLoad;
    String? clipFolder;

    void mark(ThreeDStage at) {
      stage = at;
      watch
        ..reset()
        ..start();

      ThreeDCrashGuard.markSync(
        ThreeDBreadcrumb(
          scene: 0,
          stage: at,
          at: DateTime.now(),
          assetTitle: 'اختبار ذاتي (مجسم مدمج)',
        ),
      );
    }

    try {
      await ThreeDCrashGuard.prepare();

      // Stage 1: native initialization, which loads the bundled GLB.
      mark(ThreeDStage.filamentLoad);

      var loaded = false;

      for (var attempt = 0; attempt < 75 && !loaded; attempt++) {
        final diagnostics = await FilamentRenderer.getViewDiagnostics(id);
        loaded = diagnostics['modelLoaded'] == true;

        final error = diagnostics['lastError'];

        if (!loaded && error != null && error.toString().trim().isNotEmpty) {
          throw StateError('Filament renderer error: $error');
        }

        if (!loaded) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      if (!loaded) {
        throw TimeoutException(
          'المجسم المدمج لم يُحمّل داخل Filament.',
          const Duration(seconds: 15),
        );
      }

      summary.record(
        0,
        ThreeDStage.filamentLoad,
        ok: true,
        elapsed: watch.elapsed,
        detail: 'مجسم مدمج',
      );

      // Stage 2: camera.
      mark(ThreeDStage.camera);
      await FilamentRenderer.setCameraMotion(viewId: id, mode: 'orbit');
      summary.record(
        0,
        ThreeDStage.camera,
        ok: true,
        elapsed: watch.elapsed,
        detail: 'orbit',
      );

      // Stage 3: the surface renders real frames.
      mark(ThreeDStage.ready);
      await ThreeDScenePipeline.waitUntilRenderable(id);
      summary.record(
        0,
        ThreeDStage.ready,
        ok: true,
        elapsed: watch.elapsed,
        detail: 'إطارات تُرسم على الشاشة',
      );

      // Stage 4: capture a short clip.
      mark(ThreeDStage.capture);
      final clipPath = await FilamentSceneExporter.captureAndEncode(
        viewId: id,
        durationSeconds: 1.5,
        frameRate: 12,
        width: 480,
        height: 480,
      );

      final clip = File(clipPath);
      clipFolder = clip.parent.path;
      final size = await clip.length();

      if (size < 2048) {
        throw FileSystemException('ملف الالتقاط صغير جداً ($size بايت).', clipPath);
      }

      summary.record(
        0,
        ThreeDStage.capture,
        ok: true,
        elapsed: watch.elapsed,
        detail: '${(size / 1024).round()} KB',
      );
    } catch (error) {
      summary.record(
        0,
        stage,
        ok: false,
        elapsed: watch.elapsed,
        detail: '$error',
      );
    } finally {
      ThreeDCrashGuard.clearBreadcrumbSync();

      final folder = clipFolder;

      if (folder != null) {
        try {
          final directory = Directory(folder);
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        } catch (_) {}
      }
    }

    final failed = summary.failures;

    final verdict = failed.isEmpty
        ? 'النتيجة: محرك Filament يعمل (تحميل + كاميرا + عرض + التقاط) على هذا '
            'الجهاز بالمجسم المدمج. إذا انهار التصدير مع مجسم من الإنترنت فالمشكلة '
            'في ذلك المجسم أو في مرحلة الدمج، وليست في المحرك.'
        : 'النتيجة: Filament نفسه فشل في مرحلة ${failed.first.stage.label}؛ '
            'المشكلة في المحرك أو الجهاز وليست في المجسمات.';

    if (!mounted) return;

    setState(() {
      _testing = false;
      _selfTest = '${summary.toText()}\n$verdict';
    });
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crash = _lastCrash;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير تشخيص 3D'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'نسخ التفاصيل',
            onPressed: _copyAll,
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          FilledButton.icon(
            onPressed: _copyAll,
            icon: const Icon(Icons.copy_all_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('نسخ تفاصيل التشخيص'),
            ),
          ),
          const SizedBox(height: 10),
          _section('آخر انهيار', [
            SelectableText(
              crash == null
                  ? 'لا يوجد انهيار مسجّل.'
                  : '${crash.describe()}\n${ThreeDCrashGuard.adviceFor(crash)}',
              style: const TextStyle(height: 1.6),
            ),
            if (crash != null)
              TextButton(
                onPressed: _clearCrash,
                child: const Text('مسح هذا السجل'),
              ),
          ]),
          const SizedBox(height: 10),
          _section('سجل آخر تصدير 3D (سبب فشل كل مجسم)', [
            SelectableText(
              _log.trim().isEmpty ? 'لا يوجد سجل بعد.' : _log.trim(),
              style: const TextStyle(fontSize: 12.5, height: 1.6),
            ),
          ]),
          const SizedBox(height: 10),
          _section('الحماية التلقائية', [
            Text(
              _blocked.isEmpty
                  ? 'لا توجد مجسمات محظورة.'
                  : 'مجسمات محظورة بعد انهيار (${_blocked.length}):\n${_blocked.join('\n')}',
              style: const TextStyle(height: 1.6),
            ),
            if (_blocked.isNotEmpty)
              TextButton(
                onPressed: _clearBlocked,
                child: const Text('مسح قائمة الحظر'),
              ),
            const SizedBox(height: 6),
            Text(
              _anchoringDisabled
                  ? 'ربط المجسمات بحركة الشخص: معطّل بعد انهيار (يُستخدم التركيب العادي).'
                  : 'ربط المجسمات بحركة الشخص: مفعّل.',
              style: const TextStyle(height: 1.6),
            ),
            if (_anchoringDisabled)
              TextButton(
                onPressed: _enableAnchoring,
                child: const Text('إعادة تفعيل الربط بالشخص'),
              ),
          ]),
          const SizedBox(height: 10),
          _section('اختبار Filament بدون إنترنت', [
            const Text(
              'يستخدم المجسم المدمج في التطبيق فقط: تحميل، كاميرا، عرض، التقاط. '
              'إذا نجح فالمحرك سليم والمشكلة في مجسم أو في الدمج.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            ThreeDRenderSurface(
              height: 220,
              onPlatformViewCreated: (id) {
                if (!mounted) return;
                setState(() => _viewId = id);
              },
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: (_viewId == null || _testing) ? null : _runSelfTest,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.science_rounded),
              label: Text(_testing ? 'جاري الاختبار...' : 'شغّل اختبار Filament'),
            ),
            if (_selfTest.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                _selfTest,
                style: const TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}
