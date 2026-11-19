import 'dart:typed_data';

import 'package:auto_edit/caption_lane_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usual lane is kept when scores are close', () {
    expect(CaptionLanePlanner.pickLane(<double>[10, 11, 10.5]), 0.80);
  });

  test('a clearly calmer lane replaces a busy usual lane', () {
    expect(CaptionLanePlanner.pickLane(<double>[4, 20, 12]), 0.72);
    expect(CaptionLanePlanner.pickLane(<double>[20, 20, 3]), 0.88);
  });

  test('wrong score count falls back to the usual lane', () {
    expect(CaptionLanePlanner.pickLane(<double>[1, 2]), 0.80);
  });

  test('flat band has no detail, striped band has detail', () {
    const w = 40, h = 80;
    final flat = Uint8List(w * h)..fillRange(0, w * h, 128);
    expect(CaptionLanePlanner.bandDetail(flat, w, h, 0.8), 0);
    final striped = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      striped[i] = (i % 2 == 0) ? 0 : 255;
    }
    expect(CaptionLanePlanner.bandDetail(striped, w, h, 0.8), greaterThan(100));
  });
}
