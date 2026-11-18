import 'dart:math' as math;
import 'dart:typed_data';

import 'person_anchor_path.dart';

double _clampValue(double value, double low, double high) =>
    value.isNaN ? low : value.clamp(low, high).toDouble();

String _fixed(double value) => value.toStringAsFixed(3);

/// What the footage around a 3D scene looks like: how bright it is, which
/// color cast it has, where the light comes from and how soft the picture is.
///
/// It is measured from a few small frames of the real video (see
/// SceneEnvironmentSampler), so the 3D model can be matched to the place it is
/// standing in instead of looking like a sticker pasted on top.
class SceneEnvironmentProfile {
  /// Mean brightness, 0 (black) .. 1 (white).
  final double luma;

  /// Spread of the brightness (standard deviation), 0 .. 0.5.
  final double contrast;

  /// Mean color channels, 0 .. 1.
  final double red;
  final double green;
  final double blue;

  /// Mean color saturation, 0 (gray) .. 1 (vivid).
  final double saturation;

  /// Where the light comes from horizontally: -1 = from the left,
  /// +1 = from the right, 0 = frontal / even.
  final double lightX;

  /// Where the light comes from vertically: -1 = from above,
  /// +1 = from below, 0 = even.
  final double lightY;

  /// 0 = crisp picture, 1 = very soft / out of focus picture.
  final double softness;

  const SceneEnvironmentProfile({
    required this.luma,
    required this.contrast,
    required this.red,
    required this.green,
    required this.blue,
    required this.saturation,
    required this.lightX,
    required this.lightY,
    required this.softness,
  });

  /// A neutral, evenly lit room.
  static const SceneEnvironmentProfile neutral = SceneEnvironmentProfile(
    luma: 0.45,
    contrast: 0.2,
    red: 0.45,
    green: 0.45,
    blue: 0.45,
    saturation: 0.3,
    lightX: 0.0,
    lightY: 0.0,
    softness: 0.3,
  );

  static double _axis(double first, double second) =>
      _clampValue((second - first) / (first + second + 0.02) * 2.5, -1.0, 1.0);

  /// Measures a profile from an RGBA image (4 bytes per pixel).
  /// Returns null for an image that is too small or too short.
  static SceneEnvironmentProfile? fromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) {
    if (width < 4 || height < 4 || rgba.length < width * height * 4) {
      return null;
    }

    final count = width * height;
    final lumas = Float64List(count);

    var sumRed = 0.0;
    var sumGreen = 0.0;
    var sumBlue = 0.0;
    var sumLuma = 0.0;
    var sumLumaSquared = 0.0;
    var sumSaturation = 0.0;

    var leftSum = 0.0;
    var rightSum = 0.0;
    var topSum = 0.0;
    var bottomSum = 0.0;
    var leftCount = 0;
    var rightCount = 0;
    var topCount = 0;
    var bottomCount = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 4;
        final r = rgba[offset] / 255.0;
        final g = rgba[offset + 1] / 255.0;
        final b = rgba[offset + 2] / 255.0;

        final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        lumas[y * width + x] = l;

        sumRed += r;
        sumGreen += g;
        sumBlue += b;
        sumLuma += l;
        sumLumaSquared += l * l;

        final high = math.max(r, math.max(g, b));
        final low = math.min(r, math.min(g, b));
        sumSaturation += high <= 1e-6 ? 0.0 : (high - low) / high;

        if (x * 2 < width) {
          leftSum += l;
          leftCount++;
        } else {
          rightSum += l;
          rightCount++;
        }

        if (y * 2 < height) {
          topSum += l;
          topCount++;
        } else {
          bottomSum += l;
          bottomCount++;
        }
      }
    }

    var gradientSum = 0.0;
    var gradientCount = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final here = lumas[y * width + x];

        if (x + 1 < width) {
          gradientSum += (lumas[y * width + x + 1] - here).abs();
          gradientCount++;
        }

        if (y + 1 < height) {
          gradientSum += (lumas[(y + 1) * width + x] - here).abs();
          gradientCount++;
        }
      }
    }

    final meanLuma = sumLuma / count;
    final variance = math.max(0.0, sumLumaSquared / count - meanLuma * meanLuma);
    final meanGradient =
        gradientCount == 0 ? 0.0 : gradientSum / gradientCount;

    final leftMean = leftCount == 0 ? 0.0 : leftSum / leftCount;
    final rightMean = rightCount == 0 ? 0.0 : rightSum / rightCount;
    final topMean = topCount == 0 ? 0.0 : topSum / topCount;
    final bottomMean = bottomCount == 0 ? 0.0 : bottomSum / bottomCount;

    return SceneEnvironmentProfile(
      luma: _clampValue(meanLuma, 0.0, 1.0),
      contrast: _clampValue(math.sqrt(variance), 0.0, 0.5),
      red: _clampValue(sumRed / count, 0.0, 1.0),
      green: _clampValue(sumGreen / count, 0.0, 1.0),
      blue: _clampValue(sumBlue / count, 0.0, 1.0),
      saturation: _clampValue(sumSaturation / count, 0.0, 1.0),
      lightX: _axis(leftMean, rightMean),
      lightY: _axis(topMean, bottomMean),
      softness: _clampValue(1.0 - (meanGradient - 0.012) / 0.058, 0.0, 1.0),
    );
  }

  /// Mean of several profiles (for example three frames of one scene).
  /// Returns null for an empty list.
  static SceneEnvironmentProfile? average(
    Iterable<SceneEnvironmentProfile> profiles,
  ) {
    final list = profiles.toList();
    if (list.isEmpty) return null;

    double mean(double Function(SceneEnvironmentProfile profile) pick) {
      var total = 0.0;
      for (final profile in list) {
        total += pick(profile);
      }
      return total / list.length;
    }

    return SceneEnvironmentProfile(
      luma: mean((p) => p.luma),
      contrast: mean((p) => p.contrast),
      red: mean((p) => p.red),
      green: mean((p) => p.green),
      blue: mean((p) => p.blue),
      saturation: mean((p) => p.saturation),
      lightX: mean((p) => p.lightX),
      lightY: mean((p) => p.lightY),
      softness: mean((p) => p.softness),
    );
  }
}

/// How a 3D card is matched to its environment.
///
/// The card is graded to the light and color of the place (exposure, color
/// cast, saturation), lifted toward the ambient haze by its distance, softened
/// like out-of-focus footage, given the grain of the camera, and it casts a
/// soft shadow away from the light. Everything is expressed as FFmpeg filter
/// fragments that never touch the alpha channel, so the keyed card keeps its
/// shape.
class SceneEnvironmentLook {
  /// Smallest blur that is worth a filter (below it the card stays crisp).
  static const double minimumBlurSigma = 0.35;

  /// Share of the scene color that tints the card (0 = none).
  static const double tintStrength = 0.35;

  /// Relative distance from the camera: 0 = near, 1 = far.
  final double depth;

  /// Per-channel gain (exposure combined with the color cast of the place).
  final double gainRed;
  final double gainGreen;
  final double gainBlue;

  /// Color saturation of the card (1 = unchanged).
  final double saturation;

  /// How much the blacks are lifted toward the ambient color (0..0.1).
  final double blackLift;

  /// Black-level offsets per channel, in 0..255 units.
  final double liftRed;
  final double liftGreen;
  final double liftBlue;

  /// Gaussian blur of the card in pixels (0 = none).
  final double blurSigma;

  /// Opacity of the cast shadow (0..1).
  final double shadowOpacity;

  /// Shadow offset in pixels from the card.
  final double shadowDx;
  final double shadowDy;

  /// Gaussian softness of the shadow in pixels.
  final double shadowBlur;

  /// Camera grain strength for the FFmpeg noise filter (0 = none).
  final int grain;

  const SceneEnvironmentLook({
    required this.depth,
    required this.gainRed,
    required this.gainGreen,
    required this.gainBlue,
    required this.saturation,
    required this.blackLift,
    required this.liftRed,
    required this.liftGreen,
    required this.liftBlue,
    required this.blurSigma,
    required this.shadowOpacity,
    required this.shadowDx,
    required this.shadowDy,
    required this.shadowBlur,
    required this.grain,
  });

  /// Distance of a card from the camera by where it is placed: behind the
  /// shoulder is the farthest, beside the hand (in front) the nearest.
  static double depthOf(PersonPlacement placement) {
    switch (placement) {
      case PersonPlacement.behindShoulder:
        return 0.75;
      case PersonPlacement.aboveHead:
        return 0.5;
      case PersonPlacement.besideHand:
        return 0.25;
    }
  }

  /// Plans the look of one card from the measured [profile], the card's
  /// [placement] and its side length in pixels.
  static SceneEnvironmentLook plan({
    required SceneEnvironmentProfile profile,
    required PersonPlacement placement,
    required int sidePixels,
  }) {
    final side = math.max(16, sidePixels).toDouble();
    final depth = depthOf(placement);
    final luma = _clampValue(profile.luma, 0.0, 1.0);

    // A studio-lit model is brighter than most rooms: bring it down to the
    // brightness of the place, never far past it.
    final exposure = _clampValue(0.74 + 0.5 * luma, 0.78, 1.06);

    final safeLuma = math.max(luma, 0.04);
    double gainFor(double channel) {
      final ratio = _clampValue(channel / safeLuma, 0.7, 1.4);
      return exposure * (1.0 + tintStrength * (ratio - 1.0));
    }

    final saturation = _clampValue(
      0.85 + 0.5 * _clampValue(profile.saturation, 0.0, 1.0) - 0.1 * depth,
      0.75,
      1.05,
    );

    // Distance haze: far objects have lifted, color-tinted blacks.
    final blackLift = _clampValue(0.01 + 0.07 * depth, 0.0, 0.1);
    final brightest = math.max(
      math.max(profile.red, math.max(profile.green, profile.blue)),
      0.05,
    );
    double liftFor(double channel) =>
        blackLift * 255.0 * _clampValue(channel / brightest, 0.0, 1.0);

    // Far cards are softer, and a soft picture softens them more.
    final rawBlur = side /
        600.0 *
        (0.1 + 1.5 * depth * (0.5 + _clampValue(profile.softness, 0.0, 1.0)));
    final blurSigma = _clampValue(rawBlur, 0.0, 3.0);

    // The shadow falls away from the light. Frontal / even light gives a
    // small, very soft shadow straight down.
    final lightX = _clampValue(profile.lightX, -1.0, 1.0);
    final lightY = _clampValue(profile.lightY, -1.0, 1.0);
    final directionality =
        math.min(1.0, math.sqrt(lightX * lightX + lightY * lightY) * 1.2);

    var directionX = -lightX;
    var directionY = 0.55 - lightY * 0.8;
    final magnitude =
        math.sqrt(directionX * directionX + directionY * directionY);

    if (magnitude < 1e-3) {
      directionX = 0.0;
      directionY = 1.0;
    } else {
      directionX /= magnitude;
      directionY /= magnitude;
    }

    final distance =
        side * (0.03 + 0.06 * depth) * (0.55 + 0.45 * directionality);

    // Shadows are hardly visible in dark places.
    final shadowOpacity = _clampValue(0.16 + 0.34 * luma, 0.15, 0.45);
    final shadowBlur = _clampValue(
      side * (0.012 + 0.02 * depth + 0.012 * (1.0 - directionality)),
      3.0,
      24.0,
    );

    // Phone footage is grainier in the dark.
    final grain = (2.0 + 14.0 * math.pow(1.0 - luma, 2).toDouble())
        .round()
        .clamp(2, 12)
        .toInt();

    return SceneEnvironmentLook(
      depth: depth,
      gainRed: gainFor(profile.red),
      gainGreen: gainFor(profile.green),
      gainBlue: gainFor(profile.blue),
      saturation: saturation,
      blackLift: blackLift,
      liftRed: liftFor(profile.red),
      liftGreen: liftFor(profile.green),
      liftBlue: liftFor(profile.blue),
      blurSigma: blurSigma < minimumBlurSigma ? 0.0 : blurSigma,
      shadowOpacity: shadowOpacity,
      shadowDx: directionX * distance,
      shadowDy: directionY * distance,
      shadowBlur: shadowBlur,
      grain: grain,
    );
  }

  bool get hasBlur => blurSigma >= minimumBlurSigma;

  bool get hasGrain => grain > 0;

  // Rec. 709 luma weights, used to keep brightness while changing saturation.
  static const List<double> _lumaWeights = <double>[0.2126, 0.7152, 0.0722];
  static const List<String> _channels = <String>['r', 'g', 'b'];

  /// `colorchannelmixer` that applies exposure, the color cast of the place
  /// and the saturation in one step. Alpha is left as it is.
  String get mixerFilter {
    final gains = <double>[gainRed, gainGreen, gainBlue];
    final parts = <String>[];

    for (var out = 0; out < 3; out++) {
      for (var input = 0; input < 3; input++) {
        final weight = (1.0 - saturation) * _lumaWeights[input] +
            (out == input ? saturation : 0.0);
        parts.add('${_channels[out]}${_channels[input]}='
            '${_fixed(gains[out] * weight)}');
      }
    }

    return 'colorchannelmixer=${parts.join(':')}';
  }

  /// `lutrgb` that lifts the blacks toward the ambient color of the place.
  String get liftFilter {
    final scale = _fixed(1.0 - blackLift);
    return "lutrgb=r='val*$scale+${_fixed(liftRed)}':"
        "g='val*$scale+${_fixed(liftGreen)}':"
        "b='val*$scale+${_fixed(liftBlue)}'";
  }

  /// Everything that changes the look of the card itself: light and color,
  /// distance haze and the soft focus of far objects. Keeps `rgba`.
  String get gradeChain {
    final parts = <String>[mixerFilter, liftFilter];

    if (hasBlur) {
      parts.add(
        'format=gbrap,gblur=sigma=${_fixed(blurSigma)},format=rgba',
      );
    }

    return parts.join(',');
  }

  /// Turns a copy of the card into its soft black shadow. Keeps `rgba`.
  String get shadowChain => 'colorchannelmixer=rr=0:gg=0:bb=0:'
      'aa=${_fixed(shadowOpacity)},'
      'format=gbrap,gblur=sigma=${_fixed(shadowBlur)},format=rgba';
}
