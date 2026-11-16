import 'dart:math' as math;

import 'person_anchor_path.dart';
import 'person_silhouette.dart';

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

  const AnchoredSceneSpec({
    required this.scenePath,
    required this.start,
    required this.end,
    this.path,
    this.matte,
    this.keyColors = const <String>[],
  });

  bool get isAnchored => path != null;

  bool get isOccluded {
    final p = path;
    return p != null && matte != null && p.placement.occludedByPerson;
  }
}

/// Builds the FFmpeg command that places 3D scenes next to the tracked person.
class PersonAnchoredCommand {
  PersonAnchoredCommand._();

  static String _f(double value) => value.toStringAsFixed(3);

  static int _even(int value) => value.isEven ? value : value - 1;

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

    final occludedCount = ordered.where((s) => s.isOccluded).length;

    final inputs = <String>['-i "$videoPath"'];
    final chains = <String>[];

    final base =
        '[0:v]scale=$width:$height:flags=lanczos,setsar=1,format=yuv420p';

    if (occludedCount == 0) {
      chains.add('$base[pbase]');
    } else {
      final labels = StringBuffer('[pbase]');
      for (var k = 0; k < occludedCount; k++) {
        labels.write('[pperson$k]');
      }
      chains.add('$base,split=${occludedCount + 1}$labels');
    }

    final shortEdge = math.min(width, height);
    final pipSide = _even(
      (shortEdge * 0.46).round().clamp(120, 720).toInt(),
    );
    final margin = math.max(8, (width * 0.035).round());

    var current = 'pbase';
    var personIndex = 0;

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

      chains.add(
        '[$sceneIndex:v]setpts=PTS-STARTPTS+$start/TB,'
        'scale=$side:$side:force_original_aspect_ratio=decrease:flags=lanczos,'
        'pad=$side:$side:(ow-iw)/2:(oh-ih)/2:color=$padColor,'
        'setsar=1,format=rgba,'
        '${keyChain}fade=t=in:st=$start:d=0.200:alpha=1,'
        'fade=t=out:st=$fadeOut:d=0.200:alpha=1'
        '[$card]',
      );

      chains.add(
        "[$current][$card]overlay=x='${p.xExpression()}':y='${p.yExpression()}':"
        "eof_action=pass:repeatlast=0:enable='between(t,$start,$end)'"
        '[$out]',
      );
      current = out;

      final matte = spec.matte;
      if (spec.isOccluded && matte != null) {
        inputs.add(
          '-framerate ${_f(matte.fps)} -i "${matte.pattern}"',
        );
        final matteIndex = inputs.length - 1;

        final matteLabel = 'matte$i';
        final trimLabel = 'ptrim$i';
        final cutLabel = 'pcut$i';
        final topLabel = 'ptop$i';

        chains.add(
          '[$matteIndex:v]setpts=PTS-STARTPTS+$start/TB,'
          'scale=$width:$height:flags=bilinear,'
          'gblur=sigma=2.5,format=gray[$matteLabel]',
        );
        chains.add(
          '[pperson$personIndex]trim=start=$start:end=$end,'
          'setpts=PTS-STARTPTS+$start/TB[$trimLabel]',
        );
        chains.add('[$trimLabel][$matteLabel]alphamerge[$cutLabel]');
        chains.add(
          '[$current][$cutLabel]overlay=x=0:y=0:'
          "eof_action=pass:repeatlast=0:enable='between(t,$start,$end)'"
          '[$topLabel]',
        );
        current = topLabel;
        personIndex++;
      }
    }

    final encoder = maximumQuality
        ? '-c:v libx264 -preset slow -crf 17'
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
