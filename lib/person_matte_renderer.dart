import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'person_silhouette.dart';
import 'person_tracking_models.dart';

/// Draws the approximate person matte as a small PNG sequence.
class PersonMatteRenderer {
  PersonMatteRenderer._();

  static int _even(int value) => value.isEven ? value : value + 1;

  /// Returns null when the person never appears in [start]..[end].
  static Future<PersonMatteSequence?> render({
    required PersonTrack track,
    required double start,
    required double end,
    required String directory,
    required int frameWidth,
    required int frameHeight,
    int maskWidth = 240,
    double fps = 12,
  }) async {
    if (frameWidth <= 0 || frameHeight <= 0) return null;
    if (!start.isFinite || !end.isFinite || end - start < 0.4) return null;

    final width = _even(maskWidth.clamp(96, 480).toInt());
    final height = _even(
      math.max(2, (width * frameHeight / frameWidth).round()),
    );
    final rate = fps.clamp(6.0, 24.0).toDouble();
    final count = math.min(240, ((end - start) * rate).ceil() + 1);

    final folder = Directory(directory);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final rect = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final blackPaint = ui.Paint()..color = const ui.Color(0xFF000000);
    final dotPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill
      ..isAntiAlias = true;
    final linePaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..isAntiAlias = true;

    var visible = 0;

    for (var i = 0; i < count; i++) {
      final time = start + i / rate;
      final observation = track.sampleAt(
        time,
        maxInterpolationGap: 0.8,
        holdTolerance: 0.4,
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder, rect);
      canvas.drawRect(rect, blackPaint);

      if (observation != null) {
        visible++;
        final strokes = PersonSilhouette.build(
          observation,
          width: width,
          height: height,
        );
        for (final stroke in strokes) {
          if (stroke.isCircle) {
            canvas.drawCircle(
              ui.Offset(stroke.x1, stroke.y1),
              stroke.thickness / 2,
              dotPaint,
            );
          } else {
            linePaint.strokeWidth = stroke.thickness;
            canvas.drawLine(
              ui.Offset(stroke.x1, stroke.y1),
              ui.Offset(stroke.x2, stroke.y2),
              linePaint,
            );
          }
        }
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();

      if (data == null) return null;

      final name = i.toString().padLeft(5, '0');
      await File('$directory/matte_$name.png').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }

    if (visible == 0) return null;

    return PersonMatteSequence(
      directory: directory,
      fps: rate,
      width: width,
      height: height,
      frameCount: count,
    );
  }
}
