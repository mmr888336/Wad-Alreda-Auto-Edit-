import 'dart:io';

/// Generates short, non-musical sound effects using FFmpeg noise.
/// No songs, melodies or music tracks are included.
class SoundEffectGenerator {
  static const Map<String, List<num>> _presets = {
    // duration, high-pass Hz, low-pass Hz, gain, fade-in, fade-out
    'whoosh_soft': [0.62, 220, 4200, 0.38, 0.08, 0.30],
    'whoosh_fast': [0.28, 480, 6800, 0.50, 0.01, 0.17],
    'whoosh_low': [0.58, 70, 900, 0.55, 0.03, 0.30],
    'swipe': [0.22, 700, 7000, 0.42, 0.01, 0.12],
    'air_rush': [0.75, 130, 5000, 0.36, 0.22, 0.28],
    'impact_soft': [0.20, 180, 2400, 0.45, 0.005, 0.15],
    'impact_deep': [0.26, 45, 650, 0.68, 0.003, 0.19],
    'click': [0.055, 1800, 9000, 0.50, 0.001, 0.040],
    'tap': [0.075, 900, 6000, 0.38, 0.001, 0.050],
    'pop': [0.12, 650, 5200, 0.45, 0.001, 0.080],
    'tick': [0.035, 2600, 10000, 0.45, 0.001, 0.025],
    'double_tick': [0.10, 2300, 10000, 0.45, 0.001, 0.070],
    'digital_blip': [0.085, 1500, 8500, 0.25, 0.002, 0.060],
    'camera_shutter': [0.14, 800, 8000, 0.38, 0.001, 0.10],
    'paper_swipe': [0.32, 700, 6200, 0.28, 0.025, 0.16],
    'page_flip': [0.40, 450, 6000, 0.30, 0.02, 0.20],
    'transition_hit': [0.18, 90, 1800, 0.66, 0.001, 0.14],
    'flash_hit': [0.09, 1400, 9000, 0.48, 0.001, 0.06],
    'zoom_hit': [0.24, 100, 4800, 0.52, 0.02, 0.14],
    'cut_hit': [0.10, 180, 3000, 0.52, 0.001, 0.08],
    'bubble_pop': [0.11, 900, 7000, 0.34, 0.001, 0.08],
    'riser_short': [0.65, 180, 8000, 0.30, 0.40, 0.15],
    'fall_short': [0.42, 120, 5000, 0.32, 0.02, 0.32],
    'soft_thump': [0.16, 55, 500, 0.50, 0.001, 0.13],
    'dry_snap': [0.06, 900, 8000, 0.48, 0.001, 0.045],
    'cloth_swipe': [0.34, 450, 5000, 0.25, 0.05, 0.18],
    'low_thud': [0.22, 40, 400, 0.58, 0.001, 0.16],
    'high_tick': [0.04, 3000, 11000, 0.40, 0.001, 0.028],
    'short_rush': [0.31, 240, 6200, 0.38, 0.015, 0.16],
    'low_sweep': [0.52, 55, 1300, 0.48, 0.12, 0.28],
  };

  static Future<bool> render({
    required String style,
    required String outputPath,
    required Future<bool> Function(String command) execute,
  }) async {
    if (style == 'none') return false;

    final p = _presets[style] ?? _presets['whoosh_soft']!;

    final duration = p[0].toDouble();
    final highPass = p[1].toInt();
    final lowPass = p[2].toInt();
    final gain = p[3].toDouble();

    final fadeIn =
        p[4].toDouble().clamp(0.001, duration / 2);

    final fadeOut =
        p[5].toDouble().clamp(0.02, duration / 2);

    final fadeOutStart =
        (duration - fadeOut).clamp(0.0, duration - 0.01);

    final filters = [
      'highpass=f=$highPass',
      'lowpass=f=$lowPass',
      'volume=${gain.toStringAsFixed(3)}',
      'afade=t=in:st=0:d=${fadeIn.toStringAsFixed(3)}',
      'afade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=${fadeOut.toStringAsFixed(3)}',
      'alimiter=limit=0.85',
    ].join(',');

    final command =
        '-y -f lavfi -i "anoisesrc=d=${duration.toStringAsFixed(3)}:c=pink:a=0.85" '
        '-af "$filters" '
        '-ar 44100 -ac 1 -c:a pcm_s16le "${_safePath(outputPath)}"';

    final ok = await execute(command);

    return ok && await File(outputPath).exists();
  }

  static String _safePath(String path) {
    return path.replaceAll('"', '\\"');
  }
}