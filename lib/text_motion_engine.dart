/// Phrase-level kinetic text animation for FFmpeg-rendered PNG overlays.
///
/// Each caption is already a separate transparent image on the timeline.
/// This engine animates that image on its own local clock, so captions can
/// have independent entrances without adding extra video tracks or inputs.
enum TextMotionMood { calm, cinematic, dynamic }

enum TextMotionPreset {
  softSettle,
  cinematicDrift,
  cinematicTilt,
  pop,
  bounce,
  impact,
}

class TextMotionEngine {
  TextMotionEngine._();

  static TextMotionPreset presetFor({
    required TextMotionMood mood,
    required int seed,
    String text = '',
  }) {
    final emphasis = _isEmphasisPhrase(text);

    if (emphasis) {
      switch (mood) {
        case TextMotionMood.calm:
          return TextMotionPreset.softSettle;
        case TextMotionMood.cinematic:
          return TextMotionPreset.cinematicTilt;
        case TextMotionMood.dynamic:
          return TextMotionPreset.impact;
      }
    }

    switch (mood) {
      case TextMotionMood.calm:
        return TextMotionPreset.softSettle;
      case TextMotionMood.cinematic:
        return seed.abs().isEven
            ? TextMotionPreset.cinematicDrift
            : TextMotionPreset.cinematicTilt;
      case TextMotionMood.dynamic:
        const presets = [
          TextMotionPreset.pop,
          TextMotionPreset.bounce,
          TextMotionPreset.impact,
        ];
        return presets[seed.abs() % presets.length];
    }
  }

  static bool _isEmphasisPhrase(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) return false;

    const emphasisWords = {
      'مهم',
      'انتبه',
      'الحقيقة',
      'السر',
      'السبب',
      'خطر',
      'تذكر',
      'الحل',
      'اكتشف',
      'ابدا',
      'لا',
      'important',
      'warning',
      'truth',
      'secret',
      'reason',
      'remember',
      'never',
      'stop',
      'why',
      'watch',
    };

    return normalized
        .split(' ')
        .any((word) => emphasisWords.contains(word));
  }

  static String _n(double value) => value.toStringAsFixed(3);

  /// Builds local-time scale/rotation filters for one caption or title image.
  ///
  /// The image starts at t=0 because the caller applies setpts after this
  /// filter. Output dimensions remain even for H.264 compatibility.
  static String buildFilter({
    required double duration,
    required TextMotionMood mood,
    required int seed,
    String text = '',
  }) {
    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Duration must be positive and finite.',
      );
    }

    final safeDuration = duration.clamp(0.12, 600.0).toDouble();
    final preset = presetFor(mood: mood, seed: seed, text: text);

    late final String scale;
    late final String? angle;

    switch (preset) {
      case TextMotionPreset.softSettle:
        scale = '1-0.035*(1-min(1,max(0,t/0.28)))';
        angle = null;
        break;

      case TextMotionPreset.cinematicDrift:
        scale = '1+0.055*(1-min(1,max(0,t/0.38)))';
        angle = '0.010*(1-min(1,max(0,t/0.38)))';
        break;

      case TextMotionPreset.cinematicTilt:
        scale = '1+0.075*(1-min(1,max(0,t/0.32)))';
        angle = '-0.018*(1-min(1,max(0,t/0.32)))';
        break;

      case TextMotionPreset.pop:
        // A damped spring starts compact, overshoots slightly, then settles.
        scale = '1-0.18*exp(-12*t)*cos(24*t)';
        angle = '0.028*exp(-13*t)';
        break;

      case TextMotionPreset.bounce:
        scale = '1-0.09*exp(-8*t)*cos(27*t)';
        angle = '-0.020*exp(-10*t)';
        break;

      case TextMotionPreset.impact:
        scale = '1-0.24*exp(-18*t)*cos(22*t)';
        angle = '0.040*exp(-16*t)';
        break;
    }

    final filters = <String>[];

    // A fixed 6% transparent overscan prevents the small initial tilt from
    // clipping the glyphs. The later scale animation stays centred by overlay.
    if (angle != null) {
      filters.add(
        "rotate=a='$angle':ow='ceil(iw*1.06)':"
        "oh='ceil(ih*1.06)':c=none",
      );
    }

    filters.add(
      "scale=w='max(2,trunc(iw*($scale)/2)*2)':"
      "h='max(2,trunc(ih*($scale)/2)*2)':eval=frame",
    );

    // Keep the duration read/validated here; the input stream itself is
    // bounded by the caller's -t argument.
    assert(safeDuration >= 0.12);
    return filters.join(',');
  }
}
