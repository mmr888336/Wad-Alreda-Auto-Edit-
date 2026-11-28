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
library story_understanding;

import 'depth_camera_model.dart' show DepthCameraMove;
import 'domain_story_pack.dart';
import 'motion_transitions.dart' show MotionTransitionKind;
import 'transition_director.dart';

/// The place a segment happens in.
enum StoryEnvironment {
  office,
  room,
  library,
  street,
  studio,
  outdoors,
  bathroom,
  kitchen,
  bedroom,
  livingRoom,
  hallway,
}

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

  /// Id of the domain pack that routed this beat, or `everyday_explainer`.
  final String domainId;

  /// What the speaker is doing with the idea: explaining a place, comparing
  /// two places, telling a story, warning, using a metaphor. Defaults to
  /// [StoryIntent.explain] so existing callers keep working.
  final StoryIntent intent;

  /// One short sentence (Arabic) that says what the viewer should see. Used
  /// by the diagnostics report and by the Live Assembly Board.
  final String visualExplanation;

  /// 0..1 confidence of the domain routing. Low confidence means the beat
  /// keeps the everyday lexicon.
  final double confidence;

  /// Relations between this beat and the previous one (comparison, cause,
  /// example, metaphor). Empty when there is no relation.
  final List<StoryRelation> relations;

  /// Zones of this beat (one or more connected places). Empty means the
  /// environment of the beat is a single zone.
  final List<StoryZone> zones;

  /// Shot plan of this beat (one or more shots). Empty means the beat is a
  /// single shot.
  final List<StoryShot> shotPlan;

  /// Transition plan into the next beat. Null means the beat uses
  /// [transitionToNext] as before.
  final StoryTransitionPlan? transitionPlan;

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
    this.domainId = 'everyday_explainer',
    this.intent = StoryIntent.explain,
    this.visualExplanation = '',
    this.confidence = 0,
    this.relations = const <StoryRelation>[],
    this.zones = const <StoryZone>[],
    this.shotPlan = const <StoryShot>[],
    this.transitionPlan,
  });
}

/// What the speaker is doing with the idea of a beat.
enum StoryIntent {
  /// Explaining a place, an object or a concept.
  explain,

  /// Comparing two places or two ideas.
  compare,

  /// Telling a story (a sequence of events).
  story,

  /// Warning about a risk.
  warn,

  /// Using a metaphor (the words are not literal).
  metaphor,
}

/// A relation between two beats.
enum StoryRelation {
  /// The beat compares two things.
  comparison,

  /// The beat is a cause of the next one.
  cause,

  /// The beat is an example of the previous one.
  example,

  /// The beat is a metaphor of the previous one.
  metaphor,
}

/// One connected place of a beat.
class StoryZone {
  /// Stable id inside the beat (`bathroom`, `hallway`, `bedroom`).
  final String id;

  /// Environment of the zone.
  final StoryEnvironment environment;

  /// Objects that belong to the zone (asset-style keys).
  final List<String> props;

  /// Ids of the zones this one connects to (portals).
  final List<String> portals;

  const StoryZone({
    required this.id,
    required this.environment,
    required this.props,
    this.portals = const <String>[],
  });
}

/// One shot of a beat.
class StoryShot {
  /// Stable id inside the beat (`wide`, `crane`, `push_in`).
  final String id;

  /// Kind of shot.
  final StoryShotKind kind;

  /// Camera move of the shot.
  final DepthCameraMove camera;

  /// Start and end of the shot inside the beat, in seconds from the beat
  /// start. The last shot ends at the beat duration.
  final double start;
  final double end;

  const StoryShot({
    required this.id,
    required this.kind,
    required this.camera,
    required this.start,
    required this.end,
  });

  double get duration => end - start;
}

/// The plan of the transition into the next beat.
class StoryTransitionPlan {
  /// Transition kind (the renderer already knows how to draw it).
  final MotionTransitionKind kind;

  /// Duration in seconds.
  final double duration;

  /// Why this transition was chosen (Arabic, for diagnostics).
  final String reason;

  /// 0..1 score of the chosen transition.
  final double score;

  /// Fallback kind when the chosen one cannot be rendered.
  final MotionTransitionKind fallback;

  const StoryTransitionPlan({
    required this.kind,
    required this.duration,
    required this.reason,
    required this.score,
    required this.fallback,
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
    StoryConcept(
      id: 'bathroom',
      environment: StoryEnvironment.bathroom,
      mood: StoryMood.calm,
      weight: 3,
      props: <String>['sink', 'mirror', 'bathtub'],
      triggers: <String>[
        'حمام', 'حمامات', 'دورة مياه', 'دورة مياة', 'تواليت', 'مرحاض',
        'bathroom', 'bath', 'toilet', 'restroom', 'washroom',
      ],
    ),
    StoryConcept(
      id: 'kitchen',
      environment: StoryEnvironment.kitchen,
      mood: StoryMood.calm,
      weight: 3,
      props: <String>['stove', 'fridge', 'counter'],
      triggers: <String>[
        'مطبخ', 'مطابخ', 'طبخ', 'فرن', 'ثلاجة', 'ثلاجه', 'بوتاجاز',
        'kitchen', 'cook', 'cooking', 'stove', 'fridge', 'oven',
      ],
    ),
    StoryConcept(
      id: 'bedroom',
      environment: StoryEnvironment.bedroom,
      mood: StoryMood.calm,
      weight: 3,
      props: <String>['bed', 'wardrobe', 'nightstand'],
      triggers: <String>[
        'غرفة نوم', 'غرفه نوم', 'غرف نوم', 'سرير', 'نوم', 'دولاب',
        'bedroom', 'bed', 'sleep', 'wardrobe',
      ],
    ),
    StoryConcept(
      id: 'living_room',
      environment: StoryEnvironment.livingRoom,
      mood: StoryMood.calm,
      weight: 3,
      props: <String>['sofa', 'tv', 'coffee_table'],
      triggers: <String>[
        'صالة', 'صاله', 'صالون', 'غرفة معيشة', 'غرفه معيشه', 'معيشة',
        'معيشه', 'كنبة', 'كنبه', 'انتريه',
        'living', 'living room', 'lounge', 'sofa', 'couch',
      ],
    ),
    StoryConcept(
      id: 'hallway',
      environment: StoryEnvironment.hallway,
      mood: StoryMood.calm,
      weight: 2,
      props: <String>['door_frame', 'corridor_floor'],
      triggers: <String>[
        'ممر', 'ممرات', 'طرقة', 'طرقه', 'كوريدور',
        'hallway', 'corridor', 'hall',
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

  /// Routes [text] to a domain pack. Returns the pack and a 0..1 confidence.
  /// The everyday pack is returned when no domain word is found.
  static ({DomainStoryPack pack, double confidence}) route(String text) {
    final normalized = normalize(text);
    final words = normalized.split(_splitter).where((w) => w.isNotEmpty).toSet();
    if (words.isEmpty) {
      return (pack: DomainStoryPacks.byId('everyday_explainer')!, confidence: 0);
    }

    DomainStoryPack? best;
    var bestScore = 0;
    for (final pack in DomainStoryPacks.all) {
      if (pack.id == 'everyday_explainer') continue;
      var score = 0;
      for (final trigger in pack.triggers) {
        final key = normalize(trigger);
        if (key.isEmpty) continue;
        if (words.contains(key)) {
          score += 2;
        } else if (key.length >= 4 && normalized.contains(key)) {
          score += 1;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = pack;
      }
    }

    if (best == null) {
      return (pack: DomainStoryPacks.byId('everyday_explainer')!, confidence: 0);
    }
    final confidence = (bestScore / 6).clamp(0.0, 1.0).toDouble();
    return (pack: best, confidence: confidence);
  }

  /// Plans the story of [segments] (in time order).
  static StoryPlan plan(List<StorySegment> segments) {
    final count = segments.length;
    final analyses = <_Analysis>[
      for (final segment in segments) _analyze(segment.text),
    ];
    final routes = <({DomainStoryPack pack, double confidence})>[
      for (final segment in segments) route(segment.text),
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
      final route = routes[i];
      final domainId = route.confidence >= 0.34 ? route.pack.id : 'everyday_explainer';
      final intent = _intentOf(segment.text, analysis);
      final relations = _relationsOf(segment.text, analysis);
      final previousZones =
          beats.isEmpty ? const <StoryZone>[] : beats.last.zones;
      final zones = _zonesOf(
        environments[i],
        top,
        analysis.second,
        intent: intent,
        previousZones: previousZones,
      );
      final shotPlan = _shotPlanOf(segment.duration, shot, hint);
      final transitionPlan = i + 1 < count
          ? TransitionDirector.plan(
              from: beats.isEmpty ? _placeholderBeat(i, segment) : beats.last,
              to: _placeholderBeat(i + 1, segments[i + 1]),
              fromDuration: segment.duration,
              toDuration: segments[i + 1].duration,
              fromEnvironment: environments[i],
              toEnvironment: environments[i + 1],
              window: windows[i],
              fromShot: shot,
              toShot: StoryShotKind.medium,
              fromCamera: hint,
              toCamera: DepthCameraMove.none,
              fromZones: zones,
              toZones: const <StoryZone>[],
              fromIntent: intent,
              toIntent: StoryIntent.explain,
              fromRelations: relations,
            )
          : null;

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
          domainId: domainId,
          intent: intent,
          visualExplanation: _explain(environments[i], top, intent),
          confidence: route.confidence,
          relations: relations,
          zones: zones,
          shotPlan: shotPlan,
          transitionPlan: transitionPlan,
        ),
      );
    }
    return StoryPlan(beats);
  }

  static StoryIntent _intentOf(String text, _Analysis analysis) {
    final normalized = normalize(text);
    if (normalized.contains('مثل') || normalized.contains('كأن') ||
        normalized.contains('كأنه') || normalized.contains('like ')) {
      return StoryIntent.metaphor;
    }
    if (normalized.contains('مقارنة') || normalized.contains('مقارنه') ||
        normalized.contains('أفضل') || normalized.contains('افضل') ||
        normalized.contains('compare') || normalized.contains('better')) {
      return StoryIntent.compare;
    }
    if (normalized.contains('خطر') || normalized.contains('تحذير') ||
        normalized.contains('احذر') || normalized.contains('warning') ||
        normalized.contains('danger')) {
      return StoryIntent.warn;
    }
    if (normalized.contains('قصة') || normalized.contains('قصه') ||
        normalized.contains('حكاية') || normalized.contains('حكايه') ||
        normalized.contains('story') || normalized.contains('once')) {
      return StoryIntent.story;
    }
    return StoryIntent.explain;
  }

  static List<StoryRelation> _relationsOf(String text, _Analysis analysis) {
    final normalized = normalize(text);
    final relations = <StoryRelation>[];
    if (normalized.contains('لأن') || normalized.contains('لانه') ||
        normalized.contains('بسبب') || normalized.contains('because')) {
      relations.add(StoryRelation.cause);
    }
    if (normalized.contains('مثال') || normalized.contains('مثلا') ||
        normalized.contains('example')) {
      relations.add(StoryRelation.example);
    }
    if (normalized.contains('مثل') || normalized.contains('كأن') ||
        normalized.contains('like ')) {
      relations.add(StoryRelation.metaphor);
    }
    if (normalized.contains('مقارنة') || normalized.contains('مقارنه') ||
        normalized.contains('compare')) {
      relations.add(StoryRelation.comparison);
    }
    return relations;
  }

  /// Zones of one beat.
  ///
  /// A beat always has at least one zone (its environment). It gets a second
  /// zone when:
  ///  * the speaker compares two places ([StoryIntent.compare]) and the
  ///    second idea of the sentence lives in a different environment; or
  ///  * the previous beat already had a zone in another environment and the
  ///    current beat is a continuation of it (a portal between the two).
  ///
  /// The zones are connected through [StoryZone.portals] so the renderer can
  /// move from one to the other instead of cutting.
  static List<StoryZone> _zonesOf(
    StoryEnvironment environment,
    StoryConcept? top,
    StoryConcept? second, {
    StoryIntent intent = StoryIntent.explain,
    List<StoryZone> previousZones = const <StoryZone>[],
  }) {
    final props = top == null
        ? const <String>[]
        : _propsOf(top, second);
    final primary = StoryZone(
      id: environment.name,
      environment: environment,
      props: props,
    );

    // A comparison of two places: the second idea becomes a second zone.
    if (intent == StoryIntent.compare &&
        second != null &&
        second.environment != environment) {
      final secondary = StoryZone(
        id: second.environment.name,
        environment: second.environment,
        props: _propsOf(second, top),
      );
      return <StoryZone>[
        StoryZone(
          id: primary.id,
          environment: primary.environment,
          props: primary.props,
          portals: <String>[secondary.id],
        ),
        StoryZone(
          id: secondary.id,
          environment: secondary.environment,
          props: secondary.props,
          portals: <String>[primary.id],
        ),
      ];
    }

    // A continuation of a previous beat that already had a second zone in
    // another environment: keep the portal so the camera can travel.
    for (final previous in previousZones) {
      if (previous.environment == environment) continue;
      return <StoryZone>[
        StoryZone(
          id: primary.id,
          environment: primary.environment,
          props: primary.props,
          portals: <String>[previous.id],
        ),
        StoryZone(
          id: previous.id,
          environment: previous.environment,
          props: previous.props,
          portals: <String>[primary.id],
        ),
      ];
    }

    return <StoryZone>[primary];
  }

  /// Shot plan of one beat.
  ///
  /// A short beat is one shot. A beat of at least [multiShotSeconds] seconds
  /// is split into three contiguous shots (establishing -> medium -> closeUp)
  /// so the camera changes inside the beat instead of holding one framing.
  /// The shots always cover the whole beat: each shot ends where the next one
  /// begins, and the last one ends at the beat duration.
  static const double multiShotSeconds = 3.2;

  static List<StoryShot> _shotPlanOf(
    double duration,
    StoryShotKind kind,
    DepthCameraMove camera,
  ) {
    if (!duration.isFinite || duration <= 0) return const <StoryShot>[];

    if (duration < multiShotSeconds) {
      return <StoryShot>[
        StoryShot(
          id: 'main',
          kind: kind,
          camera: camera,
          start: 0,
          end: duration,
        ),
      ];
    }

    // Three contiguous shots: 40% establishing, 35% medium, 25% closeUp.
    final firstEnd = duration * 0.40;
    final secondEnd = duration * 0.75;
    return <StoryShot>[
      StoryShot(
        id: 'establishing',
        kind: StoryShotKind.establishing,
        camera: DepthCameraMove.craneUp,
        start: 0,
        end: firstEnd,
      ),
      StoryShot(
        id: 'medium',
        kind: StoryShotKind.medium,
        camera: DepthCameraMove.orbitRight,
        start: firstEnd,
        end: secondEnd,
      ),
      StoryShot(
        id: 'closeUp',
        kind: StoryShotKind.closeUp,
        camera: DepthCameraMove.pushIn,
        start: secondEnd,
        end: duration,
      ),
    ];
  }

  /// A minimal beat used only to ask the director for a transition before the
  /// real beat is built. It carries the fields the director reads.
  static StoryBeat _placeholderBeat(int index, StorySegment segment) {
    return StoryBeat(
      index: index,
      segment: segment,
      focus: 'none',
      environment: StoryEnvironment.room,
      mood: StoryMood.calm,
      props: const <String>[],
      effectWord: '',
      shot: StoryShotKind.medium,
      cameraHint: DepthCameraMove.none,
      transitionToNext: MotionTransitionKind.hardCut,
      windowToNext: false,
    );
  }

  static String _explain(
    StoryEnvironment environment,
    StoryConcept? top,
    StoryIntent intent,
  ) {
    final place = switch (environment) {
      StoryEnvironment.office => 'مكتب',
      StoryEnvironment.room => 'غرفة',
      StoryEnvironment.library => 'مكتبة',
      StoryEnvironment.street => 'شارع',
      StoryEnvironment.studio => 'استوديو',
      StoryEnvironment.outdoors => 'خارج',
      StoryEnvironment.bathroom => 'حمام',
      StoryEnvironment.kitchen => 'مطبخ',
      StoryEnvironment.bedroom => 'غرفة نوم',
      StoryEnvironment.livingRoom => 'صالة',
      StoryEnvironment.hallway => 'ممر',
    };
    final idea = top?.id ?? 'فكرة عامة';
    final verb = switch (intent) {
      StoryIntent.explain => 'شرح',
      StoryIntent.compare => 'مقارنة',
      StoryIntent.story => 'قصة',
      StoryIntent.warn => 'تحذير',
      StoryIntent.metaphor => 'استعارة',
    };
    return '$verb $idea في $place';
  }
}
