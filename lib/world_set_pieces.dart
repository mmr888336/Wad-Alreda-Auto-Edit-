/// Art for the fixed set pieces of the story world.
///
/// [CinematicWorld] gives every environment three set pieces (the office has
/// a desk, a window and a wall clock; the library two bookshelves and a
/// ladder; ...). They are full-canvas layers: each piece is drawn at its own
/// place of a transparent image that has the size of the canvas, so the
/// layer sits at the centre with scale 1 and every piece of an environment
/// stays exactly where it was the last time that environment came back.
///
/// The pieces are drawn with code (no downloads, no licences, no network).
/// They keep the middle of the picture free (the character and the speaker's
/// face live there) and use the palette of the world: red, amber, teal, dark
/// and cream. Pure drawing, no I/O.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

class WorldSetPieces {
  WorldSetPieces._();

  /// Prefix of the library-style id of a set piece (`set:desk`).
  static const String prefix = 'set:';

  /// Every set piece that has art.
  static const List<String> names = <String>[
    'desk',
    'window',
    'wall_clock',
    'wall_shelf',
    'rug',
    'lamp_floor',
    'bookshelf_left',
    'bookshelf_right',
    'ladder',
    'building_row',
    'street_lamp',
    'kerb',
    'monitor_wall',
    'light_panel',
    'cable_tray',
    'hills',
    'sun',
    'path',
  ];

  static bool has(String name) => names.contains(name);

  /// The asset id of the set piece [name].
  static String idOf(String name) => '$prefix$name';

  /// The set piece named by [id], or null when [id] is not a set piece id.
  static String? nameOf(String id) =>
      id.startsWith(prefix) ? id.substring(prefix.length) : null;

  /// Draws the set piece [name] on a transparent [width] x [height] image
  /// and returns it as PNG bytes. Throws [ArgumentError] for an unknown name
  /// or an invalid size.
  static Future<Uint8List> renderPng(
    String name, {
    required int width,
    required int height,
  }) async {
    if (!has(name)) throw ArgumentError.value(name, 'name');
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid size: ${width}x$height');
    }
    final w = width.toDouble();
    final h = height.toDouble();
    final s = math.min(w, h);
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);

    const wood = ui.Color(0xFF8A5A33);
    const woodDark = ui.Color(0xFF4F3320);
    const steel = ui.Color(0xFF5B6472);
    const steelDark = ui.Color(0xFF2C323C);
    const ink = ui.Color(0xFF14141A);
    const amber = ui.Color(0xFFF5A524);
    const teal = ui.Color(0xFF1B998B);
    const red = ui.Color(0xFFD7263D);
    const cream = ui.Color(0xFFF4EFE6);
    const spines = <ui.Color>[red, amber, teal, cream];

    // Positions are normalised (0..1) on the canvas; sizes that must stay
    // round or keep a stroke width use the short side.
    ui.Offset o(double x, double y) => ui.Offset(x * w, y * h);
    ui.Offset polar(double cx, double cy, double r, double a) =>
        ui.Offset(cx * w + math.cos(a) * r * s, cy * h + math.sin(a) * r * s);
    ui.Rect rc(double x, double y, double bw, double bh) =>
        ui.Rect.fromLTWH(x * w, y * h, bw * w, bh * h);
    ui.Paint fillP(ui.Color k) => ui.Paint()..color = k;
    ui.Paint strokeP(ui.Color k, double wd) => ui.Paint()
      ..color = k
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = wd * s
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;
    void box(
      double x,
      double y,
      double bw,
      double bh,
      ui.Color k, {
      double r = 0,
    }) {
      c.drawRRect(
        ui.RRect.fromRectAndRadius(rc(x, y, bw, bh), ui.Radius.circular(r * s)),
        fillP(k),
      );
    }

    void line(double x1, double y1, double x2, double y2, ui.Color k, double wd) {
      c.drawLine(o(x1, y1), o(x2, y2), strokeP(k, wd));
    }

    void glow(double x, double y, double r, ui.Color k, double a) {
      c.drawCircle(
        o(x, y),
        r * s,
        ui.Paint()
          ..shader = ui.Gradient.radial(
            o(x, y),
            r * s,
            <ui.Color>[k.withOpacity(a), k.withOpacity(0)],
          ),
      );
    }

    ui.Path poly(List<double> p) {
      final path = ui.Path()..moveTo(p[0] * w, p[1] * h);
      for (var i = 2; i + 1 < p.length; i += 2) {
        path.lineTo(p[i] * w, p[i + 1] * h);
      }
      return path..close();
    }

    void vGradient(ui.Rect r, ui.Color top, ui.Color bottom) {
      c.drawRect(
        r,
        ui.Paint()
          ..shader = ui.Gradient.linear(
            r.topCenter,
            r.bottomCenter,
            <ui.Color>[top, bottom],
          ),
      );
    }

    void bookshelf(double x) {
      box(x, 0.12, 0.20, 0.76, woodDark, r: 0.005);
      for (var i = 0; i < 5; i++) {
        final y = 0.16 + i * 0.14;
        box(x + 0.012, y, 0.176, 0.12, const ui.Color(0xFF1A130E));
        var bx = x + 0.016;
        for (var j = 0; j < 7; j++) {
          final bw = 0.018 + 0.004 * ((i + j) % 3);
          final bh = 0.07 + 0.012 * ((i * 3 + j) % 4);
          if (bx + bw > x + 0.185) break;
          box(bx, y + 0.12 - bh, bw, bh, spines[(i + j * 2) % spines.length],
              r: 0.002);
          bx += bw + 0.003;
        }
        box(x + 0.008, y + 0.12, 0.184, 0.012, wood);
      }
    }

    switch (name) {
      case 'desk':
        {
          box(0.03, 0.795, 0.94, 0.035, wood, r: 0.004);
          box(0.03, 0.795, 0.94, 0.008, const ui.Color(0x33FFFFFF));
          box(0.06, 0.83, 0.88, 0.12, woodDark, r: 0.003);
          for (var i = 0; i < 3; i++) {
            box(0.10 + i * 0.28, 0.85, 0.24, 0.08, wood, r: 0.003);
            box(0.205 + i * 0.28, 0.885, 0.03, 0.008, amber, r: 0.002);
          }
          box(0.07, 0.95, 0.03, 0.05, woodDark);
          box(0.90, 0.95, 0.03, 0.05, woodDark);
        }
      case 'window':
        {
          box(0.715, 0.095, 0.23, 0.31, steelDark, r: 0.004);
          vGradient(
            rc(0.72, 0.10, 0.22, 0.30),
            const ui.Color(0xFF6FC3D6),
            const ui.Color(0xFF1F5E73),
          );
          glow(0.80, 0.16, 0.10, cream, 0.25);
          line(0.83, 0.10, 0.83, 0.40, steelDark, 0.006);
          line(0.72, 0.25, 0.94, 0.25, steelDark, 0.006);
          box(0.70, 0.40, 0.26, 0.016, steel, r: 0.003);
        }
      case 'wall_clock':
        {
          const cx = 0.14;
          const cy = 0.17;
          c.drawCircle(o(cx, cy), 0.062 * s, fillP(steelDark));
          c.drawCircle(o(cx, cy), 0.052 * s, fillP(cream));
          for (var i = 0; i < 12; i++) {
            final a = i * math.pi / 6;
            c.drawLine(
              polar(cx, cy, 0.043, a),
              polar(cx, cy, 0.049, a),
              strokeP(ink, 0.004),
            );
          }
          const hourAngle = (10 + 10 / 60) / 12 * 2 * math.pi - math.pi / 2;
          const minuteAngle = 10 / 60 * 2 * math.pi - math.pi / 2;
          c.drawLine(o(cx, cy), polar(cx, cy, 0.026, hourAngle), strokeP(ink, 0.008));
          c.drawLine(
            o(cx, cy),
            polar(cx, cy, 0.040, minuteAngle),
            strokeP(ink, 0.005),
          );
          c.drawCircle(o(cx, cy), 0.006 * s, fillP(red));
        }
      case 'wall_shelf':
        {
          box(0.05, 0.30, 0.26, 0.014, wood, r: 0.002);
          box(0.08, 0.314, 0.012, 0.03, steel);
          box(0.27, 0.314, 0.012, 0.03, steel);
          for (var i = 0; i < 6; i++) {
            final bh = 0.045 + 0.012 * (i % 3);
            box(0.07 + i * 0.033, 0.30 - bh, 0.026, bh, spines[i % spines.length],
                r: 0.002);
          }
        }
      case 'rug':
        {
          final r = rc(0.08, 0.84, 0.84, 0.11);
          c.drawOval(
            r,
            ui.Paint()
              ..shader = ui.Gradient.linear(
                r.centerLeft,
                r.centerRight,
                <ui.Color>[
                  red.withOpacity(0.85),
                  amber.withOpacity(0.85),
                  red.withOpacity(0.85),
                ],
                <double>[0, 0.5, 1],
              ),
          );
          c.drawOval(
            rc(0.14, 0.862, 0.72, 0.066),
            strokeP(cream.withOpacity(0.55), 0.005),
          );
          c.drawOval(
            rc(0.24, 0.878, 0.52, 0.034),
            strokeP(cream.withOpacity(0.35), 0.004),
          );
        }
      case 'lamp_floor':
        {
          glow(0.90, 0.34, 0.22, amber, 0.22);
          box(0.895, 0.40, 0.01, 0.50, steel);
          box(0.86, 0.89, 0.08, 0.016, steelDark, r: 0.004);
          c.drawPath(
            poly(<double>[0.85, 0.40, 0.95, 0.40, 0.92, 0.30, 0.88, 0.30]),
            fillP(const ui.Color(0xFFE8B04A)),
          );
        }
      case 'bookshelf_left':
        bookshelf(0.02);
      case 'bookshelf_right':
        bookshelf(0.78);
      case 'ladder':
        {
          line(0.215, 0.86, 0.255, 0.36, wood, 0.012);
          line(0.255, 0.86, 0.295, 0.36, wood, 0.012);
          for (var i = 0; i <= 7; i++) {
            final t = i / 7;
            line(0.215 + 0.04 * t, 0.86 - 0.5 * t, 0.255 + 0.04 * t, 0.86 - 0.5 * t,
                woodDark, 0.008);
          }
        }
      case 'building_row':
        {
          const heights = <double>[0.28, 0.36, 0.22, 0.40, 0.30, 0.26, 0.38, 0.24];
          for (var i = 0; i < heights.length; i++) {
            final bx = i * 0.125;
            final bh = heights[i];
            final top = 0.80 - bh;
            box(
              bx + 0.004,
              top,
              0.117,
              bh,
              i.isEven ? const ui.Color(0xFF2A3A4A) : const ui.Color(0xFF23313F),
            );
            final rows = (bh / 0.05).floor() - 1;
            for (var row = 0; row < rows; row++) {
              for (var col = 0; col < 3; col++) {
                final lit = (i + row + col) % 3 != 0;
                box(
                  bx + 0.016 + col * 0.034,
                  top + 0.025 + row * 0.05,
                  0.02,
                  0.028,
                  lit ? amber.withOpacity(0.75) : const ui.Color(0x33FFFFFF),
                );
              }
            }
          }
        }
      case 'street_lamp':
        {
          glow(0.175, 0.30, 0.16, amber, 0.28);
          box(0.098, 0.30, 0.008, 0.54, steel);
          line(0.102, 0.30, 0.16, 0.285, steel, 0.008);
          box(0.15, 0.28, 0.05, 0.014, steelDark, r: 0.004);
          box(0.155, 0.294, 0.04, 0.008, cream.withOpacity(0.9), r: 0.003);
          box(0.085, 0.83, 0.034, 0.016, steelDark, r: 0.004);
        }
      case 'kerb':
        {
          box(0.0, 0.84, 1.0, 0.16, const ui.Color(0xFF20262E));
          box(0.0, 0.84, 1.0, 0.012, const ui.Color(0xFF8B94A0));
          for (var i = 0; i < 6; i++) {
            box(0.05 + i * 0.17, 0.92, 0.09, 0.012, cream.withOpacity(0.6));
          }
        }
      case 'monitor_wall':
        {
          void monitor(double x, double y, double mw, double mh) {
            box(x - 0.006, y - 0.006, mw + 0.012, mh + 0.012, ink, r: 0.004);
            vGradient(
              rc(x, y, mw, mh),
              teal.withOpacity(0.9),
              const ui.Color(0xFF0E4A55),
            );
            for (var i = 0; i < 3; i++) {
              final ly = y + mh * (0.30 + 0.22 * i);
              line(x + 0.012, ly, x + mw * (0.45 + 0.15 * ((i + 1) % 3)), ly,
                  cream.withOpacity(0.55), 0.004);
            }
            glow(x + mw / 2, y + mh / 2, 0.12, teal, 0.18);
          }

          monitor(0.04, 0.10, 0.12, 0.10);
          monitor(0.17, 0.10, 0.12, 0.10);
          monitor(0.04, 0.22, 0.25, 0.11);
          monitor(0.71, 0.10, 0.12, 0.10);
          monitor(0.84, 0.10, 0.12, 0.10);
          monitor(0.71, 0.22, 0.25, 0.11);
        }
      case 'light_panel':
        {
          c.drawPath(
            poly(<double>[0.30, 0.047, 0.70, 0.047, 0.88, 0.40, 0.12, 0.40]),
            ui.Paint()
              ..shader = ui.Gradient.linear(
                o(0.5, 0.05),
                o(0.5, 0.40),
                <ui.Color>[cream.withOpacity(0.16), cream.withOpacity(0)],
              ),
          );
          box(0.30, 0.025, 0.40, 0.022, cream, r: 0.004);
          box(0.30, 0.047, 0.40, 0.006, steel);
        }
      case 'cable_tray':
        {
          box(0.0, 0.90, 1.0, 0.05, steelDark);
          box(0.0, 0.90, 1.0, 0.006, steel);
          const cableColors = <ui.Color>[red, teal, amber];
          for (var i = 0; i < 3; i++) {
            final y = 0.915 + i * 0.012;
            final cable = ui.Path()
              ..moveTo(0, y * h)
              ..cubicTo(0.3 * w, (y - 0.02) * h, 0.6 * w, (y + 0.02) * h, w, y * h);
            c.drawPath(cable, strokeP(cableColors[i], 0.005));
          }
        }
      case 'hills':
        {
          final far = ui.Path()
            ..moveTo(0, 0.72 * h)
            ..cubicTo(0.25 * w, 0.58 * h, 0.45 * w, 0.68 * h, 0.65 * w, 0.62 * h)
            ..cubicTo(0.82 * w, 0.57 * h, 0.92 * w, 0.66 * h, w, 0.64 * h)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close();
          c.drawPath(far, fillP(const ui.Color(0xFF1D5A56)));
          final near = ui.Path()
            ..moveTo(0, 0.80 * h)
            ..cubicTo(0.2 * w, 0.72 * h, 0.4 * w, 0.84 * h, 0.6 * w, 0.78 * h)
            ..cubicTo(0.8 * w, 0.72 * h, 0.92 * w, 0.82 * h, w, 0.78 * h)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close();
          c.drawPath(near, fillP(const ui.Color(0xFF14403D)));
        }
      case 'sun':
        {
          glow(0.80, 0.20, 0.20, amber, 0.35);
          c.drawCircle(o(0.80, 0.20), 0.075 * s, fillP(amber));
          c.drawCircle(
            polar(0.80, 0.20, 0.025, -math.pi * 0.75),
            0.02 * s,
            fillP(cream.withOpacity(0.5)),
          );
        }
      case 'path':
        {
          c.drawPath(
            poly(<double>[0.47, 0.64, 0.53, 0.64, 0.74, 1.0, 0.26, 1.0]),
            ui.Paint()
              ..shader = ui.Gradient.linear(
                o(0.5, 0.64),
                o(0.5, 1.0),
                <ui.Color>[
                  const ui.Color(0xFF7A5A3A).withOpacity(0.6),
                  const ui.Color(0xFFC89A5E),
                ],
              ),
          );
          line(0.47, 0.64, 0.26, 1.0, cream.withOpacity(0.35), 0.004);
          line(0.53, 0.64, 0.74, 1.0, cream.withOpacity(0.35), 0.004);
        }
      default:
        break;
    }

    final picture = rec.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('PNG encoding failed');
    return data.buffer.asUint8List();
  }
}
