/// Cinematic transition library for FFmpeg (xfade based).
///
/// Each [MotionTransitionKind] maps to a built-in FFmpeg `xfade` transition,
/// so no extra assets, plugins or network access are needed. Some kinds are
/// close approximations of the look in the Motion Smith references (for
/// example redFlash uses a dip through black rather than a red tint).
library;

enum MotionTransitionKind {
  hardCut,
  redFlash,
  pixelBlockWipe,
  glitchSlice,
  whipPan,
  zoomSmash,
  matchCut,
  lightLeak,
  rgbSplit,
  blurDissolve,
}

class MotionTransitions {
  MotionTransitions._();

  static final RegExp _label = RegExp(r'^[A-Za-z0-9_:]+$');

  static String _n(double value) => value.toStringAsFixed(3);

  /// FFmpeg xfade transition name, or null for a hard cut (no blending).
  static String? xfadeName(MotionTransitionKind kind) {
    switch (kind) {
      case MotionTransitionKind.hardCut:
        return null;
      case MotionTransitionKind.redFlash:
        return 'fadeblack';
      case MotionTransitionKind.pixelBlockWipe:
        return 'pixelize';
      case MotionTransitionKind.glitchSlice:
        return 'hlslice';
      case MotionTransitionKind.whipPan:
        return 'slideleft';
      case MotionTransitionKind.zoomSmash:
        return 'zoomin';
      case MotionTransitionKind.matchCut:
        return 'fade';
      case MotionTransitionKind.lightLeak:
        return 'fadewhite';
      case MotionTransitionKind.rgbSplit:
        return 'distance';
      case MotionTransitionKind.blurDissolve:
        return 'hblur';
    }
  }

  /// Typical duration in seconds for a transition kind.
  static double defaultDuration(MotionTransitionKind kind) {
    switch (kind) {
      case MotionTransitionKind.hardCut:
        return 0.0;
      case MotionTransitionKind.redFlash:
        return 0.30;
      case MotionTransitionKind.pixelBlockWipe:
        return 0.50;
      case MotionTransitionKind.glitchSlice:
        return 0.35;
      case MotionTransitionKind.whipPan:
        return 0.40;
      case MotionTransitionKind.zoomSmash:
        return 0.35;
      case MotionTransitionKind.matchCut:
        return 0.20;
      case MotionTransitionKind.lightLeak:
        return 0.60;
      case MotionTransitionKind.rgbSplit:
        return 0.40;
      case MotionTransitionKind.blurDissolve:
        return 0.60;
    }
  }

  /// Builds one xfade filter between two labelled streams.
  ///
  /// [inputA], [inputB] and [output] are bare stream labels without brackets
  /// (for example `v0`, `v1`, `vout`). [offset] is the time in seconds, on
  /// the first stream, at which the transition starts. Returns null for a
  /// hard cut; the caller should concatenate the clips instead.
  static String? buildXfade({
    required String inputA,
    required String inputB,
    required String output,
    required MotionTransitionKind kind,
    required double offset,
    double? duration,
  }) {
    for (final label in <String>[inputA, inputB, output]) {
      if (!_label.hasMatch(label)) {
        throw ArgumentError.value(label, 'label', 'Invalid stream label.');
      }
    }
    if (!offset.isFinite || offset < 0) {
      throw ArgumentError.value(
        offset,
        'offset',
        'Offset must be finite and not negative.',
      );
    }
    final name = xfadeName(kind);
    if (name == null) return null;

    final raw = duration ?? defaultDuration(kind);
    if (!raw.isFinite) {
      throw ArgumentError.value(raw, 'duration', 'Duration must be finite.');
    }
    final safeDuration = raw.clamp(0.05, 2.0).toDouble();

    return '[$inputA][$inputB]xfade=transition=$name:'
        'duration=${_n(safeDuration)}:offset=${_n(offset)}[$output]';
  }
}
