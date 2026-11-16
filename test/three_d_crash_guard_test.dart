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
      expect(copy.cleared, isFalse);
    });

    test('keeps the cleared flag through JSON', () {
      final cleared = ThreeDBreadcrumb(
        scene: 2,
        stage: ThreeDStage.capture,
        assetKey: 'sketchfab:abc',
        assetTitle: 'Great Hall',
        at: DateTime.utc(2026, 11, 17),
        cleared: true,
      );

      expect(ThreeDBreadcrumb.fromJson(cleared.toJson())!.cleared, isTrue);
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

    test('a crash while releasing the renderer blocks no model', () {
      final release = ThreeDBreadcrumb(
        scene: 0,
        stage: ThreeDStage.rendererRelease,
        at: DateTime.utc(2026, 11, 17),
      );

      expect(
        ThreeDCrashGuard.assetStages.contains(ThreeDStage.rendererRelease),
        isFalse,
      );
      expect(ThreeDCrashGuard.adviceFor(release), contains('تحرير'));
      expect(
        ThreeDCrashGuard.adviceFor(release),
        isNot(contains('تم حظر هذا المجسم')),
      );
    });

    test('a cleared crash says the model was not blocked', () {
      final cleared = ThreeDBreadcrumb(
        scene: 2,
        stage: ThreeDStage.capture,
        assetKey: 'sketchfab:abc',
        assetTitle: 'Great Hall',
        at: DateTime.utc(2026, 11, 17),
        cleared: true,
      );

      final advice = ThreeDCrashGuard.adviceFor(cleared);

      expect(advice, contains('بنجاح'));
      expect(advice, isNot(contains('تم حظر هذا المجسم')));
    });
  });

  group('ThreeDLogReader', () {
    final log = <String>[
      '[مشهد 1] التنزيل: فشل (935ms) — The Bathroom (Free): Bad state',
      '[مشهد 2] الالتقاط: بدأ — Great Hall',
      '[مشهد 2] الالتقاط: نجح (16268ms) — Great Hall',
      '[مشهد 3] الالتقاط: بدأ — Old Castle',
    ].join('\n');

    test('start line names the stage that began', () {
      expect(
        ThreeDStageEvent.startLine(
          2,
          ThreeDStage.capture,
          detail: 'Great Hall',
        ),
        '[مشهد 2] الالتقاط: بدأ — Great Hall',
      );
    });

    test('confirms a finished stage of the right model', () {
      expect(
        ThreeDLogReader.succeeded(
          log,
          scene: 2,
          stage: ThreeDStage.capture,
          assetTitle: 'Great Hall',
        ),
        isTrue,
      );
    });

    test('a start line or a failure is not a success', () {
      expect(
        ThreeDLogReader.succeeded(
          log,
          scene: 3,
          stage: ThreeDStage.capture,
          assetTitle: 'Old Castle',
        ),
        isFalse,
      );
      expect(
        ThreeDLogReader.succeeded(
          log,
          scene: 1,
          stage: ThreeDStage.download,
          assetTitle: 'The Bathroom (Free)',
        ),
        isFalse,
      );
    });

    test('does not mix up scenes or models', () {
      expect(
        ThreeDLogReader.succeeded(
          log,
          scene: 1,
          stage: ThreeDStage.capture,
          assetTitle: 'Great Hall',
        ),
        isFalse,
      );
      expect(
        ThreeDLogReader.succeeded(
          log,
          scene: 2,
          stage: ThreeDStage.capture,
          assetTitle: 'Another Model',
        ),
        isFalse,
      );
    });
  });

  group('ThreeDExportSummary', () {
    test('start notes are logged but are not events', () {
      final starts = <String>[];

      final summary = ThreeDExportSummary(
        onStart: (scene, stage, detail) =>
            starts.add(ThreeDStageEvent.startLine(scene, stage)),
      );

      summary.begin(0, ThreeDStage.rendererRelease);

      expect(starts, hasLength(1));
      expect(summary.events, isEmpty);
      expect(summary.failures, isEmpty);
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
