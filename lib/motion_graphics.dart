import 'editing_engine.dart';

enum MotionMood { calm, cinematic, dynamic }

/// Topic-aware motion design timings and FFmpeg expressions.
class MotionGraphicsPlan {
  final MotionMood mood;
  final String label;
  final double captionEnterSeconds;
  final double captionFadeOutSeconds;
  final double hookEnterSeconds;
  final double hookDurationSeconds;
  final double brollFadeSeconds;
  final double captionTravel;

  const MotionGraphicsPlan({
    required this.mood,
    required this.label,
    required this.captionEnterSeconds,
    required this.captionFadeOutSeconds,
    required this.hookEnterSeconds,
    required this.hookDurationSeconds,
    required this.brollFadeSeconds,
    required this.captionTravel,
  });

  factory MotionGraphicsPlan.forProfile(EditingProfile profile) {
    switch (profile.topic) {
      case EditTopic.religious:
      case EditTopic.educational:
        return const MotionGraphicsPlan(
          mood: MotionMood.calm,
          label: 'هادئ',
          captionEnterSeconds: 0.34,
          captionFadeOutSeconds: 0.22,
          hookEnterSeconds: 0.42,
          hookDurationSeconds: 3.2,
          brollFadeSeconds: 0.42,
          captionTravel: 0.34,
        );

      case EditTopic.product:
      case EditTopic.travel:
        return const MotionGraphicsPlan(
          mood: MotionMood.dynamic,
          label: 'حيوي',
          captionEnterSeconds: 0.22,
          captionFadeOutSeconds: 0.16,
          hookEnterSeconds: 0.30,
          hookDurationSeconds: 3.2,
          brollFadeSeconds: 0.28,
          captionTravel: 0.72,
        );

      case EditTopic.storytelling:
      case EditTopic.general:
        return const MotionGraphicsPlan(
          mood: MotionMood.cinematic,
          label: 'سينمائي',
          captionEnterSeconds: 0.30,
          captionFadeOutSeconds: 0.20,
          hookEnterSeconds: 0.38,
          hookDurationSeconds: 3.2,
          brollFadeSeconds: 0.36,
          captionTravel: 0.48,
        );
    }
  }

  static String _n(double value) => value.toStringAsFixed(3);

  String _easeOut(double start, double duration) =>
      'pow(max(0,1-(t-${_n(start)})/${_n(duration)}),3)';

  String overlayInputFilter({
    required double duration,
    required double timelineStart,
    double? fadeInSeconds,
    double? fadeOutSeconds,
  }) {
    final safeDuration = duration.clamp(0.12, 600.0).toDouble();

    final fadeIn = (fadeInSeconds ?? captionEnterSeconds)
        .clamp(0.06, safeDuration / 2)
        .toDouble();

    final fadeOut = (fadeOutSeconds ?? captionFadeOutSeconds)
        .clamp(0.06, safeDuration / 2)
        .toDouble();

    final fadeOutStart =
        (safeDuration - fadeOut).clamp(0.0, safeDuration);

    return [
      'format=rgba',
      'fade=t=in:st=0:d=${_n(fadeIn)}:alpha=1',
      'fade=t=out:st=${_n(fadeOutStart)}:d=${_n(fadeOut)}:alpha=1',
      'setpts=PTS-STARTPTS+${_n(timelineStart)}/TB',
    ].join(',');
  }

  String captionYExpression({
    required String baseY,
    required double start,
    required String direction,
  }) {
    if (direction != 'up' && direction != 'down') {
      return baseY;
    }

    final distance = 'overlay_h*${_n(captionTravel)}';
    final easing = _easeOut(start, captionEnterSeconds);
    final offset = direction == 'up' ? '+$distance' : '-$distance';

    return "if(lt(t,${_n(start + captionEnterSeconds)}),"
        "($baseY)$offset*$easing,$baseY)";
  }

  String captionXExpression({
    required String baseX,
    required double start,
  }) {
    if (mood != MotionMood.dynamic) {
      return baseX;
    }

    return "($baseX)+overlay_w*0.72*"
        "${_easeOut(start, captionEnterSeconds)}";
  }

  String hookXExpression({
    required String baseX,
    required double start,
  }) {
    if (mood != MotionMood.dynamic) {
      return baseX;
    }

    return "($baseX)+overlay_w*0.85*"
        "${_easeOut(start, hookEnterSeconds)}";
  }

  String hookYExpression({
    required String baseY,
    required double start,
  }) {
    if (mood == MotionMood.dynamic) {
      return baseY;
    }

    return "($baseY)-overlay_h*0.90*"
        "${_easeOut(start, hookEnterSeconds)}";
  }

  String brollInputFilter({
    required int width,
    required int height,
    required double start,
    required double end,
  }) {
    final duration = (end - start).clamp(0.12, 600.0).toDouble();

    final fade = brollFadeSeconds
        .clamp(0.06, duration / 2)
        .toDouble();

    final fadeOutStart =
        (duration - fade).clamp(0.0, duration);

    return [
      'trim=duration=${_n(duration)}',
      'setpts=PTS-STARTPTS',
      'scale=$width:$height:force_original_aspect_ratio=increase',
      'crop=$width:$height',
      'setsar=1',
      'format=rgba',
      'fade=t=in:st=0:d=${_n(fade)}:alpha=1',
      'fade=t=out:st=${_n(fadeOutStart)}:d=${_n(fade)}:alpha=1',
      'setpts=PTS+${_n(start)}/TB',
    ].join(',');
  }
}