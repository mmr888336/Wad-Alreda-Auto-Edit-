import 'package:auto_edit/motion_ffmpeg_adapter.dart';
import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/motion_transitions.dart';
import 'package:flutter_test/flutter_test.dart';

int _count(String text, String char) => char.allMatches(text).length;

MotionProject _project(List<MotionScene> scenes, {double duration = 10}) =>
    MotionProject(
      id: 'p',
      width: 1280,
      height: 720,
      frameRate: 30,
      duration: duration,
      scenes: scenes,
    );

const _assets = <String, MotionRenderAsset>{
  'pixel_camera': MotionRenderAsset(path: '/tmp/camera.png'),
};

void main() {
  group('keyframeExpression', () {
    test('two linear keyframes become one balanced piecewise expression', () {
      final expr = MotionFfmpegAdapter.keyframeExpression(
        const <MotionKeyframe>[
          MotionKeyframe(time: 0, x: 0, y: 0, easing: MotionEase.linear),
          MotionKeyframe(time: 1, x: 1, y: 0, easing: MotionEase.linear),
        ],
        (k) => k.x,
        timeVar: 'T',
      );
      expect(expr, contains('lt(T,1.0000)'));
      expect(expr, contains('1.0000*(T-0.0000)'));
      expect(_count(expr, '('), _count(expr, ')'));
    });

    test('constant values collapse to a number', () {
      final expr = MotionFfmpegAdapter.keyframeExpression(
        const <MotionKeyframe>[
          MotionKeyframe(time: 0, x: 0.5, y: 0),
          MotionKeyframe(time: 2, x: 0.5, y: 0),
        ],
        (k) => k.x,
        timeVar: 'T',
      );
      expect(expr, '0.5000');
    });

    test('eased segments are sampled and negatives are parenthesised', () {
      final expr = MotionFfmpegAdapter.keyframeExpression(
        const <MotionKeyframe>[
          MotionKeyframe(time: 0, x: -0.3, y: 0, easing: MotionEase.linear),
          MotionKeyframe(time: 1, x: 0.5, y: 0, easing: MotionEase.easeOut),
        ],
        (k) => k.x,
        timeVar: 'T',
      );
      expect(expr, contains('(-0.3000)'));
      expect('if(lt('.allMatches(expr).length, 7));
      expect(_count(expr, '('), _count(expr, ')'));
    });

    test('empty or unsorted keyframes are rejected', () {
      expect(
        () => MotionFfmpegAdapter.keyframeExpression(
          const <MotionKeyframe>[],
          (k) => k.x,
          timeVar: 'T',
        ),
        throwsArgumentError,
      );
      expect(
        () => MotionFfmpegAdapter.keyframeExpression(
          const <MotionKeyframe>[
            MotionKeyframe(time: 2, x: 0, y: 0),
            MotionKeyframe(time: 1, x: 1, y: 0),
          ],
          (k) => k.x,
          timeVar: 'T',
        ),
        throwsArgumentError,
      );
    });
  });

  group('MotionFfmpegAdapter.build', () {
    test('single scene builds background, scaled layer and overlay', () {
      final plan = MotionFfmpegAdapter.build(
        project: _project(<MotionScene>[
          const MotionScene(
            id: 's',
            start: 0,
            end: 5,
            layers: <MotionLayer>[
              MotionLayer(
                id: 'cam',
                start: 1,
                end: 4,
                assetKey: 'pixel_camera',
                keyframes: <MotionKeyframe>[
                  MotionKeyframe(
                    time: 0,
                    x: 0.2,
                    y: 0.5,
                    opacity: 0,
                    easing: MotionEase.linear,
                  ),
                  MotionKeyframe(
                    time: 1,
                    x: 0.5,
                    y: 0.5,
                    opacity: 1,
                    easing: MotionEase.linear,
                  ),
                ],
              ),
            ],
          ),
        ]),
        assets: _assets,
      );
      final f = plan.filterComplex;
      expect(f, contains('color=c=0x000000:s=1280x720:r=30:d=5.000'));
      expect(f, contains("geq=r='r(X,Y)'"));
      expect(f, contains('flags=neighbor'));
      expect(f, contains("enable='between(t,1.000,4.000)'"));
      expect(f, contains('[sc0]'));
      expect(plan.outputLabel, 'sc0');
      expect(plan.inputs.length, 1);
      expect(plan.inputs.first.duration, 5);
      expect(plan.totalDuration, 5);
      expect(plan.skippedLayerIds, isEmpty);
      expect(_count(f, '('), _count(f, ')'));
    });

    test('opaque static layers skip the opacity filter', () {
      final plan = MotionFfmpegAdapter.build(
        project: _project(<MotionScene>[
          const MotionScene(
            id: 's',
            start: 0,
            end: 5,
            layers: <MotionLayer>[
              MotionLayer(
                id: 'cam',
                start: 0,
                end: 5,
                assetKey: 'pixel_camera',
              ),
            ],
          ),
        ]),
        assets: _assets,
      );
      expect(plan.filterComplex, isNot(contains('geq')));
    });

    test('layers without a registered asset are skipped and reported', () {
      final plan = MotionFfmpegAdapter.build(
        project: _project(<MotionScene>[
          const MotionScene(
            id: 's',
            start: 0,
            end: 5,
            layers: <MotionLayer>[
              MotionLayer(id: 'missing', start: 0, end: 5, assetKey: 'nope'),
              MotionLayer(id: 'title', start: 0, end: 5, text: 'Hi'),
            ],
          ),
        ]),
        assets: _assets,
      );
      expect(plan.skippedLayerIds, <String>['missing', 'title']);
      expect(plan.inputs, isEmpty);
    });

    test('text layers use a pre-rendered asset registered as text:<id>', () {
      final plan = MotionFfmpegAdapter.build(
        project: _project(<MotionScene>[
          const MotionScene(
            id: 's',
            start: 0,
            end: 5,
            layers: <MotionLayer>[
              MotionLayer(id: 'title', start: 0, end: 5, text: 'Hi'),
            ],
          ),
        ]),
        assets: const <String, MotionRenderAsset>{
          'text:title': MotionRenderAsset(
            path: '/tmp/title.png',
            aspect: 0.25,
            widthFraction: 0.8,
          ),
        },
      );
      expect(plan.inputs.single.path, '/tmp/title.png');
      expect(plan.skippedLayerIds, isEmpty);
    });

    test('xfade transition overlaps scenes and shortens the total', () {
      final plan = MotionFfmpegAdapter.build(
        project: _project(<MotionScene>[
          const MotionScene(
            id: 'a',
            start: 0,
            end: 5,
            layers: <MotionLayer>[],
          ),
          const MotionScene(
            id: 'b',
            start: 5,
            end: 10,
            transitionIn: MotionTransitionKind.pixelBlockWipe,
            layers: <MotionLayer>[],
          ),
        ]),
        assets: _assets,
      );
      expect(
        plan.filterComplex,
        contains(
          '[sc0][sc1]xfade=transition=pixelize:duration=0.500:offset=4.500[m1]',
        ),
      );
      expect(plan.outputLabel, 'm1');
      expect(plan.totalDuration, closeTo(9.5, 1e-9));
    });

    test('hard cut joins scenes with concat', () {
      final plan = MotionFfmpegAdapter.build(
        project: _project(<MotionScene>[
          const MotionScene(
            id: 'a',
            start: 0,
            end: 5,
            layers: <MotionLayer>[],
          ),
          const MotionScene(
            id: 'b',
            start: 5,
            end: 10,
            layers: <MotionLayer>[],
          ),
        ]),
        assets: _assets,
      );
      expect(plan.filterComplex, contains('[sc0][sc1]concat=n=2:v=1:a=0[m1]'));
      expect(plan.totalDuration, 10);
    });

    test('arguments list ends with the output path and maps the output', () {
      final plan = MotionFfmpegAdapter.build(
        project: _project(<MotionScene>[
          const MotionScene(
            id: 's',
            start: 0,
            end: 5,
            layers: <MotionLayer>[
              MotionLayer(
                id: 'cam',
                start: 0,
                end: 5,
                assetKey: 'pixel_camera',
              ),
            ],
          ),
        ]),
        assets: _assets,
      );
      final args = plan.arguments(outputPath: '/tmp/out.mp4');
      expect(args.first, '-loop');
      expect(args, contains('/tmp/camera.png'));
      expect(args, contains('-filter_complex'));
      expect(args[args.indexOf('-map') + 1], '[sc0]');
      expect(args.last, '/tmp/out.mp4');
    });

    test('invalid background and empty projects are rejected', () {
      expect(
        () => MotionFfmpegAdapter.build(
          project: _project(<MotionScene>[
            const MotionScene(
              id: 's',
              start: 0,
              end: 5,
              background: '#GGGGGG',
              layers: <MotionLayer>[],
            ),
          ]),
          assets: _assets,
        ),
        throwsArgumentError,
      );
      expect(
        () => MotionFfmpegAdapter.build(
          project: _project(const <MotionScene>[]),
          assets: _assets,
        ),
        throwsStateError,
      );
    });
  });
}
