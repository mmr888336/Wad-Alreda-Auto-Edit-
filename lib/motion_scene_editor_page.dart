/// Layer editor for a motion cutaway (Motion Smith style scenes).
///
/// Shows a live preview of the scene drawn from the same [MotionProject] the
/// renderer uses, and lets the user drag layers on the canvas, resize them,
/// trim their in/out points, reorder them, edit words, swap sprites and add
/// or remove layers. Every change goes through [MotionSceneEditing], so the
/// document stays valid. "Apply" re-renders the clip with the Motion engine
/// (see [MotionCutawayRenderer.renderBuilt]) and returns the new clip.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'motion_cutaway_renderer.dart';
import 'motion_scene_editing.dart';
import 'motion_scene_json.dart';
import 'motion_scene_model.dart';
import 'pixel_art_sprites.dart';
import 'reference_scene_builder.dart';

/// The re-rendered clip returned when the user applies their edits.
class MotionSceneEditResult {
  final String clipPath;
  final double duration;

  const MotionSceneEditResult({
    required this.clipPath,
    required this.duration,
  });
}

/// Renders an edited document next to [clipPath]. Injectable for tests.
typedef MotionSceneRenderer = Future<MotionCutawayClip?> Function(
  MotionSceneDocument document,
  String clipPath,
);

/// Default renderer: the Motion engine. The new MP4 and its editable
/// description are written next to the old clip; the old clip is untouched.
Future<MotionCutawayClip?> renderMotionSceneDocument(
  MotionSceneDocument document,
  String clipPath,
) async {
  final dir = File(clipPath).parent.path;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final temps = <String>[];
  final clip = await MotionCutawayRenderer.renderBuilt(
    built: ReferenceSceneResult(
      project: document.project,
      assets: document.assets,
    ),
    dir: dir,
    stamp: stamp,
    index: 0,
    fontFamily: document.fontFamily,
    temps: temps,
  );

  // renderBuilt lists the editable description among the temporary files;
  // it must stay next to the new clip.
  final keep = clip == null ? null : MotionSceneJson.sidecarPathFor(clip.path);
  for (final path in temps) {
    if (path == keep) continue;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
  return clip;
}

TextPainter _wordPainter(
  String text,
  Size size,
  double scale,
  double opacity,
) {
  final fontSize =
      math.max(1.0, math.min(size.width, size.height) * 0.14 * scale);
  final alpha = opacity.clamp(0.0, 1.0).toDouble();
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        color: Colors.white.withValues(alpha: alpha),
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 1,
  );
  painter.layout(maxWidth: size.width * 3);
  return painter;
}

/// Screen rectangle (before rotation) covered by [layer] at time [t], or null
/// for layers that are not selectable (backgrounds, unknown assets).
Rect? _layerRect(
  MotionSceneDocument doc,
  MotionLayer layer,
  double t,
  Size size,
) {
  final key = layer.assetKey;
  if (key == null) return null;
  final spec = doc.assets[key];
  if (spec == null) return null;
  final state = layer.stateAt(t);
  final center = Offset(state.x * size.width, state.y * size.height);

  if (spec.kind == SceneAssetKind.sprite) {
    final sprite = PixelSprites.byKey(spec.spriteKey ?? '');
    if (sprite == null || sprite.width == 0) return null;
    final w = spec.widthFraction * size.width * state.scale;
    final h = w * sprite.height / sprite.width;
    return Rect.fromCenter(center: center, width: w, height: h);
  }
  if (spec.kind == SceneAssetKind.word) {
    final text = (layer.text ?? spec.text ?? '').trim();
    if (text.isEmpty) return null;
    final painter = _wordPainter(text, size, state.scale, 1);
    return Rect.fromCenter(
      center: center,
      width: painter.width,
      height: painter.height,
    );
  }
  return null;
}

class _ScenePainter extends CustomPainter {
  final MotionSceneDocument doc;
  final double time;
  final String? selectedId;

  const _ScenePainter({
    required this.doc,
    required this.time,
    required this.selectedId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = Colors.black);

    final t = math.max(0.0, math.min(time, doc.project.duration - 0.001));
    final layers = doc.project.layersAt(t);
    for (final layer in layers) {
      _paintLayer(canvas, size, layer, t);
    }
    canvas.restore();

    final selected = selectedId;
    if (selected == null) return;
    for (final layer in layers) {
      if (layer.id != selected) continue;
      final box = _layerRect(doc, layer, t, size);
      if (box == null) continue;
      canvas.drawRect(
        box.inflate(4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFFC857),
      );
    }
  }

  void _paintLayer(Canvas canvas, Size size, MotionLayer layer, double t) {
    final key = layer.assetKey;
    if (key == null) return;
    final spec = doc.assets[key];
    if (spec == null) return;
    final state = layer.stateAt(t);

    if (spec.kind == SceneAssetKind.background) {
      final rect = Offset.zero & size;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(spec.topColor), Color(spec.bottomColor)],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
      return;
    }

    final center = Offset(state.x * size.width, state.y * size.height);

    if (spec.kind == SceneAssetKind.sprite) {
      final sprite = PixelSprites.byKey(spec.spriteKey ?? '');
      if (sprite == null || sprite.width == 0) return;
      final w = spec.widthFraction * size.width * state.scale;
      final h = w * sprite.height / sprite.width;
      final px = w / sprite.width;
      final paint = Paint();
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(state.rotation * math.pi / 180);
      for (var y = 0; y < sprite.rows.length; y++) {
        final row = sprite.rows[y];
        for (var x = 0; x < row.length; x++) {
          final c = row[x];
          if (c == '.') continue;
          final argb = sprite.palette[c];
          if (argb == null) continue;
          paint.color = Color(argb).withValues(alpha: state.opacity);
          canvas.drawRect(
            Rect.fromLTWH(-w / 2 + x * px, -h / 2 + y * px, px + 0.5, px + 0.5),
            paint,
          );
        }
      }
      canvas.restore();
      return;
    }

    if (spec.kind == SceneAssetKind.word) {
      final text = (layer.text ?? spec.text ?? '').trim();
      if (text.isEmpty) return;
      final painter = _wordPainter(text, size, state.scale, state.opacity);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(state.rotation * math.pi / 180);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => true;
}

class _SpriteThumbPainter extends CustomPainter {
  final PixelSprite sprite;

  const _SpriteThumbPainter(this.sprite);

  @override
  void paint(Canvas canvas, Size size) {
    if (sprite.width == 0 || sprite.height == 0) return;
    final px = math.min(size.width / sprite.width, size.height / sprite.height);
    final dx = (size.width - px * sprite.width) / 2;
    final dy = (size.height - px * sprite.height) / 2;
    final paint = Paint();
    for (var y = 0; y < sprite.rows.length; y++) {
      final row = sprite.rows[y];
      for (var x = 0; x < row.length; x++) {
        final c = row[x];
        if (c == '.') continue;
        final argb = sprite.palette[c];
        if (argb == null) continue;
        paint.color = Color(argb);
        canvas.drawRect(
          Rect.fromLTWH(dx + x * px, dy + y * px, px + 0.5, px + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpriteThumbPainter oldDelegate) =>
      oldDelegate.sprite.key != sprite.key;
}

class MotionSceneEditorPage extends StatefulWidget {
  final MotionSceneDocument document;

  /// The clip the document belongs to. The re-rendered clip is written next
  /// to it.
  final String clipPath;

  final MotionSceneRenderer renderer;

  const MotionSceneEditorPage({
    super.key,
    required this.document,
    required this.clipPath,
    this.renderer = renderMotionSceneDocument,
  });

  @override
  State<MotionSceneEditorPage> createState() => _MotionSceneEditorPageState();
}

class _MotionSceneEditorPageState extends State<MotionSceneEditorPage>
    with SingleTickerProviderStateMixin {
  static const int _maxUndo = 40;

  late MotionSceneDocument _doc;
  late final AnimationController _clock;
  final List<MotionSceneDocument> _undo = <MotionSceneDocument>[];

  double _t = 0;
  String? _selectedId;
  String? _panLayerId;
  MotionLayer? _trimBase;
  bool _dirty = false;
  bool _rendering = false;
  String? _error;

  bool get _rtl => AppLocalizations.isRtl;
  double get _duration => math.max(0.1, _doc.project.duration).toDouble();

  String _s(String ar, String en) => _rtl ? ar : en;

  String _fmt(double value) => value.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    final ms = (_doc.project.duration * 1000).round();
    _clock = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: math.max(100, math.min(3600000, ms))),
    );
    _clock.addListener(_onClock);
    _clock.addStatusListener((status) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _onClock() {
    if (!mounted) return;
    setState(() => _t = _clock.value * _duration);
  }

  // ---------------------------------------------------------------------------
  // Lookups
  // ---------------------------------------------------------------------------

  MotionScene? _sceneAt(double t) {
    final scenes = _doc.project.scenes;
    if (scenes.isEmpty) return null;
    for (final scene in scenes) {
      if (scene.isActiveAt(t)) return scene;
    }
    return t < scenes.first.start ? scenes.first : scenes.last;
  }

  MotionLayer? _layerById(String? id) {
    if (id == null) return null;
    for (final scene in _doc.project.scenes) {
      for (final layer in scene.layers) {
        if (layer.id == id) return layer;
      }
    }
    return null;
  }

  MotionScene? _sceneOfLayer(String id) {
    for (final scene in _doc.project.scenes) {
      for (final layer in scene.layers) {
        if (layer.id == id) return scene;
      }
    }
    return null;
  }

  /// Editable (non-background) layers of [scene], front-most first.
  List<MotionLayer> _editableLayers(MotionScene scene) {
    final list = <MotionLayer>[
      for (final layer in scene.layers)
        if (!MotionSceneEditing.isBackground(layer)) layer,
    ];
    list.sort((a, b) => b.zIndex.compareTo(a.zIndex));
    return list;
  }

  String _layerTitle(MotionLayer layer) {
    if (MotionSceneEditing.isWord(_doc, layer)) {
      final text = (layer.text ?? '').trim();
      return text.isEmpty ? _s('كلمة', 'Word') : text;
    }
    if (MotionSceneEditing.isSprite(_doc, layer)) {
      return _s('عنصر بيكسل', 'Pixel sprite');
    }
    return layer.id;
  }

  MotionLayer? _hitTest(Offset point, Size size) {
    final scene = _sceneAt(_t);
    if (scene == null) return null;
    for (final layer in _editableLayers(scene)) {
      if (!layer.isActiveAt(_t)) continue;
      final box = _layerRect(_doc, layer, _t, size);
      if (box != null && box.inflate(10).contains(point)) return layer;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Document changes
  // ---------------------------------------------------------------------------

  void _pushUndo() {
    _undo.add(_doc);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
  }

  void _commit(MotionSceneDocument next) {
    if (identical(next, _doc)) return;
    _clock.stop();
    setState(() {
      _pushUndo();
      _doc = next;
      _dirty = true;
    });
  }

  void _commitAndSelectNew(MotionSceneDocument next, String sceneId) {
    final before = <String>{};
    for (final scene in _doc.project.scenes) {
      if (scene.id != sceneId) continue;
      for (final layer in scene.layers) {
        before.add(layer.id);
      }
    }
    MotionLayer? created;
    for (final scene in next.project.scenes) {
      if (scene.id != sceneId) continue;
      for (final layer in scene.layers) {
        if (!before.contains(layer.id)) created = layer;
      }
    }
    _commit(next);
    final added = created;
    if (added != null) {
      setState(() {
        _selectedId = added.id;
        _t = math.min(added.start + 0.5, added.end - 0.05);
      });
    }
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    _clock.stop();
    setState(() {
      _doc = _undo.removeLast();
      if (_layerById(_selectedId) == null) _selectedId = null;
    });
  }

  void _scaleLayer(String id, double factor) {
    _commit(
      MotionSceneEditing.updateLayer(
        _doc,
        id,
        (scene, layer) => MotionSceneEditing.scaledBy(layer, factor),
      ),
    );
  }

  void _deleteLayer(String id) {
    _commit(MotionSceneEditing.removeLayer(_doc, id));
    setState(() => _selectedId = null);
  }

  // ---------------------------------------------------------------------------
  // Canvas gestures
  // ---------------------------------------------------------------------------

  void _onTap(Offset point, Size size) {
    final hit = _hitTest(point, size);
    setState(() => _selectedId = hit?.id);
  }

  void _onPanStart(Offset point, Size size) {
    _clock.stop();
    final hit = _hitTest(point, size);
    if (hit == null) {
      _panLayerId = null;
      return;
    }
    setState(() {
      _selectedId = hit.id;
      _pushUndo();
      _dirty = true;
    });
    _panLayerId = hit.id;
  }

  void _onPanUpdate(Offset delta, Size size) {
    final id = _panLayerId;
    if (id == null || size.width <= 0 || size.height <= 0) return;
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    setState(() {
      _doc = MotionSceneEditing.updateLayer(
        _doc,
        id,
        (scene, layer) => MotionSceneEditing.translated(layer, dx, dy),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  void _seek(double seconds) {
    _clock.stop();
    setState(() => _t = seconds.clamp(0.0, _duration).toDouble());
  }

  void _togglePlay() {
    if (_clock.isAnimating) {
      _clock.stop();
      setState(() {});
      return;
    }
    final from = _t >= _duration - 0.05 ? 0.0 : _t / _duration;
    _clock.forward(from: from.clamp(0.0, 1.0).toDouble());
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  Future<String?> _askText({required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          onSubmitted: (text) => Navigator.pop(dialogContext, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_s('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(_s('تم', 'OK')),
          ),
        ],
      ),
    );
    final clean = value?.trim();
    if (clean == null || clean.isEmpty) return null;
    return clean;
  }

  Future<String?> _pickSprite() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final sprite in PixelSprites.all)
                _spriteChoice(
                  sprite,
                  false,
                  () => Navigator.pop(sheetContext, sprite.key),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_s('تجاهل التعديلات؟', 'Discard changes?')),
        content: Text(
          _s(
            'التعديلات اللي عملتها على المشهد لسه ما اتطبقتش.',
            'Your edits have not been applied yet.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_s('كمّل تعديل', 'Keep editing')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_s('تجاهل', 'Discard')),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _addWord(MotionScene scene) async {
    _clock.stop();
    final text = await _askText(title: _s('كلمة جديدة', 'New word'));
    if (text == null || !mounted) return;
    _commitAndSelectNew(
      MotionSceneEditing.addWord(_doc, scene.id, text),
      scene.id,
    );
  }

  Future<void> _addSprite(MotionScene scene) async {
    _clock.stop();
    final key = await _pickSprite();
    if (key == null || !mounted) return;
    _commitAndSelectNew(
      MotionSceneEditing.addSprite(_doc, scene.id, key),
      scene.id,
    );
  }

  Future<void> _editWord(MotionLayer layer) async {
    _clock.stop();
    final text = await _askText(
      title: _s('تعديل الكلمة', 'Edit word'),
      initial: layer.text ?? '',
    );
    if (text == null || !mounted) return;
    _commit(MotionSceneEditing.withWordText(_doc, layer, text));
  }

  // ---------------------------------------------------------------------------
  // Apply (re-render)
  // ---------------------------------------------------------------------------

  Future<void> _apply() async {
    if (_rendering) return;
    _clock.stop();
    try {
      _doc.project.validate();
    } catch (error) {
      setState(() => _error = '${_s('المشهد غير صالح', 'Invalid scene')}: $error');
      return;
    }

    setState(() {
      _rendering = true;
      _error = null;
    });

    MotionCutawayClip? clip;
    try {
      clip = await widget.renderer(_doc, widget.clipPath);
    } catch (_) {
      clip = null;
    }
    if (!mounted) return;

    if (clip == null) {
      setState(() {
        _rendering = false;
        _error = _s(
          'تعذّر إنشاء المشهد المعدّل. جرّب تاني.',
          'Could not render the edited scene. Please try again.',
        );
      });
      return;
    }

    Navigator.of(context).pop(
      MotionSceneEditResult(clipPath: clip.path, duration: clip.duration),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final project = _doc.project;
    final scene = _sceneAt(_t);
    final selected = _layerById(_selectedId);
    final selectedScene = selected == null ? null : _sceneOfLayer(selected.id);
    final ratio = project.width / project.height;

    return PopScope(
      canPop: !_dirty && !_rendering,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _rendering) return;
        final leave = await _confirmDiscard();
        if (leave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_s('محرر مشهد الموشن', 'Motion scene editor')),
          actions: [
            IconButton(
              tooltip: _s('تراجع', 'Undo'),
              onPressed: _undo.isEmpty || _rendering ? null : _undoLast,
              icon: const Icon(Icons.undo_rounded),
            ),
            TextButton.icon(
              onPressed: _rendering ? null : _apply,
              icon: const Icon(Icons.check_rounded),
              label: Text(_s('تطبيق', 'Apply')),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  _canvas(ratio),
                  const SizedBox(height: 8),
                  Text(
                    _s(
                      'اضغط على عنصر لتحديده، واسحبه لتحريكه.',
                      'Tap an element to select it, drag it to move it.',
                    ),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _controls(),
                  const SizedBox(height: 12),
                  _sceneBar(scene),
                  const SizedBox(height: 14),
                  if (scene != null) ...[
                    _sectionTitle(
                      _s('الطبقات (الأمامية أولاً)', 'Layers (front first)'),
                      Icons.layers_outlined,
                    ),
                    const SizedBox(height: 8),
                    _layerList(scene),
                  ],
                  if (selected != null && selectedScene != null) ...[
                    const SizedBox(height: 14),
                    _inspector(selectedScene, selected),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFF8A80),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_rendering) Positioned.fill(child: _renderingOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _renderingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            _s('جاري إنشاء المشهد المعدّل...', 'Rendering the edited scene...'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFC2B5FF)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 0.45,
              fontWeight: FontWeight.w800,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  Widget _canvas(double ratio) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: AspectRatio(
          aspectRatio: ratio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _onTap(details.localPosition, size),
                  onPanStart: (details) =>
                      _onPanStart(details.localPosition, size),
                  onPanUpdate: (details) => _onPanUpdate(details.delta, size),
                  onPanEnd: (_) => _panLayerId = null,
                  onPanCancel: () => _panLayerId = null,
                  child: CustomPaint(
                    size: size,
                    painter: _ScenePainter(
                      doc: _doc,
                      time: _t,
                      selectedId: _selectedId,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final playing = _clock.isAnimating;
    final value = _t.clamp(0.0, _duration).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      decoration: BoxDecoration(
        color: const Color(0xFF171721),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: _rendering ? null : _togglePlay,
            tooltip: playing ? _s('إيقاف مؤقت', 'Pause') : _s('تشغيل', 'Play'),
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: _duration,
              onChanged: _rendering ? null : _seek,
            ),
          ),
          Text(
            '${_fmt(value)} / ${_fmt(_duration)}',
            style: const TextStyle(
              color: Color(0xFFFFD477),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sceneBar(MotionScene? scene) {
    final scenes = _doc.project.scenes;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < scenes.length; i++)
          ChoiceChip(
            label: Text('${_s('مشهد', 'Scene')} ${i + 1}'),
            selected: scene != null && scene.id == scenes[i].id,
            onSelected: (_) => _seek(scenes[i].start + 0.05),
          ),
        OutlinedButton.icon(
          onPressed: scene == null ? null : () => _addWord(scene),
          icon: const Icon(Icons.title_rounded, size: 18),
          label: Text(_s('إضافة كلمة', 'Add word')),
        ),
        OutlinedButton.icon(
          onPressed: scene == null ? null : () => _addSprite(scene),
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(_s('إضافة عنصر', 'Add sprite')),
        ),
      ],
    );
  }

  Widget _layerList(MotionScene scene) {
    final layers = _editableLayers(scene);
    if (layers.isEmpty) {
      return Text(
        _s('مفيش طبقات قابلة للتعديل في المشهد ده.', 'No editable layers here.'),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: layers.length,
      onReorder: (oldIndex, newIndex) {
        var target = newIndex;
        if (target > oldIndex) target -= 1;
        final ids = <String>[for (final layer in layers) layer.id];
        final moved = ids.removeAt(oldIndex);
        ids.insert(target, moved);
        _commit(MotionSceneEditing.reordered(_doc, scene.id, ids));
      },
      itemBuilder: (context, index) {
        final layer = layers[index];
        final isSelected = layer.id == _selectedId;
        return Card(
          key: ValueKey<String>(layer.id),
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFFFFC857)
                  : const Color(0xFF292A39),
            ),
          ),
          child: ListTile(
            dense: true,
            selected: isSelected,
            leading: Icon(
              MotionSceneEditing.isWord(_doc, layer)
                  ? Icons.title_rounded
                  : Icons.image_outlined,
            ),
            title: Text(
              _layerTitle(layer),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_fmt(layer.start)}s → ${_fmt(layer.end)}s',
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () {
              _clock.stop();
              setState(() {
                _selectedId = layer.id;
                if (!layer.isActiveAt(_t)) {
                  _t = math.min(layer.start + 0.5, layer.end - 0.05);
                }
              });
            },
            trailing: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle_rounded),
            ),
          ),
        );
      },
    );
  }

  Widget _spriteChoice(PixelSprite sprite, bool current, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E2B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: current ? const Color(0xFFFFC857) : const Color(0xFF3D3E50),
            width: current ? 2 : 1,
          ),
        ),
        child: CustomPaint(painter: _SpriteThumbPainter(sprite)),
      ),
    );
  }

  Widget _inspector(MotionScene scene, MotionLayer layer) {
    final isWord = MotionSceneEditing.isWord(_doc, layer);
    final isSprite = MotionSceneEditing.isSprite(_doc, layer);
    final start = layer.start.clamp(scene.start, scene.end).toDouble();
    final end = layer.end.clamp(start, scene.end).toDouble();
    final assetKey = layer.assetKey;
    final currentSprite =
        assetKey == null ? null : _doc.assets[assetKey]?.spriteKey;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171721),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF51417B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _layerTitle(layer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                tooltip: _s('حذف الطبقة', 'Delete layer'),
                onPressed: () => _deleteLayer(layer.id),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                _s('الحجم', 'Size'),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                tooltip: _s('تصغير', 'Smaller'),
                onPressed: () => _scaleLayer(layer.id, 1 / 1.1),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Text(
                '${_fmt(layer.stateAt(_t).scale)}×',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(
                tooltip: _s('تكبير', 'Larger'),
                onPressed: () => _scaleLayer(layer.id, 1.1),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          Text(
            '${_s('الظهور', 'On screen')}: ${_fmt(start)}s → ${_fmt(end)}s',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          RangeSlider(
            values: RangeValues(start, end),
            min: scene.start,
            max: scene.end,
            onChangeStart: (_) {
              setState(() {
                _trimBase = layer;
                _pushUndo();
                _dirty = true;
              });
            },
            onChanged: (values) {
              final base = _trimBase ?? layer;
              setState(() {
                _doc = MotionSceneEditing.updateLayer(
                  _doc,
                  layer.id,
                  (s, current) => MotionSceneEditing.retimed(
                    s,
                    base,
                    newStart: values.start,
                    newEnd: values.end,
                  ),
                );
              });
            },
            onChangeEnd: (_) => _trimBase = null,
          ),
          if (isWord)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => _editWord(layer),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(_s('تعديل الكلمة', 'Edit word')),
              ),
            ),
          if (isSprite) ...[
            Text(
              _s('شكل العنصر', 'Sprite'),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sprite in PixelSprites.all)
                  _spriteChoice(
                    sprite,
                    sprite.key == currentSprite,
                    () => _commit(
                      MotionSceneEditing.withSprite(_doc, layer, sprite.key),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
