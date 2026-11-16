import 'three_d_stage_log.dart';

/// Live progress of the 3D phase of an export:
/// search -> download -> GLB inspection -> Filament -> capture -> person
/// tracking -> compositing.
class ThreeDProgress {
  const ThreeDProgress({
    required this.fraction,
    required this.message,
    this.stage,
    this.scene = 0,
    this.sceneCount = 0,
  });

  /// 0..1 across the whole 3D phase.
  final double fraction;

  /// One line that says exactly what the app is doing right now.
  final String message;

  /// Stage in progress, or null for phase-level steps such as tracking.
  final ThreeDStage? stage;

  /// 1-based scene number, 0 when the step is not tied to one scene.
  final int scene;

  final int sceneCount;

  /// Maps the 3D phase onto a slice of the whole export bar.
  double overall({double from = 0.80, double to = 0.98}) {
    final value = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0).toDouble();
    return from + (to - from) * value;
  }
}
