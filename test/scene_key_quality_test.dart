import 'dart:typed_data';

import 'package:auto_edit/scene_key_quality.dart';
import 'package:flutter_test/flutter_test.dart';

const int _size = 64;
const List<int> _bg = <int>[13, 16, 25];
const List<int> _model = <int>[220, 200, 150];

// A flat studio background with the [paint] callback drawing the subject.
Uint8List _image(void Function(void Function(int, int, List<int>) set) paint) {
  final rgba = Uint8List(_size * _size * 4);
  void set(int x, int y, List<int> c) {
    final o = (y * _size + x) * 4;
    rgba[o] = c[0];
    rgba[o + 1] = c[1];
    rgba[o + 2] = c[2];
    rgba[o + 3] = 255;
  }

  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      set(x, y, _bg);
    }
  }
  paint(set);
  return rgba;
}

void _box(
  void Function(int, int, List<int>) set,
  int left,
  int top,
  int size,
) {
  for (var y = top; y < top + size; y++) {
    for (var x = left; x < left + size; x++) {
      set(x, y, _model);
    }
  }
}

const List<String> _key = <String>['0x0D1019'];

void main() {
  group('SceneKeyQuality', () {
    test('one solid model is clean and keeps its key', () {
      final rgba = _image((set) => _box(set, 16, 16, 32));

      final quality = SceneKeyQuality.measure(rgba, _size, _size, _key);
      expect(quality.blobCount, 1);
      expect(quality.largestShare, closeTo(1, 1e-9));
      expect(quality.foregroundShare, closeTo(32 * 32 / (64 * 64), 1e-9));
      expect(quality.isClean, isTrue);
      expect(SceneKeyQuality.keepIfClean(rgba, _size, _size, _key), _key);
    });

    test('a model that fell into scattered fragments is not keyed', () {
      // Sixteen separate 6x6 pieces: what is left when the dark parts of a
      // model are eaten by the key.
      final rgba = _image((set) {
        for (var row = 0; row < 4; row++) {
          for (var col = 0; col < 4; col++) {
            _box(set, 4 + col * 14, 4 + row * 14, 6);
          }
        }
      });

      final quality = SceneKeyQuality.measure(rgba, _size, _size, _key);
      expect(quality.blobCount, 16);
      expect(quality.largestShare, closeTo(1 / 16, 1e-9));
      expect(quality.isClean, isFalse);
      expect(SceneKeyQuality.keepIfClean(rgba, _size, _size, _key), isEmpty);
    });

    test('a few tiny specks beside a solid model are tolerated', () {
      final rgba = _image((set) {
        _box(set, 16, 16, 32);
        _box(set, 2, 2, 2);
        _box(set, 58, 58, 2);
      });

      final quality = SceneKeyQuality.measure(rgba, _size, _size, _key);
      expect(quality.blobCount, 3);
      expect(quality.largestShare, greaterThan(0.9));
      expect(quality.isClean, isTrue);
    });

    test('an empty scene has nothing to show and is not keyed', () {
      final rgba = _image((set) {});

      final quality = SceneKeyQuality.measure(rgba, _size, _size, _key);
      expect(quality.foregroundShare, 0);
      expect(quality.blobCount, 0);
      expect(quality.isClean, isFalse);
      expect(SceneKeyQuality.keepIfClean(rgba, _size, _size, _key), isEmpty);
    });

    test('a tiny subject is not worth keying', () {
      // 6x6 of 64x64 is under one percent of the frame.
      final rgba = _image((set) => _box(set, 29, 29, 6));

      final quality = SceneKeyQuality.measure(rgba, _size, _size, _key);
      expect(quality.foregroundShare, lessThan(0.04));
      expect(SceneKeyQuality.keepIfClean(rgba, _size, _size, _key), isEmpty);
    });

    test('background noise within the tolerance still counts as background',
        () {
      final rgba = _image((set) => _box(set, 16, 16, 32));
      // Compression-like noise on a background pixel.
      rgba[0] = 13 + 20;
      rgba[1] = 16 - 10;

      final quality = SceneKeyQuality.measure(rgba, _size, _size, _key);
      expect(quality.blobCount, 1);
      expect(quality.isClean, isTrue);
    });

    test('no key colors means nothing to key', () {
      final rgba = _image((set) => _box(set, 16, 16, 32));

      expect(
        SceneKeyQuality.keepIfClean(rgba, _size, _size, const <String>[]),
        isEmpty,
      );
    });

    test('colors parse with or without the 0x prefix', () {
      expect(SceneKeyQuality.parseColor('0x0D1019'), 0x0D1019);
      expect(SceneKeyQuality.parseColor('0D1019'), 0x0D1019);
      expect(SceneKeyQuality.parseColor('0xZZ'), isNull);
    });

    test('a buffer that is too short measures as empty', () {
      final quality = SceneKeyQuality.measure(
        Uint8List(10),
        _size,
        _size,
        _key,
      );
      expect(quality.isClean, isFalse);
    });
  });
}
