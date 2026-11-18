import 'package:auto_edit/caption_motion_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    CaptionMotionGate.enabled = true;
  });

  test('with no window the caption keeps its plain enable expression', () {
    expect(
      CaptionMotionGate.enableExpression(
        start: 1,
        end: 3,
        windows: const <List<double>>[],
      ),
      'between(t,1.00,3.00)',
    );
  });

  test('a cutaway window inside the caption switches it off there', () {
    expect(
      CaptionMotionGate.enableExpression(
        start: 1,
        end: 3,
        windows: const <List<double>>[
          <double>[1.5, 2.0],
        ],
      ),
      'between(t,1.00,3.00)*not(between(t,1.50,2.00))',
    );
  });

  test('every overlapping window is excluded, in order', () {
    final expression = CaptionMotionGate.enableExpression(
      start: 1,
      end: 6,
      windows: const <List<double>>[
        <double>[0.5, 2.0],
        <double>[4.0, 5.0],
      ],
    );
    expect(
      expression,
      'between(t,1.00,6.00)'
      '*not(between(t,0.50,2.00))'
      '*not(between(t,4.00,5.00))',
    );
  });

  test('windows that do not touch the caption are ignored', () {
    expect(
      CaptionMotionGate.enableExpression(
        start: 5,
        end: 7,
        windows: const <List<double>>[
          <double>[1.0, 2.0],
          <double>[7.0, 9.0],
          <double>[3.0, 5.0],
        ],
      ),
      'between(t,5.00,7.00)',
    );
  });

  test('empty, reversed, short and non-finite windows are ignored', () {
    expect(
      CaptionMotionGate.enableExpression(
        start: 1,
        end: 3,
        windows: <List<double>>[
          const <double>[2.0, 2.0],
          const <double>[2.5, 2.0],
          const <double>[2.0],
          <double>[double.nan, 2.0],
          <double>[1.5, double.infinity],
        ],
      ),
      'between(t,1.00,3.00)',
    );
  });

  test('the switch restores captions over cutaways', () {
    CaptionMotionGate.enabled = false;
    expect(
      CaptionMotionGate.enableExpression(
        start: 1,
        end: 3,
        windows: const <List<double>>[
          <double>[1.5, 2.0],
        ],
      ),
      'between(t,1.00,3.00)',
    );
  });

  test('the expression has balanced brackets and quotes nothing', () {
    final expression = CaptionMotionGate.enableExpression(
      start: 0,
      end: 10,
      windows: const <List<double>>[
        <double>[1.0, 2.0],
        <double>[3.0, 4.0],
      ],
    );
    expect('('.allMatches(expression).length, ')'.allMatches(expression).length);
    expect(expression.contains("'"), isFalse);
  });
}
