import 'package:auto_edit/person_anchor_path.dart';
import 'package:auto_edit/person_anchored_command.dart';
import 'package:auto_edit/person_silhouette.dart';
import 'package:auto_edit/person_tracking_models.dart';
import 'package:auto_edit/scene_environment.dart';
import 'package:flutter_test/flutter_test.dart';

LandmarkPoint _pt(double x, double y) =>
    LandmarkPoint(x: x, y: y, confidence: 0.9);

PersonTrack _track() {
  final observations = <PersonObservation>[];
  for (var i = 0; i <= 50; i++) {
    const cx = 0.4;
    observations.add(
      PersonObservation(
        time: i * 0.2,
        box: const NormalizedRect(
          left: cx - 0.15,
          top: 0.2,
          right: cx + 0.15,
          bottom: 0.9,
        ),
        confidence: 0.9,
        landmarks: <BodyLandmark, LandmarkPoint>{
          BodyLandmark.nose: _pt(cx, 0.3),
          BodyLandmark.leftShoulder: _pt(cx + 0.1, 0.45),
          BodyLandmark.rightShoulder: _pt(cx - 0.1, 0.45),
          BodyLandmark.leftHip: _pt(cx + 0.08, 0.7),
          BodyLandmark.rightHip: _pt(cx - 0.08, 0.7),
        },
      ),
    );
  }
  return PersonTrack(id: 1, observations: observations);
}

SceneEnvironmentLook _look({int grain = 6}) => SceneEnvironmentLook(
      depth: 0.75,
      gainRed: 0.95,
      gainGreen: 0.9,
      gainBlue: 0.85,
      saturation: 0.9,
      blackLift: 0.06,
      liftRed: 15.0,
      liftGreen: 14.0,
      liftBlue: 12.0,
      blurSigma: 0.9,
      shadowOpacity: 0.35,
      shadowDx: -12.5,
      shadowDy: 18.25,
      shadowBlur: 9.0,
      grain: grain,
    );

void main() {
  final path = PersonAnchorPath.plan(
    track: _track(),
    start: 1,
    end: 3,
    placement: PersonPlacement.behindShoulder,
    frameWidth: 1080,
    frameHeight: 1920,
  )!;

  const matte = PersonMatteSequence(
    directory: '/tmp/m',
    fps: 12,
    width: 240,
    height: 426,
    frameCount: 25,
  );

  String build(List<AnchoredSceneSpec> scenes) => PersonAnchoredCommand.build(
        videoPath: '/v/in.mp4',
        outputPath: '/v/out.mp4',
        width: 1080,
        height: 1920,
        duration: 10,
        scenes: scenes,
      );

  group('PersonAnchoredCommand with an environment', () {
    test('grades the card, adds grain on the color only and a shadow under it',
        () {
      final command = build(<AnchoredSceneSpec>[
        AnchoredSceneSpec(
          scenePath: '/v/anchored.mp4',
          start: 1,
          end: 3,
          path: path,
          keyColors: const <String>['0x101521'],
          environment: _look(),
        ),
      ]);

      // keyed card -> raw -> grade -> split (color / alpha / shadow)
      expect(command, contains('colorkey=0x101521:0.12:0.08'));
      expect(command, contains('[raw0]colorchannelmixer=rr=0.950'));
      expect(command, contains("lutrgb=r='val*0.940+15.000'"));
      expect(command, contains('format=gbrap,gblur=sigma=0.900,format=rgba'));
      expect(command, contains('split=3[envc0][enva0][envs0]'));

      // grain on the color; alpha extracted and merged back untouched
      expect(command, contains('[enva0]alphaextract[envm0]'));
      expect(
        command,
        contains('[envc0]format=yuv444p,noise=alls=6:allf=t+u[envn0]'),
      );
      expect(
        command,
        contains('[envn0][envm0]alphamerge,format=rgba[card0]'),
      );

      // shadow: black copy of the card, softened
      expect(
        command,
        contains(
          '[envs0]colorchannelmixer=rr=0:gg=0:bb=0:aa=0.350,'
          'format=gbrap,gblur=sigma=9.000,format=rgba[shadow0]',
        ),
      );

      // shadow overlay at the light-driven offset, BEFORE the card overlay
      expect(command, contains('[pbase][shadow0]overlay=x=\'(if(lt(t,'));
      expect(command, contains(')+(-12.500)'));
      expect(command, contains(')+(18.250)'));
      expect(command, contains('[pshadow0]'));
      expect(command, contains('[pshadow0][card0]overlay=x=\'if(lt(t,'));
      expect(
        command.indexOf('[pbase][shadow0]overlay'),
        lessThan(command.indexOf('[pshadow0][card0]overlay')),
      );

      // shadow + card
      expect(RegExp(r'overlay=').allMatches(command).length, 2);

      // the number of inputs is unchanged by the environment match
      expect(RegExp(r'-i "').allMatches(command).length, 2);
      expect(command, contains("enable='between(t,1.000,3.000)'"));
    });

    test('every stream label is produced once and used once', () {
      final command = build(<AnchoredSceneSpec>[
        AnchoredSceneSpec(
          scenePath: '/v/anchored.mp4',
          start: 1,
          end: 3,
          path: path,
          matte: matte,
          environment: _look(),
        ),
      ]);

      final graph = RegExp(r'-filter_complex "([^"]*)"')
          .firstMatch(command)!
          .group(1)!;

      final produced = <String, int>{};
      final consumed = <String, int>{};

      for (final chain in graph.split(';')) {
        final open = chain.indexOf('[');
        final firstFilter = chain.indexOf(RegExp(r'\]\s*[A-Za-z]'));
        final lastClose = chain.lastIndexOf(']');
        final lastOpen = chain.lastIndexOf('[');

        // inputs: every [label] before the first filter name
        final head = chain.substring(open, firstFilter + 1);
        for (final match in RegExp(r'\[([^\]]+)\]').allMatches(head)) {
          consumed[match.group(1)!] = (consumed[match.group(1)!] ?? 0) + 1;
        }

        // outputs: every [label] at the end of the chain
        final tail = chain.substring(lastOpen, lastClose + 1);
        for (final match in RegExp(r'\[([^\]]+)\]').allMatches(tail)) {
          produced[match.group(1)!] = (produced[match.group(1)!] ?? 0) + 1;
        }
      }

      for (final entry in produced.entries) {
        expect(entry.value, 1, reason: '${entry.key} is produced once');
        expect(
          consumed[entry.key],
          1,
          reason: '${entry.key} is consumed exactly once',
        );
      }

      // with the person matte: shadow, card and the person cut-out
      expect(RegExp(r'overlay=').allMatches(command).length, 3);
      expect(command, contains('alphamerge[pcut0]'));
    });

    test('without grain the card is only split in two', () {
      final command = build(<AnchoredSceneSpec>[
        AnchoredSceneSpec(
          scenePath: '/v/anchored.mp4',
          start: 1,
          end: 3,
          path: path,
          environment: _look(grain: 0),
        ),
      ]);

      expect(command, contains('split=2[card0][envs0]'));
      expect(command, isNot(contains('noise=')));
      expect(command, isNot(contains('alphaextract')));
      expect(command, contains('[shadow0]'));
    });

    test('without an environment the command is the plain anchored one', () {
      final plain = build(<AnchoredSceneSpec>[
        AnchoredSceneSpec(
          scenePath: '/v/anchored.mp4',
          start: 1,
          end: 3,
          path: path,
          matte: matte,
        ),
      ]);

      expect(plain, isNot(contains('colorchannelmixer')));
      expect(plain, isNot(contains('lutrgb')));
      expect(plain, isNot(contains('shadow')));
      expect(plain, isNot(contains('noise=')));
      expect(plain, isNot(contains('split=')));
      expect(RegExp(r'overlay=').allMatches(plain).length, 2);

      final stripped = build(<AnchoredSceneSpec>[
        AnchoredSceneSpec(
          scenePath: '/v/anchored.mp4',
          start: 1,
          end: 3,
          path: path,
          matte: matte,
          environment: _look(),
        ).withoutEnvironment(),
      ]);

      expect(stripped, plain);
    });

    test('a picture-in-picture scene ignores the environment', () {
      final spec = AnchoredSceneSpec(
        scenePath: '/v/pip.mp4',
        start: 5,
        end: 7,
        environment: _look(),
      );

      expect(spec.hasEnvironment, isFalse);

      final command = build(<AnchoredSceneSpec>[spec]);

      expect(command, contains('drawbox'));
      expect(command, isNot(contains('colorchannelmixer')));
      expect(command, isNot(contains('shadow')));
    });

    test('anchored and picture-in-picture scenes can be mixed', () {
      final command = build(<AnchoredSceneSpec>[
        AnchoredSceneSpec(
          scenePath: '/v/pip.mp4',
          start: 5,
          end: 7,
        ),
        AnchoredSceneSpec(
          scenePath: '/v/anchored.mp4',
          start: 1,
          end: 3,
          path: path,
          environment: _look(),
        ),
      ]);

      expect(command, contains('[shadow0]'));
      expect(command, contains('drawbox'));
      expect(command, contains("enable='between(t,5.000,7.000)'"));
      expect(command, endsWith('"/v/out.mp4"'));
    });

    test('hasEnvironment is true only for an anchored scene with a look', () {
      expect(
        AnchoredSceneSpec(
          scenePath: '/v/a.mp4',
          start: 1,
          end: 3,
          path: path,
          environment: _look(),
        ).hasEnvironment,
        isTrue,
      );

      expect(
        AnchoredSceneSpec(
          scenePath: '/v/a.mp4',
          start: 1,
          end: 3,
          path: path,
        ).hasEnvironment,
        isFalse,
      );
    });
  });
}
