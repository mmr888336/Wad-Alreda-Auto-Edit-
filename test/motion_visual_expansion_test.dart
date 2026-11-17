import 'package:flutter_test/flutter_test.dart';
import 'package:auto_edit/motion_visual_library.dart';
import 'package:auto_edit/cinematic_vfx.dart';
import 'package:auto_edit/motion_vfx_overlay.dart';
import 'package:auto_edit/motion_visual_pipeline.dart';
void main(){
  test('catalog has a broad visual vocabulary',(){expect(MotionVisualLibrary.assets.length,greaterThanOrEqualTo(40));});
  test('Arabic and English semantic search',(){
    expect(MotionVisualLibrary.search('الطالب يقرأ كتاباً في الجامعة').first.asset.id,anyOf('book','graduation'));
    expect(MotionVisualLibrary.search('cinema video camera').first.asset.id,'camera');
    expect(MotionVisualLibrary.search('استثمار ونمو الأرباح').first.asset.category,VisualCategory.money);
  });
  test('all cinematic recipes are available',(){
    expect(CinematicVfx.presets.length,7);
    for(final e in CinematicEffect.values){expect(CinematicVfx.filterFor(e,intensity:1),isNotEmpty);}
  });
  test('new cinematic effects: cinema bars, bleach bypass, halation',(){
    expect(CinematicVfx.filterFor(CinematicEffect.cinemaBars),contains('drawbox'));
    expect(CinematicVfx.filterFor(CinematicEffect.bleachBypass),contains('saturation='));
    expect(CinematicVfx.filterFor(CinematicEffect.halation),allOf(contains('lutyuv'),contains('blend=all_mode=screen')));
    expect(CinematicVfx.preset('filmic')!.effects,contains(CinematicEffect.halation));
  });
  test('safeChain keeps only single-stream recipes',(){
    final chain=CinematicVfx.safeChain(CinematicEffect.values);
    expect(chain.length,CinematicEffect.values.length-2);
    for(final f in chain){expect(f.contains('['),isFalse);expect(f.contains(';'),isFalse);}
    expect(CinematicVfx.isSingleStream(CinematicEffect.bloomGlow),isFalse);
    expect(CinematicVfx.isSingleStream(CinematicEffect.halation),isFalse);
  });
  test('overlay kinds include light leak, rain and sparkles',(){
    expect(MotionOverlayKind.values,containsAll(<MotionOverlayKind>[MotionOverlayKind.lightLeak,MotionOverlayKind.rain,MotionOverlayKind.sparkles]));
  });
  test('planner returns assets and mood preset',(){
    final p=MotionVisualPipeline.plan(spokenText:'قلبك يحتاج الأمل بعد الحزن',mood:'dramatic');
    expect(p.assets,isNotEmpty);expect(p.preset.id,'dramatic');
    expect(p.overlays,isNotEmpty);expect(p.postFilters,isNotEmpty);
  });
  test('every preset has overlays and a safe post chain',(){
    for(final mood in const ['cinematic','calm','dynamic','dream','tech','dramatic','filmic']){
      final p=MotionVisualPipeline.plan(spokenText:'مال',mood:mood);
      expect(p.overlays,isNotEmpty,reason:mood);
      expect(p.postFilters,isNotEmpty,reason:mood);
    }
  });
}
