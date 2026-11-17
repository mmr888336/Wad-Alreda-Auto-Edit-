import 'dart:typed_data';

import 'package:auto_edit/pixel_art_sprites.dart';
import 'package:flutter_test/flutter_test.dart';

int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

void main() {
  test('every sprite grid is rectangular and uses only palette colours', () {
    for (final sprite in PixelSprites.all) {
      expect(sprite.validate, returnsNormally, reason: sprite.key);
      expect(sprite.width, 16, reason: sprite.key);
      expect(sprite.height, 16, reason: sprite.key);
    }
  });

  test('sprite keys are unique and resolvable', () {
    final keys = PixelSprites.all.map((s) => s.key).toList();
    expect(keys.toSet().length, keys.length);
    for (final key in keys) {
      expect(PixelSprites.byKey(key)?.key, key);
    }
    expect(PixelSprites.byKey('does_not_exist'), isNull);
    expect(PixelSprites.byKey('pixel_camera'), isNotNull);
  });

  test('validate rejects ragged rows and unknown palette characters', () {
    const ragged = PixelSprite(
      key: 'ragged',
      palette: <String, int>{'a': 0xFFFFFFFF},
      rows: <String>['aa', 'a'],
    );
    const unknown = PixelSprite(
      key: 'unknown',
      palette: <String, int>{'a': 0xFFFFFFFF},
      rows: <String>['ab'],
    );
    expect(ragged.validate, throwsStateError);
    expect(unknown.validate, throwsStateError);
  });

  test('toRgba keeps transparency and upscales without smoothing', () {
    const sprite = PixelSprite(
      key: 'tiny',
      palette: <String, int>{'a': 0xFFFF0000},
      rows: <String>['a.', '.a'],
    );
    final rgba = sprite.toRgba(scale: 2);
    expect(rgba.length, 4 * 4 * 4);
    // Top-left 2x2 block is opaque red.
    expect(rgba.sublist(0, 4), <int>[255, 0, 0, 255]);
    expect(rgba.sublist(4, 8), <int>[255, 0, 0, 255]);
    // Top-right block is fully transparent.
    expect(rgba.sublist(8, 12), <int>[0, 0, 0, 0]);
    expect(() => sprite.toRgba(scale: 0), throwsArgumentError);
  });

  test('toPng writes a valid RGBA PNG header with the scaled size', () {
    final png = PixelSprites.orangeMascot.toPng(scale: 4);
    expect(
      png.sublist(0, 8),
      <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    );
    expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
    expect(_u32(png, 16), 64);
    expect(_u32(png, 20), 64);
    expect(png[24], 8); // bit depth
    expect(png[25], 6); // colour type RGBA
    expect(
      String.fromCharCodes(png.sublist(png.length - 8, png.length - 4)),
      'IEND',
    );
  });

  test('mascot blink differs from the open-eye frame only in the eyes', () {
    final open = PixelSprites.orangeMascot.rows;
    final blink = PixelSprites.orangeMascotBlink.rows;
    final differing = <int>[
      for (var i = 0; i < open.length; i++)
        if (open[i] != blink[i]) i,
    ];
    expect(differing, <int>[5, 6]);
  });
}
