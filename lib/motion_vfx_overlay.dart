/// Transparent procedural overlays: smoke, dust, embers, volumetric rays,
/// soft shadows, bokeh, light leaks, rain streaks and sparkles. Render each
/// as a separate timed timeline layer.
library;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
enum MotionOverlayKind { smoke, dust, embers, volumetricRays, shadow, bokeh, lightLeak, rain, sparkles }
class MotionVfxOverlay {
  MotionVfxOverlay._();
  static int _defaultColor(MotionOverlayKind kind)=>switch(kind){
    MotionOverlayKind.embers=>0xFFFF8A3D,
    MotionOverlayKind.lightLeak=>0xFFFF9A4D,
    MotionOverlayKind.sparkles=>0xFFFFE9B0,
    _=>0xFFB9D8FF,
  };
  static Future<Uint8List> renderPng({required MotionOverlayKind kind,int width=1080,int height=1920,int seed=7,double intensity=.6,int? color}) async {
    final rec=ui.PictureRecorder();final c=ui.Canvas(rec);final rng=math.Random(seed);final v=intensity.clamp(0.0,1.0).toDouble();
    final col=ui.Color(color??_defaultColor(kind));final side=math.max(width,height).toDouble();
    if(kind==MotionOverlayKind.smoke){
      for(var i=0;i<36;i++){final x=rng.nextDouble()*width,y=rng.nextDouble()*height,r=side*(.025+rng.nextDouble()*.09);c.drawOval(ui.Rect.fromCenter(center:ui.Offset(x,y),width:r*1.7,height:r),ui.Paint()..color=col.withOpacity((.01+rng.nextDouble()*.03)*v)..maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,r*.55));}
    } else if(kind==MotionOverlayKind.dust||kind==MotionOverlayKind.embers){
      for(var i=0;i<(190*v).round();i++){final x=rng.nextDouble()*width,y=rng.nextDouble()*height,r=.5+rng.nextDouble()*(kind==MotionOverlayKind.embers?3.2:1.4);final p=ui.Paint()..color=col.withOpacity((.12+rng.nextDouble()*.65)*v);if(kind==MotionOverlayKind.embers)p.maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,r*1.8);c.drawCircle(ui.Offset(x,y),r,p);}
    } else if(kind==MotionOverlayKind.volumetricRays){
      for(var i=0;i<8;i++){final x=width*(.1+rng.nextDouble()*.8);final p=ui.Path()..moveTo(x-width*.03,0)..lineTo(x+width*.02,0)..lineTo(x+width*(.08+rng.nextDouble()*.1),height)..lineTo(x-width*.06,height)..close();c.drawPath(p,ui.Paint()..shader=ui.Gradient.linear(ui.Offset(x,0),ui.Offset(x,height.toDouble()),[col.withOpacity(0),col.withOpacity(.04*v),col.withOpacity(0)]));}
    } else if(kind==MotionOverlayKind.shadow){
      c.drawRect(ui.Rect.fromLTWH(0,0,width.toDouble(),height.toDouble()),ui.Paint()..shader=ui.Gradient.radial(ui.Offset(width*.5,height*.48),side*.72,[const ui.Color(0x00000000),ui.Color.fromARGB((v*190).round(),0,0,0)],[.28,1]));
    } else if(kind==MotionOverlayKind.lightLeak){
      // Two soft warm glows bleeding in from the edges of the frame.
      final full=ui.Rect.fromLTWH(0,0,width.toDouble(),height.toDouble());
      final edge=rng.nextBool()?width*.04:width*.96;
      c.drawRect(full,ui.Paint()..shader=ui.Gradient.radial(ui.Offset(edge,height*(.12+rng.nextDouble()*.5)),side*.55,[col.withOpacity(.55*v),col.withOpacity(0)]));
      final warm=ui.Color(0xFFFF4D6D);
      c.drawRect(full,ui.Paint()..shader=ui.Gradient.radial(ui.Offset(width-edge,height*(.55+rng.nextDouble()*.4)),side*.4,[warm.withOpacity(.3*v),warm.withOpacity(0)]));
    } else if(kind==MotionOverlayKind.rain){
      // Thin slanted streaks.
      final p=ui.Paint()..color=col.withOpacity(.35*v)..strokeWidth=math.max(1.0,width*.0016)..strokeCap=ui.StrokeCap.round;
      for(var i=0;i<(140*v).round()+20;i++){final x=rng.nextDouble()*width,y=rng.nextDouble()*height,len=height*(.02+rng.nextDouble()*.035);c.drawLine(ui.Offset(x,y),ui.Offset(x-len*.18,y+len),p);}
    } else if(kind==MotionOverlayKind.sparkles){
      // Four-point glints with a soft white core.
      for(var i=0;i<(42*v).round()+6;i++){
        final x=rng.nextDouble()*width,y=rng.nextDouble()*height,r=side*(.004+rng.nextDouble()*.012);
        final sp=ui.Paint()..color=col.withOpacity(.35+rng.nextDouble()*.5)..strokeWidth=math.max(1.0,r*.35)..strokeCap=ui.StrokeCap.round;
        c.drawLine(ui.Offset(x-r*2.2,y),ui.Offset(x+r*2.2,y),sp);
        c.drawLine(ui.Offset(x,y-r*2.2),ui.Offset(x,y+r*2.2),sp);
        c.drawCircle(ui.Offset(x,y),r*.8,ui.Paint()..color=const ui.Color(0xFFFFFFFF).withOpacity(.6*v)..maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,r*.9));
      }
    } else {
      for(var i=0;i<40;i++){final x=rng.nextDouble()*width,y=rng.nextDouble()*height,r=side*(.004+rng.nextDouble()*.018);c.drawCircle(ui.Offset(x,y),r,ui.Paint()..color=col.withOpacity(.04*v)..maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,r*1.4));}
    }
    final pic=rec.endRecording();final image=await pic.toImage(width,height);final data=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();pic.dispose();if(data==null)throw StateError('Overlay PNG encoding failed');return data.buffer.asUint8List();
  }
}
