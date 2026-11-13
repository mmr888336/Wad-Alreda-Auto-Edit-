import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:filament_renderer/filament_renderer.dart';

import 'filament_scene_exporter.dart';

/// Native 3D preview plus a first working 3D-to-video export flow.
class FilamentTestPage extends StatefulWidget {
  const FilamentTestPage({super.key});

  @override
  State<FilamentTestPage> createState() => _FilamentTestPageState();
}

class _FilamentTestPageState extends State<FilamentTestPage> {
  late Future<String> _versionFuture;
  Timer? _diagnosticsTimer;
  int _viewGeneration = 0;
  int? _viewId;
  bool _viewCreated = false;
  bool _refreshing = false;
  bool _working = false;
  bool _saving = false;
  String? _sourceVideo;
  String? _sourceName;
  String? _sceneVideo;
  String? _resultVideo;
  String? _message;
  Map<String, dynamic> _diagnostics = <String, dynamic>{};

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _rendererReady =>
      _viewCreated &&
      _diagnostics['surfaceReady'] == true &&
      _diagnostics['modelLoaded'] == true &&
      (_diagnostics['framesRendered'] as num? ?? 0) >= 2;

  @override
  void initState() {
    super.initState();
    _versionFuture = FilamentRenderer.getNativeVersion();
  }

  @override
  void dispose() {
    _diagnosticsTimer?.cancel();
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    setState(() {
      _viewId = id;
      _viewCreated = true;
      _diagnostics = <String, dynamic>{};
    });
    _refreshDiagnostics();
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => _refreshDiagnostics(),
    );
  }

  Future<void> _refreshDiagnostics() async {
    final id = _viewId;
    if (id == null || _refreshing) return;
    _refreshing = true;
    try {
      final value = await FilamentRenderer.getViewDiagnostics(id);
      if (mounted && id == _viewId) {
        setState(() => _diagnostics = value);
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر قراءة حالة 3D: $error');
    } finally {
      _refreshing = false;
    }
  }

  void _reloadView() {
    _diagnosticsTimer?.cancel();
    setState(() {
      _viewGeneration++;
      _viewId = null;
      _viewCreated = false;
      _diagnostics = <String, dynamic>{};
      _message = null;
      _versionFuture = FilamentRenderer.getNativeVersion();
    });
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.video);
      if (picked == null || picked.files.isEmpty || picked.files.single.path == null) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _sourceVideo = picked.files.single.path;
        _sourceName = picked.files.single.name;
        _resultVideo = null;
        _message = 'تم اختيار الفيديو. اسحب على المجسم لتحديد زاوية الكاميرا.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر اختيار الفيديو: $error');
    }
  }

  Future<void> _create3DVideo() async {
    final id = _viewId;
    if (id == null || !_rendererReady || _sourceVideo == null || _working) return;
    setState(() {
      _working = true;
      _message = 'جاري التقاط مشهد 3D...';
      _resultVideo = null;
    });

    try {
      final scenePath = await FilamentSceneExporter.captureAndEncode(
        viewId: id,
        durationSeconds: 3,
        frameRate: 24,
        onStatus: (message) {
          if (mounted) setState(() => _message = message);
        },
      );
      _sceneVideo = scenePath;
      final resultPath = await FilamentSceneExporter.compositeOverVideo(
        videoPath: _sourceVideo!,
        scenePath: scenePath,
        onStatus: (message) {
          if (mounted) setState(() => _message = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _resultVideo = resultPath;
        _message = 'تم إنشاء الفيديو وإضافة مشهد 3D في أعلى اليمين لأول 3 ثوانٍ.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل تصدير مشهد 3D: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveResult() async {
    final path = _resultVideo;
    if (path == null || _saving) return;
    setState(() => _saving = true);
    try {
      await Gal.requestAccess(toAlbum: true);
      if (!await Gal.hasAccess(toAlbum: true)) {
        throw Exception('إذن حفظ الفيديو في المعرض غير متاح.');
      }
      await Gal.putVideo(path, album: 'Wad Alreda Studio');
      if (mounted) setState(() => _message = 'تم حفظ الفيديو في المعرض.');
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر الحفظ: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareResult() async {
    final path = _resultVideo;
    if (path == null || !await File(path).exists()) return;
    await Share.shareXFiles([XFile(path)]);
  }

  String get _diagnosticText {
    if (!_viewCreated) return 'بانتظار إنشاء نافذة العرض الأصلية...';
    final surface = _diagnostics['surfaceReady'] == true ? 'جاهز' : 'غير جاهز';
    final model = _diagnostics['modelLoaded'] == true ? 'تم تحميله' : 'لم يتم تحميله';
    final frames = _diagnostics['framesRendered'] ?? 0;
    final width = _diagnostics['surfaceWidth'] ?? 0;
    final height = _diagnostics['surfaceHeight'] ?? 0;
    final error = _diagnostics['lastError'];
    return 'Surface: $surface  •  GLB: $model\n'
        'Frames: $frames  •  Size: ${width}×$height'
        '${error == null ? '' : '\nError: $error'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filament 3D Studio'),
        actions: [
          IconButton(
            tooltip: 'إعادة إنشاء نافذة 3D',
            onPressed: _working ? null : _reloadView,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'تحديث تشخيص المحرك',
            onPressed: _refreshDiagnostics,
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Native Filament renderer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<String>(
                    future: _versionFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Text('Plugin error: ${snapshot.error}');
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      return Text('Filament artifact: ${snapshot.data}');
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اسحب على المجسم لتغيير زاوية الكاميرا قبل إدخاله في الفيديو.',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 360,
              color: const Color(0xFF101521),
              child: _isAndroid
                  ? AndroidView(
                      key: ValueKey(_viewGeneration),
                      viewType: FilamentRenderer.modelViewType,
                      creationParams: const <String, Object>{},
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _onPlatformViewCreated,
                    )
                  : const Center(child: Text('افتح الشاشة على جهاز Android.')),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حالة محرك 3D', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(_diagnosticText),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _refreshDiagnostics,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تحديث الحالة'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _working ? null : _pickVideo,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(_sourceName == null ? 'اختر الفيديو الأصلي' : 'الفيديو: $_sourceName'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (!_rendererReady || _sourceVideo == null || _working)
                ? null
                : _create3DVideo,
            icon: _working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.view_in_ar_rounded),
            label: Text(_working ? 'جاري تجهيز الفيديو...' : 'أضف مشهد 3D إلى الفيديو'),
          ),
          if (_resultVideo != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _saveResult,
              icon: const Icon(Icons.save_alt_rounded),
              label: Text(_saving ? 'جاري الحفظ...' : 'حفظ الفيديو في المعرض'),
            ),
            OutlinedButton.icon(
              onPressed: _shareResult,
              icon: const Icon(Icons.share_rounded),
              label: const Text('مشاركة الفيديو'),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF171721),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(_message!, style: const TextStyle(height: 1.5)),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'المشهد الحالي مدته 3 ثوانٍ ويظهر كطبقة صغيرة أعلى يمين الفيديو. البحث عن مجسمات خارجية من Sketchfab وPoly Haven وObjaverse يأتي بعد إثبات المعاينة والتصدير على الجهاز.',
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}
