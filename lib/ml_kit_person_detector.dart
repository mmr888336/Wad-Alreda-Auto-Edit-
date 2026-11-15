import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'person_tracking_models.dart';
import 'visual_tracking_engine.dart';

/// [PersonDetector] backed by Google ML Kit pose detection.
///
/// ML Kit reports at most one pose per image (the most prominent person), so
/// this detector gives reliable single-person tracking. Multi-person support
/// needs a different detector behind the same [PersonDetector] interface.
class MlKitPersonDetector implements PersonDetector {
  MlKitPersonDetector({PoseDetectionModel model = PoseDetectionModel.base})
      : _detector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.single,
            model: model,
          ),
        );

  final PoseDetector _detector;

  @override
  Future<List<PersonDetection>> detect(PersonFrame frame) async {
    final poses = await _detector.processImage(
      InputImage.fromFilePath(frame.path),
    );

    final detections = <PersonDetection>[];
    for (final pose in poses) {
      final raw = pose.landmarks.values.map(
        (landmark) => RawLandmark(
          name: landmark.type.name,
          x: landmark.x,
          y: landmark.y,
          z: landmark.z,
          likelihood: landmark.likelihood,
        ),
      );

      final detection = PersonDetectionFactory.fromPixelLandmarks(
        raw,
        width: frame.width,
        height: frame.height,
      );
      if (detection != null) detections.add(detection);
    }
    return detections;
  }

  @override
  Future<void> dispose() => _detector.close();
}
