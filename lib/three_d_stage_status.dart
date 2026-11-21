import 'three_d_stage_log.dart';

/// Where one stage of the 3D export stands, read from the on-disk log.
enum ThreeDStageStatus { notRun, started, succeeded, failed }

class ThreeDStageStatusReader {
  ThreeDStageStatusReader._();

  /// The stages of the world path, in execution order.
  static const List<ThreeDStage> worldStages = <ThreeDStage>[
    ThreeDStage.worldPlan,
    ThreeDStage.worldGlb,
    ThreeDStage.inspect,
    ThreeDStage.filamentLoad,
    ThreeDStage.manualCamera,
    ThreeDStage.ready,
    ThreeDStage.capture,
    ThreeDStage.rendererRelease,
    ThreeDStage.worldFlat,
    ThreeDStage.worldFallback,
    ThreeDStage.worldComposite,
  ];

  /// Failed wins over succeeded (any scene), succeeded over a start line that
  /// never finished.
  static ThreeDStageStatus statusOf(String log, ThreeDStage stage) {
    final failed = '] ${stage.label}: فشل';
    final done = '] ${stage.label}: نجح';
    final began = '] ${stage.label}: بدأ';

    var hasDone = false;
    var hasBegan = false;

    for (final raw in log.split('\n')) {
      final line = raw.trim();

      if (line.contains(failed)) return ThreeDStageStatus.failed;
      if (line.contains(done)) hasDone = true;
      if (line.contains(began)) hasBegan = true;
    }

    if (hasDone) return ThreeDStageStatus.succeeded;
    if (hasBegan) return ThreeDStageStatus.started;
    return ThreeDStageStatus.notRun;
  }

  static String describe(ThreeDStageStatus status) => switch (status) {
        ThreeDStageStatus.notRun => 'لم تعمل',
        ThreeDStageStatus.started => 'بدأت ولم تنتهِ',
        ThreeDStageStatus.succeeded => 'نجحت',
        ThreeDStageStatus.failed => 'فشلت',
      };

  /// One line per world stage, for the copied report.
  static String reportOf(String log) {
    final buffer = StringBuffer();

    for (final stage in worldStages) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(
        '${stage.label}: ${describe(statusOf(log, stage))}',
      );
    }

    return buffer.toString();
  }
}
