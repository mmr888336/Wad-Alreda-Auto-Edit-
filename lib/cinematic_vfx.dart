/// FFmpeg cinematic filter recipes. Validate each chain against the bundled
/// FFmpegKit build before enabling it globally on mobile exports.
///
/// Some recipes (bloom, halation) split the picture into two streams, so they
/// carry their own pad labels and can only be used as a stand-alone `-vf`
/// graph. [CinematicVfx.safeChain] returns only the single-stream recipes,
/// which can be appended to an existing filter_complex output.
library;
enum CinematicEffect { bloomGlow, volumetricLight, smokeSoftness, particlesDetail, softShadow, motionBlur, vignette, filmGrain, chromaticAberration, sharpen, warmGrade, coolGrade, depthOfField, cinemaBars, bleachBypass, halation }
class CinematicVfxPreset {
  final String id,label; final List<CinematicEffect> effects;
  const CinematicVfxPreset(this.id,this.label,this.effects);
}
class CinematicVfx {
  CinematicVfx._();
  static const presets=<CinematicVfxPreset>[
    CinematicVfxPreset('clean_cinema','Clean Cinema',[CinematicEffect.bloomGlow,CinematicEffect.vignette,CinematicEffect.warmGrade]),
    CinematicVfxPreset('dramatic','Dramatic',[CinematicEffect.bloomGlow,CinematicEffect.softShadow,CinematicEffect.volumetricLight,CinematicEffect.filmGrain]),
    CinematicVfxPreset('dream','Dream',[CinematicEffect.bloomGlow,CinematicEffect.depthOfField,CinematicEffect.motionBlur]),
    CinematicVfxPreset('tech','Tech',[CinematicEffect.chromaticAberration,CinematicEffect.coolGrade,CinematicEffect.sharpen]),
    CinematicVfxPreset('documentary','Documentary',[CinematicEffect.softShadow,CinematicEffect.filmGrain,CinematicEffect.warmGrade]),
    CinematicVfxPreset('action','Action',[CinematicEffect.motionBlur,CinematicEffect.chromaticAberration,CinematicEffect.vignette]),
    CinematicVfxPreset('filmic','Filmic',[CinematicEffect.halation,CinematicEffect.bleachBypass,CinematicEffect.filmGrain]),
  ];
  static String filterFor(CinematicEffect e,{double intensity=.55}) {
    final v=intensity.clamp(0.0,1.0).toDouble();
    switch(e){
      case CinematicEffect.bloomGlow:
        return "split[base][glow];[glow]gblur=sigma=${(2+v*9).toStringAsFixed(2)},eq=brightness=0.02[soft];[base][soft]blend=all_mode=screen:all_opacity=${(.12+v*.32).toStringAsFixed(3)}";
      case CinematicEffect.volumetricLight: return "eq=brightness=${(v*.05).toStringAsFixed(3)}:contrast=${(1+v*.08).toStringAsFixed(3)},vignette=PI/5";
      case CinematicEffect.smokeSoftness: return "gblur=sigma=${(1+v*2).toStringAsFixed(2)},eq=contrast=${(1-v*.12).toStringAsFixed(3)}";
      case CinematicEffect.particlesDetail: return "unsharp=5:5:${(v*.45).toStringAsFixed(2)}:5:5:0";
      case CinematicEffect.softShadow: return "eq=contrast=${(1+v*.16).toStringAsFixed(3)}:brightness=${(-v*.025).toStringAsFixed(3)}";
      case CinematicEffect.motionBlur: return "tblend=all_mode=average:all_opacity=${(.12+v*.30).toStringAsFixed(3)}";
      case CinematicEffect.vignette: return "vignette=PI/${(8-v*3).toStringAsFixed(2)}";
      case CinematicEffect.filmGrain: return "noise=alls=${(2+v*12).toStringAsFixed(1)}:allf=t+u";
      case CinematicEffect.chromaticAberration: return "rgbashift=rh=${(v*2).round()}:bh=${(-v*2).round()}";
      case CinematicEffect.sharpen: return "unsharp=5:5:${(v*1.1).toStringAsFixed(2)}:5:5:0";
      case CinematicEffect.warmGrade: return "colorbalance=rs=${(v*.12).toStringAsFixed(3)}:gs=${(v*.025).toStringAsFixed(3)}:bs=${(-v*.1).toStringAsFixed(3)},eq=saturation=${(1+v*.12).toStringAsFixed(3)}";
      case CinematicEffect.coolGrade: return "colorbalance=rs=${(-v*.08).toStringAsFixed(3)}:gs=${(v*.02).toStringAsFixed(3)}:bs=${(v*.12).toStringAsFixed(3)}";
      case CinematicEffect.depthOfField: return "gblur=sigma=${(v*1.8).toStringAsFixed(2)}";
      // Letterbox bars: black bands on the top and bottom edges.
      case CinematicEffect.cinemaBars: return "drawbox=x=0:y=0:w=iw:h=ih*${(.05+v*.05).toStringAsFixed(3)}:color=black:t=fill,drawbox=x=0:y=ih-ih*${(.05+v*.05).toStringAsFixed(3)}:w=iw:h=ih*${(.05+v*.05).toStringAsFixed(3)}:color=black:t=fill";
      // Bleach bypass: less colour, harder contrast, slightly deeper gamma.
      case CinematicEffect.bleachBypass: return "eq=saturation=${(1-v*.45).toStringAsFixed(3)}:contrast=${(1+v*.2).toStringAsFixed(3)}:gamma=${(1-v*.05).toStringAsFixed(3)}";
      // Halation: the brightest areas bleed a soft red-orange glow.
      case CinematicEffect.halation:
        return "split[hl_base][hl_src];[hl_src]lutyuv=y='if(gt(val,200),val,0)',gblur=sigma=${(3+v*10).toStringAsFixed(2)},colorchannelmixer=rr=1:gg=0.45:bb=0.2[hl_glow];[hl_base][hl_glow]blend=all_mode=screen:all_opacity=${(.1+v*.3).toStringAsFixed(3)}";
    }
  }
  static CinematicVfxPreset? preset(String id){for(final p in presets){if(p.id==id)return p;}return null;}
  static List<String> chain(Iterable<CinematicEffect> effects,{double intensity=.55})=>effects.map((e)=>filterFor(e,intensity:intensity)).toList();

  /// False for recipes that split the picture and use their own pad labels.
  static bool isSingleStream(CinematicEffect e)=>e!=CinematicEffect.bloomGlow&&e!=CinematicEffect.halation;

  /// Only the single-stream recipes, ready to be joined with commas and
  /// appended to the output pad of an existing filter_complex.
  static List<String> safeChain(Iterable<CinematicEffect> effects,{double intensity=.4})=>[for(final e in effects)if(isSingleStream(e))filterFor(e,intensity:intensity)];
}
