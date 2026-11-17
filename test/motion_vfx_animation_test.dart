import 'package:flutter_test/flutter_test.dart';
import 'package:auto_edit/cinematic_vfx.dart';
import 'package:auto_edit/motion_ffmpeg_adapter.dart';
import 'package:auto_edit/motion_vfx_animator.dart';
import 'package:auto_edit/motion_vfx_overlay.dart';
import 'package:auto_edit/reference_scene_builder.dart';

void main() {
  test('bloom and halation build one complete, labelled graph', () {
    final g = CinematicVfx.buildGraph(
      input: 'sc0',
      output: 'vfx',
      effects: const <CinematicEffect>[
        CinematicEffect.bloomGlow,
        CinematicEffect.vignette,
        CinematicEffect.halation,
      ],
      intensity: .5,
    )!;
    expect(g, startsWith('[sc0]'));
    expect(g, endsWith('[vfx]'));
    expect(g, contains('lutrgb'));
    expect(g, contains('format=gbrp'));
    expect(g, contains('blend=all_mode=screen'));
    expect(g, contains('colorchannelmixer'));
    // Two glow blocks plus the single vignette stage in between.
    expect(RegExp('blend=all_mode=screen').allMatches(g).length, 2);
    expect(g, contains('[fx_1]'));
    expect(g, contains('[fx_2]'));
  });

  test('single-stream effects merge into one plain chain', () {
    final g = CinematicVfx.buildGraph(
      input: 'a',
      output: 'b',
      effects: const <CinematicEffect>[
        CinematicEffect.vignette,
        CinematicEffect.warmGrade,
      ],
    )!;
    expect(g, startsWith('[a]'));
    expect(g, endsWith('[b]'));
    expect(g.contains(';'), isFalse);
    expect(CinematicVfx.buildGraph(input: 'a', output: 'b', effects: const <CinematicEffect>[]), isNull);
  });

  test('overlay animator moves overlays and enlarges their asset', () {
    final built = ReferenceSceneBuilder.buildCutaway(
      id: 't',
      spec: const CutawaySpec(start: 0, end: 2.0, text: 'المال والنجاح الكبير'),
      width: 720,
      height: 1280,
    );
    final out = MotionVfxAnimator.animate(built);
    out.project.validate();
    final fx = <String>[];
    for (final scene in out.project.scenes) {
      for (final layer in scene.layers) {
        if (MotionVfxAnimator.isOverlayKey(layer.assetKey)) {
          expect(layer.keyframes.length, greaterThanOrEqualTo(2));
          fx.add(layer.assetKey!);
        }
      }
    }
    expect(fx, isNotEmpty);
    for (final key in fx) {
      expect(out.assets[key]!.kind, SceneAssetKind.overlay);
      expect(out.assets[key]!.widthFraction, greaterThanOrEqualTo(1.0));
    }
    // Idempotent: animating twice adds no further companion layers.
    final twice = MotionVfxAnimator.animate(out);
    expect(twice.project.scenes.first.layers.length, out.project.scenes.first.layers.length);
  });

  test('screen blend layers get a real blend, normal layers do not', () {
    final built = ReferenceSceneBuilder.buildCutaway(
      id: 't',
      spec: const CutawaySpec(start: 0, end: 2.0, text: 'المال والنجاح الكبير'),
      width: 360,
      height: 640,
    );
    final out = MotionVfxAnimator.animate(built);
    final assets = <String, MotionRenderAsset>{};
    for (final e in out.assets.entries) {
      if (e.value.kind == SceneAssetKind.look) continue;
      final overlay = e.value.kind == SceneAssetKind.overlay;
      assets[e.key] = MotionRenderAsset(
        path: '/tmp/${e.key.hashCode}.png',
        aspect: 1.0,
        widthFraction: e.value.widthFraction,
        screen: overlay &&
            MotionVfxOverlay.prefersScreen(MotionOverlayKind.values.firstWhere((k) => k.name == e.value.spriteKey)),
      );
    }
    final withBlend = MotionFfmpegAdapter.build(project: out.project, assets: assets);
    final without = MotionFfmpegAdapter.build(project: out.project, assets: assets, blendModes: false);
    expect(without.filterComplex.contains('blend=all_mode=screen'), isFalse);
    if (assets.values.any((a) => a.screen)) {
      expect(withBlend.filterComplex, contains('blend=all_mode=screen'));
    }
  });
}
