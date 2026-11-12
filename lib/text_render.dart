import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'caption_style_engine.dart';

/// Renders transparent PNG captions with a cached, project-stable font style.
class TextRender {
  static final Map<String, Future<TextStyle>> _fontStyleCache = {};

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

  static Future<TextStyle> _loadFontStyle({
    required String fontFamily,
    required double fontSize,
    required String style,
  }) {
    final normalizedStyle = CaptionStyleEngine.normalize(style);
    final key = '$fontFamily|${fontSize.toStringAsFixed(2)}|$normalizedStyle';
    return _fontStyleCache.putIfAbsent(key, () async {
      final weight = normalizedStyle == 'classic'
          ? FontWeight.w800
          : FontWeight.w900;
      final base = TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: weight,
        height: 1.3,
        letterSpacing: normalizedStyle == 'cinematic' ? 0.25 : 0,
      );
      try {
        final loaded = GoogleFonts.getFont(fontFamily, textStyle: base);
        // Wait for pending font downloads once, rather than allowing each
        // caption image to race between downloaded and fallback typefaces.
        await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 8));
        return loaded;
      } catch (_) {
        // Cache the same fallback for every caption in this export.
        return base;
      }
    });
  }

  /// Call once before rendering a batch of captions. The cached result is
  /// reused by every subsequent caption PNG with the same style/font size.
  static Future<void> prepareFont({
    required String fontFamily,
    required double fontSize,
    required String style,
  }) async {
    await _loadFontStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      style: style,
    );
  }

  static String resolveFontFamily({
    required String requestedFont,
    required String language,
  }) => CaptionStyleEngine.fontForLanguage(requestedFont, language);

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
    final stableStyle = CaptionStyleEngine.normalize(style);
    final direction = _directionOf(text);
    final maxW = width * 0.9;
    final effectiveFontSize = fontSize *
        ((stableStyle == 'bold_center') ? 1.08 : 1.0);
    final pad = effectiveFontSize * 0.35;
    final strokeW = switch (stableStyle) {
      'bold_center' => effectiveFontSize * 0.25,
      'outline' => effectiveFontSize * 0.09,
      _ => effectiveFontSize * 0.16,
    };
    final hasBox = box || stableStyle == 'boxed';

    final baseStyle = await _loadFontStyle(
      fontFamily: fontFamily,
      fontSize: effectiveFontSize,
      style: stableStyle,
    );

    final effectiveFill = switch (stableStyle) {
      'neon' => const Color(0xFF8BFFF2),
      'cinematic' => const Color(0xFFFFE3B0),
      'bold_center' => const Color(0xFFFFE082),
      _ => fill,
    };

    final backColor = stableStyle == 'neon'
        ? const Color(0xFF5B27FF)
        : stroke;
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
    if (stableStyle == 'neon') {
      shadows = [
        Shadow(
          color: const Color(0xFF00D9FF),
          blurRadius: effectiveFontSize * 0.25,
        ),
        Shadow(
          color: const Color(0xFF8B5CF6),
          blurRadius: effectiveFontSize * 0.40,
        ),
      ];
    } else if (stableStyle == 'cinematic') {
      shadows = [
        Shadow(
          color: Colors.black.withOpacity(0.92),
          blurRadius: effectiveFontSize * 0.18,
          offset: Offset(effectiveFontSize * 0.03, effectiveFontSize * 0.05),
        ),
      ];
    } else {
      shadows = [
        Shadow(
          color: Colors.black.withOpacity(0.80),
          blurRadius: effectiveFontSize * 0.16,
          offset: Offset(effectiveFontSize * 0.025, effectiveFontSize * 0.04),
        ),
      ];
    }

    final TextStyle frontStyle = stableStyle == 'outline'
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
      final boxColor = stableStyle == 'cinematic'
          ? const Color(0xB3221A10)
          : stableStyle == 'neon'
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

    if (stableStyle != 'outline') {
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
