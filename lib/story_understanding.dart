/// Story understanding: turns what the speaker says into a visual story.
///
/// The old flow looked for one picture that matched one word. This planner
/// reads every spoken segment as an idea and decides, for each one:
///  * the environment that fits it (office, room, library, ...);
///  * the objects that belong to the idea (secondary props);
///  * the main effect word (the one word that gets the big title);
///  * the kind of shot and a camera move hint;
///  * the transition into the next idea (and whether to "enter the window").
///
/// It is an offline, rule based planner (Arabic and English, no network, no
/// API key). When a segment has no known idea it keeps the environment of the
/// previous segment, so the world does not jump around.
///
/// The camera move is only a HINT: the existing CinematicCameraDirector keeps
/// the final say on the shot list. Pure Dart, no I/O.
library;

import 'depth_camera_model.dart' show DepthCameraMove;
import 'motion_transitions.dart' show MotionTransitionKind;

/// The place a segment happens in.
enum StoryEnvironment { office, room, library, street, studio, outdoors }

/// Emotional colour of a segment (drives the light of the world).
enum StoryMood { calm, energetic, tense }

/// Kind of shot a segment gets.
enum StoryShotKind { establishing, medium, closeUp, detail, reveal }

/// One spoken segment with its time range in seconds.
class StorySegment {
  final String text;
  final double start;
  final double end;

  const StorySegment({
    required this.text,
    required this.start,
    required this.end,
  });

  double get duration => end - start;
}

/// One idea of the lexicon: the words that trigger it and what it brings.
class StoryConcept {
  final String id;
  final StoryEnvironment environment;
  final StoryMood mood;

  /// How strongly the idea shapes a scene (1 weak .. 4 strong).
  final int weight;

  /// Secondary objects that belong to the idea (asset-style keys).
  final List<String> props;

  /// Trigger words, Arabic and English. They are normalised when the lexicon
  /// is indexed, so any common spelling works.
  final List<String> triggers;

  const StoryConcept({
    required this.id,
    required this.environment,
    required this.mood,
    required this.weight,
    required this.props,
    required this.triggers,
  });
}

/// The plan of one segment.
class StoryBeat {
  final int index;
  final StorySegment segment;

  /// Id of the main idea, or `none` when the segment has no known idea.
  final String focus;
  final StoryEnvironment environment;
  final StoryMood mood;

  /// Up to three secondary objects chosen by the meaning of the sentence.
  final List<String> props;

  /// The word that gets the big animated title.
  final String effectWord;
  final StoryShotKind shot;

  /// Suggested camera move (a hint for the camera director).
  final DepthCameraMove cameraHint;

  /// Transition into the next beat (hard cut for the last beat).
  final MotionTransitionKind transitionToNext;

  /// True when the next beat is entered by diving into the window / screen.
  final bool windowToNext;

  const StoryBeat({
    required this.index,
    required this.segment,
    required this.focus,
    required this.environment,
    required this.mood,
    required this.props,
    required this.effectWord,
    required this.shot,
    required this.cameraHint,
    required this.transitionToNext,
    required this.windowToNext,
  });
}

/// The story of a whole video.
class StoryPlan {
  final List<StoryBeat> beats;

  const StoryPlan(this.beats);

  /// Environments in the order they first appear.
  List<StoryEnvironment> get environments {
    final seen = <StoryEnvironment>[];
    for (final beat in beats) {
      if (!seen.contains(beat.environment)) seen.add(beat.environment);
    }
    return seen;
  }
}

class _Analysis {
  final StoryConcept? top;
  final StoryConcept? second;
  final int score;
  final String word;

  const _Analysis({
    required this.top,
    required this.second,
    required this.score,
    required this.word,
  });
}

class StoryUnderstanding {
  StoryUnderstanding._();

  static const List<StoryConcept> concepts = <StoryConcept>[
    StoryConcept(
      id: 'money',
      environment: StoryEnvironment.office,
      mood: StoryMood.energetic,
      weight: 4,
      props: <String>['coins', 'chart', 'wallet'],
      triggers: <String>[
        'مال', 'فلوس', 'ربح', 'ارباح', 'دخل', 'تجارة', 'بيع', 'مبيعات',
        'استثمار', 'راتب', 'money', 'profit', 'sales', 'income', 'business',
        'invest', 'cash',
      ],
    ),
    StoryConcept(
      id: 'knowledge',
      environment: StoryEnvironment.library,
      mood: StoryMood.calm,
      weight: 3,
      props: <String>['books', 'lamp', 'notebook'],
      triggers: <String>[
        'علم', 'كتاب', 'كتب', 'قراءة', 'تعلم', 'دراسة', 'معرفة', 'مذاكرة',
        'book', 'read', 'learn', 'study', 'knowledge', 'education',
      ],
    ),
    StoryConcept(
      id: 'work',
      environment: StoryEnvironment.office,
      mood: StoryMood.energetic,
      weight: 3,
      props: <String>['laptop', 'notebook', 'clock'],
      triggers: <String>[
        'عمل', 'شغل', 'وظيفة', 'مشروع', 'تركيز', 'مهمة', 'انتاجية', 'work',
        'project', 'job', 'focus', 'task', 'productivity',
      ],
    ),
    StoryConcept(
      id: 'time',
      environment: StoryEnvironment.room,
      mood: StoryMood.tense,
      weight: 2,
      props: <String>['clock', 'calendar'],
      triggers: <String>[
        'وقت', 'ساعة', 'يوم', 'عمر', 'سنة', 'time', 'deadline', 'hour',
        'year', 'today',
      ],
    ),
    StoryConcept(
      id: 'idea',
      environment: StoryEnvironment.studio,
      mood: StoryMood.energetic,
      weight: 3,
      props: <String>['lightbulb', 'sketch', 'notebook'],
      triggers: <String>[
        'فكرة', 'افكار', 'ابداع', 'تفكير', 'خيال', 'ابتكار', 'idea', 'think',
        'creative', 'imagine', 'innovation',
      ],
    ),
    StoryConcept(
      id: 'success',
      environment: StoryEnvironment.outdoors,
      mood: StoryMood.energetic,
      weight: 4,
      props: <String>['trophy', 'flag', 'stairs'],
      triggers: <String>[
        'نجاح', 'هدف', 'حلم', 'انجاز', 'فوز', 'تفوق', 'طموح', 'success',
        'goal', 'dream', 'win', 'achieve', 'ambition',
      ],
    ),
    StoryConcept(
      id: 'health',
      environment: StoryEnvironment.room,
      mood: StoryMood.calm,
      weight: 3,
      props: <String>['plant', 'water', 'dumbbell'],
      triggers: <String>[
        'صحة', 'جسم', 'رياضة', 'نوم', 'راحة', 'علاج', 'health', 'sleep',
        'sport', 'body', 'rest', 'fitness',
      ],
    ),
    StoryConcept(
      id: 'blessing',
      environment: StoryEnvironment.room,
      mood: StoryMood.calm,
      weight: 4,
      props: <String>['lantern', 'stars', 'plant'],
      triggers: <String>[
        'بركة', 'البركة', 'خير', 'دعاء', 'صلاة', 'ذكر', 'رزق', 'دين', 'ايمان',
        'توكل', 'blessing', 'prayer', 'faith', 'gratitude',
      ],
    ),
    StoryConcept(
      id: 'people',
      environment: StoryEnvironment.room,
      mood: StoryMood.calm,
      weight: 2,
      props: <String>['sofa', 'cups', 'frame'],
      triggers: <String>[
        'ناس', 'اسرة', 'عيلة', 'اهل', 'صديق', 'اصدقاء', 'زوجة', 'ولد', 'family',
        'people', 'friend', 'friends', 'parents', 'community',
      ],
    ),
    StoryConcept(
      id: 'journey',
      environment: StoryEnvironment.street,
      mood: StoryMood.energetic,
      weight: 3,
      props: <String>['road_sign', 'car', 'suitcase'],
      triggers: <String>[
        'طريق', 'رحلة', 'سفر', 'سيارة', 'مشوار', 'بداية', 'road', 'travel',
        'journey', 'trip', 'start', 'begin',
      ],
    ),
    StoryConcept(
      id: 'tech',
      environment: StoryEnvironment.studio,
      mood: StoryMood.energetic,
      weight: 3,
      props: <String>['screen', 'chip', 'phone'],
      triggers: <String>[
        'ذكاء', 'تقنية', 'برنامج', 'تطبيق', 'موبايل', 'كود', 'انترنت', 'ai',
        'app', 'tech', 'code', 'software', 'phone', 'internet', 'digital',
      ],
    ),
    StoryConcept(
      id: 'problem',
      environment: StoryEnvironment.room,
      mood: StoryMood.tense,
      weight: 3,
      props: <String>['warning', 'crumpled_paper', 'clock'],
      triggers: <String>[
        'مشكلة', 'خطر', 'خوف', 'فشل', 'خسارة', 'تعب', 'ضغط', 'قلق', 'problem',
        'fail', 'failure', 'loss', 'risk', 'fear', 'stress', 'mistake',
      ],
    ),
    StoryConcept(
      id: 'growth',
      environment: StoryEnvironment.outdoors,
      mood: StoryMood.calm,
      weight: 3,
      props: <String>['plant', 'chart', 'stairs'],
      triggers: <String>[
        'نمو', 'تطور', 'زيادة', 'تحسن', 'تقدم', 'grow', 'growth', 'improve',
        'progress', 'increase', 'upgrade',
      ],
    ),
  ];

  // Arabic prefixes that stick to a word (and, with, for, the, ...).
  static const List<String> _prefixes = <String>[
    'وال', 'بال', 'كال', 'فال', 'لل', 'ال', 'و', 'ب', 'ل', 'ف', 'ك',
  ];

  static final RegExp _splitter = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static Map<String, StoryConcept>? _indexCache;

  static Map<String, StoryConcept> get _index {
    final cached = _indexCache;
    if (cached != null) return cached;
    final built = <String, StoryConcept>{};
    for (final concept in concepts) {
      for (final trigger in concept.triggers) {
        final key = normalize(trigger);
        if (key.isNotEmpty && !built.containsKey(key)) {
          built[key] = concept;
        }
      }
    }
    _indexCache = built;
    return built;
  }

  /// Lower-cases and unifies Arabic spellings (hamza forms of alef, alef
  /// maqsura, teh marbuta), and removes diacritics and tatweel.
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final unit in input.toLowerCase().runes) {
      if (unit >= 0x064B && unit <= 0x065F) continue;
      if (unit == 0x0640) continue;
      if (unit == 0x0623 || unit == 0x0625 || unit == 0x0622) {
        buffer.writeCharCode(0x0627);
      } else if (unit == 0x0649) {
        buffer.writeCharCode(0x064A);
      } else if (unit == 0x0629) {
        buffer.writeCharCode(0x0647);
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  /// Words of [text] without punctuation.
  static List<String> tokens(String text) {
    return <String>[
      for (final part in text.split(_splitter))
        if (part.isNotEmpty) part,
    ];
  }

  static StoryConcept? _lookup(String normalized) {
    final index = _index;
    final direct = index[normalized];
    if (direct != null) return direct;
    for (final prefix in _prefixes) {
      if (normalized.startsWith(prefix) &&
          normalized.length - prefix.length >= 2) {
        final hit = index[normalized.substring(prefix.length)];
        if (hit != null) return hit;
      }
    }
    if (normalized.length > 3 && normalized.endsWith('s')) {
      final hit = index[normalized.substring(0, normalized.length - 1)];
      if (hit != null) return hit;
    }
    return null;
  }

  static _Analysis _analyze(String text) {
    final words = tokens(text);
    final scores = <String, int>{};
    final firstWord = <String, String>{};
    final firstPosition = <String, int>{};
    final byId = <String, StoryConcept>{};

    for (var i = 0; i < words.length; i++) {
      final concept = _lookup(normalize(words[i]));
      if (concept == null) continue;
      scores[concept.id] = (scores[concept.id] ?? 0) + concept.weight;
      firstWord.putIfAbsent(concept.id, () => words[i]);
      firstPosition.putIfAbsent(concept.id, () => i);
      byId[concept.id] = concept;
    }

    final ids = scores.keys.toList();
    ids.sort((a, b) {
      final byScore = scores[b]!.compareTo(scores[a]!);
      if (byScore != 0) return byScore;
      return firstPosition[a]!.compareTo(firstPosition[b]!);
    });

    if (ids.isEmpty) {
      var longest = '';
      for (final word in words) {
        if (word.length > longest.length) longest = word;
      }
      return _Analysis(top: null, second: null, score: 0, word: longest);
    }

    final top = byId[ids.first]!;
    final second = ids.length > 1 ? byId[ids[1]] : null;
    return _Analysis(
      top: top,
      second: second,
      score: scores[ids.first]!,
      word: firstWord[ids.first]!,
    );
  }

  static List<String> _propsOf(StoryConcept top, StoryConcept? second) {
    final result = <String>[...top.props.take(2)];
    if (second != null) {
      for (final prop in second.props) {
        if (result.length >= 3) break;
        if (!result.contains(prop)) result.add(prop);
      }
    }
    if (result.length < 3) {
      for (final prop in top.props) {
        if (result.length >= 3) break;
        if (!result.contains(prop)) result.add(prop);
      }
    }
    return result;
  }

  /// Plans the story of [segments] (in time order).
  static StoryPlan plan(List<StorySegment> segments) {
    final count = segments.length;
    final analyses = <_Analysis>[
      for (final segment in segments) _analyze(segment.text),
    ];

    // Pass 1: environment and mood of every beat. A segment without a known
    // idea keeps the previous environment, so the world stays the same.
    final environments = <StoryEnvironment>[];
    final moods = <StoryMood>[];
    for (var i = 0; i < count; i++) {
      final top = analyses[i].top;
      if (top != null) {
        environments.add(top.environment);
        moods.add(top.mood);
      } else if (i > 0) {
        environments.add(environments[i - 1]);
        moods.add(moods[i - 1]);
      } else {
        environments.add(StoryEnvironment.room);
        moods.add(StoryMood.calm);
      }
    }

    // Pass 2: where the story dives into the window to enter a new world.
    final windows = List<bool>.filled(count, false);
    for (var i = 0; i < count - 1; i++) {
      windows[i] = environments[i] != environments[i + 1] &&
          segments[i].duration >= 1.2 &&
          segments[i + 1].duration >= 1.2;
    }

    // Pass 3: shots, transitions and props.
    final beats = <StoryBeat>[];
    for (var i = 0; i < count; i++) {
      final segment = segments[i];
      final analysis = analyses[i];
      final arrival = i > 0 && windows[i - 1];

      StoryShotKind shot;
      DepthCameraMove hint;
      if (i == 0) {
        shot = StoryShotKind.establishing;
        hint = DepthCameraMove.craneUp;
      } else if (arrival) {
        shot = StoryShotKind.reveal;
        hint = DepthCameraMove.windowOut;
      } else if (analysis.score >= 3) {
        shot = StoryShotKind.closeUp;
        hint = DepthCameraMove.pushIn;
      } else if (segment.duration >= 3.2) {
        shot = StoryShotKind.medium;
        hint = i.isEven
            ? DepthCameraMove.orbitRight
            : DepthCameraMove.orbitLeft;
      } else {
        shot = StoryShotKind.detail;
        hint = DepthCameraMove.pullOut;
      }
      if (windows[i]) hint = DepthCameraMove.windowIn;

      MotionTransitionKind transition;
      if (i >= count - 1) {
        transition = MotionTransitionKind.hardCut;
      } else if (windows[i]) {
        transition = MotionTransitionKind.zoomSmash;
      } else if (environments[i] != environments[i + 1]) {
        transition = MotionTransitionKind.whipPan;
      } else if (segment.duration < 1.2) {
        transition = MotionTransitionKind.hardCut;
      } else {
        transition = MotionTransitionKind.matchCut;
      }

      final top = analysis.top;
      beats.add(
        StoryBeat(
          index: i,
          segment: segment,
          focus: top == null ? 'none' : top.id,
          environment: environments[i],
          mood: moods[i],
          props: top == null
              ? const <String>[]
              : _propsOf(top, analysis.second),
          effectWord: analysis.word,
          shot: shot,
          cameraHint: hint,
          transitionToNext: transition,
          windowToNext: windows[i],
        ),
      );
    }
    return StoryPlan(beats);
  }
}
