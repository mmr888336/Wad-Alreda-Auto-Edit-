import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:auto_edit/scene_frame_guard.dart';

Uint8List _solid(int w, int h, int r, int g, int b) {
  final data = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    data[i * 4] = r;
    data[i * 4 + 1] = g;
    data[i * 4 + 2] = b;
    data[i * 4 + 3] = 255;
  }
  return data;
}

void main() {
  test('green band is detected', () {
    expect(SceneFrameGuard.greenShare(_solid(8, 8, 60, 230, 0), 8, 8), 1.0);
  });

  test('skin, wood and dark scene colors are not green', () {
    expect(SceneFrameGuard.greenShare(_solid(8, 8, 200, 150, 120), 8, 8), 0.0);
    expect(SceneFrameGuard.greenShare(_solid(8, 8, 16, 21, 33), 8, 8), 0.0);
    expect(SceneFrameGuard.greenShare(_solid(8, 8, 120, 160, 90), 8, 8), 0.0);
  });

  test('corrupt rules', () {
    expect(SceneFrameGuard.isCorrupt(const <double>[0, 0.12, 0]), isTrue);
    expect(SceneFrameGuard.isCorrupt(const <double>[0.05, 0, 0.05]), isTrue);
    expect(SceneFrameGuard.isCorrupt(const <double>[0.05, 0, 0]), isFalse);
    expect(SceneFrameGuard.isCorrupt(const <double>[]), isFalse);
  });
}
