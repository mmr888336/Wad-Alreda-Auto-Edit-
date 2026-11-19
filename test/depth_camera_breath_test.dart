import 'package:auto_edit/depth_camera_engine.dart';
import 'package:auto_edit/depth_camera_model.dart';
import 'package:flutter_test/flutter_test.dart';

int _count(String text, String char) => char.allMatches(text).length;

void main() {
  group('living camera (handheld drift)', () {
    setUp(() => DepthCameraEngine.breathing = true);
    tearDown(() => DepthCameraEngine.breathing = true);

    const camera = SceneCamera(move: DepthCameraMove.pushIn, intensity: 1);

    CameraSample plain(double progress, double depth) {
      DepthCameraEngine.breathing = false;
      final s = DepthCameraEngine.sample(
        camera: camera,
        depth: depth,
        progress: progress,
      );
      DepthCameraEngine.breathing = true;
      return s;
    }

    test('the drift is zero at the start and at the end of a scene', () {
      for (final p in <double>[0.0, 1.0]) {
        final live = DepthCameraEngine.sample(
          camera: camera,
          depth: 0.5,
          progress: p,
        );
        final base = plain(p, 0.5);
        expect(live.dx, closeTo(base.dx, 1e-9));
        expect(live.dy, closeTo(base.dy, 1e-9));
        expect(live.zoom, closeTo(base.zoom, 1e-12));
      }
    });

    test('the camera keeps drifting inside the scene', () {
      final liveX = DepthCameraEngine.sample(
        camera: camera,
        depth: 0.5,
        progress: 0.25,
      );
      expect(liveX.dx - plain(0.25, 0.5).dx, greaterThan(0));
      final liveY = DepthCameraEngine.sample(
        camera: camera,
        depth: 0.5,
        progress: 0.125,
      );
      expect(liveY.dy - plain(0.125, 0.5).dy, greaterThan(0));
    });

    test('near layers drift more than far layers and stay tiny', () {
      final near = DepthCameraEngine.sample(
            camera: camera,
            depth: 1,
            progress: 0.25,
          ).dx -
          plain(0.25, 1).dx;
      final far = DepthCameraEngine.sample(
            camera: camera,
            depth: 0,
            progress: 0.25,
          ).dx -
          plain(0.25, 0).dx;
      expect(near, greaterThan(far));
      expect(near, lessThan(0.01));
    });

    test('expressions carry the drift and stay balanced', () {
      final e = DepthCameraEngine.expressions(
        camera: camera,
        depth: 0.6,
        duration: 2.0,
        xExpr: '0.5',
        yExpr: '0.3',
        scaleExpr: '1.0',
      );
      expect(e.x, contains('sin(2*PI*'));
      expect(e.y, contains('sin(4*PI*'));
      for (final text in <String>[e.x, e.y, e.scale]) {
        expect(_count(text, '('), _count(text, ')'));
      }
    });

    test('switching the drift off gives the plain move expressions', () {
      DepthCameraEngine.breathing = false;
      final e = DepthCameraEngine.expressions(
        camera: camera,
        depth: 0.6,
        duration: 2.0,
        xExpr: '0.5',
        yExpr: '0.3',
        scaleExpr: '1.0',
      );
      expect(e.x, isNot(contains('sin(')));
      expect(e.y, isNot(contains('sin(')));
      expect(e.x, contains('cos(PI*'));
    });

    test('a full-canvas background still covers the canvas', () {
      for (final move in DepthCameraMove.values) {
        final live = DepthCameraEngine.coverScale(
          SceneCamera(move: move, intensity: 1),
          0,
        );
        expect(live, inInclusiveRange(1.0, DepthCameraEngine.maxCoverScale));
      }
    });
  });
}
