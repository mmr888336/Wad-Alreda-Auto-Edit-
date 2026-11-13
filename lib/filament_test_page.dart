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
import 'settings.dart';
import 'three_d_asset_service.dart';

/// Real 3D asset browser + native Filament camera/animation studio.
class FilamentTestPage extends StatefulWidget {
  const FilamentTestPage({super.key});

  @override
  State<FilamentTestPage> createState() => _FilamentTestPageState();
}

class _FilamentTestPageState extends State<FilamentTestPage> {
  final TextEditingController _searchController = TextEditingController();
  late Future<String> _versionFuture;
  Timer? _diagnosticsTimer;
  int _viewGeneration = 0;
  int? _viewId;
  bool _viewCreated = false;
  bool _refreshing = false;
  bool _searching = false;
  bool _working = false;
  bool _saving = false;
  String? _sourceVideo;
  String? _sourceName;
  String? _resultVideo;
  String? _message;
  String _cameraMode = 'orbit';
  String? _activeModelName;
  Map<String, dynamic> _diagnostics = <String, dynamic>{};
  List<ThreeDAsset> _assets = <ThreeDAsset>[];
  List<String> _providerWarnings = <String>[];
  ThreeDAssetService? _assetService;
  AppSettings? _settings;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _rendererReady =>
      _viewCreated &&
      _diagnostics['surfaceReady'] == true &&
      _diagnostics['modelLoaded'] == true &&
      (_diagnostics['framesRendered'] as num? ?? 0) >= 2;

  @override
  void initState() {
    super.initState();
    _versionFuture = FilamentRenderer.getNativeVersion();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final value = await AppSettings.load();
      if (!mounted) return;
      setState(() => _settings = value);
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر تحميل إعدادات مصادر 3D: $error');
    }
  }

  @override
  void dispose() {
    _diagnosticsTimer?.cancel();
    _searchController.dispose();
    _assetService?.dispose();
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
      if (mounted && id == _viewId) setState(() => _diagnostics = value);
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

  Future<void> _searchAssets() async {
    final query = _searchController.text.trim();
    if (query.length < 2 || _searching) return;
    setState(() {
      _searching = true;
      _assets = <ThreeDAsset>[];
      _providerWarnings = <String>[];
      _message = 'جاري البحث في Sketchfab وPoly Haven وHugging Face...';
    });
    try {
      final settings = _settings ?? await AppSettings.load();
      _assetService?.dispose();
      final service = ThreeDAssetService(settings: settings);
      final items = await service.search(query);
      if (!mounted) {
        service.dispose();
        return;
      }
      setState(() {
        _settings = settings;
        _assetService = service;
        _assets = items;
        _providerWarnings = service.warnings.toList();
        _message = items.isEmpty
            ? 'لم أجد ملفات GLB مباشرة لهذا البحث. جرّب كلمة أبسط مثل human أو car أو room.'
            : 'تم العثور على ${items.length} نموذج قابل للفحص والتحميل.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'فشل البحث عن المجسمات: $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadAsset(ThreeDAsset asset) async {
    final id = _viewId;
    final service = _assetService;
    if (id == null || service == null || _working) return;
    setState(() {
      _working = true;
      _message = 'جاري تنزيل ${asset.title} والتحقق من ملف GLB...';
    });
    try {
      final path = await service.download(asset);
      if (!mounted) return;
      setState(() => _message = 'تم التنزيل. جاري تحميل المجسم داخل محرك Filament...');
      await FilamentRenderer.loadModelFromFile(viewId: id, filePath: path);
      await FilamentRenderer.setCameraMotion(viewId: id, mode: _cameraMode);
      if (!mounted) return;
      setState(() {
        _activeModelName = asset.title;
        _message = 'تم استيراد المجسم الحقيقي من ${asset.providerLabel}. اختر حركة الكاميرا ثم صدّر المشهد.';
      });
      await _refreshDiagnostics();
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر استيراد المجسم: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setCamera(String mode) async {
    final id = _viewId;
    if (id == null) return;
    try {
      await FilamentRenderer.setCameraMotion(viewId: id, mode: mode);
      if (!mounted) return;
      setState(() {
        _cameraMode = mode;
        _message = 'حركة الكاميرا: ${_cameraLabel(mode)}. يمكن السحب على المجسم للتحكم اليدوي.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'تعذر تشغيل مسار الكاميرا: $error');
    }
  }

  String _cameraLabel(String mode) {
    switch (mode) {
      case 'orbit': return 'دوران سينمائي حول المجسم';
      case 'orbit_fast': return 'دوران سريع';
      case 'push_in': return 'اقتراب / Dolly In';
      case 'pull_out': return 'ابتعاد / Dolly Out';
      case 'follow': return 'تحريك نقطة التتبّع حول المجسم';
      default: return 'يدوي';
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.video);
      if (picked == null || picked.files.isEmpty || picked.files.single.path == null) return;
      if (!mounted) return;
      setState(() {
        _sourceVideo = picked.files.single.path;
        _sourceName = picked.files.single.name;
        _resultVideo = null;
        _message = 'تم اختيار الفيديو. مشهد 3D سيظهر بكامل الشاشة في البداية ثم يعود الفيديو الأصلي.';
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
      _message = 'جاري التقاط المشهد ثلاثي الأبعاد...';
      _resultVideo = null;
    });
    try {
      final scenePath = await FilamentSceneExporter.captureAndEncode(
        viewId: id,
        durationSeconds: 4,
        frameRate: 24,
        onStatus: (message) {
          if (mounted) setState(() => _message = message);
        },
      );
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
        _message = 'تم إنشاء الفيديو: مشهد 3D حقيقي بكامل الشاشة لأول 4 ثوانٍ، ثم يكمل الفيديو الأصلي مع صوته.';
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
      if (!await Gal.hasAccess(toAlbum: true)) throw Exception('إذن حفظ الفيديو في المعرض غير متاح.');
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
    final animations = _diagnostics['animationCount'] ?? 0;
    final camera = _diagnostics['cameraMotion'] ?? '—';
    final error = _diagnostics['lastError'];
    return 'Surface: $surface • GLB: $model\n'
        'Frames: $frames • Size: ${width}×$height\n'
        'GLB animations: $animations • Camera: $camera'
        '${error == null ? '' : '\nError: $error'}';
  }

  Widget _cameraButton(String mode, IconData icon) {
    final selected = _cameraMode == mode;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 7, bottom: 7),
      child: ChoiceChip(
        selected: selected,
        avatar: Icon(icon, size: 17),
        label: Text(_cameraLabel(mode)),
        onSelected: _working ? null : (_) => _setCamera(mode),
      ),
    );
  }

  Widget _assetCard(ThreeDAsset asset) {
    return Card(
      child: ListTile(
        leading: asset.previewUrl == null
            ? const CircleAvatar(child: Icon(Icons.view_in_ar_rounded))
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  asset.previewUrl!,
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 58,
                    height: 58,
                    child: Icon(Icons.view_in_ar_rounded),
                  ),
                ),
              ),
        title: Text(asset.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('${asset.providerLabel} • ${asset.license ?? 'License راجع صفحة الأصل'}'),
        trailing: IconButton(
          tooltip: 'تنزيل واستيراد إلى Filament',
          onPressed: _working ? null : () => _loadAsset(asset),
          icon: const Icon(Icons.download_rounded),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Asset & Camera Studio'),
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
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('محرك Filament الأصلي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 7),
                  FutureBuilder<String>(
                    future: _versionFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Text('Plugin error: ${snapshot.error}');
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      return Text('Filament: ${snapshot.data}');
                    },
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _activeModelName == null ? 'المجسم الحالي: النموذج المحلي الاحتياطي' : 'المجسم الحالي: $_activeModelName',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 420,
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
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حركة الكاميرا الحقيقية', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(children: [
                    _cameraButton('orbit', Icons.threesixty_rounded),
                    _cameraButton('orbit_fast', Icons.rotate_right_rounded),
                    _cameraButton('push_in', Icons.zoom_in_rounded),
                    _cameraButton('pull_out', Icons.zoom_out_rounded),
                    _cameraButton('follow', Icons.center_focus_strong_rounded),
                    _cameraButton('manual', Icons.pan_tool_alt_rounded),
                  ]),
                  const Text(
                    'هذه حركة كاميرا داخل محرك Filament: دوران، اقتراب، ابتعاد وتحريك نقطة التتبّع. أول Animation مضمّن في ملف GLB يُشغّل تلقائياً عند وجوده.',
                    style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('استيراد مجسمات حقيقية من الإنترنت', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  const Text(
                    'البحث يستخدم المفاتيح المحفوظة في الإعدادات. يقبل هذا المسار ملفات GLB v2 المستقلة فقط حتى لا يدخل ملف ZIP أو glTF ناقص إلى المحرك.',
                    style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.45),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _searchAssets(),
                          decoration: const InputDecoration(
                            hintText: 'مثلاً: human, car, robot, room',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _searching ? null : _searchAssets,
                        child: _searching
                            ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search_rounded),
                      ),
                    ],
                  ),
                  if (_providerWarnings.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ..._providerWarnings.map((warning) => Text(warning, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11))),
                  ],
                  if (_assets.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('نتائج البحث: ${_assets.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ..._assets.map(_assetCard),
                  ],
                  if (_settings != null &&
                      _settings!.sketchfabToken.trim().isEmpty &&
                      _settings!.polyHavenApiKey.trim().isEmpty &&
                      _settings!.objaverseToken.trim().isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('لم يتم العثور على مفاتيح مصادر 3D. أضفها من الإعدادات أولاً.', style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حالة محرك 3D', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 7),
                  SelectableText(_diagnosticText),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _refreshDiagnostics,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تحديث الحالة'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _working ? null : _pickVideo,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(_sourceName == null ? 'اختر الفيديو الأصلي' : 'الفيديو: $_sourceName'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: (!_rendererReady || _sourceVideo == null || _working) ? null : _create3DVideo,
            icon: _working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.movie_filter_rounded),
            label: Text(_working ? 'جاري تجهيز المشهد...' : 'صدّر المشهد 3D بكامل الشاشة داخل الفيديو'),
          ),
          if (_resultVideo != null) ...[
            const SizedBox(height: 8),
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
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF171721), borderRadius: BorderRadius.circular(12)),
              child: SelectableText(_message!, style: const TextStyle(height: 1.5)),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'ملاحظة: هذه المرحلة تربط مصادر الأصول بمحرك Filament وتصدّر مشهد 3D حقيقياً. إدخال المشاهد المختارة تلقائياً داخل كل مهمة Enhancer دون فتح شاشة الاستوديو هو خطوة الدمج التالية.',
            style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}
