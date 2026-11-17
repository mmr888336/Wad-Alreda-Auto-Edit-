import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'caption_style_engine.dart';
import 'text_render.dart';
import 'typography_engine.dart';

/// Renders a [TypographyPlan] as a transparent film-strip PNG.
///
/// Frame k of the strip shows the words 0..k at their final positions (the
/// layout never jumps), with word k drawn in the highlight color. Giant words
/// keep the accent color. The strip is consumed exactly like the existing
/// word strips: crop the frame of the active word with
/// WordCaptionPlanner.cropFilter(frameHeight: ..., cues: plan.cues).
class TypographyRender {
  TypographyRender._();

  static Future<WordStrip> pngTypographyStrip({
    required TypographyPlan plan,
    required String outPath,
    required int width,
    required double fontSize,
    String style = 'classic',
    String fontFamily = 'Noto Sans Arabic',
    Color fill = Colors.white,
    Color stroke = Colors.black,
    bool giantUsesAccent = true,
  }) async {
    final stableStyle = CaptionStyleEngine.normalize(style);
    final direction = plan.rtl ? TextDirection.rtl : TextDirection.ltr;
    final maxW = width * 0.92;
    final left = (width - maxW) / 2;
    final pad = fontSize * 0.35;
    final gap = fontSize * 0.28;

    await TextRender.prepareFont(
      fontFamily: fontFamily,
      fontSize: fontSize,
      style: stableStyle,
    );

    var base = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: stableStyle == 'classic' ? FontWeight.w800 : FontWeight.w900,
      height: plan.lineHeight,
      letterSpacing: plan.letterSpacingEm * fontSize,
    );
    try {
      base = GoogleFonts.getFont(fontFamily, textStyle: base);
    } catch (_) {
      // Same fallback for every phrase of the export.
    }

    final fillColor = switch (stableStyle) {
      'neon' => const Color(0xFF8BFFF2),
      'cinematic' => const Color(0xFFFFE3B0),
      'bold_center' => const Color(0xFFFFE082),
      _ => fill,
    };
    final backColor =
        stableStyle == 'neon' ? const Color(0xFF5B27FF) : stroke;
    final accent = TextRender.highlightFor(stableStyle);
    final strokeWidth = switch (stableStyle) {
      'bold_center' => fontSize * 0.25,
      'outline' => fontSize * 0.09,
      _ => fontSize * 0.16,
    };

    final List<Shadow> shadows = stableStyle == 'neon'
        ? <Shadow>[
            Shadow(
              color: const Color(0xFF00D9FF),
              blurRadius: fontSize * 0.25,
            ),
            Shadow(
              color: const Color(0xFF8B5CF6),
              blurRadius: fontSize * 0.40,
            ),
          ]
        : <Shadow>[
            Shadow(
              color: Colors.black.withOpacity(0.80),
              blurRadius: fontSize * 0.16,
              offset: Offset(fontSize * 0.025, fontSize * 0.04),
            ),
          ];

    TextPainter painter(String text, double size, TextStyle style) {
      return TextPainter(
        text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
        textDirection: direction,
        maxLines: 1,
      )..layout();
    }

    // Pass 1: shrink a line that is wider than the screen.
    final fits = <double>[];
    for (final line in plan.lines) {
      var total = gap * (line.length - 1);
      for (final index in line) {
        final word = plan.words[index];
        total += painter(word.text, fontSize * word.scale, base).width;
      }
      fits.add(total > maxW ? maxW / total : 1.0);
    }

    // Pass 2: measure every word at its final size.
    final strokeStyle = base.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = backColor,
    );

    final wordSize = List<double>.filled(plan.words.length, fontSize);
    final backPainters = List<TextPainter?>.filled(plan.words.length, null);
    final measure = List<TextPainter?>.filled(plan.words.length, null);
    for (var l = 0; l < plan.lines.length; l++) {
      for (final index in plan.lines[l]) {
        final word = plan.words[index];
        final size = fontSize * word.scale * fits[l];
        wordSize[index] = size;
        measure[index] = painter(word.text, size, base);
        backPainters[index] = painter(word.text, size, strokeStyle);
      }
    }

    // Line geometry (baseline aligned, centred, reading order respects RTL).
    final lineTops = <double>[];
    final lineBaselines = <double>[];
    final lineWidths = <double>[];
    var cursorY = 0.0;
    for (final line in plan.lines) {
      var ascent = 0.0;
      var descent = 0.0;
      var width = gap * (line.length - 1);
      for (final index in line) {
        final p = measure[index]!;
        final baseline = p.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        ascent = ascent < baseline ? baseline : ascent;
        final below = p.height - baseline;
        descent = descent < below ? below : descent;
        width += p.width;
      }
      lineTops.add(cursorY);
      lineBaselines.add(ascent);
      lineWidths.add(width);
      cursorY += ascent + descent;
    }

    final frameHeight = (cursorY + pad * 2).ceil();
    final frames = plan.words.length;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final hasBox = stableStyle == 'boxed';

    for (var frame = 0; frame < frames; frame++) {
      final frameTop = (frame * frameHeight).toDouble();

      if (hasBox) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, frameTop, maxW, frameHeight.toDouble()),
            Radius.circular(fontSize * 0.4),
          ),
          Paint()..color = const Color(0xB3000000),
        );
      }

      for (var l = 0; l < plan.lines.length; l++) {
        final line = plan.lines[l];
        var x = left + (maxW - lineWidths[l]) / 2;
        // In RTL the first word of the line is the right-most one.
        final order = plan.rtl ? line.reversed.toList() : line;

        for (final index in order) {
          final word = plan.words[index];
          final p = measure[index]!;
          final baseline = p.computeDistanceToActualBaseline(
            TextBaseline.alphabetic,
          );
          final y = frameTop +
              pad +
              lineTops[l] +
              (lineBaselines[l] - baseline);
          final offset = Offset(x, y);

          if (index <= frame) {
            final active = index == frame;
            final accentWord = active || (giantUsesAccent && word.giant);

            if (stableStyle != 'outline') {
              backPainters[index]!.paint(canvas, offset);
            }

            final color = accentWord ? accent : fillColor;
            final TextStyle front = stableStyle == 'outline'
                ? base.copyWith(
                    fontSize: wordSize[index],
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = fontSize * 0.09
                      ..strokeJoin = StrokeJoin.round
                      ..color = color,
                  )
                : base.copyWith(
                    fontSize: wordSize[index],
                    color: color,
                    shadows: shadows,
                  );
            TextPainter(
              text: TextSpan(text: word.text, style: front),
              textDirection: direction,
              maxLines: 1,
            )
              ..layout()
              ..paint(canvas, offset);
          }
          x += p.width + gap;
        }
      }
    }

    final image = await recorder.endRecording().toImage(
          width,
          frameHeight * frames,
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw Exception('Could not render typography image.');
    }

    await File(outPath).writeAsBytes(data.buffer.asUint8List());
    return WordStrip(
      path: outPath,
      frameHeight: frameHeight,
      wordCount: frames,
    );
  }
}
