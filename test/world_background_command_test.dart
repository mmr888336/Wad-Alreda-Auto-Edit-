import 'package:auto_edit/world_scene_compositor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const plain = WorldBackgroundClip(path: '/tmp/w1.mp4', start: 2, end: 4);
  const layered = WorldBackgroundClip(
    path: '/tmp/w2.mp4',
    start: 6,
    end: 8.5,
    overlayPath: '/tmp/o2.mp4',
  );

  WorldBackgroundPlan planOf(List<WorldBackgroundClip> clips) =>
      WorldBackgroundCommand.build(
        videoPath: '/tmp/v.mp4',
        width: 1080,
        height: 1920,
        clips: clips,
      );

  group('WorldBackgroundCommand', () {
    test('a world clip replaces the picture without a screen blend', () {
      final plan = planOf(const <WorldBackgroundClip>[plain]);

      expect(
        plan.inputs,
        equals(<String>['-i "/tmp/v.mp4"', '-i "/tmp/w1.mp4"']),
      );
      expect(plan.filterComplex, contains('overlay=x=0:y=0:eof_action=repeat'));
      expect(plan.filterComplex, contains("enable='between(t,2.000,4.000)'"));
      expect(plan.filterComplex, isNot(contains('blend=')));
      expect(plan.outputLabel, WorldBackgroundCommand.outputLabel);
      expect(plan.filterComplex, endsWith('[world_bg_out]'));
    });

    test('the clip covers the whole frame and fades at both ends', () {
      final filter = planOf(const <WorldBackgroundClip>[plain]).filterComplex;

      expect(filter, contains('force_original_aspect_ratio=increase'));
      expect(filter, contains('crop=1080:1920'));
      expect(filter, contains('fade=t=in:st=0:d=0.350:alpha=1'));
      expect(filter, contains('fade=t=out:st=1.650:d=0.350:alpha=1'));
      expect(filter, contains('setpts=PTS-STARTPTS+2.000/TB'));
    });

    test('flat layers are screen-blended on top, one blend per overlay', () {
      final plan = planOf(const <WorldBackgroundClip>[plain, layered]);
      final filter = plan.filterComplex;

      expect(plan.inputs.length, 4);
      expect(plan.inputs.last, '-i "/tmp/o2.mp4"');
      expect(filter, contains('[3:v]'));
      expect(filter, contains('format=gbrp'));
      expect(
        filter,
        contains(
          "blend=all_mode=screen:all_opacity=1:enable='between(t,6.000,8.500)'",
        ),
      );
      expect(
        filter,
        contains('tpad=start_mode=add:start_duration=6.000:color=black'),
      );
      expect('blend='.allMatches(filter).length, 1);
    });

    test('fade is at most a third of the clip', () {
      expect(WorldBackgroundCommand.fadeFor(0.9), closeTo(0.3, 1e-9));
      expect(WorldBackgroundCommand.fadeFor(5), closeTo(0.35, 1e-9));
      expect(WorldBackgroundCommand.fadeFor(0), 0);
    });

    test('the command keeps the audio and picks the encoder', () {
      final plan = planOf(const <WorldBackgroundClip>[plain]);

      final high = WorldBackgroundCommand.command(
        plan: plan,
        outputPath: '/tmp/out.mp4',
        duration: 10,
      );
      expect(high, contains('-map "[world_bg_out]"'));
      expect(high, contains('-map "0:a?"'));
      expect(high, contains('-preset fast -crf 17'));
      expect(high, contains('-t 10.000'));

      final light = WorldBackgroundCommand.command(
        plan: plan,
        outputPath: '/tmp/out.mp4',
        duration: 10,
        maximumQuality: false,
      );
      expect(light, contains('-preset veryfast -crf 20'));
    });

    test('no clips is an error', () {
      expect(
        () => planOf(const <WorldBackgroundClip>[]),
        throwsArgumentError,
      );
    });
  });
}
