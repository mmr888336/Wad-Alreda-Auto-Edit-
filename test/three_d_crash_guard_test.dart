import 'package:auto_edit/three_d_crash_guard.dart';
import 'package:auto_edit/three_d_progress.dart';
import 'package:auto_edit/three_d_stage_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThreeDBreadcrumb', () {
    final crumb = ThreeDBreadcrumb(
      scene: 2,
      stage: ThreeDStage.filamentLoad,
      assetKey: 'sketchfab:abc',
      assetTitle: 'Robot',
      at: DateTime.utc(2026, 11, 16, 12),
    );

    test('round-trips through JSON', () {
      final copy = ThreeDBreadcrumb.fromJson(crumb.toJson());

      expect(copy, isNotNull);
      expect(copy!.scene, 2);
      expect(copy.stage, ThreeDStage.filamentLoad);
      expect(copy.assetKey, 'sketchfab:abc');
      expect(copy.assetTitle, 'Robot');
      expect(copy.at.isAtSameMomentAs(crumb.at), isTrue);
    });

    test('rejects broken data', () {
      expect(ThreeDBreadcrumb.fromJson('nope'), isNull);
      expect(
        ThreeDBreadcrumb.fromJson(<String, Object>{'stage': 'unknown'}),
        isNull,
      );
    });

    test('describes the scene, stage and model', () {
      final text = crumb.describe();

      expect(text, contains('مشهد 2'));
      expect(text, contains(ThreeDStage.filamentLoad.label));
      expect(text, contains('Robot'));
    });

    test('advice depends on the crashed stage', () {
      final compositing = ThreeDBreadcrumb(
        scene: 0,
        stage: ThreeDStage.composite,
        at: DateTime.utc(2026, 11, 16),
      );

      expect(ThreeDCrashGuard.adviceFor(compositing), contains('تعطيل'));
      expect(ThreeDCrashGuard.adviceFor(crumb), contains('حظر'));
    });
  });

  group('ThreeDProgress', () {
    test('maps the 3D phase onto the export bar', () {
      const start = ThreeDProgress(fraction: 0, message: 'a');
      const middle = ThreeDProgress(fraction: 0.5, message: 'b');
      const end = ThreeDProgress(fraction: 2, message: 'c');

      expect(start.overall(), closeTo(0.80, 1e-9));
      expect(middle.overall(), closeTo(0.89, 1e-9));
      expect(end.overall(), closeTo(0.98, 1e-9));
    });
  });
}
