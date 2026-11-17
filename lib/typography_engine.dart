import 'dart:math' as math;

import 'text_motion_engine.dart';
import 'word_caption_planner.dart';

/// Professional kinetic-typography planner (pure Dart, no Flutter imports).
///
/// It decides, for one phrase:
///  * a size for every word (giant emphasis words, small connector words),
///  * how the words are distributed over lines on the screen,
///  * the entrance / exit animation of the phrase,
///  * the exact moment each word becomes active (sync with the speech).
///
/// Arabic is handled as a first-class language: right-to-left detection,
/// diacritics/tatweel aware matching, no letter-spacing (it would break the
/// letter joining) and a taller line height.
enum TypographyEntrance {
  fadeUp,
  slideFromRight,
  slideFromLeft,
  zoomIn,
  dropIn,
  pop,
  blurFocus,
  tiltIn,
}

enum TypographyExit {
  fadeOut,
  riseOut,
  zoomOut,
  shrinkOut,
  cut,
}

/// One word of a planned phrase.
class TypoWord {
  final int index;
  final String text;

  /// Seconds from the phrase start when the word is spoken.
  final double start;

  /// Seconds from the phrase start when the highlight leaves the word.
  final double end;

  /// Size multiplier relative to the base font size.
  final double scale;

  /// True for the huge emphasis words.
  final bool giant;

  /// Index of the line the word sits on.
  final int line;

  const TypoWord({
    required this.index,
    required this.text,
    required this.start,
    required this.end,
    required this.scale,
    required this.giant,
    required this.line,
  });
}

/// The complete plan of one phrase.
class TypographyPlan {
  final List<TypoWord> words;

  /// Word indexes of every line, in reading (logical) order.
  final List<List<int>> lines;
  final TypographyEntrance entrance;
  final TypographyExit exit;
  final bool rtl;

  /// Letter spacing in em. Always 0 for Arabic.
  final double letterSpacingEm;
  final double lineHeight;
  final double duration;

  const TypographyPlan({
    required this.words,
    required this.lines,
    required this.entrance,
    required this.exit,
    required this.rtl,
    required this.letterSpacingEm,
    required this.lineHeight,
    required this.duration,
  });

  int get frameCount => words.length;

  /// Cues usable with [WordCaptionPlanner.cropFilter].
  List<WordCue> get cues => <WordCue>[
        for (final word in words)
          WordCue(index: word.index, start: word.start, end: word.end),
      ];
}

class _Metrics {
  final List<double> scales;
  final List<bool> giant;

  const _Metrics(this.scales, this.giant);
}

class TypographyEngine {
  TypographyEngine._();

  static const int maxWordsPerPhrase = 8;
  static const int maxLines = 4;

  /// Width budget of one line, in "letters at base size".
  static const double maxLineUnits = 15.0;
  static const double _wordGap = 0.9;
  static const double smallScale = 0.8;
  static const double giantScale = 1.9;

  static final RegExp _diacritics = RegExp(r'[\u064B-\u065F\u0670\u0640]');
  static final RegExp _notLetter = RegExp(r'[^\u0600-\u06FFa-z0-9]');
  static final RegExp _digit = RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]');

  /// Words that carry the meaning of a hook: shown giant.
  static final Set<String> _emphasis = <String>{
    'مهم',
    'انتبه',
    'الحقيقة',
    'السر',
    'السبب',
    'خطر',
    'تذكر',
    'الحل',
    'اكتشف',
    'ابدا',
    'مجانا',
    'ممنوع',
    'صدمة',
    'خطير',
    'مستحيل',
    'important',
    'warning',
    'truth',
    'secret',
    'reason',
    'remember',
    'never',
    'stop',
    'why',
    'watch',
    'free',
    'danger',
    'impossible',
    'shocking',
  }.map(_core).toSet();

  /// Connector words: shown small so the key words breathe.
  static final Set<String> _stop = <String>{
    'في',
    'من',
    'على',
    'الى',
    'إلى',
    'عن',
    'مع',
    'ان',
    'أن',
    'إن',
    'ما',
    'لا',
    'هو',
    'هي',
    'هذا',
    'هذه',
    'ذلك',
    'التي',
    'الذي',
    'كان',
    'او',
    'أو',
    'ثم',
    'يا',
    'the',
    'a',
    'an',
    'of',
    'to',
    'in',
    'on',
    'and',
    'or',
    'is',
    'are',
    'it',
    'at',
    'for',
    'with',
    'that',
    'this',
  }.map(_core).toSet();

  /// Lower-cases, removes diacritics / tatweel / punctuation and unifies the
  /// Arabic letter variants, so words can be matched reliably.
  static String _core(String word) {
    return word
        .toLowerCase()
        .replaceAll(_diacritics, '')
        .replaceAll(RegExp(r'[\u0622\u0623\u0625\u0671]'), '\u0627')
        .replaceAll('\u0649', '\u064A')
        .replaceAll(_notLetter, '');
  }

  /// True when the first strong letter of [text] is right-to-left.
  static bool isRtlText(String text) {
    for (final rune in text.runes) {
      final isRtl = (rune >= 0x0590 && rune <= 0x08FF) ||
          (rune >= 0xFB1D && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF);
      if (isRtl) return true;
      final isLtr = (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A) ||
          (rune >= 0xC0 && rune <= 0x24F) ||
          (rune >= 0x370 && rune <= 0x52F);
      if (isLtr) return false;
    }
    return false;
  }

  /// Removes tatweel (it breaks the shaping of tight captions) and collapses
  /// whitespace. Zero-width joiners are kept on purpose.
  static String normalizeText(String text) {
    return text.replaceAll('\u0640', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _endsSentence(String word) {
    if (word.isEmpty) return false;
    const marks = <String>{'.', '!', '?', ':', ';', '\u060C', '\u061B', '\u061F', ','};
    return marks.contains(word.substring(word.length - 1));
  }

  /// Splits a long sentence into short phrases of at most [maxWords] words,
  /// preferring to cut after punctuation.
  static List<String> splitPhrases(
    String text, {
    int maxWords = maxWordsPerPhrase,
  }) {
    final words = WordCaptionPlanner.splitWords(normalizeText(text));
    if (words.isEmpty) return const <String>[];
    final limit = math.max(1, maxWords);

    final chunks = <List<String>>[];
    var current = <String>[];
    for (final word in words) {
      current.add(word);
      final full = current.length >= limit;
      final punctuationCut = _endsSentence(word) && current.length >= 3;
      if (full || punctuationCut) {
        chunks.add(current);
        current = <String>[];
      }
    }
    if (current.isNotEmpty) {
      if (current.length == 1 && chunks.isNotEmpty) {
        chunks.last.add(current.first);
      } else {
        chunks.add(current);
      }
    }
    return <String>[for (final chunk in chunks) chunk.join(' ')];
  }

  static _Metrics _metrics(List<String> words) {
    final count = words.length;
    final scales = List<double>.filled(count, 1.0);
    final giant = List<bool>.filled(count, false);

    if (count == 1) {
      scales[0] = 1.6;
      giant[0] = true;
      return _Metrics(scales, giant);
    }

    var bestIndex = -1;
    var bestLength = 0;
    for (var i = 0; i < count; i++) {
      final core = _core(words[i]);
      if (core.isEmpty) continue;
      final length = core.runes.length;
      if (_digit.hasMatch(core)) {
        scales[i] = giantScale + 0.1;
        giant[i] = true;
      } else if (_emphasis.contains(core)) {
        scales[i] = giantScale;
        giant[i] = true;
      } else if (_stop.contains(core)) {
        scales[i] = smallScale;
      } else {
        scales[i] = 1.0 + ((length - 4) * 0.05).clamp(0.0, 0.25).toDouble();
        if (length > bestLength) {
          bestLength = length;
          bestIndex = i;
        }
      }
    }

    // Every phrase of 3+ words gets one hero word.
    final hasGiant = giant.any((value) => value);
    if (!hasGiant && count >= 3 && bestIndex >= 0) {
      scales[bestIndex] = 1.7;
      giant[bestIndex] = true;
    }

    // At most two giant words: more would stop being emphasis.
    var giantSeen = 0;
    for (var i = 0; i < count; i++) {
      if (!giant[i]) continue;
      giantSeen++;
      if (giantSeen > 2) {
        giant[i] = false;
        scales[i] = 1.25;
      }
    }
    return _Metrics(scales, giant);
  }

  static double _units(String word, double scale) =>
      math.max(2, word.runes.length) * scale;

  static List<List<int>> _breakLines(List<String> words, _Metrics metrics) {
    final lines = <List<int>>[];
    var current = <int>[];
    var currentUnits = 0.0;
    const heroShare = 0.55;

    for (var i = 0; i < words.length; i++) {
      final units = _units(words[i], metrics.scales[i]);
      final isHero = metrics.giant[i] && units >= maxLineUnits * heroShare;
      final added = current.isEmpty ? units : _wordGap + units;

      if (current.isNotEmpty &&
          (isHero || currentUnits + added > maxLineUnits)) {
        lines.add(current);
        current = <int>[];
        currentUnits = 0.0;
      }

      currentUnits += current.isEmpty ? units : _wordGap + units;
      current.add(i);

      if (isHero) {
        lines.add(current);
        current = <int>[];
        currentUnits = 0.0;
      }
    }
    if (current.isNotEmpty) lines.add(current);

    while (lines.length > maxLines) {
      final last = lines.removeLast();
      lines.last.addAll(last);
    }
    return lines;
  }

  static List<WordCue> _cues(
    List<String> words,
    double duration,
    List<WordCue>? timings,
  ) {
    if (timings != null && timings.length == words.length) {
      var valid = true;
      for (var i = 0; i < timings.length; i++) {
        final start = timings[i].start;
        if (!start.isFinite || start < 0) {
          valid = false;
          break;
        }
        if (i > 0 && start <= timings[i - 1].start) {
          valid = false;
          break;
        }
      }
      if (valid) {
        // The highlight moves to a word exactly when it starts to be spoken.
        final cues = <WordCue>[];
        for (var i = 0; i < timings.length; i++) {
          final start = math.min(timings[i].start, duration);
          var end = i == timings.length - 1
              ? duration
              : math.min(timings[i + 1].start, duration);
          if (end <= start) end = start + 0.01;
          cues.add(WordCue(index: i, start: start, end: end));
        }
        return cues;
      }
    }

    if (words.length >= 2) {
      final planned =
          WordCaptionPlanner.plan(text: words.join(' '), duration: duration);
      if (planned.length == words.length) return planned;
    }
    return <WordCue>[
      for (var i = 0; i < words.length; i++)
        WordCue(index: i, start: 0, end: duration),
    ];
  }

  static TypographyEntrance entranceFor({
    required TextMotionMood mood,
    required int seed,
    required bool rtl,
  }) {
    final pick = seed.abs();
    switch (mood) {
      case TextMotionMood.calm:
        const options = <TypographyEntrance>[
          TypographyEntrance.fadeUp,
          TypographyEntrance.blurFocus,
        ];
        return options[pick % options.length];
      case TextMotionMood.cinematic:
        const options = <TypographyEntrance>[
          TypographyEntrance.blurFocus,
          TypographyEntrance.tiltIn,
          TypographyEntrance.zoomIn,
        ];
        return options[pick % options.length];
      case TextMotionMood.dynamic:
        final options = <TypographyEntrance>[
          TypographyEntrance.pop,
          TypographyEntrance.zoomIn,
          TypographyEntrance.dropIn,
          rtl
              ? TypographyEntrance.slideFromRight
              : TypographyEntrance.slideFromLeft,
          TypographyEntrance.tiltIn,
        ];
        return options[pick % options.length];
    }
  }

  static TypographyExit exitFor({
    required TextMotionMood mood,
    required int seed,
  }) {
    final pick = seed.abs() ~/ 2;
    switch (mood) {
      case TextMotionMood.calm:
        return TypographyExit.fadeOut;
      case TextMotionMood.cinematic:
        const options = <TypographyExit>[
          TypographyExit.fadeOut,
          TypographyExit.zoomOut,
        ];
        return options[pick % options.length];
      case TextMotionMood.dynamic:
        const options = <TypographyExit>[
          TypographyExit.shrinkOut,
          TypographyExit.riseOut,
          TypographyExit.cut,
          TypographyExit.zoomOut,
        ];
        return options[pick % options.length];
    }
  }

  /// Plans one phrase. [wordTimings] are optional real word times (seconds
  /// from the phrase start, one per word); without them the time is shared by
  /// word length.
  static TypographyPlan plan({
    required String text,
    required double duration,
    List<WordCue>? wordTimings,
    TextMotionMood mood = TextMotionMood.dynamic,
    int seed = 0,
  }) {
    final clean = normalizeText(text);
    final words = WordCaptionPlanner.splitWords(clean);
    if (words.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Caption text is empty.');
    }
    final safeDuration = (duration.isFinite && duration > 0) ? duration : 1.0;
    final rtl = isRtlText(clean);

    final metrics = _metrics(words);
    final lines = _breakLines(words, metrics);
    final cues = _cues(words, safeDuration, wordTimings);

    final lineOf = List<int>.filled(words.length, 0);
    for (var l = 0; l < lines.length; l++) {
      for (final index in lines[l]) {
        lineOf[index] = l;
      }
    }

    final typoWords = <TypoWord>[
      for (var i = 0; i < words.length; i++)
        TypoWord(
          index: i,
          text: words[i],
          start: cues[i].start,
          end: cues[i].end,
          scale: metrics.scales[i],
          giant: metrics.giant[i],
          line: lineOf[i],
        ),
    ];

    return TypographyPlan(
      words: typoWords,
      lines: lines,
      entrance: entranceFor(mood: mood, seed: seed, rtl: rtl),
      exit: exitFor(mood: mood, seed: seed),
      rtl: rtl,
      letterSpacingEm:
          (!rtl && mood == TextMotionMood.cinematic) ? 0.02 : 0.0,
      lineHeight: rtl ? 1.5 : 1.25,
      duration: safeDuration,
    );
  }
}

/// FFmpeg filter / expression builders for the entrance and exit of a phrase.
///
/// Scale and rotate filters use the local clock of the caption image (t = 0 at
/// its first frame), exactly like [TextMotionEngine.buildFilter]. Overlay
/// offsets use the main timeline clock, so they take the phrase start time.
class TypographyMotion {
  TypographyMotion._();

  static const double entranceSeconds = 0.30;
  static const double exitSeconds = 0.22;
  static const double _fadeInSeconds = 0.18;

  static String _f(double value) => value.toStringAsFixed(3);

  static double _exitSpan(double duration) =>
      math.min(exitSeconds, math.max(0.05, duration * 0.25));

  /// Alpha fade in / fade out. Needs an RGBA input (PNG overlays are).
  static String buildAlphaFilter({
    required double duration,
    required TypographyEntrance entrance,
    required TypographyExit exit,
  }) {
    final safe = duration.isFinite && duration > 0 ? duration : 1.0;
    final fadeIn = math.min(_fadeInSeconds, safe * 0.3);
    final parts = <String>[
      'format=rgba',
      'fade=t=in:st=0:d=${_f(fadeIn)}:alpha=1',
    ];
    if (exit != TypographyExit.cut && safe >= 0.5) {
      final span = _exitSpan(safe);
      parts.add('fade=t=out:st=${_f(safe - span)}:d=${_f(span)}:alpha=1');
    }
    return parts.join(',');
  }

  static String _entranceScale(TypographyEntrance entrance) {
    switch (entrance) {
      case TypographyEntrance.zoomIn:
        return '(0.82+0.18*(1-pow(1-min(1,t/0.30),3)))';
      case TypographyEntrance.pop:
        return '(1-0.22*exp(-12*t)*cos(26*t))';
      case TypographyEntrance.dropIn:
        return '(1+0.30*pow(1-min(1,t/0.28),2))';
      case TypographyEntrance.blurFocus:
        return '(1.06-0.06*min(1,t/0.40))';
      case TypographyEntrance.fadeUp:
      case TypographyEntrance.slideFromRight:
      case TypographyEntrance.slideFromLeft:
      case TypographyEntrance.tiltIn:
        return '1';
    }
  }

  static String _exitScale(TypographyExit exit, double duration) {
    final span = _exitSpan(duration);
    final from = _f(duration - span);
    final progress = 'pow(min(1,max(0,(t-$from)/${_f(span)})),2)';
    switch (exit) {
      case TypographyExit.zoomOut:
        return '(1+0.12*$progress)';
      case TypographyExit.shrinkOut:
        return '(1-0.20*$progress)';
      case TypographyExit.fadeOut:
      case TypographyExit.riseOut:
      case TypographyExit.cut:
        return '1';
    }
  }

  /// Scale (and tilt) filter for the entrance + exit, or null when the pair
  /// needs no scaling at all.
  static String? buildScaleFilter({
    required double duration,
    required TypographyEntrance entrance,
    required TypographyExit exit,
  }) {
    if (!duration.isFinite || duration <= 0) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Duration must be positive and finite.',
      );
    }
    final entranceScale = _entranceScale(entrance);
    final exitScale = _exitScale(exit, duration);
    final filters = <String>[];

    if (entrance == TypographyEntrance.tiltIn) {
      filters.add(
        "rotate=a='-0.05*pow(1-min(1,t/0.30),2)':"
        "ow='ceil(iw*1.06)':oh='ceil(ih*1.06)':c=none",
      );
    }

    if (entranceScale != '1' || exitScale != '1') {
      final scale = '$entranceScale*$exitScale';
      filters.add(
        "scale=w='max(2,trunc(iw*($scale)/2)*2)':"
        "h='max(2,trunc(ih*($scale)/2)*2)':eval=frame",
      );
    }
    return filters.isEmpty ? null : filters.join(',');
  }

  /// Pixel offset expression to add to the overlay's y position. [start] is
  /// the phrase start on the main timeline. Null when there is no vertical
  /// travel. Wrap it in single quotes inside the filter graph.
  static String? overlayYOffset({
    required TypographyEntrance entrance,
    required TypographyExit exit,
    required double start,
    required double duration,
    required double travelPixels,
  }) {
    final parts = <String>[];
    final s = _f(start);
    final enterProgress = 'pow(1-min(1,max(0,(t-$s)/${_f(entranceSeconds)})),3)';

    if (entrance == TypographyEntrance.fadeUp) {
      parts.add('${_f(travelPixels)}*$enterProgress');
    } else if (entrance == TypographyEntrance.dropIn) {
      parts.add('-${_f(travelPixels)}*$enterProgress');
    }

    if (exit == TypographyExit.riseOut) {
      final span = _exitSpan(duration);
      final from = _f(start + duration - span);
      parts.add(
        '-${_f(travelPixels)}*pow(min(1,max(0,(t-$from)/${_f(span)})),2)',
      );
    }
    return parts.isEmpty ? null : parts.join('+');
  }

  /// Pixel offset expression to add to the overlay's x position for the two
  /// slide entrances. Null for every other entrance.
  static String? overlayXOffset({
    required TypographyEntrance entrance,
    required double start,
    required double travelPixels,
  }) {
    final s = _f(start);
    final progress = 'pow(1-min(1,max(0,(t-$s)/${_f(entranceSeconds)})),3)';
    switch (entrance) {
      case TypographyEntrance.slideFromRight:
        return '${_f(travelPixels * 1.6)}*$progress';
      case TypographyEntrance.slideFromLeft:
        return '-${_f(travelPixels * 1.6)}*$progress';
      case TypographyEntrance.fadeUp:
      case TypographyEntrance.zoomIn:
      case TypographyEntrance.dropIn:
      case TypographyEntrance.pop:
      case TypographyEntrance.blurFocus:
      case TypographyEntrance.tiltIn:
        return null;
    }
  }
}
