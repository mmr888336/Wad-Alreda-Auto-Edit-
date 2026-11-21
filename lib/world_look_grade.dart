/// Light and atmosphere of the world, from [WorldLook].
///
/// The native Filament viewer owns its lights, so the look is applied where it
/// is safe and testable, without touching the native code:
///  * a colour grade on the captured world clip (the tint of the scene pulls
///    the picture a little towards it, stronger with the intensity of the
///    mood), and a vignette whose centre is pushed away from the key light,
///    so the side the light comes from stays brighter. The vignette is
///    stronger with the vignette and shadow share of the look;
///  * the atmosphere particles of the look (dust, sparks, pollen) as a 2.5D
///    overlay layer on top of the world (see [WorldFlatRenderer]).
///
/// Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'cinematic_world.dart' show WorldLook;

class WorldLookGrade {
  WorldLookGrade._();

  /// Master switch. When false the world clip and its overlay are not graded
  /// and get no particles.
  static bool enabled = true;

  /// Below this particle density of the look no particle layer is added.
  static const double minParticleDensity = 0.1;

  static String _f(double value) => value.toStringAsFixed(3);

  /// `[r, g, b]` (0..1) of `#RRGGBB`, or null for any other text.
  static List<double>? _rgb(String hex) {
    if (hex.length != 7 || !hex.startsWith('#')) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) return null;
    return <double>[
      ((value >> 16) & 0xFF) / 255,
      ((value >> 8) & 0xFF) / 255,
      (value & 0xFF) / 255,
    ];
  }

  /// How far the picture is pulled towards the tint (0..0.5).
  static double tintStrength(WorldLook look) {
    final intensity = look.intensity.isFinite ? look.intensity : 0.0;
    return (0.35 * intensity).clamp(0.0, 0.5).toDouble();
  }

  /// Angle (radians) of the FFmpeg vignette: smaller = stronger.
  static double vignetteAngle(WorldLook look) {
    final share = look.vignette.isFinite ? look.vignette : 0.0;
    final shadow = look.shadowOpacity.isFinite ? look.shadowOpacity : 0.0;
    final strength = (share + shadow * 0.3).clamp(0.0, 1.0).toDouble();
    return (0.9 - 0.9 * strength).clamp(0.3, 0.9).toDouble();
  }

  /// The overlay kind (a MotionOverlayKind name) for the particles of the
  /// look, or null when the look has none.
  static String? particleKind(WorldLook look) {
    if (!look.particleDensity.isFinite ||
        look.particleDensity < minParticleDensity) {
      return null;
    }

    switch (look.particleKind) {
      case 'dust':
        return 'dust';
      case 'sparks':
        return 'embers';
      case 'pollen':
        return 'sparkles';
      default:
        return null;
    }
  }

  /// The filter chain (no input or output labels) that grades one world clip,
  /// or null when the tint of the look is not a valid colour.
  static String? filters(WorldLook look) {
    final rgb = _rgb(look.tint);
    if (rgb == null) return null;

    final strength = tintStrength(look);
    double factor(double channel) => 1 + strength * (channel - 0.5);

    // The key light comes from the upper left at 0 degrees and swings down
    // with the angle; the vignette centre moves towards it.
    final radians = look.keyAngleDegrees * math.pi / 180;
    final centreX = 0.5 - 0.1 * math.cos(radians);
    final centreY = 0.5 - 0.1 * math.sin(radians);

    return 'format=gbrp,'
        'colorchannelmixer=rr=${_f(factor(rgb[0]))}:'
        'gg=${_f(factor(rgb[1]))}:'
        'bb=${_f(factor(rgb[2]))},'
        'format=yuv420p,'
        'vignette=angle=${_f(vignetteAngle(look))}:'
        'x0=w*${_f(centreX)}:y0=h*${_f(centreY)}';
  }
}
