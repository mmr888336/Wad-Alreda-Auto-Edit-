import 'package:auto_edit/motion_camera_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MotionCameraEngine', () {
    test('builds a fixed-size animated camera crop for video layers', () {
      final filter = MotionCameraEngine.buildFilter(
        duration: 2.5,
        style: CameraMotionStyle.cinematic,
        depth: 0.48,
        seed: 0,
        outputWidth: 1080,
        outputHeight: 1920,
      );

      expect(filter, contains("scale=w='ceil(iw*1.075/2)*2'"));
      expect(filter, contains('crop=w=1080:h=1920'));
      expect(filter, contains('cos(PI*'));
      expect(filter, contains(':y='));
    });

    test('uses different pan directions for different deterministic seeds', () {
      final first = MotionCameraEngine.buildFilter(
        duration: 3,
        style: CameraMotionStyle.energetic,
        depth: 0.5,
        seed: 0,
        outputWidth: 720,
        outputHeight: 1280,
      );
      final second = MotionCameraEngine.buildFilter(
        duration: 3,
        style: CameraMotionStyle.energetic,
        depth: 0.5,
        seed: 1,
        outputWidth: 720,
        outputHeight: 1280,
      );

      expect(first, isNot(second));
    });

    test('restores the original transparent layer dimensions after overscan', () {
      final filter = MotionCameraEngine.buildFilter(
        duration: 1.5,
        style: CameraMotionStyle.restrained,
        depth: 0.78,
        seed: 4,
      );

      expect(filter, contains("scale=w='ceil(iw*1.055/2)*2'"));
      expect(filter, contains('crop=w=trunc(iw/1.055)'));
      expect(filter, contains("x='(iw-ow)*"));
      expect(filter, contains("y='(ih-oh)*"));
    });

    test('rejects invalid duration, depth and incomplete output size', () {
      expect(
        () => MotionCameraEngine.buildFilter(
          duration: 0,
          style: CameraMotionStyle.cinematic,
          depth: 0.5,
        ),
        throwsArgumentError,
      );
      expect(
        () => MotionCameraEngine.buildFilter(
          duration: 2,
          style: CameraMotionStyle.cinematic,
          depth: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => MotionCameraEngine.buildFilter(
          duration: 2,
          style: CameraMotionStyle.cinematic,
          depth: 0.5,
          outputWidth: 1080,
        ),
        throwsArgumentError,
      );
    });
  });
}
