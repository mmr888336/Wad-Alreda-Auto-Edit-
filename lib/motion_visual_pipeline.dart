/// Scene-level semantic visual and cinematic-look planner.
library;
import 'motion_visual_library.dart';
import 'motion_vfx_overlay.dart';
import 'cinematic_vfx.dart';

class MotionVisualPlan {
  final List<MotionVisualMatch> assets;
  final CinematicVfxPreset preset;

  /// Transparent overlay layers that suit the preset, most fitting first.
  final List<MotionOverlayKind> overlays;
  const MotionVisualPlan(this.assets,this.preset,{this.overlays=const <MotionOverlayKind>[]});
  List<CinematicEffect> get effects=>preset.effects;

  /// Mobile-safe grade for the whole clip: only the single-stream recipes of
  /// the preset, at a moderate intensity.
  List<String> get postFilters=>CinematicVfx.safeChain(effects);
}
class MotionVisualPipeline {
  MotionVisualPipeline._();
  static const _overlaysByPreset=<String,List<MotionOverlayKind>>{
    'clean_cinema':[MotionOverlayKind.bokeh,MotionOverlayKind.lightLeak],
    'dramatic':[MotionOverlayKind.smoke,MotionOverlayKind.volumetricRays],
    'dream':[MotionOverlayKind.bokeh,MotionOverlayKind.sparkles],
    'tech':[MotionOverlayKind.dust,MotionOverlayKind.sparkles],
    'documentary':[MotionOverlayKind.dust],
    'action':[MotionOverlayKind.embers,MotionOverlayKind.smoke],
    'filmic':[MotionOverlayKind.lightLeak,MotionOverlayKind.dust],
  };
  static String presetIdFor(String mood)=>switch(mood){'calm'=>'documentary','dynamic'=>'action','dream'=>'dream','tech'=>'tech','dramatic'=>'dramatic','filmic'=>'filmic',_=>'clean_cinema'};
  static MotionVisualPlan plan({required String spokenText,String mood='cinematic',int maxAssets=3}) {
    final id=presetIdFor(mood);
    return MotionVisualPlan(MotionVisualLibrary.search(spokenText,limit:maxAssets),CinematicVfx.preset(id)!,overlays:_overlaysByPreset[id]??const <MotionOverlayKind>[]);
  }
}
