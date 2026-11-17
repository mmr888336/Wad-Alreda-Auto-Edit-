/// Semantic catalogue and original procedural visual assets for Wad Alreda.
library;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

enum VisualCategory { people, emotion, faith, education, business, money, technology, media, travel, nature, health, food, architecture, objects, abstract }

class MotionVisualAsset {
  final String id;
  final VisualCategory category;
  final List<String> tags;
  final String description;
  final int color;
  const MotionVisualAsset(this.id,this.category,this.tags,this.description,this.color);
}
class MotionVisualMatch {
  final MotionVisualAsset asset;
  final double score;
  const MotionVisualMatch(this.asset,this.score);
}

class MotionVisualLibrary {
  MotionVisualLibrary._();
  static const assets = <MotionVisualAsset>[
    MotionVisualAsset('person',VisualCategory.people,['شخص','انسان','رجل','امرأة','شاب','طفل','human','person','people','man','woman'],'Human silhouette',0xFF65D6CE),
    MotionVisualAsset('thinking_head',VisualCategory.people,['تفكير','عقل','فكرة','وعي','mind','think','brain','idea'],'Thinking profile',0xFFB8A0FF),
    MotionVisualAsset('crowd',VisualCategory.people,['جمهور','مجموعة','مجتمع','فريق','crowd','community','team'],'Crowd',0xFF75B9FF),
    MotionVisualAsset('heart',VisualCategory.emotion,['حب','قلب','رحمة','حنان','عشق','مشاعر','love','heart','care','emotion'],'Heart',0xFFFF668B),
    MotionVisualAsset('broken_heart',VisualCategory.emotion,['حزن','فراق','انكسار','ألم','خذلان','sad','pain','broken'],'Broken heart',0xFFFF7C83),
    MotionVisualAsset('hope',VisualCategory.emotion,['أمل','بداية','فجر','رجاء','hope','sunrise','beginning'],'Hope',0xFFFFC46A),
    MotionVisualAsset('book',VisualCategory.education,['كتاب','قراءة','علم','تعلم','دراسة','معرفة','book','read','learn','study','knowledge'],'Open book',0xFFFFD27A),
    MotionVisualAsset('graduation',VisualCategory.education,['تخرج','جامعة','طالب','مدرسة','شهادة','تعليم','graduate','school','student','education'],'Graduation',0xFF78B8FF),
    MotionVisualAsset('bulb',VisualCategory.education,['ابتكار','اختراع','حل','فكرة','ذكاء','innovation','solution','lightbulb','idea'],'Light bulb',0xFFFFD35C),
    MotionVisualAsset('mosque',VisualCategory.faith,['مسجد','صلاة','إسلام','مسلمين','عبادة','قرآن','mosque','prayer','islam','muslim','quran'],'Mosque',0xFF7BD8C6),
    MotionVisualAsset('crescent',VisualCategory.faith,['هلال','رمضان','عيد','قمر','crescent','ramadan','eid','moon'],'Crescent',0xFFFFD27A),
    MotionVisualAsset('prayer_beads',VisualCategory.faith,['تسبيح','ذكر','استغفار','سبحة','dhikr','tasbih'],'Prayer beads',0xFF73CBAE),
    MotionVisualAsset('briefcase',VisualCategory.business,['عمل','وظيفة','شركة','مهنة','إدارة','business','work','career','company','office'],'Briefcase',0xFF82B7FF),
    MotionVisualAsset('store',VisualCategory.business,['متجر','تجارة','بيع','شراء','سوق','محل','shop','store','market','commerce'],'Store',0xFF75D4C3),
    MotionVisualAsset('handshake',VisualCategory.business,['اتفاق','شراكة','تعاون','ثقة','صفقة','deal','partnership','trust'],'Handshake',0xFFFFC078),
    MotionVisualAsset('coins',VisualCategory.money,['مال','فلوس','نقود','ذهب','رزق','ثروة','money','cash','coin','wealth','gold'],'Coins',0xFFFFD15D),
    MotionVisualAsset('wallet',VisualCategory.money,['محفظة','مصروف','ميزانية','دفع','wallet','budget','payment'],'Wallet',0xFF70B9FF),
    MotionVisualAsset('growth',VisualCategory.money,['نمو','استثمار','ربح','أرباح','اقتصاد','أسهم','growth','investment','profit','finance'],'Growth chart',0xFF5DE0A0),
    MotionVisualAsset('phone',VisualCategory.technology,['هاتف','جوال','موبايل','تطبيق','اتصال','phone','mobile','app','call'],'Smartphone',0xFF7CCBFF),
    MotionVisualAsset('laptop',VisualCategory.technology,['حاسوب','كمبيوتر','لابتوب','برمجة','موقع','computer','laptop','coding','software'],'Laptop',0xFF90A9FF),
    MotionVisualAsset('chip',VisualCategory.technology,['ذكاء اصطناعي','تقنية','معالج','روبوت','بيانات','ai','technology','chip','robot','data'],'AI chip',0xFFB69AFF),
    MotionVisualAsset('camera',VisualCategory.media,['كاميرا','تصوير','فيديو','صورة','محتوى','camera','video','photo','content','film'],'Camera',0xFFFFA66E),
    MotionVisualAsset('microphone',VisualCategory.media,['ميكروفون','بودكاست','تسجيل','مذيع','صوت','microphone','podcast','record','audio'],'Microphone',0xFFFF8C9E),
    MotionVisualAsset('clapper',VisualCategory.media,['سينما','فيلم','مونتاج','إخراج','مشهد','cinema','movie','editing','film'],'Clapperboard',0xFFB5A4FF),
    MotionVisualAsset('airplane',VisualCategory.travel,['سفر','طائرة','رحلة','مطار','سياحة','travel','airplane','flight','airport'],'Airplane',0xFF80C8FF),
    MotionVisualAsset('mountain',VisualCategory.travel,['جبل','مغامرة','تسلق','طبيعة','mountain','adventure','hiking'],'Mountain',0xFF8FD0B1),
    MotionVisualAsset('globe',VisualCategory.travel,['عالم','دول','بلاد','كرة أرضية','global','world','country','earth'],'Globe',0xFF6FC7D9),
    MotionVisualAsset('tree',VisualCategory.nature,['شجرة','زرع','نبات','غابة','بيئة','tree','plant','forest','environment'],'Tree',0xFF70D69A),
    MotionVisualAsset('water',VisualCategory.nature,['ماء','بحر','نهر','مطر','محيط','water','sea','river','rain','ocean'],'Water',0xFF69C8FF),
    MotionVisualAsset('flower',VisualCategory.nature,['زهرة','ورد','جمال','ربيع','flower','rose','spring'],'Flower',0xFFFF91BD),
    MotionVisualAsset('medical',VisualCategory.health,['طب','صحة','مستشفى','علاج','طبيب','دواء','medical','health','hospital','doctor','medicine'],'Medical cross',0xFF75DDBB),
    MotionVisualAsset('brain',VisualCategory.health,['دماغ','مخ','ذاكرة','أعصاب','brain','memory','neuron'],'Brain',0xFFFF9BB2),
    MotionVisualAsset('apple',VisualCategory.food,['تفاح','فاكهة','طعام','أكل','غذاء','apple','fruit','food','nutrition'],'Apple',0xFFFF6D73),
    MotionVisualAsset('coffee',VisualCategory.food,['قهوة','شاي','مشروب','كافيه','coffee','tea','drink','cafe'],'Coffee',0xFFC99A72),
    MotionVisualAsset('house',VisualCategory.architecture,['بيت','منزل','سكن','عمارة','غرفة','house','home','building','room'],'House',0xFFFFBE78),
    MotionVisualAsset('door',VisualCategory.architecture,['باب','مدخل','خروج','دخول','فرصة','door','entrance','exit','opportunity'],'Door',0xFFC69C78),
    MotionVisualAsset('key',VisualCategory.objects,['مفتاح','حل','سر','فتح','key','unlock','secret','solution'],'Key',0xFFFFD16B),
    MotionVisualAsset('clock',VisualCategory.objects,['وقت','زمن','ساعة','موعد','time','clock','deadline'],'Clock',0xFF9DBBFF),
    MotionVisualAsset('shield',VisualCategory.objects,['حماية','أمان','دفاع','خصوصية','security','protection','shield','privacy'],'Shield',0xFF76D6C7),
    MotionVisualAsset('warning',VisualCategory.objects,['خطر','تحذير','مشكلة','خطأ','انتباه','warning','danger','problem','alert'],'Warning',0xFFFFA45E),
    MotionVisualAsset('star',VisualCategory.abstract,['نجاح','تميز','أفضل','إنجاز','فوز','success','achievement','winner','star'],'Star',0xFFFFD36B),
    MotionVisualAsset('target',VisualCategory.abstract,['هدف','تركيز','خطة','طموح','goal','focus','target','ambition'],'Target',0xFFFF7D88),
    MotionVisualAsset('fire',VisualCategory.abstract,['نار','حماس','قوة','طاقة','اشتعال','fire','energy','power','passion'],'Flame',0xFFFF965C),
  ];

  static String normalize(String value) {
    var s=value.toLowerCase().replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'),'');
    const map={'أ':'ا','إ':'ا','آ':'ا','ى':'ي','ة':'ه','ؤ':'و','ئ':'ي'};
    map.forEach((a,b){s=s.replaceAll(a,b);});
    return s.replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9\s]'),' ').replaceAll(RegExp(r'\s+'),' ').trim();
  }

  static List<MotionVisualMatch> search(String sentence,{int limit=5}) {
    final q=normalize(sentence);
    final words=q.split(' ').where((w)=>w.length>1).toSet();
    final results=<MotionVisualMatch>[];
    for(final a in assets){
      var score=0.0;
      for(final tag in a.tags){
        final t=normalize(tag);
        if(q.contains(t)) score+=t.contains(' ')?5:3;
        for(final w in words){if(w.length>=3&&(t.startsWith(w)||w.startsWith(t)))score+=.8;}
      }
      if(score>0)results.add(MotionVisualMatch(a,score));
    }
    results.sort((a,b)=>b.score.compareTo(a.score));
    return results.take(limit.clamp(1,20)).toList(growable:false);
  }
  static MotionVisualAsset? byId(String id) {
    for(final a in assets){if(a.id==id)return a;} return null;
  }

  /// Draws a consistent high-resolution transparent icon/illustration.
  static Future<Uint8List> renderPng(String id,{int size=512,int seed=0}) async {
    final a=byId(id); if(a==null)throw ArgumentError.value(id,'id');
    final rec=ui.PictureRecorder(); final c=ui.Canvas(rec);
    final s=size.toDouble(), center=ui.Offset(size/2,size/2), color=ui.Color(a.color);
    final glow=ui.Paint()..color=color.withOpacity(.2)..maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,s*.055);
    final fill=ui.Paint()..color=color;
    final dark=ui.Paint()..color=const ui.Color(0xFF101827);
    final line=ui.Paint()..color=const ui.Color(0xFFF5F7FF)..style=ui.PaintingStyle.stroke..strokeWidth=s*.025..strokeCap=ui.StrokeCap.round;
    c.drawCircle(center,s*.29,glow);
    void circle(double x,double y,double r,ui.Paint p)=>c.drawCircle(ui.Offset(s*x,s*y),s*r,p);
    void box(double x,double y,double w,double h,ui.Paint p)=>c.drawRRect(ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(s*x,s*y,s*w,s*h),ui.Radius.circular(s*.035)),p);
    switch(a.category){
      case VisualCategory.people:
        circle(.5,.31,.12,fill); box(.36,.46,.28,.32,fill);
        if(id=='crowd'){circle(.25,.4,.08,fill);circle(.75,.4,.08,fill);box(.13,.53,.22,.22,fill);box(.65,.53,.22,.22,fill);}
        if(id=='thinking_head'){circle(.75,.2,.035,fill);circle(.83,.13,.02,fill);}
      case VisualCategory.emotion:
        final p=ui.Path()..moveTo(s*.5,s*.77)..cubicTo(s*.08,s*.49,s*.18,s*.22,s*.39,s*.29)..cubicTo(s*.46,s*.31,s*.49,s*.37,s*.5,s*.4)..cubicTo(s*.65,s*.15,s*.94,s*.27,s*.84,s*.52)..close(); c.drawPath(p,fill);
      case VisualCategory.faith:
        if(id=='crescent'){circle(.5,.45,.25,fill);circle(.61,.36,.22,dark);}
        else if(id=='prayer_beads'){for(var i=0;i<22;i++){final t=i*math.pi*2/22;circle(.5+math.cos(t)*.22,.48+math.sin(t)*.22,.025,fill);}}
        else {final p=ui.Path()..moveTo(s*.18,s*.72)..lineTo(s*.18,s*.48)..quadraticBezierTo(s*.5,s*.08,s*.82,s*.48)..lineTo(s*.82,s*.72)..close();c.drawPath(p,fill);box(.44,.52,.12,.2,dark);}
      case VisualCategory.education:
        if(id=='bulb'){circle(.5,.4,.2,fill);box(.4,.59,.2,.09,fill);}
        else {final p=ui.Path()..moveTo(s*.15,s*.3)..quadraticBezierTo(s*.35,s*.24,s*.5,s*.38)..lineTo(s*.5,s*.75)..quadraticBezierTo(s*.3,s*.62,s*.15,s*.7)..close();c.drawPath(p,fill);c.drawLine(ui.Offset(s*.5,s*.38),ui.Offset(s*.5,s*.75),line);}
      case VisualCategory.technology:
        box(.32,.16,.36,.68,fill);box(.36,.23,.28,.52,dark);circle(.5,.79,.018,line);
      case VisualCategory.media:
        if(id=='camera'){box(.2,.34,.6,.38,fill);circle(.5,.53,.16,dark);circle(.5,.53,.09,line);}
        else {box(.4,.2,.2,.42,fill);c.drawArc(ui.Rect.fromLTWH(s*.29,s*.34,s*.42,s*.43),0,math.pi,false,line);}
      case VisualCategory.money:
        circle(.5,.42,.23,fill);circle(.5,.42,.15,dark);circle(.5,.42,.07,fill);box(.25,.65,.5,.1,fill);
      case VisualCategory.business:
        box(.25,.3,.5,.43,fill);c.drawLine(ui.Offset(s*.25,s*.44),ui.Offset(s*.75,s*.44),line);
      case VisualCategory.travel:
        circle(.5,.5,.25,fill);c.drawCircle(center,s*.18,line);
      case VisualCategory.nature:
        final p=ui.Path()..moveTo(s*.5,s*.18)..quadraticBezierTo(s*.1,s*.42,s*.5,s*.68)..quadraticBezierTo(s*.9,s*.42,s*.5,s*.18)..close();c.drawPath(p,fill);c.drawLine(ui.Offset(s*.5,s*.5),ui.Offset(s*.5,s*.82),line);
      case VisualCategory.health:
        circle(.5,.5,.25,fill);box(.44,.29,.12,.42,dark);box(.29,.44,.42,.12,dark);
      case VisualCategory.food:
        circle(.5,.5,.25,fill);c.drawLine(ui.Offset(s*.5,s*.25),ui.Offset(s*.55,s*.17),line);
      case VisualCategory.architecture:
        final p=ui.Path()..moveTo(s*.18,s*.43)..lineTo(s*.5,s*.18)..lineTo(s*.82,s*.43)..lineTo(s*.78,s*.78)..lineTo(s*.22,s*.78)..close();c.drawPath(p,fill);box(.44,.54,.12,.24,dark);
      case VisualCategory.objects:
      case VisualCategory.abstract:
        circle(.5,.5,.25,fill);circle(.5,.5,.13,dark);circle(.5,.5,.05,line);
    }
    c.drawCircle(center,s*.34,ui.Paint()..color=color.withOpacity(.55)..style=ui.PaintingStyle.stroke..strokeWidth=s*.009);
    for(var i=0;i<3;i++){final t=(seed+i*2.1)*.7;c.drawCircle(ui.Offset(center.dx+math.cos(t)*s*.39,center.dy+math.sin(t)*s*.39),s*.012,ui.Paint()..color=const ui.Color(0xFFFFD27A));}
    final pic=rec.endRecording();final image=await pic.toImage(size,size);final data=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();pic.dispose();
    if(data==null)throw StateError('PNG encoding failed');return data.buffer.asUint8List();
  }
}
