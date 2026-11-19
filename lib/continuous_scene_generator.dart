/// Continuous scene generator.
///
/// A cutaway is no longer two or three scenes with the same layout. The
/// phrase is cut into short beats (about 1.4 s each, up to five) and every
/// beat gets its OWN composition, chosen from the character of the sentence:
/// a question opens with a title on top, a number gets one huge word, an
/// exclamation spins its subject in, a list walks diagonally, a long sentence
/// puts its words on a lower third... A composition never repeats the scene
/// before it (nor, when possible, the one before that), so the shape of the
/// video keeps changing.
///
/// The visual content of every beat (pixel sprite, semantic library visual,
/// VFX overlay, background, cinematic look) still comes from
/// [ReferenceSceneBuilder]: every beat is built as a mini cutaway, then its
/// sprite, decor and word layers are re-animated for the chosen composition
/// and the beats are joined with a SHORT transition (0.35 seconds at most,
/// the same kinds the scene builder uses, never the same one twice in a row).
/// The depth camera (see DepthCameraPlanner) is added afterwards by the
/// renderer, so perspective changes from scene to scene as well.
///
/// Story world: the beats are also read as a story (see
/// [StoryWorldBridge.plan]: StoryUnderstanding, then CinematicWorld). Every
/// scene then gets the fixed world art of its environment: the backdrop in
/// the fixed palette, the ONE main character at the same place in every
/// scene, and the props chosen by the meaning of the sentence, each with its
/// own depth. The scene's own background gradient and its companion mascot
/// are replaced by them (a main sprite that is the mascot itself is replaced
/// by the character too). [worldEnabled] switches this off. Pure Dart, no
/// I/O.
library;

import 'dart:math' as math;

import 'motion_graphics.dart' show MotionMood;
import 'motion_scene_editing.dart';
import 'motion_scene_model.dart';
import 'motion_transitions.dart';
import 'reference_scene_builder.dart';
import 'story_understanding.dart' show StorySegment;
import 'story_world_bridge.dart';

/// Where the elements of a scene sit and how they enter.
enum SceneLayout {
  /// Subject in the upper middle, words below (the classic look).
  heroCenter,

  /// Subject slides in from the left, words on the right side.
  heroLeft,

  /// Subject slides in from the right, words on the left side.
  heroRight,

  /// Words on top (dropping in), subject in the middle.
  titleTop,

  /// Small subject, one huge word block in the middle.
  bigWord,

  /// Subject top-left, words walking down diagonally.
  diagonal,

  /// Big subject in the middle, words as a lower third.
  lowerThird,

  /// Subject spins in from a tiny size, words below.
  spinReveal,
}

/// What a sentence (or beat) is like.
enum SentenceKind { plain, question, number, exclaim, list, short, long }

/// How the small decor sprite moves.
enum DecorMotion { orbit, float }

/// Numbers of one [SceneLayout]. Positions are normalised canvas units.
class SceneComposition {
  final SceneLayout layout;

  /// Resting place of the main sprite and where it enters from.
  final double spriteX;
  final double spriteY;
  final double fromX;
  final double fromY;
  final double spriteScale;

  /// Rotation (degrees) the sprite starts with.
  final double entrySpin;

  final DecorMotion decor;
  final double decorX;
  final double decorY;

  /// First word position, the step to the next word, where words enter
  /// from (offset) and their size factor.
  final double wordX;
  final double wordY;
  final double wordStepX;
  final double wordStepY;
  final double wordFromDx;
  final double wordFromDy;
  final double wordScale;

  const SceneComposition({
    required this.layout,
    required this.spriteX,
    required this.spriteY,
    required this.fromX,
    required this.fromY,
    required this.spriteScale,
    required this.entrySpin,
    required this.decor,
    required this.decorX,
    required this.decorY,
    required this.wordX,
    required this.wordY,
    required this.wordStepX,
    required this.wordStepY,
    required this.wordFromDx,
    required this.wordFromDy,
    required this.wordScale,
  });

  static SceneComposition of(SceneLayout layout) {
    switch (layout) {
      case SceneLayout.heroCenter:
        return const SceneComposition(
          layout: SceneLayout.heroCenter,
          spriteX: 0.5,
          spriteY: 0.31,
          fromX: 0.5,
          fromY: 0.38,
          spriteScale: 1.0,
          entrySpin: -25,
          decor: DecorMotion.orbit,
          decorX: 0.5,
          decorY: 0.30,
          wordX: 0.5,
          wordY: 0.50,
          wordStepX: 0,
          wordStepY: 0.105,
          wordFromDx: 0,
          wordFromDy: 0.10,
          wordScale: 1.0,
        );
      case SceneLayout.heroLeft:
        return const SceneComposition(
          layout: SceneLayout.heroLeft,
          spriteX: 0.30,
          spriteY: 0.32,
          fromX: -0.12,
          fromY: 0.32,
          spriteScale: 1.0,
          entrySpin: -25,
          decor: DecorMotion.float,
          decorX: 0.80,
          decorY: 0.20,
          wordX: 0.56,
          wordY: 0.52,
          wordStepX: 0,
          wordStepY: 0.105,
          wordFromDx: 0.10,
          wordFromDy: 0.04,
          wordScale: 1.0,
        );
      case SceneLayout.heroRight:
        return const SceneComposition(
          layout: SceneLayout.heroRight,
          spriteX: 0.70,
          spriteY: 0.32,
          fromX: 1.12,
          fromY: 0.32,
          spriteScale: 1.0,
          entrySpin: 25,
          decor: DecorMotion.float,
          decorX: 0.20,
          decorY: 0.20,
          wordX: 0.44,
          wordY: 0.52,
          wordStepX: 0,
          wordStepY: 0.105,
          wordFromDx: -0.10,
          wordFromDy: 0.04,
          wordScale: 1.0,
        );
      case SceneLayout.titleTop:
        return const SceneComposition(
          layout: SceneLayout.titleTop,
          spriteX: 0.5,
          spriteY: 0.55,
          fromX: 0.5,
          fromY: 0.75,
          spriteScale: 1.1,
          entrySpin: 20,
          decor: DecorMotion.orbit,
          decorX: 0.5,
          decorY: 0.55,
          wordX: 0.5,
          wordY: 0.16,
          wordStepX: 0,
          wordStepY: 0.10,
          wordFromDx: 0,
          wordFromDy: -0.10,
          wordScale: 1.0,
        );
      case SceneLayout.bigWord:
        return const SceneComposition(
          layout: SceneLayout.bigWord,
          spriteX: 0.5,
          spriteY: 0.22,
          fromX: 0.5,
          fromY: 0.10,
          spriteScale: 0.7,
          entrySpin: -40,
          decor: DecorMotion.float,
          decorX: 0.82,
          decorY: 0.30,
          wordX: 0.5,
          wordY: 0.42,
          wordStepX: 0,
          wordStepY: 0.12,
          wordFromDx: 0,
          wordFromDy: 0.12,
          wordScale: 1.25,
        );
      case SceneLayout.diagonal:
        return const SceneComposition(
          layout: SceneLayout.diagonal,
          spriteX: 0.34,
          spriteY: 0.28,
          fromX: 0.05,
          fromY: 0.02,
          spriteScale: 1.0,
          entrySpin: -60,
          decor: DecorMotion.float,
          decorX: 0.80,
          decorY: 0.26,
          wordX: 0.40,
          wordY: 0.46,
          wordStepX: 0.08,
          wordStepY: 0.11,
          wordFromDx: 0.10,
          wordFromDy: 0.06,
          wordScale: 1.0,
        );
      case SceneLayout.lowerThird:
        return const SceneComposition(
          layout: SceneLayout.lowerThird,
          spriteX: 0.5,
          spriteY: 0.40,
          fromX: 0.5,
          fromY: 0.58,
          spriteScale: 1.15,
          entrySpin: 0,
          decor: DecorMotion.orbit,
          decorX: 0.5,
          decorY: 0.40,
          wordX: 0.5,
          wordY: 0.70,
          wordStepX: 0,
          wordStepY: 0.08,
          wordFromDx: 0,
          wordFromDy: 0.10,
          wordScale: 0.95,
        );
      case SceneLayout.spinReveal:
        return const SceneComposition(
          layout: SceneLayout.spinReveal,
          spriteX: 0.5,
          spriteY: 0.36,
          fromX: 0.5,
          fromY: 0.36,
          spriteScale: 1.1,
          entrySpin: -180,
          decor: DecorMotion.orbit,
          decorX: 0.5,
          decorY: 0.36,
          wordX: 0.5,
          wordY: 0.58,
          wordStepX: 0,
          wordStepY: 0.10,
          wordFromDx: 0,
          wordFromDy: 0.12,
          wordScale: 1.05,
        );
    }
  }
}

/// Reads a sentence and picks a layout for it.
class SceneCompositionPlanner {
  SceneCompositionPlanner._();

  // Normalised (see ReferenceSceneBuilder.normalize) question openers.
  static const Set<String> _questionWords = <String>{
    'هل',
    'كيف',
    'ليش',
    'لماذا',
    'ليه',
    'شنو',
    'ايش',
    'وين',
    'متي',
    'كم',
    'ماذا',
    'why',
    'how',
    'what',
    'who',
    'when',
    'where',
  };

  static const Map<SentenceKind, List<SceneLayout>> _pools =
      <SentenceKind, List<SceneLayout>>{
    SentenceKind.question: <SceneLayout>[
      SceneLayout.titleTop,
      SceneLayout.spinReveal,
      SceneLayout.heroCenter,
    ],
    SentenceKind.number: <SceneLayout>[
      SceneLayout.bigWord,
      SceneLayout.lowerThird,
      SceneLayout.heroLeft,
    ],
    SentenceKind.exclaim: <SceneLayout>[
      SceneLayout.spinReveal,
      SceneLayout.diagonal,
      SceneLayout.bigWord,
    ],
    SentenceKind.list: <SceneLayout>[
      SceneLayout.diagonal,
      SceneLayout.heroRight,
      SceneLayout.heroLeft,
    ],
    SentenceKind.short: <SceneLayout>[
      SceneLayout.bigWord,
      SceneLayout.heroCenter,
      SceneLayout.spinReveal,
    ],
    SentenceKind.long: <SceneLayout>[
      SceneLayout.lowerThird,
      SceneLayout.heroLeft,
      SceneLayout.heroRight,
      SceneLayout.titleTop,
    ],
    SentenceKind.plain: <SceneLayout>[
      SceneLayout.heroCenter,
      SceneLayout.heroLeft,
      SceneLayout.heroRight,
      SceneLayout.titleTop,
      SceneLayout.lowerThird,
      SceneLayout.diagonal,
    ],
  };

  /// The character of [text].
  static SentenceKind classify(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return SentenceKind.plain;
    final words = ReferenceSceneBuilder.wordsOf(raw);

    if (raw.contains('؟') || raw.contains('?')) return SentenceKind.question;
    if (words.isNotEmpty &&
        _questionWords.contains(ReferenceSceneBuilder.normalize(words.first))) {
      return SentenceKind.question;
    }
    if (RegExp('[0-9\u0660-\u0669]').hasMatch(raw)) return SentenceKind.number;
    if (raw.contains('!')) return SentenceKind.exclaim;
    if (raw.split(RegExp('[،,]')).where((p) => p.trim().isNotEmpty).length >=
        3) {
      return SentenceKind.list;
    }
    if (words.length <= 2) return SentenceKind.short;
    if (words.length >= 6) return SentenceKind.long;
    return SentenceKind.plain;
  }

  /// The layout of scene number [sceneIndex]. It is never [previous], and
  /// avoids [beforePrevious] whenever the pool allows. Deterministic for the
  /// same [variant], so a re-render draws the same scene.
  static SceneLayout pick({
    required SentenceKind kind,
    required int sceneIndex,
    int variant = 0,
    SceneLayout? previous,
    SceneLayout? beforePrevious,
  }) {
    final pool = _pools[kind] ?? _pools[SentenceKind.plain]!;
    final start = (variant.abs() + sceneIndex.abs()) % pool.length;
    for (var i = 0; i < pool.length; i++) {
      final candidate = pool[(start + i) % pool.length];
      if (candidate != previous && candidate != beforePrevious) {
        return candidate;
      }
    }
    for (var i = 0; i < pool.length; i++) {
      final candidate = pool[(start + i) % pool.length];
      if (candidate != previous) return candidate;
    }
    for (final candidate in SceneLayout.values) {
      if (candidate != previous) return candidate;
    }
    return pool.first;
  }
}

/// A generated cutaway and the layout of each of its scenes.
class ContinuousScenePlan {
  final ReferenceSceneResult result;
  final List<SceneLayout> layouts;

  /// The story and the world planned for this cutaway, or null when the
  /// world is switched off or could not be planned.
  final StoryWorldPlan? world;

  const ContinuousScenePlan({
    required this.result,
    required this.layouts,
    this.world,
  });
}

class ContinuousSceneGenerator {
  ContinuousSceneGenerator._();

  /// Master switch: when false the renderer uses the plain scene builder.
  static bool enabled = true;

  /// Story world: the fixed character, the fixed palette per environment and
  /// the props chosen by the meaning of each beat. When false the scenes are
  /// exactly what [ReferenceSceneBuilder] built.
  static bool worldEnabled = true;

  /// Most scenes one cutaway is cut into.
  static const int maxScenes = 5;

  /// Wanted length of one beat, and the shortest one allowed.
  static const double targetSceneSeconds = 1.4;
  static const double minSceneSeconds = 1.2;

  // ReferenceSceneBuilder turns a clip of this length or more into two
  // scenes; a beat must stay below it so it remains one scene.
  static const double _singleSceneLimit = 2.4;

  static final RegExp _wordId = RegExp(r'_w(\d+)$');

  /// The transition between two beats. It is the same short kind the scene
  /// builder uses (0.35 seconds at most): a long wipe or dissolve keeps two
  /// pictures on screen together, the reference cuts last 0.1-0.3 seconds.
  static MotionTransitionKind _transition(MotionMood mood, int n) =>
      ReferenceSceneBuilder.transitionKindFor(mood, n);

  // -------------------------------------------------------------------------
  // Keyframes of a composition
  // -------------------------------------------------------------------------

  /// Pop-in, overshoot and gentle hover of the main sprite.
  static List<MotionKeyframe> spriteKeys(double dur, SceneComposition c) {
    final t1 = math.min(0.26, dur * 0.3);
    final t2 = math.min(0.46, dur * 0.5);
    final keys = <MotionKeyframe>[
      MotionKeyframe(
        time: 0,
        x: c.fromX,
        y: c.fromY,
        scale: 0.05,
        rotation: c.entrySpin,
        opacity: 0,
        easing: MotionEase.easeOut,
      ),
      MotionKeyframe(
        time: t1,
        x: c.spriteX,
        y: c.spriteY - 0.01,
        scale: 1.2 * c.spriteScale,
        rotation: 8,
        easing: MotionEase.overshoot,
      ),
      MotionKeyframe(
        time: t2,
        x: c.spriteX,
        y: c.spriteY,
        scale: c.spriteScale,
        rotation: -4,
        easing: MotionEase.easeInOut,
      ),
    ];
    var t = t2;
    var up = true;
    while (t + 0.55 < dur - 0.2) {
      t += 0.55;
      keys.add(
        MotionKeyframe(
          time: t,
          x: c.spriteX,
          y: up ? c.spriteY - 0.015 : c.spriteY + 0.005,
          scale: (up ? 1.04 : 0.98) * c.spriteScale,
          rotation: up ? 5 : -5,
          easing: MotionEase.easeInOut,
        ),
      );
      up = !up;
    }
    keys.add(
      MotionKeyframe(
        time: dur,
        x: c.spriteX,
        y: c.spriteY,
        scale: 0.96 * c.spriteScale,
        rotation: 0,
        easing: MotionEase.easeInOut,
      ),
    );
    return keys;
  }

  /// The small decor sprite: orbit around the subject or float in a corner.
  static List<MotionKeyframe> decorKeys(double dur, SceneComposition c) {
    const step = 0.30;
    MotionKeyframe at(double time, int k, double opacity) {
      final a = k * math.pi / 4;
      final orbit = c.decor == DecorMotion.orbit;
      return MotionKeyframe(
        time: time,
        x: orbit ? c.decorX + 0.30 * math.cos(a) : c.decorX + 0.025 * math.cos(a),
        y: orbit ? c.decorY + 0.09 * math.sin(a) : c.decorY + 0.02 * math.sin(a),
        rotation: k * (orbit ? 45.0 : 30.0),
        opacity: opacity,
        easing: MotionEase.linear,
      );
    }

    final keys = <MotionKeyframe>[];
    var t = 0.0;
    var k = 0;
    while (t < dur - 1e-6) {
      keys.add(at(t, k, k == 0 ? 0 : 1));
      t += step;
      k++;
    }
    keys.add(at(dur, k, 1));
    return keys;
  }

  /// Entrance of word number [j] of the scene.
  static List<MotionKeyframe> wordKeys(
    double layerDur,
    SceneComposition c,
    int j,
  ) {
    final rot = j.isEven ? -9.0 : 9.0;
    final x = (c.wordX + j * c.wordStepX).clamp(0.3, 0.7).toDouble();
    final y = (c.wordY + j * c.wordStepY).clamp(0.08, 0.92).toDouble();
    final s = c.wordScale;
    final t1 = math.min(0.22, layerDur * 0.30);
    final t2 = math.min(0.40, layerDur * 0.55);
    return <MotionKeyframe>[
      MotionKeyframe(
        time: 0,
        x: x + c.wordFromDx,
        y: y + c.wordFromDy,
        scale: 0.55 * s,
        rotation: rot,
        opacity: 0,
        easing: MotionEase.easeOut,
      ),
      MotionKeyframe(
        time: t1,
        x: x,
        y: y - 0.012,
        scale: 1.12 * s,
        rotation: -rot * 0.4,
        easing: MotionEase.overshoot,
      ),
      MotionKeyframe(
        time: t2,
        x: x,
        y: y,
        scale: s,
        rotation: 0,
        easing: MotionEase.easeInOut,
      ),
      MotionKeyframe(
        time: layerDur,
        x: x,
        y: y - 0.006,
        scale: 1.03 * s,
        rotation: -rot * 0.1,
        easing: MotionEase.easeInOut,
      ),
    ];
  }

  /// [layer] moved by [shift] seconds, with sprite, decor and word layers
  /// re-animated for [comp]. Backgrounds and overlays keep their motion.
  static MotionLayer _recompose(
    MotionLayer layer,
    SceneComposition comp,
    double shift,
  ) {
    final dur = layer.end - layer.start;
    List<MotionKeyframe>? keys;
    if (layer.id.endsWith('_sprite')) {
      keys = spriteKeys(dur, comp);
    } else if (layer.id.endsWith('_decor')) {
      keys = decorKeys(dur, comp);
    } else {
      final match = _wordId.firstMatch(layer.id);
      if (match != null) {
        keys = wordKeys(dur, comp, int.parse(match.group(1)!));
      }
    }
    return MotionSceneEditing.copyLayer(
      layer,
      start: layer.start + shift,
      end: layer.end + shift,
      keyframes: keys,
    );
  }

  // -------------------------------------------------------------------------
  // Story world
  // -------------------------------------------------------------------------

  /// Plans the story and the world of the beats [chunks]. Only the text and
  /// the order of the beats shape the world layers; the times just have to
  /// be valid. Returns null when the world is off or planning fails, so the
  /// cutaway is never lost because of it.
  static StoryWorldPlan? _planWorld(List<String> chunks, double beatSeconds) {
    if (!worldEnabled || chunks.isEmpty) return null;
    try {
      return StoryWorldBridge.plan(<StorySegment>[
        for (var i = 0; i < chunks.length; i++)
          StorySegment(
            text: chunks[i],
            start: i * beatSeconds,
            end: (i + 1) * beatSeconds,
          ),
      ]);
    } catch (_) {
      return null;
    }
  }

  /// True for the layers the world art takes over: the scene's own
  /// background, its companion mascot, and a main sprite that is the mascot.
  static bool _replacedByWorld(
    MotionLayer layer,
    Map<String, SceneAssetSpec> assets,
  ) {
    if (layer.id.endsWith('_bg') || layer.id.endsWith('_decor')) return true;
    if (!layer.id.endsWith('_sprite')) return false;
    final spec = assets[layer.assetKey];
    return spec != null &&
        spec.kind == SceneAssetKind.sprite &&
        spec.spriteKey == ReferenceSceneBuilder.mascotSprite;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  /// Builds the cutaway of [spec] as a chain of beats with different
  /// compositions. [previousLayout] is the last layout of the cutaway before
  /// this one (if any), so the first scene differs from it too. Throws like
  /// [ReferenceSceneBuilder.buildCutaway] for an invalid canvas or a cutaway
  /// shorter than one second.
  static ContinuousScenePlan build({
    required String id,
    required CutawaySpec spec,
    required int width,
    required int height,
    int frameRate = 30,
    MotionMood mood = MotionMood.cinematic,
    int variant = 0,
    SceneLayout? previousLayout,
  }) {
    if (width <= 0 || height <= 0 || frameRate <= 0) {
      throw ArgumentError('Invalid canvas size.');
    }
    final total = spec.duration;
    if (!total.isFinite || total < 1.0) {
      throw StateError('Cutaway is too short: $total');
    }

    final words = ReferenceSceneBuilder.wordsOf(spec.text);
    final maxN = math.max(1, math.min(maxScenes, words.length));
    var n = (total / targetSceneSeconds).round().clamp(1, maxN).toInt();

    // Number of beats: each one stays one scene and at least minSceneSeconds
    // long. The transitions overlap, so the beats are a little longer than
    // total / n and the rendered clip is exactly [total] seconds.
    var kinds = <MotionTransitionKind>[];
    var sceneDur = total;
    for (var guard = 0; guard < 10; guard++) {
      kinds = <MotionTransitionKind>[
        for (var i = 1; i < n; i++) _transition(mood, variant + i - 1),
      ];
      final overlap = kinds.fold<double>(
        0,
        (sum, kind) => sum + MotionTransitions.defaultDuration(kind),
      );
      sceneDur = (total + overlap) / n;
      if (sceneDur >= _singleSceneLimit && n < maxN) {
        n++;
        continue;
      }
      if (sceneDur < minSceneSeconds && n > 1) {
        n--;
        continue;
      }
      break;
    }

    // Words are shared out evenly between the beats.
    final chunks = <String>[];
    if (words.isEmpty) {
      chunks.add(spec.text);
    } else {
      final base = words.length ~/ n;
      final extra = words.length % n;
      var from = 0;
      for (var i = 0; i < n; i++) {
        final take = base + (i < extra ? 1 : 0);
        chunks.add(words.sublist(from, from + take).join(' '));
        from += take;
      }
    }

    // The story and the world of the beats: one character and one palette
    // for every scene of the cutaway (and of every other cutaway, because
    // both are fixed defaults).
    final world = _planWorld(chunks, sceneDur);

    final scenes = <MotionScene>[];
    final assets = <String, SceneAssetSpec>{};
    final layouts = <SceneLayout>[];
    SceneLayout? previous = previousLayout;
    SceneLayout? beforePrevious;
    var cursor = 0.0;

    for (var i = 0; i < chunks.length; i++) {
      final chunk = ReferenceSceneBuilder.buildCutaway(
        id: '${id}c$i',
        spec: CutawaySpec(start: 0, end: sceneDur, text: chunks[i]),
        width: width,
        height: height,
        frameRate: frameRate,
        mood: mood,
        variant: variant * 5 + i,
      );

      for (final entry in chunk.assets.entries) {
        // One clip-wide look: the first beat decides.
        if (entry.key == 'bg:look' && assets.containsKey(entry.key)) continue;
        assets[entry.key] = entry.value;
      }

      final chunkStart = cursor;
      for (var si = 0; si < chunk.project.scenes.length; si++) {
        final scene = chunk.project.scenes[si];
        final kind = (i == 0 && si == 0)
            ? SceneCompositionPlanner.classify(spec.text)
            : SceneCompositionPlanner.classify(chunks[i]);
        final layout = SceneCompositionPlanner.pick(
          kind: kind,
          sceneIndex: scenes.length,
          variant: variant,
          previous: previous,
          beforePrevious: beforePrevious,
        );
        beforePrevious = previous;
        previous = layout;
        layouts.add(layout);
        final comp = SceneComposition.of(layout);

        final sceneStart = scene.start + chunkStart;
        final sceneEnd = scene.end + chunkStart;
        var sceneLayers = <MotionLayer>[
          for (final layer in scene.layers) _recompose(layer, comp, chunkStart),
        ];
        var background = scene.background;

        // Merge the world art of this beat into the scene. A problem here
        // only means the scene stays as the scene builder made it.
        final worldScene = world?.worldSceneOf(i);
        if (worldScene != null) {
          try {
            final rendering = StoryWorldBridge.renderingOf(
              worldScene,
              idPrefix: scene.id,
              start: sceneStart,
              end: sceneEnd,
            );
            final kept = <MotionLayer>[];
            final droppedKeys = <String>[];
            for (final layer in sceneLayers) {
              if (_replacedByWorld(layer, chunk.assets)) {
                final key = layer.assetKey;
                if (key != null) droppedKeys.add(key);
              } else {
                kept.add(layer);
              }
            }
            sceneLayers = <MotionLayer>[...kept, ...rendering.layers];
            background = rendering.background;
            for (final key in droppedKeys) {
              assets.remove(key);
            }
            assets.addAll(rendering.assets);
          } catch (_) {
            // Keep the scene as built.
          }
        }

        scenes.add(
          MotionScene(
            id: scene.id,
            start: sceneStart,
            end: sceneEnd,
            background: background,
            transitionIn: (i > 0 && si == 0) ? kinds[i - 1] : scene.transitionIn,
            layers: sceneLayers,
          ),
        );
      }
      cursor += chunk.project.duration;
    }

    return ContinuousScenePlan(
      result: ReferenceSceneResult(
        project: MotionProject(
          id: id,
          width: width,
          height: height,
          frameRate: frameRate,
          duration: cursor,
          scenes: scenes,
        ),
        assets: assets,
      ),
      layouts: layouts,
      world: world,
    );
  }

  /// Same as [build] but returns null instead of throwing, so the caller can
  /// fall back to [ReferenceSceneBuilder.buildCutaway].
  static ReferenceSceneResult? tryBuild({
    required String id,
    required CutawaySpec spec,
    required int width,
    required int height,
    int frameRate = 30,
    MotionMood mood = MotionMood.cinematic,
    int variant = 0,
    SceneLayout? previousLayout,
  }) {
    try {
      return build(
        id: id,
        spec: spec,
        width: width,
        height: height,
        frameRate: frameRate,
        mood: mood,
        variant: variant,
        previousLayout: previousLayout,
      ).result;
    } catch (_) {
      return null;
    }
  }
}
