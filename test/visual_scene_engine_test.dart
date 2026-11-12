import 'package:auto_edit/visual_scene_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisualSceneEngine', () {
    test('builds an FFmpeg scene-detection command with the requested threshold', () {
      final command = VisualSceneEngine.buildDetectionCommand(
        videoPath: '/storage/emulated/0/Movies/source clip.mp4',
        threshold: 0.32,
      );

      expect(command, contains('select='));
      expect(command, contains('gt(scene,0.32)'));
      expect(command, contains('showinfo'));
      expect(command, contains('source clip.mp4'));
      expect(command, contains('-f null -'));
    });

    test('rejects an invalid threshold or empty video path', () {
      expect(
        () => VisualSceneEngine.buildDetectionCommand(videoPath: '  '),
        throwsArgumentError,
      );
      expect(
        () => VisualSceneEngine.buildDetectionCommand(
          videoPath: 'video.mp4',
          threshold: 1,
        ),
        throwsArgumentError,
      );
    });

    test('parses, sorts and deduplicates scene timestamps', () {
      const logs = '''
[Parsed_showinfo_1] n:0 pts:100 pts_time:2.000
[Parsed_showinfo_1] n:1 pts:200 pts_time:1.000
[Parsed_showinfo_1] n:2 pts:205 pts_time:1.050
[Parsed_showinfo_1] n:3 pts:500 pts_time:5.000
''';

      final cuts = VisualSceneEngine.parseDetectedTimestamps(
        logs,
        duration: 8,
      );

      expect(cuts, [1.0, 2.0, 5.0]);
    });

    test('ignores timestamps outside the safe video range and malformed values', () {
      const logs = '''
pts_time:0.010
pts_time:0.500
pts_time:9.900
pts_time:nan
pts_time:bad
''';

      final cuts = VisualSceneEngine.parseDetectedTimestamps(
        logs,
        duration: 10,
      );

      expect(cuts, [0.5]);
    });

    test('limits the number of returned cuts', () {
      final logs = List<String>.generate(
        8,
        (index) => 'pts_time:${(index + 1).toStringAsFixed(2)}',
      ).join('\n');

      final cuts = VisualSceneEngine.parseDetectedTimestamps(
        logs,
        duration: 10,
        minimumGap: 0.1,
        maximumCuts: 3,
      );

      expect(cuts, hasLength(3));
    });

    test('creates one complete shot when no scene changes are found', () {
      final plan = VisualSceneEngine.buildPlan(
        duration: 12,
        sceneTimes: const [],
      );

      expect(plan.cuts, isEmpty);
      expect(plan.shots, hasLength(1));
      expect(plan.shots.single.start, 0);
      expect(plan.shots.single.end, 12);
      expect(plan.transitions, isEmpty);
    });

    test('creates contiguous shot ranges and transitions at detected changes', () {
      final plan = VisualSceneEngine.buildPlan(
        duration: 10,
        sceneTimes: const [4, 2, 2.1, 7],
        minimumGap: 0.35,
        pace: VisualPace.energetic,
      );

      expect(plan.cuts, [2, 4, 7]);
      expect(plan.shots, hasLength(4));
      expect(plan.transitions, hasLength(3));
      expect(plan.transitions.every(
        (cue) => cue.type == SceneTransitionType.subtleFlash,
      ), isTrue);

      expect(plan.shots.first.start, 0);
      expect(plan.shots.last.end, 10);
      for (var i = 0; i < plan.shots.length - 1; i++) {
        expect(plan.shots[i].end, plan.shots[i + 1].start);
      }
      expect(plan.shots.every((shot) => shot.duration > 0), isTrue);
    });

    test('selects restrained transitions for calm content', () {
      final plan = VisualSceneEngine.buildPlan(
        duration: 6,
        sceneTimes: const [3],
        pace: VisualPace.calm,
      );

      expect(plan.transitions.single.type, SceneTransitionType.softFade);
      expect(plan.transitions.single.duration, 0.20);
    });

    test('rejects invalid duration and maximum cut count', () {
      expect(
        () => VisualSceneEngine.buildPlan(
          duration: 0,
          sceneTimes: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => VisualSceneEngine.buildPlan(
          duration: 5,
          sceneTimes: const [],
          maximumCuts: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
