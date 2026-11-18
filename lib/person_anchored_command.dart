import 'dart:math' as math;

import 'person_anchor_path.dart';
import 'person_silhouette.dart';
import 'scene_environment.dart';

/// One 3D scene clip and how it is placed on the video.
///
/// [path] null means the old picture-in-picture panel is used.
class AnchoredSceneSpec {
  final String scenePath;
  final double start;
  final double end;
  final PersonAnchorPath? path;
  final PersonMatteSequence? matte;
  final List<String> keyColors;

  /// How the card is matched to the light, color and depth of the place it
  /// stands in (grade, haze, soft focus, grain and a cast shadow). Null keeps
  /// the plain anchored look.
  final SceneEnvironmentLook? environment;

  const AnchoredSceneSpec({
    required this.scenePath,
    required this.start,
    required this.end,
    this.path,
    this.matte,
    this.keyColors = const <String>[],
    this.environment,
  });

  bool get isAnchored => path != null;

  bool get isOccluded {
    final p = path;
    return p != null && matte != null && p.placement.occludedByPerson;
  }

  /// Only anchored cards are matched to their environment.
  bool get hasEnvironment => path != null && environment != null;

  /// The same scene without the environment match (used as a safe retry).
  AnchoredSceneSpec withoutEnvironment() => AnchoredSceneSpec(
        scenePath: scenePath,
        start: start,
        end: end,
        path: path,
        matte: matte,
        keyColors: keyColors,
      );
}

/// Builds the FFmpeg command that places 3D scenes next to the tracked person.
class PersonAnchoredCommand {
  PersonAnchoredCommand._();

  static String _f(double value) => value.toStringAsFixed(3);

  static int _even(int value) => value.isEven ? value : value - 1;

  /// Adds the environment match of one anchored card to [chains]:
  /// grade + haze + soft focus (+ grain on the color only, never on the alpha)
  /// and a soft cast shadow drawn under the card. Returns the label of the
  /// video that already holds the shadow; the card itself is left in [card].
  static String _addEnvironment({
    required List<String> chains,
    required int index,
    required String source,
    required String card,
    required String current,
    required PersonAnchorPath path,
    required SceneEnvironmentLook environment,
    required String start,
    required String end,
  }) {
    final colorLabel = 'envc$index';
    final alphaLabel = 'enva$index';
    final shadowSource = 'envs$index';
    final maskLabel = 'envm$index';
    final grainLabel = 'envn$index';
    final shadowLabel = 'shadow$index';
    final shadowOut = 'pshadow$index';

    if (environment.hasGrain) {
      // The grain is added to the color only; the alpha (the card shape)
      // travels separately and is merged back, so it never gets speckled.
      chains.add(
        '[$source]${environment.gradeChain},'
        'split=3[$colorLabel][$alphaLabel][$shadowSource]',
      );
      chains.add('[$alphaLabel]alphaextract[$maskLabel]');
      chains.add(
        '[$colorLabel]format=yuv444p,'
        'noise=alls=${environment.grain}:allf=t+u[$grainLabel]',
      );
      chains.add(
        '[$grainLabel][$maskLabel]alphamerge,format=rgba[$card]',
      );
    } else {
      chains.add(
        '[$source]${environment.gradeChain},'
        'split=2[$card][$shadowSource]',
      );
    }

    chains.add('[$shadowSource]${environment.shadowChain}[$shadowLabel]');

    chains.add(
      "[$current][$shadowLabel]overlay="
      "x='(${path.xExpression()})+(${_f(environment.shadowDx)})':"
      "y='(${path.yExpression()})+(${_f(environment.shadowDy)})':"
      "eof_action=pass:repeatlast=0:enable='between(t,$start,$end)'"
      '[$shadowOut]',
    );

    return shadowOut;
  }

  static String build({
    required String videoPath,
    required String outputPath,
    required int width,
    required int height,
    required double duration,
    required List<AnchoredSceneSpec> scenes,
    bool maximumQuality = true,
  }) {
    if (scenes.isEmpty) {
      throw ArgumentError('At least one scene is required.');
    }
    if (width < 2 || height < 2) {
      throw ArgumentError('Video size is invalid.');
    }

    final ordered = List<AnchoredSceneSpec>.from(scenes)
      ..sort((a, b) => a.start.compareTo(b.start));

    final inputs = <String>['-i "$videoPath"'];
    final chains = <String>[];

    chains.add(
      '[0:v]scale=$width:$height:flags=lanczos,setsar=1,format=yuv420p'
      '[pbase]',
    );

    final shortEdge = math.min(width, height);
    final pipSide = _even(
      (shortEdge * 0.46).round().clamp(120, 720).toInt(),
    );
    final margin = math.max(8, (width * 0.035).round());

    var current = 'pbase';

    for (var i = 0; i < ordered.length; i++) {
      final spec = ordered[i];
      final start = _f(spec.start);
      final end = _f(spec.end);

      inputs.add('-i "${spec.scenePath}"');
      final sceneIndex = inputs.length - 1;

      final card = 'card$i';
      final out = 'pcomp$i';
      final p = spec.path;

      if (p == null) {
        // Picture-in-picture fallback, identical to the previous behaviour.
        chains.add(
          '[$sceneIndex:v]setpts=PTS-STARTPTS+$start/TB,'
          'scale=$pipSide:$pipSide:'
          'force_original_aspect_ratio=decrease:flags=lanczos,'
          'pad=$pipSide:$pipSide:(ow-iw)/2:(oh-ih)/2:color=0x101521,'
          'setsar=1,'
          'drawbox=x=0:y=0:w=iw:h=ih:color=0xB69AFF@0.95:t=3'
          '[$card]',
        );
        chains.add(
          '[$current][$card]overlay='
          'x=main_w-overlay_w-$margin:y=(main_h-overlay_h)/2:'
          "eof_action=pass:repeatlast=0:enable='between(t,$start,$end)'"
          '[$out]',
        );
        current = out;
        continue;
      }

      final side = p.sidePixels;
      final padColor =
          spec.keyColors.isNotEmpty ? spec.keyColors.first : '0x101521';
      final keys =
          spec.keyColors.map((c) => 'colorkey=$c:0.12:0.08').join(',');
      final keyChain = keys.isEmpty ? '' : '$keys,';
      final fadeOut = _f(math.max(spec.start, spec.end - 0.2));

      final environment = spec.environment;

      // With an environment match the keyed card first goes to "raw", then
      // through the grade / shadow chains, and ends up in "card".
      final cardSource = environment == null ? card : 'raw$i';

      chains.add(
        '[$sceneIndex:v]setpts=PTS-STARTPTS+$start/TB,'
        'scale=$side:$side:force_original_aspect_ratio=decrease:flags=lanczos,'
        'pad=$side:$side:(ow-iw)/2:(oh-ih)/2:color=$padColor,'
        'setsar=1,format=rgba,'
        '${keyChain}fade=t=in:st=$start:d=0.200:alpha=1,'
        'fade=t=out:st=$fadeOut:d=0.200:alpha=1'
        '[$cardSource]',
      );

      if (environment != null) {
        current = _addEnvironment(
          chains: chains,
          index: i,
          source: cardSource,
          card: card,
          current: current,
          path: p,
          environment: environment,
          start: start,
          end: end,
        );
      }

      chains.add(
        "[$current][$card]overlay=x='${p.xExpression()}':y='${p.yExpression()}':"
        "eof_action=pass:repeatlast=0:enable='between(t,$start,$end)'"
        '[$out]',
      );
      current = out;

      final matte = spec.matte;
      if (spec.isOccluded && matte != null) {
        // The person layer reads ITS OWN short window of the video (-ss/-t).
        // It used to be a split + trim of the full-resolution stream: the
        // overlay then waited for the first person frame of a scene that
        // starts seconds later and buffered every full-size frame in between,
        // which ran the phone out of memory and closed the app near the end
        // of the export. A separate input delivers its first frame at once.
        final windowSeconds = math.max(0.2, spec.end - spec.start + 0.1);
        inputs.add(
          '-ss $start -t ${_f(windowSeconds)} -i "$videoPath"',
        );
        final personIndex = inputs.length - 1;

        inputs.add(
          '-framerate ${_f(matte.fps)} -i "${matte.pattern}"',
        );
        final matteIndex = inputs.length - 1;

        final matteLabel = 'matte$i';
        final windowLabel = 'pwin$i';
        final cutLabel = 'pcut$i';
        final topLabel = 'ptop$i';

        chains.add(
          '[$matteIndex:v]setpts=PTS-STARTPTS+$start/TB,'
          'scale=$width:$height:flags=bilinear,'
          'gblur=sigma=2.5,format=gray[$matteLabel]',
        );
        chains.add(
          '[$personIndex:v]scale=$width:$height:flags=lanczos,setsar=1,'
          'format=yuv420p,setpts=PTS-STARTPTS+$start/TB[$windowLabel]',
        );
        chains.add('[$windowLabel][$matteLabel]alphamerge[$cutLabel]');
        chains.add(
          '[$current][$cutLabel]overlay=x=0:y=0:'
          "eof_action=pass:repeatlast=0:enable='between(t,$start,$end)'"
          '[$topLabel]',
        );
        current = topLabel;
      }
    }

    // The video was already encoded at high quality by the editor, so this
    // second pass uses a lighter preset: far less memory and time on a phone.
    final encoder = maximumQuality
        ? '-c:v libx264 -preset fast -crf 17'
        : '-c:v libx264 -preset veryfast -crf 20';

    return '-y ${inputs.join(' ')} '
        '-filter_complex "${chains.join(';')}" '
        '-map "[$current]" '
        '-map "0:a?" '
        '$encoder '
        '-pix_fmt yuv420p '
        '-c:a aac -b:a 192k -ar 48000 '
        '-t ${_f(duration)} '
        '-movflags +faststart "$outputPath"';
  }
}
