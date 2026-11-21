import 'package:flutter/material.dart';

import 'three_d_stage_log.dart';
import 'three_d_stage_status.dart';

/// Shows every stage of the world path with its state in the last export.
class WorldStagePanel extends StatelessWidget {
  const WorldStagePanel({super.key, required this.log});

  final String log;

  static IconData _icon(ThreeDStageStatus status) => switch (status) {
        ThreeDStageStatus.succeeded => Icons.check_circle_rounded,
        ThreeDStageStatus.failed => Icons.error_rounded,
        ThreeDStageStatus.started => Icons.hourglass_bottom_rounded,
        ThreeDStageStatus.notRun => Icons.remove_circle_outline_rounded,
      };

  static Color _color(ThreeDStageStatus status) => switch (status) {
        ThreeDStageStatus.succeeded => Colors.greenAccent,
        ThreeDStageStatus.failed => Colors.redAccent,
        ThreeDStageStatus.started => Colors.orangeAccent,
        ThreeDStageStatus.notRun => Colors.white38,
      };

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (final ThreeDStage stage in ThreeDStageStatusReader.worldStages) {
      final status = ThreeDStageStatusReader.statusOf(log, stage);

      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(_icon(status), size: 18, color: _color(status)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stage.label,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                ThreeDStageStatusReader.describe(status),
                style: TextStyle(fontSize: 12, color: _color(status)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}
