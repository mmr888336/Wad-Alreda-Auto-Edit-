/// Reference-video scene builder (Motion Smith style).
///
/// Turns a spoken phrase into a short motion cutaway made of scenes. Every
/// scene is a composition of layers: a pixel-grid background, one main
/// pixel-art sprite chosen from the MEANING of the words, a small orbiting
/// decor sprite, and up to three words that enter one by one with their own
/// timing, rotation and overshoot. Scenes are joined with the transition
/// library. The result is a renderer-neutral [MotionProject] plus the list of
/// assets the renderer has to create. Pure Dart, no I/O.
library;

import 'dart:math' as math;

import 'keyword_callout_planner.dart';
import 'motion_graphics.dart' show MotionMood;
import 'motion_scene_model.dart';
import 'motion_transitions.dart';

/// A moment of the video that will be replaced by a motion cutaway.
class CutawaySpec {
  final double start;
  final double end;
  final String text;

  const CutawaySpec({
    required this.start,
    required this.end,
    required this.text,
  });

  double get duration => end - start;
}

enum SceneAssetKind { background, sprite, word }

/// Describes one image the renderer must create for the motion project.
class SceneAssetSpec {
  final SceneAssetKind kind;

  /// Sprite key for [SceneAssetKind.sprite], for example `pixel_camera`.
  final String? spriteKey;

  /// Word to draw for [SceneAssetKind.word].
  final String? text;

  /// Width on screen at layer scale 1, as a fraction of the canvas width.
  final double widthFraction;

  /// Gradient colours (0xAARRGGBB) for [SceneAssetKind.background].
  final int topColor;
  final int bottomColor;

  const SceneAssetSpec({
    required this.kind,
    this.spriteKey,
    this.text,
    this.widthFraction = 1.0,
    this.topColor = 0xFF000000,
    this.bottomColor = 0xFF000000,
  });
}

class ReferenceSceneResult {
  final MotionProject project;

  /// Asset key (as used by [MotionLayer.assetKey]) -> what to render.
  final Map<String, SceneAssetSpec> assets;

  const ReferenceSceneResult({required this.project, required this.assets});
}

class _Candidate {
  final CutawaySpec spec;
  final double score;

  const _Candidate(this.spec, this.score);
}

class ReferenceSceneBuilder {
  ReferenceSceneBuilder._();

  /// Master switch for planning motion cutaways.
  static bool enabled = true;

  /// The hook title owns the first seconds of the video.
  static const double firstAllowedStart = 3.6;
  static const double minDuration = 1.2;
  static const double maxDuration = 2.6;
  static const double minimumGap = 7.0;

  /// Cutaways may cover at most this share of the video.
  static const double maxCoverage = 0.25;

  static const List<String> _fallbackSprites = <String>[
    'pixel_orange_mascot',
    'pixel_camera',
    'pixel_red_heart',
    'pixel_gold_coin',
    'pixel_potted_plant',
    'pixel_game_controller',
  ];

  // Stems are written already normalised (see [normalize]) and are matched
  // with startsWith after removing a leading definite article.
  static const Map<String, List<String>> _spriteStems = <String, List<String>>{
    'pixel_red_heart': <String>[
      'حب',
      'قلب',
      'رحم',
      'حنان',
      'عشق',
      'مود',
      'love',
      'heart',
    ],
    'pixel_gold_coin': <String>[
      'مال',
      'فلوس',
      'رزق',
      'ذهب',
      'كنز',
      'ثرو',
      'دينار',
      'ريال',
      'درهم',
      'دولار',
      'تجار',
      'ربح',
      'ارباح',
      'راتب',
      'استثمار',
      'money',
      'coin',
      'gold',
      'profit',
    ],
    'pixel_camera': <String>[
      'كاميرا',
      'فيديو',
      'تصوير',
      'صور',
      'مشاهد',
      'قناه',
      'محتوي',
      'مقطع',
      'لقطه',
      'video',
      'camera',
      'photo',
      'content',
      'stream',
    ],
    'pixel_potted_plant': <String>[
      'شجر',
      'نبات',
      'زرع',
      'نمو',
      'بركه',
      'ثمر',
      'ارض',
      'زهر',
      'ورد',
      'حديق',
      'خير',
      'طبيع',
      'plant',
      'tree',
      'grow',
      'nature',
      'garden',
    ],
    'pixel_game_controller': <String>[
      'لعب',
      'عاب',
      'تحدي',
      'مسابق',
      'جائز',
      'جايز',
      'فوز',
      'game',
      'play',
      'win',
      'challenge',
    ],
  };

  // Background gradients (top, bottom) as 0xAARRGGBB.
  static const List<List<int>> _palettes = <List<int>>[
    <int>[0xFF10153A, 0xFF2B1B5E],
    <int>[0xFF062B2F, 0xFF0F5257],
    <int>[0xFF2B0A12, 0xFF5A1626],
    <int>[0xFF1B1F0A, 0xFF3F4A14],
  ];

  /// Lower-cases Latin text and folds common Arabic spelling variants so a
  /// keyword matches however the speech-to-text wrote it.
  static String normalize(String text) {
    var out = text.toLowerCase();
    out = out.replaceAll(RegExp('[\u064B-\u065F\u0670\u0640]'), '');
    out = out
        .replaceAll('\u0623', '\u0627')
        .replaceAll('\u0625', '\u0627')
        .replaceAll('\u0622', '\u0627')
        .replaceAll('\u0649', '\u064A')
        .replaceAll('\u0629', '\u0647');
    return out;
  }

  static String _stripPrefix(String word) {
    const prefixes = <String>[
      '\u0648\u0627\u0644',
      '\u0628\u0627\u0644',
      '\u0643\u0627\u0644',
      '\u0641\u0627\u0644',
      '\u0644\u0644',
      '\u0627\u0644',
    ];
    for (final prefix in prefixes) {
      if (word.startsWith(prefix) && word.length - prefix.length >= 2) {
        return word.substring(prefix.length);
      }
    }
    return word;
  }

  /// Clean words of [text] (at least two letters, punctuation removed).
  static List<String> wordsOf(String text) {
    final out = <String>[];
    for (final raw in text.split(RegExp(r'\s+'))) {
      final word = KeywordCalloutPlanner.cleanWord(raw);
      if (word.runes.length >= 2) out.add(word);
    }
    return out;
  }

  /// The sprite that matches the meaning of [text], or null when no word of
  /// the text is a known keyword.
  static String? spriteKeyFor(String text) {
    for (final word in wordsOf(text)) {
      final stripped = _stripPrefix(normalize(word));
      if (stripped.length < 2) continue;
      for (final entry in _spriteStems.entries) {
        for (final stem in entry.value) {
          if (stripped.startsWith(stem)) return entry.key;
        }
      }
    }
    return null;
  }

  static bool _overlaps(double start, double end, List<List<double>> avoid) {
    for (final range in avoid) {
      if (range.length < 2) continue;
      if (start < range[1] && end > range[0]) return true;
    }
    return false;
  }

  /// Spreads at most [maxCount] cutaways over the video, preferring phrases
  /// with a strong keyword or a known sprite meaning.
  static List<CutawaySpec> planCutaways({
    required List<CalloutSource> captions,
    required double duration,
    int maxCount = 2,
    List<List<double>> avoid = const <List<double>>[],
  }) {
    if (!enabled || maxCount <= 0 || !duration.isFinite || duration < 8) {
      return const <CutawaySpec>[];
    }

    final candidates = <_Candidate>[];
    for (final caption in captions) {
      if (caption.end - caption.start < minDuration) continue;
      if (caption.start < firstAllowedStart) continue;
      if (caption.start > duration - 2.2) continue;

      final best = KeywordCalloutPlanner.bestWord(caption.text);
      final sprite = spriteKeyFor(caption.text);
      if (best == null && sprite == null) continue;

      final start = caption.start;
      final end = math.min(
        caption.end,
        math.min(start + maxDuration, duration - 0.3),
      );
      if (end - start < minDuration) continue;
      if (_overlaps(start, end, avoid)) continue;

      final score =
          (best == null ? 0 : best.runes.length) + (sprite == null ? 0 : 6);
      candidates.add(
        _Candidate(
          CutawaySpec(start: start, end: end, text: caption.text),
          score.toDouble(),
        ),
      );
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.spec.start.compareTo(b.spec.start);
    });

    final picked = <CutawaySpec>[];
    var covered = 0.0;
    for (final candidate in candidates) {
      if (picked.length >= maxCount) break;
      final spec = candidate.spec;
      if (covered + spec.duration > duration * maxCoverage) continue;
      var tooClose = false;
      for (final other in picked) {
        if ((spec.start - other.start).abs() < minimumGap) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) continue;
      picked.add(spec);
      covered += spec.duration;
    }

    picked.sort((a, b) => a.start.compareTo(b.start));
    return picked;
  }

  static List<String> _pickWords(List<String> all, int limit) {
    if (all.length <= limit) return all;
    final order = List<int>.generate(all.length, (i) => i);
    order.sort((a, b) {
      final byLength = all[b].runes.length.compareTo(all[a].runes.length);
      return byLength != 0 ? byLength : a.compareTo(b);
    });
    final keep = order.take(limit).toList()..sort();
    return <String>[for (final i in keep) all[i]];
  }

  static MotionTransitionKind _transitionFor(MotionMood mood, int variant) {
    const dynamicKinds = <MotionTransitionKind>[
      MotionTransitionKind.pixelBlockWipe,
      MotionTransitionKind.glitchSlice,
      MotionTransitionKind.zoomSmash,
      MotionTransitionKind.rgbSplit,
    ];
    const calmKinds = <MotionTransitionKind>[
      MotionTransitionKind.blurDissolve,
      MotionTransitionKind.lightLeak,
      MotionTransitionKind.matchCut,
    ];
    const cinematicKinds = <MotionTransitionKind>[
      MotionTransitionKind.whipPan,
      MotionTransitionKind.redFlash,
      MotionTransitionKind.blurDissolve,
    ];
    final kinds = switch (mood) {
      MotionMood.calm => calmKinds,
      MotionMood.cinematic => cinematicKinds,
      MotionMood.dynamic => dynamicKinds,
    };
    return kinds[variant.abs() % kinds.length];
  }

  static String _hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static List<MotionKeyframe> _spriteKeys(double dur) {
    final keys = <MotionKeyframe>[
      const MotionKeyframe(
        time: 0,
        x: 0.5,
        y: 0.38,
        scale: 0.05,
        rotation: -25,
        opacity: 0,
        easing: MotionEase.easeOut,
      ),
      const MotionKeyframe(
        time: 0.26,
        x: 0.5,
        y: 0.30,
        scale: 1.2,
        rotation: 8,
        easing: MotionEase.overshoot,
      ),
      const MotionKeyframe(
        time: 0.46,
        x: 0.5,
        y: 0.31,
        scale: 1.0,
        rotation: -4,
        easing: MotionEase.easeInOut,
      ),
    ];
    var t = 0.46;
    var up = true;
    while (t + 0.55 < dur - 0.2) {
      t += 0.55;
      keys.add(
        MotionKeyframe(
          time: t,
          x: 0.5,
          y: up ? 0.295 : 0.315,
          scale: up ? 1.04 : 0.98,
          rotation: up ? 5 : -5,
          easing: MotionEase.easeInOut,
        ),
      );
      up = !up;
    }
    keys.add(
      MotionKeyframe(
        time: dur,
        x: 0.5,
        y: 0.31,
        scale: 0.96,
        rotation: 0,
        easing: MotionEase.easeInOut,
      ),
    );
    return keys;
  }

  static List<MotionKeyframe> _decorKeys(double dur) {
    const step = 0.30;
    final keys = <MotionKeyframe>[];
    var t = 0.0;
    var k = 0;
    while (t < dur - 1e-6) {
      final a = k * math.pi / 4;
      keys.add(
        MotionKeyframe(
          time: t,
          x: 0.5 + 0.30 * math.cos(a),
          y: 0.30 + 0.09 * math.sin(a),
          rotation: k * 45.0,
          opacity: k == 0 ? 0 : 1,
          easing: MotionEase.linear,
        ),
      );
      t += step;
      k++;
    }
    final a = k * math.pi / 4;
    keys.add(
      MotionKeyframe(
        time: dur,
        x: 0.5 + 0.30 * math.cos(a),
        y: 0.30 + 0.09 * math.sin(a),
        rotation: k * 45.0,
        easing: MotionEase.linear,
      ),
    );
    return keys;
  }

  static List<MotionKeyframe> _wordKeys(double layerDur, double y, int j) {
    final rot = j.isEven ? -9.0 : 9.0;
    final t1 = math.min(0.22, layerDur * 0.30);
    final t2 = math.min(0.40, layerDur * 0.55);
    return <MotionKeyframe>[
      MotionKeyframe(
        time: 0,
        x: 0.5,
        y: y + 0.10,
        scale: 0.55,
        rotation: rot,
        opacity: 0,
        easing: MotionEase.easeOut,
      ),
      MotionKeyframe(
        time: t1,
        x: 0.5,
        y: y - 0.012,
        scale: 1.12,
        rotation: -rot * 0.4,
        easing: MotionEase.overshoot,
      ),
      MotionKeyframe(
        time: t2,
        x: 0.5,
        y: y,
        scale: 1.0,
        rotation: 0,
        easing: MotionEase.easeInOut,
      ),
      MotionKeyframe(
        time: layerDur,
        x: 0.5,
        y: y - 0.006,
        scale: 1.03,
        rotation: -rot * 0.1,
        easing: MotionEase.easeInOut,
      ),
    ];
  }

  /// Builds the motion project for one cutaway. The project timeline starts
  /// at zero; its length matches [CutawaySpec.duration] (a two-scene cutaway
  /// overlaps its scenes by the transition length, so the rendered clip
  /// length is the scene sum minus that overlap).
  static ReferenceSceneResult buildCutaway({
    required String id,
    required CutawaySpec spec,
    required int width,
    required int height,
    int frameRate = 30,
    MotionMood mood = MotionMood.cinematic,
    int variant = 0,
  }) {
    if (width <= 0 || height <= 0 || frameRate <= 0) {
      throw ArgumentError('Invalid canvas size.');
    }
    final total = spec.duration;
    if (!total.isFinite || total < 1.0) {
      throw StateError('Cutaway is too short: $total');
    }

    final words = wordsOf(spec.text);
    final sceneCount = total >= 2.4 ? 2 : 1;
    final transition = sceneCount == 2
        ? _transitionFor(mood, variant)
        : MotionTransitionKind.hardCut;
    final overlap =
        sceneCount == 2 ? MotionTransitions.defaultDuration(transition) : 0.0;
    final sceneDuration = sceneCount == 2 ? (total + overlap) / 2 : total;

    final perScene = (words.length / sceneCount).ceil();
    final spriteFraction = height >= width ? 0.34 : 0.22;
    final assets = <String, SceneAssetSpec>{};
    final scenes = <MotionScene>[];
    var cursor = 0.0;

    for (var si = 0; si < sceneCount; si++) {
      final sid = '${id}_s$si';
      final sceneStart = cursor;
      final sceneEnd = cursor + sceneDuration;
      final dur = sceneEnd - sceneStart;

      final from = math.min(words.length, si * perScene);
      final to = math.min(words.length, from + perScene);
      final sceneWords = _pickWords(words.sublist(from, to), 3);
      final sceneText = sceneWords.join(' ');

      final mainSprite = spriteKeyFor(sceneText) ??
          spriteKeyFor(spec.text) ??
          _fallbackSprites[(variant + si).abs() % _fallbackSprites.length];
      final mainIndex = _fallbackSprites.indexOf(mainSprite);
      final decorSprite = _fallbackSprites[
          ((mainIndex < 0 ? 0 : mainIndex) + 1 + variant.abs()) %
              _fallbackSprites.length];

      final palette = _palettes[(variant + si).abs() % _palettes.length];
      assets['bg:$sid'] = SceneAssetSpec(
        kind: SceneAssetKind.background,
        topColor: palette[0],
        bottomColor: palette[1],
      );
      assets['sprite:$sid'] = SceneAssetSpec(
        kind: SceneAssetKind.sprite,
        spriteKey: mainSprite,
        widthFraction: spriteFraction,
      );
      assets['decor:$sid'] = SceneAssetSpec(
        kind: SceneAssetKind.sprite,
        spriteKey: decorSprite,
        widthFraction: spriteFraction * 0.42,
      );

      final layers = <MotionLayer>[
        MotionLayer(
          id: '${sid}_bg',
          start: sceneStart,
          end: sceneEnd,
          zIndex: 0,
          assetKey: 'bg:$sid',
        ),
        MotionLayer(
          id: '${sid}_decor',
          start: sceneStart,
          end: sceneEnd,
          zIndex: 5,
          assetKey: 'decor:$sid',
          keyframes: _decorKeys(dur),
        ),
        MotionLayer(
          id: '${sid}_sprite',
          start: sceneStart,
          end: sceneEnd,
          zIndex: 10,
          assetKey: 'sprite:$sid',
          keyframes: _spriteKeys(dur),
        ),
      ];

      final stagger = sceneWords.isEmpty
          ? 0.0
          : math.min(0.28, (dur - 0.7) / sceneWords.length);
      for (var j = 0; j < sceneWords.length; j++) {
        final layerId = '${sid}_w$j';
        final layerStart = sceneStart + 0.10 + j * stagger;
        final y = 0.50 + j * 0.105;
        assets['text:$layerId'] = SceneAssetSpec(
          kind: SceneAssetKind.word,
          text: sceneWords[j],
        );
        layers.add(
          MotionLayer(
            id: layerId,
            start: layerStart,
            end: sceneEnd,
            zIndex: 20 + j,
            assetKey: 'text:$layerId',
            text: sceneWords[j],
            keyframes: _wordKeys(sceneEnd - layerStart, y, j),
          ),
        );
      }

      scenes.add(
        MotionScene(
          id: sid,
          start: sceneStart,
          end: sceneEnd,
          background: _hex(palette[0]),
          transitionIn: si == 0 ? MotionTransitionKind.hardCut : transition,
          layers: layers,
        ),
      );
      cursor = sceneEnd;
    }

    return ReferenceSceneResult(
      project: MotionProject(
        id: id,
        width: width,
        height: height,
        frameRate: frameRate,
        duration: cursor,
        scenes: scenes,
      ),
      assets: assets,
    );
  }
}
