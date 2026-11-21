import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/world_look_grade.dart';
import 'package:auto_edit/world_scene_compositor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calmOffice = CinematicWorld.lookFor(
    StoryEnvironment.office,
    StoryMood.calm,
    const WorldPalette(),
  );

  WorldLook look({String particle = 'dust', double density = 0.25}) =>
      WorldLook(
        tint: '#F5A524',
        keyAngleDegrees: 35,
        intensity: 0.7,
        shadowOpacity: 0.32,
        vignette: 0.35,
        particleKind: particle,
        particleDensity: density,
      );

  group('WorldLookGrade', () {
    test('the tint pulls the colour of the picture a little', () {
      final filters = WorldLookGrade.filters(calmOffice)!;

      expect(filters, startsWith('format=gbrp,colorchannelmixer='));
      expect(filters, contains('rr=1.113'));
      expect(filters, contains('gg=1.036'));
      expect(filters, contains('bb=0.912'));
      expect(filters, contains('format=yuv420p,vignette=angle='));
    });

    test('the vignette follows the look and the vignette centre the light',
        () {
      expect(WorldLookGrade.vignetteAngle(calmOffice), closeTo(0.4986, 1e-3));
      expect(WorldLookGrade.filters(calmOffice), contains('x0=w*0.418'));
      expect(WorldLookGrade.filters(calmOffice), contains('y0=h*0.443'));
    });

    test('a bad tint gives no grade', () {
      final bad = WorldLook(
        tint: 'red',
        keyAngleDegrees: 35,
        intensity: 0.7,
        shadowOpacity: 0.3,
        vignette: 0.3,
        particleKind: 'dust',
        particleDensity: 0.3,
      );

      expect(WorldLookGrade.filters(bad), isNull);
    });

    test('particles follow the look and need some density', () {
      expect(WorldLookGrade.particleKind(look()), 'dust');
      expect(WorldLookGrade.particleKind(look(particle: 'sparks')), 'embers');
      expect(WorldLookGrade.particleKind(look(particle: 'pollen')), 'sparkles');
      expect(WorldLookGrade.particleKind(look(particle: 'fog')), isNull);
      expect(WorldLookGrade.particleKind(look(density: 0.05)), isNull);
    });
  });

  group('the look in the composition', () {
    test('a graded world clip gets the grade before the fade', () {
      final plan = WorldBackgroundCommand.build(
        videoPath: '/tmp/v.mp4',
        width: 1080,
        height: 1920,
        clips: <WorldBackgroundClip>[
          WorldBackgroundClip(
            path: '/tmp/w1.mp4',
            start: 2,
            end: 4,
            look: calmOffice,
          ),
        ],
      );

      expect(plan.filterComplex, contains('colorchannelmixer=rr=1.113'));
      expect(
        plan.filterComplex.indexOf('colorchannelmixer'),
        lessThan(plan.filterComplex.indexOf('format=yuva420p')),
      );
    });

    test('a clip without a look is not graded', () {
      final plan = WorldBackgroundCommand.build(
        videoPath: '/tmp/v.mp4',
        width: 1080,
        height: 1920,
        clips: const <WorldBackgroundClip>[
          WorldBackgroundClip(path: '/tmp/w1.mp4', start: 2, end: 4),
        ],
      );

      expect(plan.filterComplex, isNot(contains('colorchannelmixer')));
      expect(plan.filterComplex, isNot(contains('vignette')));
    });
  });
}
