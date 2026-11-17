/// Transparent procedural overlays: smoke, dust, embers, volumetric rays,
/// soft shadows, bokeh, light leaks, rain streaks and sparkles. Render each
/// as a separate timed timeline layer.
///
/// Particles are drawn in three depth layers (small and dim far away, large
/// and soft up close) with additive blending, so overlapping lights add up
/// like real light. Every overlay can carry a baked soft alpha mask (see
/// [OverlayMask]) that keeps the middle of the frame clear for the subject
/// and words. The renderer composites light-type overlays with a screen
/// blend (see [MotionVfxOverlay.prefersScreen]) and moves them with the
/// keyframes of MotionVfxAnimator.
library;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
enum MotionOverlayKind { smoke, dust, embers, volumetricRays, shadow, bokeh, lightLeak, rain, sparkles }

/// Soft alpha mask multiplied into an overlay after it is drawn.
enum OverlayMask {
  /// No mask.
  none,
  /// Fades towards the edges of the frame.
  vignette,
  /// Keeps the edges, thins out the centre (subject and words live there).
  centerClear,
  /// Strong at the bottom, fades upwards (ground fog, rising embers).
  bottomFog,
  /// Strong at the top, fades downwards (light falling from above).
  topLight,
}

class MotionVfxOverlay {
  MotionVfxOverlay._();
  static int _defaultColor(MotionOverlayKind kind)=>switch(kind){
    MotionOverlayKind.embers=>0xFFFF8A3D,
    MotionOverlayKind.lightLeak=>0xFFFF9A4D,
    MotionOverlayKind.sparkles=>0xFFFFE9B0,
    _=>0xFFB9D8FF,
  };

  /// The mask that suits [kind] when none is given.
  static OverlayMask defaultMask(MotionOverlayKind kind)=>switch(kind){
    MotionOverlayKind.smoke=>OverlayMask.centerClear,
    MotionOverlayKind.embers=>OverlayMask.bottomFog,
    MotionOverlayKind.volumetricRays=>OverlayMask.topLight,
    MotionOverlayKind.bokeh=>OverlayMask.centerClear,
    MotionOverlayKind.dust=>OverlayMask.vignette,
    _=>OverlayMask.none,
  };

  /// Light-type overlays are composited with a screen blend; smoke and
  /// shadows darken or veil the picture and use the normal alpha blend.
  static bool prefersScreen(MotionOverlayKind kind)=>kind!=MotionOverlayKind.smoke&&kind!=MotionOverlayKind.shadow;

  /// How much larger than the canvas the overlay is rendered, so it can drift
  /// without showing its edges (and without being scaled up).
  static double travelFactor(MotionOverlayKind kind)=>switch(kind){
    MotionOverlayKind.smoke=>1.18,
    MotionOverlayKind.embers=>1.25,
    MotionOverlayKind.dust=>1.12,
    MotionOverlayKind.bokeh=>1.12,
    MotionOverlayKind.volumetricRays=>1.10,
    MotionOverlayKind.lightLeak=>1.10,
    MotionOverlayKind.rain=>1.10,
    MotionOverlayKind.sparkles=>1.10,
    MotionOverlayKind.shadow=>1.0,
  };

  static double _cl(double a)=>a<0?0.0:(a>1?1.0:a);

  static Future<Uint8List> renderPng({required MotionOverlayKind kind,int width=1080,int height=1920,int seed=7,double intensity=.6,int? color,OverlayMask? mask}) async {
    final rec=ui.PictureRecorder();final c=ui.Canvas(rec);final rng=math.Random(seed);final v=intensity.clamp(0.0,1.0).toDouble();
    final w=width.toDouble(),h=height.toDouble();
    final col=ui.Color(color??_defaultColor(kind));final side=math.max(w,h);
    final area=((w*h)/(720*1280)).clamp(.5,2.5).toDouble();
    final full=ui.Rect.fromLTWH(0,0,w,h);
    const white=ui.Color(0xFFFFFFFF);
    c.saveLayer(full,ui.Paint());

    ui.Paint add()=>ui.Paint()..blendMode=ui.BlendMode.plus;
    // Soft round light: a radial gradient is much cheaper than a blur filter.
    void glow(double x,double y,double r,ui.Color k,double a,{bool plus=true}){
      final p=plus?add():ui.Paint();
      p.shader=ui.Gradient.radial(ui.Offset(x,y),r,[k.withOpacity(_cl(a)),k.withOpacity(0)]);
      c.drawCircle(ui.Offset(x,y),r,p);
    }

    if(kind==MotionOverlayKind.smoke){
      // Rising plumes: puffs follow a swaying curve, grow and thin out.
      final plumes=3+rng.nextInt(2);
      for(var p=0;p<plumes;p++){
        final bx=w*(.12+rng.nextDouble()*.76),amp=w*(.04+rng.nextDouble()*.07),ph=rng.nextDouble()*6.28,fr=1.2+rng.nextDouble()*1.4;
        const puffs=15;
        for(var i=0;i<puffs;i++){
          final t=i/(puffs-1);
          final x=bx+math.sin(t*fr*math.pi+ph)*amp*(.4+t),y=h*(1.02-t*.95);
          final r=side*(.045+t*.10)*(.8+rng.nextDouble()*.5);
          final a=.12*v*(1-t*.7)*(.7+rng.nextDouble()*.6);
          glow(x,y,r,col,a,plus:false);
          glow(x+r*.25,y-r*.2,r*.7,ui.Color.lerp(col,white,.4)!,a*.7,plus:false);
        }
      }
    } else if(kind==MotionOverlayKind.dust){
      // Far (many, tiny, dim), middle and near (few, big, soft) motes.
      final layers=<List<double>>[[260,.6,1.3,.35],[90,1.2,2.4,.45],[22,5,11,.16]];
      for(var li=0;li<layers.length;li++){
        final L=layers[li];
        final n=(L[0]*v*area*1.4).round()+4;
        for(var i=0;i<n;i++){
          final x=rng.nextDouble()*w,y=rng.nextDouble()*h;
          final r=(L[1]+rng.nextDouble()*(L[2]-L[1]))*math.sqrt(area);
          final a=L[3]*(.4+rng.nextDouble()*.6)*(.4+v*.8);
          if(li==2){glow(x,y,r*1.6,col,a*.5);}else{c.drawCircle(ui.Offset(x,y),r,add()..color=col.withOpacity(_cl(a)));}
        }
      }
    } else if(kind==MotionOverlayKind.embers){
      // Dense near the bottom; each ember has a hot core, a glow and a short
      // streak that suggests its motion.
      final n=(120*v*area).round()+14;
      for(var i=0;i<n;i++){
        final rise=math.pow(rng.nextDouble(),1.7).toDouble();
        final x=rng.nextDouble()*w,y=h*(1-rise*.92),depth=rng.nextDouble();
        final r=(1+depth*3.4)*math.sqrt(area),heat=1-rise*.6;
        final hot=ui.Color.lerp(col,const ui.Color(0xFFFFE08A),heat*.8)!;
        final a=(.35+rng.nextDouble()*.5)*heat*(.5+v*.7),len=r*(3+depth*5);
        c.drawLine(ui.Offset(x,y),ui.Offset(x-len*.28,y+len),add()..color=hot.withOpacity(_cl(a*.55))..strokeWidth=r*.9..strokeCap=ui.StrokeCap.round);
        glow(x,y,r*3.2,col,a*.45);
        c.drawCircle(ui.Offset(x,y),r*.7,add()..color=const ui.Color(0xFFFFF4C8).withOpacity(_cl(a)));
      }
    } else if(kind==MotionOverlayKind.volumetricRays){
      // Shafts fan out from one light source above a corner and fade with
      // distance; overlapping shafts add up.
      final left=rng.nextBool();
      final src=ui.Offset(left?-w*.1:w*1.1,-h*.12);
      final rays=9+rng.nextInt(5);
      final base=math.atan2(h*.9-src.dy,w*.5-src.dx),len=side*2.2;
      for(var i=0;i<rays;i++){
        final ang=base+(rng.nextDouble()-.5)*.9,spread=.018+rng.nextDouble()*.05;
        final p1=src+ui.Offset(math.cos(ang-spread)*len,math.sin(ang-spread)*len);
        final p2=src+ui.Offset(math.cos(ang+spread)*len,math.sin(ang+spread)*len);
        final end=src+ui.Offset(math.cos(ang)*len,math.sin(ang)*len);
        final path=ui.Path()..moveTo(src.dx,src.dy)..lineTo(p1.dx,p1.dy)..lineTo(p2.dx,p2.dy)..close();
        final a=.20*v*(.5+rng.nextDouble()*.8);
        c.drawPath(path,add()..shader=ui.Gradient.linear(src,end,[col.withOpacity(_cl(a)),col.withOpacity(0)]));
      }
      glow(left?w*.05:w*.95,h*.03,side*.5,col,.22*v);
    } else if(kind==MotionOverlayKind.shadow){
      c.drawRect(full,ui.Paint()..shader=ui.Gradient.radial(ui.Offset(w*.5,h*.48),side*.72,[const ui.Color(0x00000000),ui.Color.fromARGB((v*190).round(),0,0,0)],[.28,1]));
    } else if(kind==MotionOverlayKind.bokeh){
      // Out-of-focus lights: a soft disc with a brighter rim, three sizes.
      const tints=<int>[0xFFFFE2A8,0xFFB8D8FF,0xFFFFC2D8];
      final n=(26*area).round()+10;
      for(var i=0;i<n;i++){
        final depth=rng.nextDouble(),r=side*(.012+depth*depth*.05);
        final x=rng.nextDouble()*w,y=rng.nextDouble()*h;
        final k=ui.Color.lerp(col,ui.Color(tints[rng.nextInt(3)]),.55)!;
        final a=(.05+rng.nextDouble()*.07)*(.6+v);
        c.drawCircle(ui.Offset(x,y),r,add()..color=k.withOpacity(_cl(a)));
        c.drawCircle(ui.Offset(x,y),r,add()..color=k.withOpacity(_cl(a*2.2))..style=ui.PaintingStyle.stroke..strokeWidth=math.max(1.0,r*.07));
      }
    } else if(kind==MotionOverlayKind.lightLeak){
      // Warm glows bleeding in from one edge of the frame.
      final ex=rng.nextBool()?w*.02:w*.98;
      glow(ex,h*(.12+rng.nextDouble()*.5),side*.62,col,.62*v);
      glow(w-ex,h*(.5+rng.nextDouble()*.4),side*.45,const ui.Color(0xFFFF4D6D),.38*v);
      glow(ex,h*(.5+rng.nextDouble()*.45),side*.34,const ui.Color(0xFFFFD27A),.26*v);
      c.drawRect(full,add()..shader=ui.Gradient.linear(ui.Offset(ex,0),ui.Offset(w*.5,0),[col.withOpacity(_cl(.25*v)),col.withOpacity(0)]));
    } else if(kind==MotionOverlayKind.rain){
      // Three depths: thin and faint, medium, thick and bright.
      for(var li=0;li<3;li++){
        final n=((li==0?110:(li==1?60:24))*v*area).round()+8;
        for(var i=0;i<n;i++){
          final x=rng.nextDouble()*w,y=rng.nextDouble()*h,len=h*(.02+li*.018+rng.nextDouble()*.03);
          final a=(.14+li*.12)*(.6+v);
          c.drawLine(ui.Offset(x,y),ui.Offset(x-len*.18,y+len),ui.Paint()..color=col.withOpacity(_cl(a))..strokeWidth=math.max(1.0,w*(.0009+li*.0009))..strokeCap=ui.StrokeCap.round);
        }
      }
    } else if(kind==MotionOverlayKind.sparkles){
      // Four-point glints with diagonal rays and a soft white core.
      final n=(36*v*area).round()+6;
      for(var i=0;i<n;i++){
        final x=rng.nextDouble()*w,y=rng.nextDouble()*h;
        final r=side*(.004+rng.nextDouble()*.012)*(rng.nextDouble()<.15?2.2:1.0);
        final a=.35+rng.nextDouble()*.5;
        final sp=add()..color=col.withOpacity(_cl(a))..strokeWidth=math.max(1.0,r*.28)..strokeCap=ui.StrokeCap.round;
        final dp=add()..color=col.withOpacity(_cl(a*.5))..strokeWidth=math.max(1.0,r*.18)..strokeCap=ui.StrokeCap.round;
        c.drawLine(ui.Offset(x-r*2.6,y),ui.Offset(x+r*2.6,y),sp);
        c.drawLine(ui.Offset(x,y-r*2.6),ui.Offset(x,y+r*2.6),sp);
        c.drawLine(ui.Offset(x-r*1.2,y-r*1.2),ui.Offset(x+r*1.2,y+r*1.2),dp);
        c.drawLine(ui.Offset(x-r*1.2,y+r*1.2),ui.Offset(x+r*1.2,y-r*1.2),dp);
        glow(x,y,r*2.2,white,.55*v);
      }
    }

    _applyMask(c,full,mask??defaultMask(kind),w,h,side);
    c.restore();
    final pic=rec.endRecording();final image=await pic.toImage(width,height);final data=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();pic.dispose();if(data==null)throw StateError('Overlay PNG encoding failed');return data.buffer.asUint8List();
  }

  /// Multiplies the alpha of everything drawn so far in the current layer by
  /// a soft gradient (destination-in blend).
  static void _applyMask(ui.Canvas c,ui.Rect full,OverlayMask m,double w,double h,double side) {
    if(m==OverlayMask.none)return;
    const white=ui.Color(0xFFFFFFFF),clear=ui.Color(0x00FFFFFF);
    final p=ui.Paint()..blendMode=ui.BlendMode.dstIn;
    switch(m){
      case OverlayMask.none:
        return;
      case OverlayMask.vignette:
        p.shader=ui.Gradient.radial(ui.Offset(w/2,h/2),side*.72,[white,white,clear],[0,.5,1]);
      case OverlayMask.centerClear:
        p.shader=ui.Gradient.radial(ui.Offset(w/2,h*.46),side*.5,[const ui.Color(0x55FFFFFF),white],[0,1]);
      case OverlayMask.bottomFog:
        p.shader=ui.Gradient.linear(ui.Offset.zero,ui.Offset(0,h),[clear,const ui.Color(0x88FFFFFF),white],[0,.45,1]);
      case OverlayMask.topLight:
        p.shader=ui.Gradient.linear(ui.Offset.zero,ui.Offset(0,h),[white,const ui.Color(0x66FFFFFF),clear],[0,.55,1]);
    }
    c.drawRect(full,p);
  }
}
