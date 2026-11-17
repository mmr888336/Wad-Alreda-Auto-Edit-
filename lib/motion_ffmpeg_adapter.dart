/// Turns a [MotionProject] into an FFmpeg filter_complex plan.
///
/// Per scene: a solid colour background, then every sprite/image layer is
/// scaled (nearest-neighbour, animated) and overlaid with animated position
/// and optional animated opacity. Scenes are joined with the transition
/// library (xfade, or concat for hard cuts).
///
/// Limits of this first version (by design, to stay predictable):
///  * layer rotation is not rendered yet;
///  * layers without a registered asset are skipped and reported;
///  * a transition overlaps the end of the previous scene and the start of
///    the next one, so the total length is the scene sum minus the overlaps.
///
/// The plan is returned as an argument list (no shell quoting involved).
library;

import 'dart:math' as math;

import 'motion_scene_model.dart';
import 'motion_transitions.dart';

/// An image the renderer can overlay (sprite PNG, pre-rendered text PNG...).
class MotionRenderAsset {
  final String path;

  /// Height divided by width of the image.
  final double aspect;

  /// Width on screen at layer scale 1, as a fraction of the canvas width.
  final double widthFraction;

  const MotionRenderAsset({
    required this.path,
    this.aspect = 1.0,
    this.widthFraction = 0.12,
  });
}

class MotionFfmpegInput {
  final String path;
  final double duration;

  const MotionFfmpegInput({required this.path, required this.duration});
}

class MotionFfmpegPlan {
  final int width;
  final int height;
  final int frameRate;
  final List<MotionFfmpegInput> inputs;
  final String filterComplex;
  final String outputLabel;
  final double totalDuration;
  final List<String> skippedLayerIds;

  const MotionFfmpegPlan({
    required this.width,
    required this.height,
    required this.frameRate,
    required this.inputs,
    required this.filterComplex,
    required this.outputLabel,
    required this.totalDuration,
    required this.skippedLayerIds,
  });

  /// Full FFmpeg argument list (video only, H.264, no audio).
  List<String> arguments({required String outputPath}) {
    final args = <String>[];
    for (final input in inputs) {
      args.addAll(<String>[
        '-loop',
        '1',
        '-framerate',
        '$frameRate',
        '-t',
        input.duration.toStringAsFixed(3),
        '-i',
        input.path,
      ]);
    }
    args.addAll(<String>[
      '-filter_complex',
      filterComplex,
      '-map',
      '[$outputLabel]',
      '-r',
      '$frameRate',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-pix_fmt',
      'yuv420p',
      '-an',
      '-movflags',
      '+faststart',
      '-y',
      outputPath,
    ]);
    return args;
  }
}

class _Pt {
  final double t;
  final double v;

  const _Pt(this.t, this.v);
}

class MotionFfmpegAdapter {
  MotionFfmpegAdapter._();

  static final RegExp _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

  static String _n(double value) => value.toStringAsFixed(3);

  /// Number for use inside an FFmpeg expression (negatives are wrapped).
  static String _num(double value) {
    final s = value.toStringAsFixed(4);
    return value < 0 ? '($s)' : s;
  }

  static String _color(String hex) {
    if (!_hex.hasMatch(hex)) {
      throw ArgumentError.value(hex, 'background', 'Expected #RRGGBB.');
    }
    return '0x${hex.substring(1).toUpperCase()}';
  }

  /// Piecewise-linear FFmpeg expression for one keyframe property.
  ///
  /// Non-linear easings are sampled in six steps per segment. Before the
  /// first keyframe and after the last one the value is held. [timeVar] is
  /// the already-offset layer-local time expression, for example `(t-1.0)`.
  static String keyframeExpression(
    List<MotionKeyframe> keys,
    double Function(MotionKeyframe) pick, {
    required String timeVar,
  }) {
    if (keys.isEmpty) {
      throw ArgumentError('Keyframes must not be empty.');
    }
    final pts = <_Pt>[_Pt(keys.first.time, pick(keys.first))];
    for (var i = 1; i < keys.length; i++) {
      final a = keys[i - 1];
      final b = keys[i];
      if (b.time < a.time) {
        throw ArgumentError('Keyframes must be sorted by time.');
      }
      final steps = b.easing == MotionEase.linear ? 1 : 6;
      final va = pick(a);
      final vb = pick(b);
      for (var s = 1; s <= steps; s++) {
        final u = s / steps;
        pts.add(
          _Pt(
            a.time + (b.time - a.time) * u,
            va + (vb - va) * MotionEasing.apply(b.easing, u),
          ),
        );
      }
    }

    var constant = true;
    for (final p in pts) {
      if ((p.v - pts.first.v).abs() > 1e-9) {
        constant = false;
        break;
      }
    }
    if (constant) return _num(pts.first.v);

    var expr = _num(pts.last.v);
    for (var i = pts.length - 2; i >= 0; i--) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final dt = p1.t - p0.t;
      final seg = dt <= 1e-6
          ? _num(p1.v)
          : '${_num(p0.v)}+${_num((p1.v - p0.v) / dt)}'
              '*($timeVar-${_num(p0.t)})';
      expr = 'if(lt($timeVar,${_num(p1.t)}),$seg,$expr)';
    }
    return 'if(lt($timeVar,${_num(pts.first.t)}),${_num(pts.first.v)},$expr)';
  }

  static String _prop(
    MotionLayer layer,
    double Function(MotionKeyframe) pick,
    double fallback,
    String timeVar,
  ) {
    if (layer.keyframes.isEmpty) return _num(fallback);
    return keyframeExpression(layer.keyframes, pick, timeVar: timeVar);
  }

  static bool _needsOpacity(MotionLayer layer) {
    if (layer.keyframes.isEmpty) return (layer.opacity - 1).abs() > 1e-9;
    return layer.keyframes.any((k) => (k.opacity - 1).abs() > 1e-9);
  }

  static MotionFfmpegPlan build({
    required MotionProject project,
    required Map<String, MotionRenderAsset> assets,
  }) {
    project.validate();
    if (project.scenes.isEmpty) {
      throw StateError('Project has no scenes.');
    }

    final inputs = <MotionFfmpegInput>[];
    final chains = <String>[];
    final skipped = <String>[];

    for (var si = 0; si < project.scenes.length; si++) {
      final scene = project.scenes[si];
      final dur = scene.duration;
      chains.add(
        'color=c=${_color(scene.background)}:'
        's=${project.width}x${project.height}:'
        'r=${project.frameRate}:d=${_n(dur)}[b${si}_0]',
      );
      var current = 'b${si}_0';
      var step = 0;

      final layers = List<MotionLayer>.of(scene.layers)
        ..sort((a, b) {
          final byZ = a.zIndex.compareTo(b.zIndex);
          return byZ != 0 ? byZ : a.id.compareTo(b.id);
        });

      for (final layer in layers) {
        final asset = assets[layer.assetKey ?? 'text:${layer.id}'];
        if (asset == null) {
          skipped.add(layer.id);
          continue;
        }
        final inputIndex = inputs.length;
        inputs.add(MotionFfmpegInput(path: asset.path, duration: dur));
        step++;

        final off = layer.start - scene.start;
        final tVar = '(t-${_num(off)})';
        final gVar = '(T-${_num(off)})';

        final xExpr = _prop(layer, (k) => k.x, layer.x, tVar);
        final yExpr = _prop(layer, (k) => k.y, layer.y, tVar);
        final sExpr = _prop(layer, (k) => k.scale, layer.scale, tVar);

        final baseW = project.width * asset.widthFraction;
        final wExpr = "max(2,trunc(${_num(baseW)}*($sExpr)/2)*2)";
        final hExpr =
            "max(2,trunc(${_num(baseW * asset.aspect)}*($sExpr)/2)*2)";

        final parts = <String>['format=rgba'];
        if (_needsOpacity(layer)) {
          final oExpr = _prop(layer, (k) => k.opacity, layer.opacity, gVar);
          parts.add(
            "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':"
            "a='alpha(X,Y)*(clip($oExpr,0,1))'",
          );
          parts.add('format=rgba');
        }
        parts.add(
          "scale=w='$wExpr':h='$hExpr':eval=frame:flags=neighbor",
        );
        final layerLabel = 'ly${si}_$step';
        chains.add('[$inputIndex:v]${parts.join(',')}[$layerLabel]');

        final next = 'b${si}_$step';
        chains.add(
          '[$current][$layerLabel]overlay='
          "x='W*($xExpr)-w/2':y='H*($yExpr)-h/2':"
          "enable='between(t,${_n(off)},${_n(layer.end - scene.start)})':"
          'format=auto[$next]',
        );
        current = next;
      }

      chains.add('[$current]format=yuv420p,setsar=1[sc$si]');
    }

    var merged = 'sc0';
    var mergedLen = project.scenes.first.duration;
    for (var i = 1; i < project.scenes.length; i++) {
      final scene = project.scenes[i];
      final kind = scene.transitionIn;
      final out = 'm$i';
      final maxAllowed = math.min(mergedLen, scene.duration) / 2;

      if (kind == MotionTransitionKind.hardCut || maxAllowed < 0.05) {
        chains.add('[$merged][sc$i]concat=n=2:v=1:a=0[$out]');
        mergedLen += scene.duration;
      } else {
        final td = math
            .min(MotionTransitions.defaultDuration(kind), maxAllowed)
            .clamp(0.05, 2.0)
            .toDouble();
        final xfade = MotionTransitions.buildXfade(
          inputA: merged,
          inputB: 'sc$i',
          output: out,
          kind: kind,
          offset: mergedLen - td,
          duration: td,
        );
        chains.add(xfade!);
        mergedLen += scene.duration - td;
      }
      merged = out;
    }

    return MotionFfmpegPlan(
      width: project.width,
      height: project.height,
      frameRate: project.frameRate,
      inputs: inputs,
      filterComplex: chains.join(';'),
      outputLabel: merged,
      totalDuration: mergedLen,
      skippedLayerIds: skipped,
    );
  }
}
