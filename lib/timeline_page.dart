import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'timeline_engine.dart';

/// A lightweight, interactive overview of the actual layers used by an export.
///
/// This screen is intentionally a review surface in Phase 3B: it can scrub the
/// playhead, zoom the timeline, and inspect layer/keyframe metadata. It does
/// not claim to modify or re-render the exported video.
class TimelinePage extends StatefulWidget {
  final TimelineProject project;

  const TimelinePage({super.key, required this.project});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  static const double _labelWidth = 126;
  static const double _rulerHeight = 46;
  static const double _rowHeight = 72;
  static const double _tailWidth = 28;

  final ScrollController _timelineScroll = ScrollController();
  double _pixelsPerSecond = 72;
  double _playhead = 0;
  String? _selectedLayerId;

  bool get _rtl => AppLocalizations.isRtl;
  double get _duration => math.max(0.1, widget.project.duration).toDouble();

  List<TimelineTrack> get _tracks {
    final tracks = widget.project.tracks.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return tracks;
  }

  TimelineLayer? get _selectedLayer {
    final id = _selectedLayerId;
    if (id == null) return null;
    return widget.project.layerById(id);
  }

  @override
  void dispose() {
    _timelineScroll.dispose();
    super.dispose();
  }

  void _setPlayhead(double value) {
    setState(() {
      _playhead = value.clamp(0.0, _duration).toDouble();
    });
  }

  void _zoom(double factor) {
    setState(() {
      _pixelsPerSecond =
          (_pixelsPerSecond * factor).clamp(34.0, 180.0).toDouble();
    });
  }

  void _handleTimelineTap(Offset point) {
    final trackIndex = ((point.dy - _rulerHeight) / _rowHeight).floor();
    if (trackIndex >= 0 && trackIndex < _tracks.length) {
      final track = _tracks[trackIndex];
      final time = (point.dx - _labelWidth) / _pixelsPerSecond;
      TimelineLayer? tapped;

      if (time >= 0) {
        for (final layer in track.layers) {
          final left = _labelWidth + layer.start * _pixelsPerSecond;
          final right = _labelWidth + layer.end * _pixelsPerSecond;
          final top = _rulerHeight + trackIndex * _rowHeight + 14;
          final bottom = top + 40;
          if (point.dx >= left &&
              point.dx <= math.max(left + 14, right) &&
              point.dy >= top &&
              point.dy <= bottom) {
            tapped = layer;
            break;
          }
        }
      }

      if (tapped != null) {
        setState(() {
          _selectedLayerId = tapped!.id;
          _playhead = time.clamp(tapped.start, tapped.end).toDouble();
        });
        return;
      }
    }

    if (point.dx >= _labelWidth) {
      _setPlayhead((point.dx - _labelWidth) / _pixelsPerSecond);
    }
  }

  String _time(double value) {
    final safe = value.isFinite ? value.clamp(0.0, 359999.0) : 0.0;
    final minutes = safe ~/ 60;
    final seconds = safe - minutes * 60;
    return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
  }

  String _trackTitle(TimelineTrack track) {
    if (_rtl) {
      switch (track.type) {
        case TimelineTrackType.video:
          return 'الفيديو';
        case TimelineTrackType.broll:
          return 'لقطات B-roll';
        case TimelineTrackType.captions:
          return 'الكابشن';
        case TimelineTrackType.graphics:
          return 'موشن جرافيك';
        case TimelineTrackType.audio:
          return 'الصوت';
        case TimelineTrackType.effects:
          return 'المؤثرات';
      }
    }
    switch (track.type) {
      case TimelineTrackType.video:
        return 'VIDEO';
      case TimelineTrackType.broll:
        return 'B-ROLL';
      case TimelineTrackType.captions:
        return 'CAPTIONS';
      case TimelineTrackType.graphics:
        return 'MOTION';
      case TimelineTrackType.audio:
        return 'AUDIO';
      case TimelineTrackType.effects:
        return 'SOUND FX';
    }
  }

  String _layerType(TimelineLayerType type) {
    if (_rtl) {
      switch (type) {
        case TimelineLayerType.sourceVideo:
          return 'الفيديو الأصلي';
        case TimelineLayerType.broll:
          return 'لقطة توضيحية';
        case TimelineLayerType.caption:
          return 'كابشن';
        case TimelineLayerType.title:
          return 'عنوان';
        case TimelineLayerType.shape:
          return 'شكل';
        case TimelineLayerType.icon:
          return 'أيقونة';
        case TimelineLayerType.sourceAudio:
          return 'الصوت الأصلي';
        case TimelineLayerType.soundEffect:
          return 'مؤثر صوتي';
      }
    }
    switch (type) {
      case TimelineLayerType.sourceVideo:
        return 'Source video';
      case TimelineLayerType.broll:
        return 'B-roll clip';
      case TimelineLayerType.caption:
        return 'Caption';
      case TimelineLayerType.title:
        return 'Title';
      case TimelineLayerType.shape:
        return 'Shape';
      case TimelineLayerType.icon:
        return 'Icon';
      case TimelineLayerType.sourceAudio:
        return 'Source audio';
      case TimelineLayerType.soundEffect:
        return 'Sound effect';
    }
  }

  Color _layerColor(TimelineLayerType type) {
    switch (type) {
      case TimelineLayerType.sourceVideo:
        return const Color(0xFF4779B8);
      case TimelineLayerType.broll:
        return const Color(0xFF168F91);
      case TimelineLayerType.caption:
        return const Color(0xFF7958C9);
      case TimelineLayerType.title:
        return const Color(0xFFC58A31);
      case TimelineLayerType.shape:
        return const Color(0xFF4E9C68);
      case TimelineLayerType.icon:
        return const Color(0xFF4E9C68);
      case TimelineLayerType.sourceAudio:
        return const Color(0xFF397FA5);
      case TimelineLayerType.soundEffect:
        return const Color(0xFFB0528C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedLayer;
    final canvasWidth = _labelWidth + _duration * _pixelsPerSecond + _tailWidth;
    final canvasHeight = _rulerHeight + _tracks.length * _rowHeight + 12;
    final layerCount = widget.project.layers.length;
    final keyframeCount = widget.project.layers.fold<int>(
      0,
      (count, layer) => count + layer.keyframes.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_rtl ? 'استوديو التايم لاين' : 'Studio Timeline'),
        actions: [
          IconButton(
            tooltip: _rtl ? 'تصغير' : 'Zoom out',
            onPressed: () => _zoom(0.8),
            icon: const Icon(Icons.remove),
          ),
          Center(
            child: Text(
              '${_pixelsPerSecond.round()} px/s',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          IconButton(
            tooltip: _rtl ? 'تكبير' : 'Zoom in',
            onPressed: () => _zoom(1.25),
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            _projectSummary(layerCount: layerCount, keyframeCount: keyframeCount),
            const SizedBox(height: 14),
            _playheadControl(),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF11121B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF292A39)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                controller: _timelineScroll,
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _handleTimelineTap(details.localPosition),
                  child: CustomPaint(
                    size: Size(canvasWidth, canvasHeight),
                    painter: _TimelinePainter(
                      project: widget.project,
                      tracks: _tracks,
                      playhead: _playhead,
                      pixelsPerSecond: _pixelsPerSecond,
                      selectedLayerId: _selectedLayerId,
                      rtl: _rtl,
                      labelWidth: _labelWidth,
                      rulerHeight: _rulerHeight,
                      rowHeight: _rowHeight,
                      layerColor: _layerColor,
                      trackTitle: _trackTitle,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.touch_app_outlined,
                    size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _rtl
                        ? 'اضغط على أي طبقة لمشاهدة تفاصيلها، أو اضغط على المساحة الفارغة لتحريك المؤشر.'
                        : 'Tap a clip to inspect it, or tap an empty area to move the playhead.',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: selected == null
                  ? _emptySelection()
                  : _layerDetails(selected, key: ValueKey(selected.id)),
            ),
            const SizedBox(height: 12),
            _reviewNote(),
          ],
        ),
      ),
    );
  }

  Widget _projectSummary({
    required int layerCount,
    required int keyframeCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF29204C), Color(0xFF171725)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF51417B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_filter_outlined,
                  color: Color(0xFFC2B5FF), size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _rtl ? 'خريطة المونتاج الفعلية' : 'ACTUAL EDIT MAP',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    fontSize: 12,
                  ),
                ),
              ),
              const Icon(Icons.auto_awesome,
                  size: 16, color: Color(0xFFC2B5FF)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_rtl ? 'مدة الفيديو' : 'Duration'}  ${_time(_duration)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _metricChip(Icons.aspect_ratio,
                  '${widget.project.width} × ${widget.project.height}'),
              _metricChip(Icons.speed,
                  '${widget.project.frameRate.toStringAsFixed(0)} FPS'),
              _metricChip(Icons.layers_outlined,
                  '$layerCount ${_rtl ? 'طبقة' : 'layers'}'),
              _metricChip(Icons.key,
                  '$keyframeCount ${_rtl ? 'مفتاح حركة' : 'keyframes'}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _playheadControl() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF171721),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location,
                  color: Color(0xFFFFC857), size: 17),
              const SizedBox(width: 7),
              Text(
                _rtl ? 'مؤشر التشغيل' : 'PLAYHEAD',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                '${_time(_playhead)} / ${_time(_duration)}',
                style: const TextStyle(
                  color: Color(0xFFFFD477),
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _playhead.clamp(0.0, _duration).toDouble(),
            min: 0,
            max: _duration,
            onChanged: _setPlayhead,
          ),
        ],
      ),
    );
  }

  Widget _emptySelection() {
    return Container(
      key: const ValueKey('no-selection'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171721),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF292A39)),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_outlined, color: Colors.white54, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _rtl
                  ? 'اختَر طبقة من التايم لاين عشان تشوف توقيتها وتفاصيل الحركة.'
                  : 'Select a timeline layer to inspect its timing and motion.',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerDetails(TimelineLayer layer, {Key? key}) {
    final sampleTime = _playhead.clamp(layer.start, layer.end).toDouble();
    final transform = layer.transformAt(sampleTime);
    final title = layer.text?.trim().isNotEmpty == true
        ? layer.text!.trim()
        : layer.name;
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF171721),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _layerColor(layer.type).withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 30,
                decoration: BoxDecoration(
                  color: _layerColor(layer.type),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                tooltip: _rtl ? 'إلغاء التحديد' : 'Clear selection',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _selectedLayerId = null),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _layerType(layer.type),
            style: TextStyle(
              color: _layerColor(layer.type),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _detailChip(_rtl ? 'البداية' : 'IN', _time(layer.start)),
              _detailChip(_rtl ? 'النهاية' : 'OUT', _time(layer.end)),
              _detailChip(
                _rtl ? 'المدة' : 'LENGTH',
                '${layer.duration.toStringAsFixed(2)}s',
              ),
              _detailChip(
                _rtl ? 'الحركة' : 'KEYFRAMES',
                '${layer.keyframes.length}',
              ),
            ],
          ),
          if (layer.keyframes.isNotEmpty) ...[
            const SizedBox(height: 13),
            Text(
              _rtl ? 'قيم التحويل عند المؤشر' : 'TRANSFORM AT PLAYHEAD',
              style: const TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _detailChip('X', transform.x.toStringAsFixed(2)),
                _detailChip('Y', transform.y.toStringAsFixed(2)),
                _detailChip('Scale', '${transform.scale.toStringAsFixed(2)}×'),
                _detailChip('Rotation', '${transform.rotation.toStringAsFixed(1)}°'),
                _detailChip('Opacity', '${(transform.opacity * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _rtl ? 'نقاط الحركة' : 'KEYFRAME POINTS',
              style: const TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: layer.keyframes.map((frame) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2940),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${_time(frame.time)} · ${frame.easing.name}',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF252532),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242033),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 17, color: Color(0xFFC2B5FF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _rtl
                  ? 'دي خريطة مراجعة للطبقات المستخدمة في التصدير. تعديل الطبقات وإعادة تصديرها حنضيفه في مرحلة لاحقة.'
                  : 'This is a review map of the layers used for export. Direct layer editing and re-export will be added in a later phase.',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final TimelineProject project;
  final List<TimelineTrack> tracks;
  final double playhead;
  final double pixelsPerSecond;
  final String? selectedLayerId;
  final bool rtl;
  final double labelWidth;
  final double rulerHeight;
  final double rowHeight;
  final Color Function(TimelineLayerType) layerColor;
  final String Function(TimelineTrack) trackTitle;

  const _TimelinePainter({
    required this.project,
    required this.tracks,
    required this.playhead,
    required this.pixelsPerSecond,
    required this.selectedLayerId,
    required this.rtl,
    required this.labelWidth,
    required this.rulerHeight,
    required this.rowHeight,
    required this.layerColor,
    required this.trackTitle,
  });

  TextDirection get _direction => rtl ? TextDirection.rtl : TextDirection.ltr;

  void _text(
    Canvas canvas,
    String value,
    Offset offset, {
    double size = 10,
    Color color = Colors.white70,
    FontWeight weight = FontWeight.normal,
    double maxWidth = 110,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: _direction,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFF11121B), BlendMode.src);

    final labelPaint = Paint()..color = const Color(0xFF191A26);
    canvas.drawRect(Rect.fromLTWH(0, 0, labelWidth, size.height), labelPaint);

    final rulerPaint = Paint()..color = const Color(0xFF202130);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, rulerHeight), rulerPaint);
    _text(
      canvas,
      rtl ? 'المسارات / الزمن' : 'TRACKS / TIME',
      const Offset(12, 16),
      size: 9,
      color: const Color(0xFFB9B8C9),
      weight: FontWeight.bold,
      maxWidth: labelWidth - 20,
    );

    final duration = math.max(0.1, project.duration).toDouble();
    final interval = duration > 90 ? 10 : (duration > 30 ? 5 : (duration > 12 ? 2 : 1));
    final gridPaint = Paint()
      ..color = const Color(0xFF303142)
      ..strokeWidth = 1;
    for (var second = 0.0; second <= duration + 0.001; second += interval) {
      final x = labelWidth + second * pixelsPerSecond;
      canvas.drawLine(Offset(x, rulerHeight), Offset(x, size.height), gridPaint);
      _text(
        canvas,
        _formatTime(second),
        Offset(x + 4, 7),
        size: 9,
        color: const Color(0xFFB9B8C9),
        maxWidth: 58,
      );
    }

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final top = rulerHeight + i * rowHeight;
      final rowColor = i.isEven
          ? const Color(0xFF171823)
          : const Color(0xFF14151F);
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, rowHeight),
        Paint()..color = rowColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, top, labelWidth, rowHeight),
        Paint()..color = const Color(0xFF1D1E2B),
      );
      canvas.drawLine(
        Offset(0, top + rowHeight),
        Offset(size.width, top + rowHeight),
        Paint()
          ..color = const Color(0xFF292A38)
          ..strokeWidth = 1,
      );
      _text(
        canvas,
        trackTitle(track),
        Offset(10, top + 28),
        size: 10,
        color: const Color(0xFFD5D3E4),
        weight: FontWeight.bold,
        maxWidth: labelWidth - 18,
      );
      _text(
        canvas,
        '${track.layers.length} ${rtl ? 'عنصر' : 'items'}',
        Offset(10, top + 45),
        size: 8,
        color: Colors.white38,
        maxWidth: labelWidth - 18,
      );

      for (final layer in track.layers) {
        final start = layer.start.clamp(0.0, duration).toDouble();
        final end = layer.end.clamp(start, duration).toDouble();
        final left = labelWidth + start * pixelsPerSecond;
        final clipWidth =
            math.max(14.0, (end - start) * pixelsPerSecond).toDouble();
        final rect = Rect.fromLTWH(left, top + 15, clipWidth, 38);
        final color = layerColor(layer.type);
        final selected = layer.id == selectedLayerId;
        final fill = Paint()
          ..color = color.withValues(alpha: layer.visible ? 0.88 : 0.28);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(7)),
          fill,
        );
        if (selected) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(7)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.white,
          );
        }
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(5)),
        );
        final label = layer.text?.trim().isNotEmpty == true
            ? layer.text!.trim()
            : layer.name;
        _text(
          canvas,
          label,
          Offset(left + 7, top + 27),
          size: 9,
          color: Colors.white,
          weight: FontWeight.w700,
          maxWidth: math.max(8.0, clipWidth - 14).toDouble(),
        );
        canvas.restore();

        for (final frame in layer.keyframes) {
          final keyX = labelWidth + frame.time * pixelsPerSecond;
          final center = Offset(keyX, top + 13);
          final path = Path()
            ..moveTo(center.dx, center.dy - 5)
            ..lineTo(center.dx + 5, center.dy)
            ..lineTo(center.dx, center.dy + 5)
            ..lineTo(center.dx - 5, center.dy)
            ..close();
          canvas.drawPath(path, Paint()..color = const Color(0xFFFFE08A));
        }
      }
    }

    final playheadX = labelWidth + playhead * pixelsPerSecond;
    final playheadPaint = Paint()
      ..color = const Color(0xFFFFC857)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
    final head = Path()
      ..moveTo(playheadX - 6, 0)
      ..lineTo(playheadX + 6, 0)
      ..lineTo(playheadX, 9)
      ..close();
    canvas.drawPath(head, Paint()..color = const Color(0xFFFFC857));

    canvas.drawLine(
      Offset(labelWidth, 0),
      Offset(labelWidth, size.height),
      Paint()
        ..color = const Color(0xFF3D3E50)
        ..strokeWidth = 1.2,
    );
  }

  static String _formatTime(double value) {
    final safe = value.isFinite ? value.clamp(0.0, 359999.0) : 0.0;
    final minutes = safe ~/ 60;
    final seconds = safe - minutes * 60;
    return '$minutes:${seconds.toStringAsFixed(0).padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.project != project ||
        oldDelegate.tracks != tracks ||
        oldDelegate.playhead != playhead ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.selectedLayerId != selectedLayerId ||
        oldDelegate.rtl != rtl;
  }
}
