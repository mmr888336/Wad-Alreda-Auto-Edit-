import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'person_tracking_models.dart';
import 'person_tracking_service.dart';

/// Draws the tracked boxes and skeletons over a video frame.
class PersonOverlayPainter extends CustomPainter {
  PersonOverlayPainter(this.people);

  final List<TrackedPerson> people;

  static const List<Color> _palette = <Color>[
    Color(0xFF7CF5C8),
    Color(0xFFFFC857),
    Color(0xFFFF6B8B),
    Color(0xFF6BB8FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final person in people) {
      final color = _palette[person.trackId % _palette.length];
      final observation = person.observation;
      final box = observation.box;

      canvas.drawRect(
        Rect.fromLTRB(
          box.left * size.width,
          box.top * size.height,
          box.right * size.width,
          box.bottom * size.height,
        ),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      final bonePaint = Paint()
        ..color = color.withValues(alpha: 0.9)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      for (final pair in kBodySkeleton) {
        final a = observation.landmark(pair[0]);
        final b = observation.landmark(pair[1]);
        if (a == null || b == null) continue;
        canvas.drawLine(
          Offset(a.x * size.width, a.y * size.height),
          Offset(b.x * size.width, b.y * size.height),
          bonePaint,
        );
      }

      final dotPaint = Paint()..color = Colors.white;
      for (final type in BodyLandmark.values) {
        final point = observation.landmark(type);
        if (point == null) continue;
        canvas.drawCircle(
          Offset(point.x * size.width, point.y * size.height),
          3,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant PersonOverlayPainter oldDelegate) => true;
}

/// Manual test screen for the Phase 1 visual tracking engine: pick a video,
/// analyze it, then scrub through the frames with the detected boxes and
/// skeletons drawn on top.
class PersonTrackingTestPage extends StatefulWidget {
  const PersonTrackingTestPage({super.key});

  @override
  State<PersonTrackingTestPage> createState() =>
      _PersonTrackingTestPageState();
}

class _PersonTrackingTestPageState extends State<PersonTrackingTestPage> {
  String? _videoPath;
  String? _videoName;
  bool _busy = false;
  bool _cancel = false;
  String _status = '';
  double? _progress;
  PersonTrackingRun? _run;
  int _frameIndex = 0;

  String _t(String ar, String en) => AppLocalizations.isRtl ? ar : en;

  @override
  void initState() {
    super.initState();
    _status = _t(
      'اختر فيديو فيه شخص ظاهر ثم اضغط بدء التحليل.',
      'Choose a video with a visible person, then press Start analysis.',
    );
  }

  @override
  void dispose() {
    _cancel = true;
    _run?.deleteFramesSync();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.video);
      if (picked == null ||
          picked.files.isEmpty ||
          picked.files.single.path == null) {
        return;
      }
      if (!mounted) return;

      _run?.deleteFramesSync();
      setState(() {
        _videoPath = picked.files.single.path;
        _videoName = picked.files.single.name;
        _run = null;
        _frameIndex = 0;
        _status = _t(
          'تم اختيار الفيديو. اضغط بدء التحليل.',
          'Video selected. Press Start analysis.',
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = '${_t('تعذر اختيار الفيديو', 'Pick failed')}: $error');
      }
    }
  }

  String _summary(PersonTrackingResult result) {
    final lines = <String>[
      '${_t('الإطارات المحللة', 'Frames analyzed')}: ${result.framesAnalyzed} '
          '(${result.sampleFps.toStringAsFixed(0)} fps)',
      '${_t('حجم الإطار', 'Frame size')}: ${result.frameWidth}×${result.frameHeight}',
      '${_t('المسارات المكتشفة', 'Tracks found')}: ${result.tracks.length}',
      '${_t('ظهور الشخص الرئيسي', 'Main person coverage')}: '
          '${(result.coverage * 100).toStringAsFixed(0)}%',
    ];
    for (final note in result.notes) {
      lines.add('- $note');
    }
    return lines.join('\n');
  }

  Future<void> _analyze() async {
    final path = _videoPath;
    if (path == null || _busy) return;

    _run?.deleteFramesSync();
    setState(() {
      _busy = true;
      _cancel = false;
      _run = null;
      _frameIndex = 0;
      _progress = 0;
      _status = _t('جاري التحليل...', 'Analyzing...');
    });

    try {
      final run = await PersonTrackingService.analyzeVideo(
        path,
        keepFrames: true,
        isCancelled: () => _cancel,
        onStatus: (message) {
          if (mounted) setState(() => _status = message);
        },
        onProgress: (value) {
          if (!mounted) return;
          final current = _progress ?? 0;
          if (value >= 1 || value - current >= 0.02) {
            setState(() => _progress = value);
          }
        },
      );

      if (!mounted) {
        run.deleteFramesSync();
        return;
      }
      setState(() {
        _run = run;
        _status = _summary(run.result);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = '${_t('فشل التحليل', 'Analysis failed')}\n$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  String _infoFor(List<TrackedPerson> people) {
    if (people.isEmpty) {
      return _t(
        'لا يوجد شخص مكتشف في هذا الإطار.',
        'No person detected in this frame.',
      );
    }

    final buffer = StringBuffer();
    for (final person in people) {
      final o = person.observation;
      buffer.writeln(
        '#${person.trackId}  ${_t('الثقة', 'confidence')} '
        '${(o.confidence * 100).round()}%  '
        '${_t('المركز', 'center')} '
        '(${o.box.centerX.toStringAsFixed(2)}, ${o.box.centerY.toStringAsFixed(2)})',
      );
      final tilt = o.bodyTiltDegrees;
      if (tilt != null) {
        buffer.writeln(
          '${_t('ميلان الجسم', 'Body tilt')}: ${tilt.toStringAsFixed(1)}°',
        );
      }
      final shoulders = o.shoulderWidth;
      if (shoulders != null) {
        buffer.writeln(
          '${_t('عرض الكتفين', 'Shoulder width')}: ${shoulders.toStringAsFixed(2)}',
        );
      }
      final head = o.anchor(PersonAnchor.head);
      if (head != null) {
        buffer.writeln(
          '${_t('الرأس', 'Head')}: (${head.x.toStringAsFixed(2)}, ${head.y.toStringAsFixed(2)})',
        );
      }
    }
    return buffer.toString().trim();
  }

  Widget _buildPreview(PersonTrackingRun run) {
    final frames = run.frames;
    if (frames.isEmpty) return const SizedBox.shrink();

    final index = _frameIndex.clamp(0, frames.length - 1);
    final frame = frames[index];
    final people = run.result.peopleAt(frame.time);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: AspectRatio(
              aspectRatio: frame.width / frame.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(frame.path),
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                  CustomPaint(painter: PersonOverlayPainter(people)),
                ],
              ),
            ),
          ),
        ),
        if (frames.length > 1)
          Slider(
            value: index.toDouble(),
            min: 0,
            max: (frames.length - 1).toDouble(),
            divisions: frames.length - 1,
            label: '${index + 1}/${frames.length}',
            onChanged: (value) => setState(() => _frameIndex = value.round()),
          ),
        Text(
          '${_t('الوقت', 'Time')}: ${frame.time.toStringAsFixed(2)}s',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF171721),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _infoFor(people),
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('اختبار تتبع الأشخاص', 'Person tracking test')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          Text(
            _t(
              'المرحلة 1: اكتشاف الشخص وتتبّع حركته ومواضعه ووضع جسمه. المحرك الحالي يتتبع شخصاً واحداً بصورة موثوقة.',
              'Phase 1: person detection, motion tracking, positions and body pose. The current engine tracks one person reliably.',
            ),
            style: const TextStyle(color: Colors.white70, height: 1.6),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.video_library_outlined),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _videoName == null
                    ? _t('اختيار فيديو', 'Choose video')
                    : '${_t('تغيير الفيديو', 'Change video')}: $_videoName',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_busy)
            OutlinedButton.icon(
              onPressed: () => setState(() => _cancel = true),
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(_t('إيقاف التحليل', 'Stop analysis')),
            )
          else
            FilledButton.icon(
              onPressed: _videoPath == null ? null : _analyze,
              icon: const Icon(Icons.accessibility_new_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(_t('بدء التحليل', 'Start analysis')),
              ),
            ),
          const SizedBox(height: 16),
          if (_busy) ...[
            LinearProgressIndicator(
              value: _progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF171721),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              _status,
              style: const TextStyle(fontSize: 14, height: 1.65),
            ),
          ),
          if (run != null) _buildPreview(run),
        ],
      ),
    );
  }
}
