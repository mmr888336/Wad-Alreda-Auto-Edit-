import 'dart:typed_data';

import 'package:auto_edit/person_anchor_path.dart';
import 'package:auto_edit/scene_environment.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _image(
  int width,
  int height,
  List<int> Function(int x, int y) colorAt,
) {
  final data = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = colorAt(x, y);
      final offset = (y * width + x) * 4;
      data[offset] = color[0];
      data[offset + 1] = color[1];
      data[offset + 2] = color[2];
      data[offset + 3] = 255;
    }
  }
  return data;
}

SceneEnvironmentProfile _profile({
  double luma = 0.5,
  double red = 0.5,
  double green = 0.5,
  double blue = 0.5,
  double saturation = 0.3,
  double lightX = 0.0,
  double lightY = 0.0,
  double softness = 0.3,
}) =>
    SceneEnvironmentProfile(
      luma: luma,
      contrast: 0.2,
      red: red,
      green: green,
      blue: blue,
      saturation: saturation,
      lightX: lightX,
      lightY: lightY,
      softness: softness,
    );

SceneEnvironmentLook _plan(
  SceneEnvironmentProfile profile, {
  PersonPlacement placement = PersonPlacement.aboveHead,
  int side = 540,
}) =>
    SceneEnvironmentLook.plan(
      profile: profile,
      placement: placement,
      sidePixels: side,
    );

void main() {
  group('SceneEnvironmentProfile.fromRgba', () {
    test('reads brightness, color and softness of a flat gray picture', () {
      final profile = SceneEnvironmentProfile.fromRgba(
        _image(16, 16, (x, y) => <int>[128, 128, 128]),
        16,
        16,
      )!;

      expect(profile.luma, closeTo(0.502, 0.01));
      expect(profile.saturation, closeTo(0.0, 0.001));
      expect(profile.contrast, closeTo(0.0, 0.001));
      expect(profile.lightX, closeTo(0.0, 0.001));
      expect(profile.lightY, closeTo(0.0, 0.001));
      expect(profile.softness, closeTo(1.0, 0.001));
    });

    test('a bright left side means light from the left', () {
      final profile = SceneEnvironmentProfile.fromRgba(
        _image(
          16,
          16,
          (x, y) => x < 8 ? <int>[220, 220, 220] : <int>[40, 40, 40],
        ),
        16,
        16,
      )!;

      expect(profile.lightX, lessThan(-0.5));
      expect(profile.lightY.abs(), lessThan(0.01));
    });

    test('a bright top means light from above', () {
      final profile = SceneEnvironmentProfile.fromRgba(
        _image(
          16,
          16,
          (x, y) => y < 8 ? <int>[220, 220, 220] : <int>[40, 40, 40],
        ),
        16,
        16,
      )!;

      expect(profile.lightY, lessThan(-0.5));
      expect(profile.lightX.abs(), lessThan(0.01));
    });

    test('a sharp checkerboard is crisper than a flat picture', () {
      final sharp = SceneEnvironmentProfile.fromRgba(
        _image(
          16,
          16,
          (x, y) =>
              (x + y).isEven ? <int>[250, 250, 250] : <int>[10, 10, 10],
        ),
        16,
        16,
      )!;

      expect(sharp.softness, lessThan(0.1));
      expect(sharp.contrast, greaterThan(0.3));
    });

    test('a warm picture has more red than blue', () {
      final profile = SceneEnvironmentProfile.fromRgba(
        _image(16, 16, (x, y) => <int>[200, 140, 60]),
        16,
        16,
      )!;

      expect(profile.red, greaterThan(profile.green));
      expect(profile.green, greaterThan(profile.blue));
      expect(profile.saturation, greaterThan(0.5));
    });

    test('returns null for invalid input', () {
      expect(SceneEnvironmentProfile.fromRgba(Uint8List(8), 16, 16), isNull);
      expect(
        SceneEnvironmentProfile.fromRgba(Uint8List(2 * 2 * 4), 2, 2),
        isNull,
      );
    });
  });

  group('SceneEnvironmentProfile.average', () {
    test('averages every field and returns null for an empty list', () {
      final mean = SceneEnvironmentProfile.average(<SceneEnvironmentProfile>[
        _profile(luma: 0.2, lightX: -0.6),
        _profile(luma: 0.6, lightX: 0.2),
      ])!;

      expect(mean.luma, closeTo(0.4, 1e-9));
      expect(mean.lightX, closeTo(-0.2, 1e-9));

      expect(
        SceneEnvironmentProfile.average(const <SceneEnvironmentProfile>[]),
        isNull,
      );
    });
  });

  group('SceneEnvironmentLook.plan', () {
    test('depth follows the placement: behind is far, beside the hand is near',
        () {
      expect(
        SceneEnvironmentLook.depthOf(PersonPlacement.behindShoulder),
        greaterThan(SceneEnvironmentLook.depthOf(PersonPlacement.aboveHead)),
      );
      expect(
        SceneEnvironmentLook.depthOf(PersonPlacement.aboveHead),
        greaterThan(SceneEnvironmentLook.depthOf(PersonPlacement.besideHand)),
      );
    });

    test('far cards are softer and hazier than near cards', () {
      final far = _plan(
        _profile(),
        placement: PersonPlacement.behindShoulder,
      );
      final near = _plan(
        _profile(),
        placement: PersonPlacement.besideHand,
      );

      expect(far.blurSigma, greaterThan(near.blurSigma));
      expect(far.blackLift, greaterThan(near.blackLift));
      expect(far.saturation, lessThan(near.saturation));
      expect(far.shadowBlur, greaterThan(near.shadowBlur));
    });

    test('a soft picture softens the card more', () {
      final crisp = _plan(
        _profile(softness: 0.0),
        placement: PersonPlacement.behindShoulder,
      );
      final soft = _plan(
        _profile(softness: 1.0),
        placement: PersonPlacement.behindShoulder,
      );

      expect(soft.blurSigma, greaterThan(crisp.blurSigma));
    });

    test('a tiny card gets no blur filter at all', () {
      final tiny = _plan(
        _profile(),
        placement: PersonPlacement.besideHand,
        side: 100,
      );

      expect(tiny.hasBlur, isFalse);
      expect(tiny.blurSigma, 0.0);
      expect(tiny.gradeChain, isNot(contains('gblur')));
    });

    test('a normal card far from the camera is blurred', () {
      final look = _plan(
        _profile(),
        placement: PersonPlacement.behindShoulder,
      );

      expect(look.hasBlur, isTrue);
      expect(look.gradeChain, contains('format=gbrap,gblur=sigma='));
      expect(look.gradeChain, endsWith('format=rgba'));
    });

    test('a dark place gets a darker card, more grain and a fainter shadow',
        () {
      final dark = _plan(_profile(luma: 0.1, red: 0.1, green: 0.1, blue: 0.1));
      final bright =
          _plan(_profile(luma: 0.8, red: 0.8, green: 0.8, blue: 0.8));

      expect(dark.gainGreen, lessThan(bright.gainGreen));
      expect(dark.grain, greaterThan(bright.grain));
      expect(dark.shadowOpacity, lessThan(bright.shadowOpacity));
    });

    test('the color cast of the place tints the card and its haze', () {
      final warm = _plan(
        _profile(luma: 0.5, red: 0.65, green: 0.5, blue: 0.3, saturation: 0.5),
      );

      expect(warm.gainRed, greaterThan(warm.gainGreen));
      expect(warm.gainGreen, greaterThan(warm.gainBlue));
      expect(warm.liftRed, greaterThan(warm.liftBlue));
    });

    test('the shadow falls away from the light', () {
      final fromLeft = _plan(_profile(lightX: -0.9));
      final fromRight = _plan(_profile(lightX: 0.9));
      final fromTop = _plan(_profile(lightY: -0.9));

      expect(fromLeft.shadowDx, greaterThan(0));
      expect(fromRight.shadowDx, lessThan(0));
      expect(fromTop.shadowDy, greaterThan(0));
    });

    test('even frontal light drops a small soft shadow straight down', () {
      final even = _plan(_profile());
      final directional = _plan(_profile(lightX: -0.9, lightY: -0.9));

      expect(even.shadowDx, closeTo(0.0, 1e-9));
      expect(even.shadowDy, greaterThan(0));
      expect(
        even.shadowDy,
        lessThan(directional.shadowDy + directional.shadowDx),
      );
      expect(even.shadowBlur, greaterThan(directional.shadowBlur));
    });

    test('values stay in safe ranges for extreme measurements', () {
      for (final luma in <double>[0.0, 1.0]) {
        for (final placement in PersonPlacement.values) {
          final look = _plan(
            _profile(
              luma: luma,
              red: luma,
              green: 0.0,
              blue: 1.0,
              saturation: 1.0,
              lightX: -1.0,
              lightY: 1.0,
              softness: 1.0,
            ),
            placement: placement,
          );

          for (final gain in <double>[
            look.gainRed,
            look.gainGreen,
            look.gainBlue,
          ]) {
            expect(gain, inInclusiveRange(0.5, 1.5));
          }

          expect(look.saturation, inInclusiveRange(0.75, 1.05));
          expect(look.blackLift, inInclusiveRange(0.0, 0.1));
          expect(look.blurSigma, inInclusiveRange(0.0, 3.0));
          expect(look.shadowOpacity, inInclusiveRange(0.15, 0.45));
          expect(look.shadowBlur, inInclusiveRange(3.0, 24.0));
          expect(look.grain, inInclusiveRange(2, 12));
          expect(look.shadowDx.isFinite, isTrue);
          expect(look.shadowDy.isFinite, isTrue);
          expect(look.liftBlue, lessThanOrEqualTo(25.5));
        }
      }
    });
  });

  group('FFmpeg filter fragments', () {
    test('the mixer keeps brightness: each row sums to its gain', () {
      final look = _plan(
        _profile(luma: 0.5, red: 0.65, green: 0.5, blue: 0.3, saturation: 0.5),
      );

      final values = <String, double>{};
      for (final match in RegExp(r'([rgb])([rgb])=(-?\d+\.\d+)')
          .allMatches(look.mixerFilter)) {
        values['${match.group(1)}${match.group(2)}'] =
            double.parse(match.group(3)!);
      }

      expect(values.length, 9);

      expect(
        values['rr']! + values['rg']! + values['rb']!,
        closeTo(look.gainRed, 0.005),
      );
      expect(
        values['gr']! + values['gg']! + values['gb']!,
        closeTo(look.gainGreen, 0.005),
      );
      expect(
        values['br']! + values['bg']! + values['bb']!,
        closeTo(look.gainBlue, 0.005),
      );
    });

    test('the grade never touches the alpha channel', () {
      final chain = _plan(
        _profile(),
        placement: PersonPlacement.behindShoulder,
      ).gradeChain;

      expect(chain, startsWith('colorchannelmixer=rr='));
      expect(chain, contains("lutrgb=r='val*"));
      expect(chain, isNot(contains('aa=')));
      expect(chain, isNot(contains('ra=')));
      expect(chain, isNot(contains('ga=')));
      expect(chain, isNot(contains('ba=')));
      expect(chain, isNot(contains(RegExp(r"a='"))));
    });

    test('the lift raises the blacks without passing white', () {
      final look = _plan(
        _profile(),
        placement: PersonPlacement.behindShoulder,
      );

      expect(look.liftFilter, contains("g='val*"));
      expect(look.liftFilter, contains("b='val*"));

      final scale = 1.0 - look.blackLift;
      expect(scale * 255 + look.liftRed, lessThanOrEqualTo(255.0 + 1e-9));
    });

    test('the shadow chain turns the card black, keeps its shape and softens '
        'it', () {
      final chain = _plan(_profile()).shadowChain;

      expect(chain, startsWith('colorchannelmixer=rr=0:gg=0:bb=0:aa='));
      expect(chain, contains('format=gbrap,gblur=sigma='));
      expect(chain, endsWith('format=rgba'));
    });
  });
}
