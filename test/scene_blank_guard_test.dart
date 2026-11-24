import 'dart:typed_data';

import 'package:auto_edit/scene_frame_guard.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = a;
  }
  return bytes;
}

/// Left half dark, right half bright: a scene with something in it.
Uint8List _split(int w, int h) {
  final bytes = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      final bright = x >= w ~/ 2;
      bytes[o] = bright ? 230 : 30;
      bytes[o + 1] = bright ? 210 : 40;
      bytes[o + 2] = bright ? 190 : 60;
      bytes[o + 3] = 255;
    }
  }
  return bytes;
}

FrameStats _stats(Uint8List pixels, int w, int h) =>
    SceneFrameGuard.frameStats(pixels, w, h)!;

void main() {
  group('frame statistics', () {
    test('a black frame is blank', () {
      final stats = _stats(_solid(8, 8, 0, 0, 0), 8, 8);
      expect(stats.dark, 1.0);
      expect(stats.isBlank, isTrue);
    });

    test('a transparent frame is blank', () {
      final stats = _stats(_solid(8, 8, 90, 120, 200, 0), 8, 8);
      expect(stats.transparent, 1.0);
      expect(stats.isBlank, isTrue);
    });

    test('one flat colour is blank even when it is bright', () {
      final stats = _stats(_solid(8, 8, 180, 180, 180), 8, 8);
      expect(stats.dark, 0.0);
      expect(stats.deviation, lessThan(SceneFrameGuard.flatDeviation));
      expect(stats.isBlank, isTrue);
    });

    test('a scene with a dark side and a lit side is not blank', () {
      final stats = _stats(_split(8, 8), 8, 8);
      expect(stats.isBlank, isFalse);
      expect(stats.dark, 0.0);
    });

    test('a dark but lit scene colour is not black', () {
      // The old placeholder of the view, rgb(13, 16, 25), is black; a night
      // room wall (rgb(32, 40, 62)) is not.
      expect(_stats(_solid(8, 8, 13, 16, 25), 8, 8).dark, 1.0);
      expect(_stats(_solid(8, 8, 32, 40, 62), 8, 8).dark, 0.0);
    });

    test('a buffer that is too small gives no statistics', () {
      expect(SceneFrameGuard.frameStats(Uint8List(8), 8, 8), isNull);
      expect(SceneFrameGuard.frameStats(Uint8List(0), 0, 0), isNull);
    });
  });

  group('clip verdict', () {
    final black = _stats(_solid(8, 8, 0, 0, 0), 8, 8);
    final scene = _stats(_split(8, 8), 8, 8);
    final green = _stats(_solid(8, 8, 60, 230, 0), 8, 8);

    test('a clip of black frames is rejected as blank', () {
      expect(
        SceneFrameGuard.verdictOf(<FrameStats>[black, black, black, black]),
        SceneFrameVerdict.blank,
      );
    });

    test('three black frames of four reject the clip', () {
      expect(
        SceneFrameGuard.verdictOf(<FrameStats>[black, black, black, scene]),
        SceneFrameVerdict.blank,
      );
    });

    test('half black frames do not reject it (a fade or a dark moment)', () {
      expect(
        SceneFrameGuard.verdictOf(<FrameStats>[black, scene, black, scene]),
        SceneFrameVerdict.clean,
      );
    });

    test('a lit scene is clean', () {
      expect(
        SceneFrameGuard.verdictOf(<FrameStats>[scene, scene, scene]),
        SceneFrameVerdict.clean,
      );
    });

    test('green frames are rejected as green, before the blank check', () {
      expect(
        SceneFrameGuard.verdictOf(<FrameStats>[green, black, black]),
        SceneFrameVerdict.green,
      );
    });

    test('no inspected frame means the clip is accepted', () {
      expect(
        SceneFrameGuard.verdictOf(const <FrameStats>[]),
        SceneFrameVerdict.clean,
      );
    });

    test('the blank check can be switched off', () {
      expect(
        SceneFrameGuard.verdictOf(
          <FrameStats>[black, black, black],
          checkBlank: false,
        ),
        SceneFrameVerdict.clean,
      );
    });
  });
}
