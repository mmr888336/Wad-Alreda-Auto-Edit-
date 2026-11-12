/// 2.5D virtual camera motion for FFmpeg-rendered visual layers.
///
/// The camera uses a small overscan canvas and an animated crop window.
/// Different depth values create a parallax-like separation between
/// background B-roll and foreground text/graphic layers.
enum CameraMotionStyle { restrained, cinematic, energetic }

enum CameraDirection {
  leftToRight,
  rightToLeft,
  topToBottom,
  bottomToTop,
  diagonalDownRight,
  diagonalUpLeft,
  diagonalDownLeft,
  diagonalUpRight,
}

class MotionCameraEngine {
  MotionCameraEngine._();

  static String _n(double value) => value.toStringAsFixed(3);

  static double _overscan(CameraMotionStyle style) {
    switch (style) {
      case CameraMotionStyle.restrained:
        return 1.055;
      case CameraMotionStyle.cinematic:
        return 1.075;
      case CameraMotionStyle.energetic:
        return 1.095;
    }
  }

  static double _intensity(CameraMotionStyle style) {
    switch (style) {
      case CameraMotionStyle.restrained:
        return 0.62;
      case CameraMotionStyle.cinematic:
        return 0.82;
      case CameraMotionStyle.energetic:
        return 1.0;
    }
  }

  /// Creates a smooth pan/tilt crop filter.
  ///
  /// When output dimensions are supplied (video/B-roll), the result is
  /// exactly that size. For transparent text layers, the original dimensions
  /// are recovered from the overscanned image.
  ///
  /// [depth] is a normalized layer depth: lower values move less, while
  /// foreground graphics can move more to create a parallax impression.
  static String buildFilter({
    required double duration,
    required CameraMotionStyle style,
    required double depth,
    int seed = 0,
    int? outputWidth,
    int? outputHeight,
  }) {
    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Duration must be positive and finite.',
      );
    }
    if (!depth.isFinite) {
      throw ArgumentError.value(
        depth,
        'depth',
        'Depth must be finite.',
      );
    }
    if ((outputWidth == null) != (outputHeight == null)) {
      throw ArgumentError(
        'Both outputWidth and outputHeight must be supplied together.',
      );
    }
    if (outputWidth != null && (outputWidth < 2 || outputHeight! < 2)) {
      throw ArgumentError('Camera output dimensions must be at least 2 pixels.');
    }

    final safeDuration = duration.clamp(0.12, 600.0).toDouble();
    final factor = _overscan(style);
    final effectiveDepth =
        depth.clamp(0.0, 1.0).toDouble() * _intensity(style);
    final direction =
        CameraDirection.values[seed.abs() % CameraDirection.values.length];

    final progress = 'min(1,max(0,t/${_n(safeDuration)}))';
    final ease = '(0.5-0.5*cos(PI*$progress))';
    final xRange = 0.32 * effectiveDepth;
    final yRange = 0.28 * effectiveDepth;
    final crossDrift = 0.035 * effectiveDepth;

    late final String x;
    late final String y;

    switch (direction) {
      case CameraDirection.leftToRight:
        x = '(${_n(0.5 - xRange)}+${_n(2 * xRange)}*$ease)';
        y = '(0.5+${_n(crossDrift)}*sin(PI*$progress))';
        break;
      case CameraDirection.rightToLeft:
        x = '(${_n(0.5 + xRange)}-${_n(2 * xRange)}*$ease)';
        y = '(0.5-${_n(crossDrift)}*sin(PI*$progress))';
        break;
      case CameraDirection.topToBottom:
        x = '(0.5-${_n(crossDrift)}*sin(PI*$progress))';
        y = '(${_n(0.5 - yRange)}+${_n(2 * yRange)}*$ease)';
        break;
      case CameraDirection.bottomToTop:
        x = '(0.5+${_n(crossDrift)}*sin(PI*$progress))';
        y = '(${_n(0.5 + yRange)}-${_n(2 * yRange)}*$ease)';
        break;
      case CameraDirection.diagonalDownRight:
        x = '(${_n(0.5 - xRange)}+${_n(2 * xRange)}*$ease)';
        y = '(${_n(0.5 - yRange)}+${_n(2 * yRange)}*$ease)';
        break;
      case CameraDirection.diagonalUpLeft:
        x = '(${_n(0.5 + xRange)}-${_n(2 * xRange)}*$ease)';
        y = '(${_n(0.5 + yRange)}-${_n(2 * yRange)}*$ease)';
        break;
      case CameraDirection.diagonalDownLeft:
        x = '(${_n(0.5 + xRange)}-${_n(2 * xRange)}*$ease)';
        y = '(${_n(0.5 - yRange)}+${_n(2 * yRange)}*$ease)';
        break;
      case CameraDirection.diagonalUpRight:
        x = '(${_n(0.5 - xRange)}+${_n(2 * xRange)}*$ease)';
        y = '(${_n(0.5 + yRange)}-${_n(2 * yRange)}*$ease)';
        break;
    }

    final scale =
        "scale=w='ceil(iw*${_n(factor)}/2)*2':"
        "h='ceil(ih*${_n(factor)}/2)*2':flags=lanczos";

    final crop = outputWidth != null
        ? "crop=w=$outputWidth:h=$outputHeight:"
            "x='(iw-ow)*$x':y='(ih-oh)*$y'"
        : "crop=w=trunc(iw/${_n(factor)}):"
            "h=trunc(ih/${_n(factor)}):"
            "x='(iw-ow)*$x':y='(ih-oh)*$y'";

    return '$scale,$crop';
  }
}
