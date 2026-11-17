import 'package:auto_edit/motion_ffmpeg_adapter.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:flutter_test/flutter_test.dart';

int _count(String text, String char) => char.allMatches(text).length;

MotionProject _project(List<MotionLayer> layers) => MotionProject(
      id: 'p',
      width: 720,
      height: 1280,
      frameRate: 30,
      duration: 3,
      scenes: <MotionScene>[
        MotionScene(id: 's', start: 0, end: 3, layers: layers),
      ],
    );

const _assets = <String, MotionRenderAsset>{
  'sprite': MotionRenderAsset(
    path: '/tmp/sprite.png',
    aspect: 1.0,
    widthFraction: 0.3,
  ),
};

void main() {
  test('animated rotation uses the rotate filter on a transparent canvas', () {
    final plan = MotionFfmpegAdapter.build(
      project: _project(const <MotionLayer>[
        MotionLayer(
          id: 'a',
          start: 0,
          end: 3,
          assetKey: 'sprite',
          keyframes: <MotionKeyframe>[
            MotionKeyframe(
              time: 0,
              x: 0.5,
              y: 0.5,
              rotation: -20,
              easing: MotionEase.linear,
            ),
            MotionKeyframe(
              time: 1,
              x: 0.5,
              y: 0.5,
              rotation: 30,
              easing: MotionEase.linear,
            ),
          ],
        ),
      ]),
      assets: _assets,
    );
    final f = plan.filterComplex;
    expect(f, contains("rotate=a='"));
    expect(f, contains('c=none'));
    expect(f, contains('*PI/180'));
    expect(f, contains("ow='hypot(iw,ih)'"));
    expect(_count(f, '('), _count(f, ')'));
  });

  test('static rotation is applied and unrotated layers have no rotate', () {
    final rotated = MotionFfmpegAdapter.build(
      project: _project(const <MotionLayer>[
        MotionLayer(id: 'a', start: 0, end: 3, assetKey: 'sprite', rotation: 15),
      ]),
      assets: _assets,
    );
    expect(rotated.filterComplex, contains('rotate=a='));

    final plain = MotionFfmpegAdapter.build(
      project: _project(const <MotionLayer>[
        MotionLayer(id: 'a', start: 0, end: 3, assetKey: 'sprite'),
      ]),
      assets: _assets,
    );
    expect(plain.filterComplex, isNot(contains('rotate=')));
  });
}
