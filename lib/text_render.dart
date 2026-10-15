import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Renders captions as transparent PNG images for FFmpeg overlays.
class TextRender {
  /// Detect direction from the first strong script character in the text.
  static TextDirection _directionOf(String text) {
    for (final rune in text.runes) {
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

  /// Loads the selected Google Font. If it cannot be loaded (for example,
  /// while offline), TextPainter falls back to the platform's default font.
  static Future<TextStyle> _loadFontStyle({
    required String fontFamily,
    required double fontSize,
    required String style,
  }) async {
    final weight = style == 'minimal' ? FontWeight.w600 : FontWeight.w900;
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      height: 1.3,
      letterSpacing: style == 'cinematic' ? 0.25 : 0,
    );
    try {
      return await GoogleFonts.getFont(fontFamily, textStyle: base);
    } catch (_) {
      return base;
    }
  }

  static Future<String> png({
    required String text,
    required String outPath,
    required int width,
    required double fontSize,
    Color fill = Colors.white,
    Color stroke = Colors.black,
    bool box = false,
    String style = 'classic',
    String fontFamily = 'Cairo',
  }) async {
    final direction = _directionOf(text);
    final maxW = width * 0.9;
    final effectiveFontSize = fontSize *
        ((style == 'minimal') ? 0.90 : (style == 'bold_center' ? 1.08 : 1.0));
    final pad = effectiveFontSize * 0.35;
    final strokeW = style == 'minimal'
        ? 0.0
        : (style == 'bold_center' ? effectiveFontSize * 0.25 : effectiveFontSize * 0.16);
    final hasBox = box || style == 'boxed';

    final baseStyle = await _loadFontStyle(
      fontFamily: fontFamily,
      fontSize: effectiveFontSize,
      style: style,
    );

    final effectiveFill = switch (style) {
      'neon' => const Color(0xFF8BFFF2),
      'cinematic' => const Color(0xFFFFE3B0),
      'bold_center' => const Color(0xFFFFE082),
      _ => fill,
    };

    final backColor = style == 'neon' ? const Color(0xFF5B27FF) : stroke;
    TextPainter build(TextStyle textStyle) => TextPainter(
          text: TextSpan(text: text, style: textStyle),
          textDirection: direction,
          textAlign: TextAlign.center,
          maxLines: 3,
        )..layout(minWidth: maxW, maxWidth: maxW);

    final back = build(
      baseStyle.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeJoin = StrokeJoin.round
          ..color = backColor,
      ),
    );

    final List<Shadow> shadows;
    if (style == 'neon') {
      shadows = [
        Shadow(color: const Color(0xFF00D9FF), blurRadius: effectiveFontSize * 0.25),
        Shadow(color: const Color(0xFF8B5CF6), blurRadius: effectiveFontSize * 0.40),
      ];
    } else if (style == 'shadow') {
      shadows = [
        Shadow(
          color: Colors.black.withValues(alpha: 0.95),
          blurRadius: effectiveFontSize * 0.20,
          offset: Offset(effectiveFontSize * 0.04, effectiveFontSize * 0.06),
        ),
      ];
    } else {
      shadows = const <Shadow>[];
    }

    final TextStyle frontStyle = style == 'outline'
        ? baseStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = effectiveFontSize * 0.09
              ..strokeJoin = StrokeJoin.round
              ..color = effectiveFill,
            shadows: const <Shadow>[],
          )
        : baseStyle.copyWith(color: effectiveFill, shadows: shadows);
    final front = build(frontStyle);

    final height = (back.height + pad * 2).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final left = (width - maxW) / 2;

    if (hasBox) {
      final boxColor = style == 'cinematic'
          ? const Color(0xB3221A10)
          : style == 'neon'
              ? const Color(0xB31B1242)
              : const Color(0xB3000000);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, maxW, height.toDouble()),
          Radius.circular(effectiveFontSize * 0.4),
        ),
        Paint()..color = boxColor,
      );
    }

    if (style != 'minimal' && style != 'outline') {
      back.paint(canvas, Offset(left, pad));
    }
    front.paint(canvas, Offset(left, pad));

    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw Exception('Could not render caption image.');
    }

    await File(outPath).writeAsBytes(data.buffer.asUint8List());
    return outPath;
  }
}