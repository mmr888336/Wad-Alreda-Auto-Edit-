import 'package:auto_edit/motion_scene_model.dart';
import 'package:auto_edit/motion_transitions.dart';
import 'package:flutter_test/flutter_test.dart';

MotionProject _project(List<MotionScene> scenes, {double duration = 10}) =>
    MotionProject(
      id: 'p',
      width: 1280,
      height: 720,
      frameRate: 30,
      duration: duration,
      scenes: scenes,
    );

void main() {
  group('MotionEasing', () {
    test('every curve starts at 0 and ends at 1', () {
      for (final ease in MotionEase.values) {
        expect(MotionEasing.apply(ease, 0), closeTo(0, 1e-9), reason: '$ease');
        expect(MotionEasing.apply(ease, 1), closeTo(1, 1e-9), reason: '$ease');
      }
    });

    test('input is clamped and NaN is treated as 0', () {
      expect(MotionEasing.apply(MotionEase.linear, -3), 0);
      expect(MotionEasing.apply(MotionEase.linear, 5), 1);
      expect(MotionEasing.apply(MotionEase.linear, double.nan), 0);
    });

    test('overshoot goes past 1 before settling', () {
      expect(MotionEasing.apply(MotionEase.overshoot, 0.7), greaterThan(1));
    });
  });

  group('MotionLayer.stateAt', () {
    const layer = MotionLayer(
      id: 'l',
      start: 10,
      end: 14,
      keyframes: <MotionKeyframe>[
        MotionKeyframe(
          time: 0,
          x: 0,
          y: 0,
          opacity: 0,
          easing: MotionEase.linear,
        ),
        MotionKeyframe(
          time: 2,
          x: 1,
          y: 0.5,
          opacity: 1,
          easing: MotionEase.linear,
        ),
      ],
    );

    test('interpolates between keyframes in layer-local time', () {
      final s = layer.stateAt(11);
      expect(s.x, closeTo(0.5, 1e-9));
      expect(s.y, closeTo(0.25, 1e-9));
      expect(s.opacity, closeTo(0.5, 1e-9));
    });

    test('holds the first and last keyframe outside their range', () {
      expect(layer.stateAt(5).x, 0);
      expect(layer.stateAt(13.5).x, 1);
    });

    test('without keyframes the static values are used', () {
      const still = MotionLayer(
        id: 's',
        start: 0,
        end: 1,
        x: 0.2,
        y: 0.8,
        scale: 2,
        opacity: 3,
      );
      final s = still.stateAt(0.5);
      expect(s.x, 0.2);
      expect(s.y, 0.8);
      expect(s.scale, 2);
      expect(s.opacity, 1); // clamped
    });

    test('active range is start inclusive and end exclusive', () {
      expect(layer.isActiveAt(10), isTrue);
      expect(layer.isActiveAt(13.99), isTrue);
      expect(layer.isActiveAt(14), isFalse);
      expect(layer.isActiveAt(9.99), isFalse);
    });
  });

  group('MotionProject', () {
    test('layersAt returns active layers sorted by zIndex', () {
      final project = _project(<MotionScene>[
        const MotionScene(
          id: 's1',
          start: 0,
          end: 5,
          transitionIn: MotionTransitionKind.hardCut,
          layers: <MotionLayer>[
            MotionLayer(id: 'top', start: 0, end: 5, zIndex: 9),
            MotionLayer(id: 'bottom', start: 0, end: 5, zIndex: 1),
            MotionLayer(id: 'later', start: 3, end: 5, zIndex: 4),
          ],
        ),
      ]);
      expect(project.layersAt(1).map((l) => l.id), <String>['bottom', 'top']);
      expect(
        project.layersAt(4).map((l) => l.id),
        <String>['bottom', 'later', 'top'],
      );
      expect(project.layersAt(6), isEmpty);
    });

    test('validate accepts a consistent project', () {
      final project = _project(<MotionScene>[
        const MotionScene(
          id: 's1',
          start: 0,
          end: 5,
          layers: <MotionLayer>[MotionLayer(id: 'a', start: 0, end: 5)],
        ),
        const MotionScene(
          id: 's2',
          start: 5,
          end: 10,
          layers: <MotionLayer>[MotionLayer(id: 'b', start: 5, end: 10)],
        ),
      ]);
      expect(project.validate, returnsNormally);
    });

    test('validate rejects bad canvas, overlaps and stray layers', () {
      expect(
        MotionProject(
          id: 'bad',
          width: 0,
          height: 720,
          frameRate: 30,
          duration: 10,
          scenes: const <MotionScene>[],
        ).validate,
        throwsStateError,
      );
      expect(
        _project(<MotionScene>[
          const MotionScene(id: 'a', start: 0, end: 6, layers: <MotionLayer>[]),
          const MotionScene(id: 'b', start: 5, end: 10, layers: <MotionLayer>[]),
        ]).validate,
        throwsStateError,
      );
      expect(
        _project(<MotionScene>[
          const MotionScene(
            id: 'a',
            start: 0,
            end: 5,
            layers: <MotionLayer>[MotionLayer(id: 'x', start: 0, end: 6)],
          ),
        ]).validate,
        throwsStateError,
      );
      expect(
        _project(<MotionScene>[
          const MotionScene(
            id: 'a',
            start: 0,
            end: 5,
            layers: <MotionLayer>[
              MotionLayer(
                id: 'k',
                start: 0,
                end: 2,
                keyframes: <MotionKeyframe>[
                  MotionKeyframe(time: 3, x: 0, y: 0),
                ],
              ),
            ],
          ),
        ]).validate,
        throwsStateError,
      );
    });
  });
}
