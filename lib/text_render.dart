import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders text into a transparent PNG so FFmpeg can overlay it on a video.
class TextRender {
  /// Determine text direction from the text itself, not the app's UI language.
  static TextDirection _directionOf(String text) {
    for (final rune in text.runes) {
      // Hebrew and Arabic script ranges are right-to-left.
      final isRtlLetter =
          (rune >= 0x05D0 && rune <= 0x05EA) ||
          (rune >= 0x05EF && rune <= 0x05F2) ||
          (rune >= 0x0620 && rune <= 0x064A) ||
          (rune >= 0x066E && rune <= 0x066F) ||
          (rune >= 0x0671 && rune <= 0x06D3) ||
          rune == 0x06D5 ||
          (rune >= 0x06E5 && rune <= 0x06E6) ||
          (rune >= 0x06EE && rune <= 0x06EF) ||
          (rune >= 0x06FA && rune <= 0x06FC) ||
          rune == 0x06FF ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08C9) ||
          (rune >= 0xFB1D && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF);

      if (isRtlLetter) return TextDirection.rtl;

      // Latin, Greek, and Cyrillic ranges are left-to-right.
      final isLtrLetter =
          (rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A) ||
          (rune >= 0x00C0 && rune <= 0x02AF) ||
          (rune >= 0x0370 && rune <= 0x03FF) ||
          (rune >= 0x0400 && rune <= 0x052F);

      if (isLtrLetter) return TextDirection.ltr;
    }

    return TextDirection.ltr;
  }
  static Future<String> png({
    required String text,
    required String outPath,
    required int width,
    required double fontSize,
    Color fill = Colors.white,
    Color stroke = Colors.black,
    bool box = false,
  }) async {
    final direction = _directionOf(text);
    final maxW = width * 0.9;
    final pad = fontSize * 0.35;
    final strokeW = fontSize * 0.2;

    TextPainter build(TextStyle style) => TextPainter(
          text: TextSpan(
            text: text,
            style: style,
          ),
          textDirection: direction,
          textAlign: TextAlign.center,
          maxLines: 3,
        )..layout(
            minWidth: maxW,
            maxWidth: maxW,
          );

    final back = build(
      TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.3,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeJoin = StrokeJoin.round
          ..color = stroke,
      ),
    );

    final front = build(
      TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.3,
        color: fill,
      ),
    );
    final h = (back.height + pad * 2).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final left = (width - maxW) / 2;

    if (box) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left,
            0,
            maxW,
            h.toDouble(),
          ),
          Radius.circular(fontSize * 0.4),
        ),
        Paint()..color = const Color(0xB3000000),
      );
    }

    back.paint(canvas, Offset(left, pad));
    front.paint(canvas, Offset(left, pad));

    final image = await recorder.endRecording().toImage(width, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);

    if (data == null) {
      throw Exception('Could not render caption image.');
    }

    await File(outPath).writeAsBytes(data.buffer.asUint8List());
    return outPath;
  }
}