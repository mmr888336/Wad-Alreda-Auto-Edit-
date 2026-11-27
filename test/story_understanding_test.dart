import 'package:auto_edit/depth_camera_model.dart';
import 'package:auto_edit/motion_transitions.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:flutter_test/flutter_test.dart';

StorySegment _seg(String text, double start, double end) =>
    StorySegment(text: text, start: start, end: end);

void main() {
  group('normalize', () {
    test('unifies Arabic spellings and removes diacritics', () {
      expect(
        StoryUnderstanding.normalize('\u0628\u064E\u0631\u064E\u0643\u064E\u0629'),
        '\u0628\u0631\u0643\u0647',
      );
      expect(StoryUnderstanding.normalize('Money'), 'money');
    });
  });

  group('understanding', () {
    test('a blessing sentence becomes a calm room with its own props', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('سر البركة والخير في حياة الناس', 5, 7.6),
      ]);
      final beat = plan.beats.single;
      expect(beat.focus, 'blessing');
      expect(beat.environment, StoryEnvironment.room);
      expect(beat.mood, StoryMood.calm);
      expect(beat.effectWord, 'البركة');
      expect(beat.props.length, 3);
      expect(beat.props.first, 'lantern');
      expect(beat.shot, StoryShotKind.establishing);
    });

    test('money goes to the office, English works too', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة جدا', 0, 3),
        _seg('learn from a good book', 3, 6),
      ]);
      expect(plan.beats[0].focus, 'money');
      expect(plan.beats[0].environment, StoryEnvironment.office);
      expect(plan.beats[0].effectWord, 'الفلوس');
      expect(plan.beats[1].focus, 'knowledge');
      expect(plan.beats[1].environment, StoryEnvironment.library);
      expect(plan.beats[1].effectWord, 'learn');
    });

    test('a sentence without a known idea keeps the previous world', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة', 0, 3),
        _seg('وبعدين نكمل الكلام', 3, 6),
      ]);
      expect(plan.beats[1].focus, 'none');
      expect(plan.beats[1].environment, StoryEnvironment.office);
      expect(plan.beats[1].props, isEmpty);
      expect(plan.beats[1].effectWord, isNotEmpty);
    });
  });

  group('transitions', () {
    test('a new world is entered through the window', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة', 0, 3),
        _seg('البركة والخير', 3, 6),
      ]);
      expect(plan.beats[0].windowToNext, isTrue);
      expect(plan.beats[0].transitionToNext, MotionTransitionKind.zoomSmash);
      expect(plan.beats[0].cameraHint, DepthCameraMove.windowIn);
      expect(plan.beats[1].shot, StoryShotKind.reveal);
      expect(plan.beats[1].cameraHint, DepthCameraMove.windowOut);
      expect(plan.beats[1].windowToNext, isFalse);
      expect(plan.beats[1].transitionToNext, MotionTransitionKind.hardCut);
    });

    test('short beats do not dive, they whip', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة', 0, 1.0),
        _seg('البركة والخير', 1.0, 2.0),
      ]);
      expect(plan.beats[0].windowToNext, isFalse);
      expect(plan.beats[0].transitionToNext, MotionTransitionKind.whipPan);
    });

    test('same world gives a match cut', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة', 0, 3),
        _seg('والتجارة كمان', 3, 6),
      ]);
      expect(plan.beats[0].environment, plan.beats[1].environment);
      expect(plan.beats[0].transitionToNext, MotionTransitionKind.matchCut);
    });
  });

  group('multi-zone', () {
    test('a comparison of two places gives two connected zones', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('مقارنة بين الفلوس والعلم', 0, 3),
      ]);
      final beat = plan.beats.single;
      expect(beat.intent, StoryIntent.compare);
      expect(beat.zones.length, 2);
      expect(beat.zones[0].environment, StoryEnvironment.office);
      expect(beat.zones[1].environment, StoryEnvironment.library);
      expect(beat.zones[0].portals, contains(beat.zones[1].id));
      expect(beat.zones[1].portals, contains(beat.zones[0].id));
    });

    test('a plain sentence keeps one zone', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة', 0, 3),
      ]);
      expect(plan.beats.single.zones.length, 1);
      expect(plan.beats.single.zones.single.portals, isEmpty);
    });

    test('a continuation keeps a portal to the previous zone', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('مقارنة بين الفلوس والعلم', 0, 3),
        _seg('وبعدين نكمل الكلام', 3, 6),
      ]);
      final second = plan.beats[1];
      expect(second.zones.length, 2);
      expect(second.zones[0].portals, isNotEmpty);
      expect(second.zones[1].portals, isNotEmpty);
    });
  });

  group('multi-shot', () {
    test('a short beat is one shot covering the whole beat', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة', 0, 2),
      ]);
      final shots = plan.beats.single.shotPlan;
      expect(shots.length, 1);
      expect(shots.single.start, 0);
      expect(shots.single.end, 2);
    });

    test('a long beat is establishing -> medium -> closeUp', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة جدا في حياتنا', 0, 4),
      ]);
      final shots = plan.beats.single.shotPlan;
      expect(shots.length, 3);
      expect(shots[0].kind, StoryShotKind.establishing);
      expect(shots[1].kind, StoryShotKind.medium);
      expect(shots[2].kind, StoryShotKind.closeUp);
    });

    test('the shots are contiguous and cover the whole beat', () {
      final plan = StoryUnderstanding.plan(<StorySegment>[
        _seg('الفلوس مهمة جدا في حياتنا', 0, 4),
      ]);
      final shots = plan.beats.single.shotPlan;
      expect(shots.first.start, 0);
      expect(shots.last.end, 4);
      for (var i = 0; i < shots.length - 1; i++) {
        expect(shots[i].end, closeTo(shots[i + 1].start, 1e-9));
      }
    });
  });
}
