import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'app_localizations.dart';
import 'timeline_engine.dart';
import 'timeline_page.dart';

/// Phase 3D-1: real video playback linked to a lightweight timeline overview.
///
/// This is a review/preview surface. It does not alter media or re-render the
/// project. Detailed layer and keyframe inspection remains in TimelinePage.
class TimelinePreviewPage extends StatefulWidget {
  final TimelineProject project;
  final String? videoPath;

  const TimelinePreviewPage({
    super.key,
    required this.project,
    this.videoPath,
  });

  @override
  State<TimelinePreviewPage> createState() => _TimelinePreviewPageState();
}

class _TimelinePreviewPageState extends State<TimelinePreviewPage> {
  static const double _pixelsPerSecond = 68;
  static const double _labelWidth = 104;
  static const double _rulerHeight = 30;
  static const double _rowHeight = 42;

  VideoPlayerController? _controller;
  String? _playerError;
  bool _playerReady = false;
  bool _dragging = false;
  double _playhead = 0;
  DateTime _lastUiTick = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _rtl => AppLocalizations.isRtl;
  double get _duration => math.max(0.1, widget.project.duration).toDouble();

  List<TimelineTrack> get _tracks {
    final items = widget.project.tracks.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return items;
  }

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final path = widget.videoPath?.trim();
    if (path == null || path.isEmpty) return;

    try {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('ملف الفيديو غير موجود', path);
      }

      final controller = VideoPlayerController.file(file);
      _controller = controller;
      controller.addListener(_onPlayerTick);
      await controller.initialize();
      await controller.setLooping(false);

      if (!mounted) return;
      setState(() {
        _playerReady = true;
        _playerError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _playerError = error.toString();
        _playerReady = false;
      });
    }
  }

  void _onPlayerTick() {
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    if (_dragging) return;

    final now = DateTime.now();
    final value = controller.value;
    final completed = value.isCompleted;
    if (!completed && now.difference(_lastUiTick).inMilliseconds < 90) {
      return;
    }
    _lastUiTick = now;

    final seconds = value.position.inMilliseconds / 1000.0;
    final safe = seconds.clamp(0.0, _duration).toDouble();
    if ((safe - _playhead).abs() < 0.035 && !completed) return;

    setState(() => _playhead = safe);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.isCompleted) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seek(double seconds) async {
    final controller = _controller;
    final target = seconds.clamp(0.0, _duration).toDouble();
    setState(() => _playhead = target);
    if (controller == null || !controller.value.isInitialized) return;

    final mediaDuration = controller.value.duration;
    final maxMs = mediaDuration.inMilliseconds;
    final targetMs = (target * 1000).round().clamp(0, maxMs);
    try {
      await controller.seekTo(Duration(milliseconds: targetMs));
    } catch (error) {
      if (mounted) {
        setState(() => _playerError = 'تعذر تحريك الفيديو: $error');
      }
    }
  }

  void _onTimelineTap(Offset localPosition) {
    final seconds = (localPosition.dx - _labelWidth) / _pixelsPerSecond;
    if (seconds < 0) return;
    _seek(seconds);
  }

  String _time(double value) {
    final safe = value.isFinite ? value.clamp(0.0, 359999.0) : 0.0;
    final minutes = safe ~/ 60;
    final seconds = safe - minutes * 60;
    return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final canvasWidth = _labelWidth + _duration * _pixelsPerSecond + 24;
    final canvasHeight = _rulerHeight + _tracks.length * _rowHeight;
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(_rtl ? 'معاينة الاستوديو' : 'Studio Preview'),
        actions: [
          IconButton(
            tooltip: _rtl ? 'تفاصيل الطبقات' : 'Layer details',
            onPressed: _openDetailedTimeline,
            icon: const Icon(Icons.timeline_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            _sectionTitle(
              _rtl ? 'معاينة الفيديو' : 'VIDEO PREVIEW',
              Icons.play_circle_outline_rounded,
            ),
            const SizedBox(height: 9),
            _videoSurface(controller),
            const SizedBox(height: 10),
            _playerControls(controller),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _sectionTitle(
                    _rtl ? 'طبقات المشروع' : 'PROJECT TIMELINE',
                    Icons.layers_outlined,
                  ),
                ),
                Text(
                  '${widget.project.width}×${widget.project.height}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Container(
              height: canvasHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF11121B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF292A39)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _onTimelineTap(details.localPosition),
                  child: CustomPaint(
                    size: Size(canvasWidth, canvasHeight),
                    painter: _PreviewTimelinePainter(
                      tracks: _tracks,
                      duration: _duration,
                      playhead: _playhead,
                      pixelsPerSecond: _pixelsPerSecond,
                      labelWidth: _labelWidth,
                      rulerHeight: _rulerHeight,
                      rowHeight: _rowHeight,
                      rtl: _rtl,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _rtl
                  ? 'اضغط على أي مكان في التايم لاين لتحريك الفيديو لنفس اللحظة.'
                  : 'Tap anywhere on the timeline to seek the video to that moment.',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _openDetailedTimeline,
              icon: const Icon(Icons.tune_rounded),
              label: Text(
                _rtl ? 'فتح تفاصيل الطبقات والحركات' : 'Open layer and motion details',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFC2B5FF)),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.45,
            fontWeight: FontWeight.w800,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _videoSurface(VideoPlayerController? controller) {
    if (controller != null && _playerReady && controller.value.isInitialized) {
      final ratio = controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : 16 / 9;
      return Container(
        constraints: const BoxConstraints(maxHeight: 340),
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF292A39)),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: ratio,
          child: VideoPlayer(controller),
        ),
      );
    }

    final message = _playerError != null
        ? (_rtl ? 'تعذر فتح الفيديو للمعاينة' : 'Could not open video preview')
        : widget.videoPath == null || widget.videoPath!.trim().isEmpty
            ? (_rtl ? 'مسار الفيديو غير متوفر' : 'Video path is not available')
            : (_rtl ? 'جاري تجهيز معاينة الفيديو...' : 'Preparing video preview...');

    return Container(
      height: 230,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF11121B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF292A39)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _playerError == null
                ? Icons.movie_outlined
                : Icons.error_outline_rounded,
            size: 42,
            color: Colors.white38,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (_playerError != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                _playerError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ),
          ],
          if (widget.videoPath != null && !_playerReady && _playerError == null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _playerControls(VideoPlayerController? controller) {
    final ready = controller != null && _playerReady && controller.value.isInitialized;
    final playing = ready && controller.value.isPlaying;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      decoration: BoxDecoration(
        color: const Color(0xFF171721),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: ready ? _togglePlayback : null,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                tooltip: playing
                    ? (_rtl ? 'إيقاف مؤقت' : 'Pause')
                    : (_rtl ? 'تشغيل' : 'Play'),
              ),
              const SizedBox(width: 8),
              Text(
                '${_time(_playhead)} / ${_time(_duration)}',
                style: const TextStyle(
                  color: Color(0xFFFFD477),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              if (ready)
                Icon(
                  playing ? Icons.graphic_eq_rounded : Icons.pause_circle_outline,
                  color: Colors.white54,
                  size: 18,
                ),
            ],
          ),
          Slider(
            value: _playhead.clamp(0.0, _duration).toDouble(),
            min: 0,
            max: _duration,
            onChangeStart: ready ? (_) => setState(() => _dragging = true) : null,
            onChanged: ready
                ? (value) => setState(() => _playhead = value)
                : null,
            onChangeEnd: ready
                ? (value) {
                    setState(() => _dragging = false);
                    _seek(value);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  void _openDetailedTimeline() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TimelinePage(project: widget.project),
      ),
    );
  }
}

class _PreviewTimelinePainter extends CustomPainter {
  final List<TimelineTrack> tracks;
  final double duration;
  final double playhead;
  final double pixelsPerSecond;
  final double labelWidth;
  final double rulerHeight;
  final double rowHeight;
  final bool rtl;

  const _PreviewTimelinePainter({
    required this.tracks,
    required this.duration,
    required this.playhead,
    required this.pixelsPerSecond,
    required this.labelWidth,
    required this.rulerHeight,
    required this.rowHeight,
    required this.rtl,
  });

  Color _color(TimelineLayerType type) {
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
      case TimelineLayerType.icon:
        return const Color(0xFF4E9C68);
      case TimelineLayerType.sourceAudio:
        return const Color(0xFF397FA5);
      case TimelineLayerType.soundEffect:
        return const Color(0xFFB0528C);
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth, {
    Color color = Colors.white70,
    double fontSize = 10,
    FontWeight weight = FontWeight.w600,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFF11121B);
    canvas.drawRect(Offset.zero & size, background);

    final labelPaint = Paint()..color = const Color(0xFF191A26);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, labelWidth, size.height),
      labelPaint,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var second = 0.0; second <= duration; second += 1) {
      final x = labelWidth + second * pixelsPerSecond;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      if (second % 5 == 0 || second == 0) {
        _drawText(
          canvas,
          '${second.toInt()}s',
          Offset(x + 4, 8),
          34,
          color: Colors.white54,
          fontSize: 9,
        );
      }
    }

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final top = rulerHeight + i * rowHeight;
      final rowPaint = Paint()
        ..color = i.isEven
            ? const Color(0xFF171823)
            : const Color(0xFF141520);
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, rowHeight),
        rowPaint,
      );
      canvas.drawLine(
        Offset(0, top + rowHeight),
        Offset(size.width, top + rowHeight),
        gridPaint,
      );
      _drawText(
        canvas,
        track.name,
        Offset(7, top + 14),
        labelWidth - 14,
        color: const Color(0xFFD8D5E8),
        fontSize: 9,
      );

      for (final layer in track.layers) {
        if (!layer.visible) continue;
        final start = layer.start.clamp(0.0, duration).toDouble();
        final end = layer.end.clamp(start, duration).toDouble();
        final left = labelWidth + start * pixelsPerSecond;
        final right = labelWidth + end * pixelsPerSecond;
        final rect = Rect.fromLTWH(
          left + 1,
          top + 7,
          math.max(4.0, right - left - 2),
          rowHeight - 14,
        );
        final paint = Paint()..color = _color(layer.type);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          paint,
        );
        if (rect.width > 38) {
          _drawText(
            canvas,
            layer.text?.trim().isNotEmpty == true ? layer.text!.trim() : layer.name,
            Offset(rect.left + 5, rect.top + 5),
            rect.width - 10,
            color: Colors.white,
            fontSize: 8,
          );
        }
      }
    }

    final playX = labelWidth + playhead.clamp(0.0, duration) * pixelsPerSecond;
    final playPaint = Paint()
      ..color = const Color(0xFFFFC857)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playX, 0),
      Offset(playX, size.height),
      playPaint,
    );
    canvas.drawCircle(Offset(playX, 5), 4, Paint()..color = const Color(0xFFFFC857));
  }

  @override
  bool shouldRepaint(covariant _PreviewTimelinePainter oldDelegate) {
    return oldDelegate.tracks != tracks ||
        oldDelegate.duration != duration ||
        oldDelegate.playhead != playhead ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.rtl != rtl;
  }
}