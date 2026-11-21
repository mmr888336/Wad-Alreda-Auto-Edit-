import 'package:auto_edit/three_d_stage_log.dart';
import 'package:auto_edit/three_d_stage_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final log = <String>[
    '[مشهد 1] تخطيط مشهد العالم: بدأ',
    '[مشهد 1] تخطيط مشهد العالم: نجح (3ms) — 5 جسم',
    '[مشهد 1] الالتقاط: بدأ',
    '[مشهد 2] فحص GLB: نجح (4ms)',
    '[مشهد 2] فحص GLB: فشل (4ms) — bad',
    '[التصدير] تركيب العالم كخلفية كاملة: نجح (90ms)',
  ].join('\n');

  test('reads the state of each stage from the log', () {
    expect(
      ThreeDStageStatusReader.statusOf(log, ThreeDStage.worldPlan),
      ThreeDStageStatus.succeeded,
    );
    expect(
      ThreeDStageStatusReader.statusOf(log, ThreeDStage.capture),
      ThreeDStageStatus.started,
    );
    expect(
      ThreeDStageStatusReader.statusOf(log, ThreeDStage.inspect),
      ThreeDStageStatus.failed,
    );
    expect(
      ThreeDStageStatusReader.statusOf(log, ThreeDStage.worldComposite),
      ThreeDStageStatus.succeeded,
    );
    expect(
      ThreeDStageStatusReader.statusOf(log, ThreeDStage.worldFlat),
      ThreeDStageStatus.notRun,
    );
  });

  test('the composite stage is not confused with the world composite', () {
    expect(
      ThreeDStageStatusReader.statusOf(log, ThreeDStage.composite),
      ThreeDStageStatus.notRun,
    );
  });

  test('the report has one line per world stage', () {
    final lines = ThreeDStageStatusReader.reportOf(log).split('\n');

    expect(lines.length, ThreeDStageStatusReader.worldStages.length);
    expect(lines.first, 'تخطيط مشهد العالم: نجحت');
  });
}
