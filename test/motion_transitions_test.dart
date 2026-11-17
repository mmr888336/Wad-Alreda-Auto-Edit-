import 'package:auto_edit/motion_transitions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hard cut has no xfade and returns null', () {
    expect(MotionTransitions.xfadeName(MotionTransitionKind.hardCut), isNull);
    expect(
      MotionTransitions.buildXfade(
        inputA: 'v0',
        inputB: 'v1',
        output: 'vout',
        kind: MotionTransitionKind.hardCut,
        offset: 2,
      ),
      isNull,
    );
  });

  test('every other kind maps to an xfade name and a positive duration', () {
    for (final kind in MotionTransitionKind.values) {
      if (kind == MotionTransitionKind.hardCut) continue;
      expect(MotionTransitions.xfadeName(kind), isNotNull, reason: '$kind');
      expect(
        MotionTransitions.defaultDuration(kind),
        greaterThan(0),
        reason: '$kind',
      );
    }
  });

  test('buildXfade produces a labelled filter with offset and duration', () {
    final filter = MotionTransitions.buildXfade(
      inputA: 'v0',
      inputB: 'v1',
      output: 'vout',
      kind: MotionTransitionKind.pixelBlockWipe,
      offset: 4.6,
      duration: 0.4,
    );
    expect(
      filter,
      '[v0][v1]xfade=transition=pixelize:duration=0.400:offset=4.600[vout]',
    );
  });

  test('duration is clamped and defaults are used when omitted', () {
    final tooLong = MotionTransitions.buildXfade(
      inputA: 'a',
      inputB: 'b',
      output: 'c',
      kind: MotionTransitionKind.whipPan,
      offset: 1,
      duration: 99,
    );
    expect(tooLong, contains('duration=2.000'));

    final defaulted = MotionTransitions.buildXfade(
      inputA: 'a',
      inputB: 'b',
      output: 'c',
      kind: MotionTransitionKind.whipPan,
      offset: 1,
    );
    expect(defaulted, contains('duration=0.400'));
  });

  test('invalid labels and offsets are rejected', () {
    expect(
      () => MotionTransitions.buildXfade(
        inputA: 'v0];drawtext=[x',
        inputB: 'v1',
        output: 'o',
        kind: MotionTransitionKind.matchCut,
        offset: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => MotionTransitions.buildXfade(
        inputA: 'v0',
        inputB: 'v1',
        output: 'o',
        kind: MotionTransitionKind.matchCut,
        offset: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => MotionTransitions.buildXfade(
        inputA: 'v0',
        inputB: 'v1',
        output: 'o',
        kind: MotionTransitionKind.matchCut,
        offset: double.nan,
      ),
      throwsArgumentError,
    );
  });
}
