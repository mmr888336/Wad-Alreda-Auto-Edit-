/// Semantic catalogue and original procedural visual assets for Wad Alreda.
///
/// Every asset has its own illustration (no shared category shapes): shaded
/// with gradients, a specular highlight, rim light and a soft floor shadow,
/// so it reads as a lit object instead of a flat icon. People and a few
/// other assets vary with the seed (skin tone, hair, colour tint), so the
/// same word does not always give the same picture.
///
/// Search understands Arabic and English: spelling variants are folded,
/// common Arabic prefixes and suffixes are stripped, short tags only match
/// whole words, and assets of the same category as other strong matches get
/// a small context bonus. [MotionVisualLibrary.searchDiverse] avoids two
/// neighbouring results of the same category.
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
class _Idx {
  final MotionVisualAsset asset;
  final List<String> tags;
  const _Idx(this.asset,this.tags);
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
    MotionVisualAsset('lightning',VisualCategory.abstract,['برق','صاعقة','سرعة','كهرباء','سريع','lightning','electric','speed','fast','thunder'],'Lightning bolt',0xFFFFD84D),
    MotionVisualAsset('rocket',VisualCategory.technology,['صاروخ','انطلاق','إطلاق','مشروع ناشئ','فضاء','rocket','launch','startup','space'],'Rocket',0xFFFF7A66),
    MotionVisualAsset('trophy',VisualCategory.abstract,['كأس','بطولة','مسابقة','بطل','جائزة','تتويج','trophy','champion','award','competition','prize'],'Trophy',0xFFFFC94D),
    MotionVisualAsset('gift',VisualCategory.objects,['هدية','مفاجأة','عيدية','هدايا','gift','present','surprise'],'Gift box',0xFFFF7BAA),
    MotionVisualAsset('megaphone',VisualCategory.media,['إعلان','اعلان','تسويق','حملة','ترويج','نشر','announcement','marketing','advertise','promotion','megaphone'],'Megaphone',0xFFFFA05E),
    MotionVisualAsset('chat',VisualCategory.media,['رسالة','محادثة','تواصل','حوار','دردشة','كلام','message','chat','conversation','talk','communication'],'Chat bubbles',0xFF7FD3FF),
    MotionVisualAsset('lock',VisualCategory.objects,['قفل','سرية','كلمة مرور','تشفير','lock','password','encrypt','secure'],'Padlock',0xFF8FB4FF),
    MotionVisualAsset('magnifier',VisualCategory.objects,['بحث','تحقق','فحص','تحليل','تحقيق','search','research','find','analysis','inspect','investigate'],'Magnifier',0xFF86D0FF),
    MotionVisualAsset('scales',VisualCategory.objects,['عدل','قانون','محكمة','قاضي','محاماة','ميزان','justice','law','court','legal','judge','balance'],'Scales of justice',0xFFFFD27A),
    MotionVisualAsset('calendar',VisualCategory.objects,['تاريخ','جدول','أسبوع','شهر','سنة','calendar','date','schedule','month','week','year'],'Calendar',0xFFFF8F8F),
    MotionVisualAsset('car',VisualCategory.travel,['سيارة','قيادة','طريق','مركبة','سباق','car','drive','driving','vehicle','road'],'Car',0xFFFF7E7E),
    MotionVisualAsset('music',VisualCategory.media,['موسيقى','أغنية','نغمة','غناء','لحن','إيقاع','music','song','melody','sing','rhythm','note'],'Music notes',0xFFC59BFF),
    MotionVisualAsset('sun',VisualCategory.nature,['شمس','نهار','صيف','ضوء','دفء','نور','sun','sunny','summer','daylight','light'],'Sun',0xFFFFC84D),
    MotionVisualAsset('moon_stars',VisualCategory.nature,['ليل','نجوم','نوم','ليلة','سهر','حلم','night','stars','sleep','moonlight','dream'],'Moon and stars',0xFFB9A8FF),
    MotionVisualAsset('cloud',VisualCategory.nature,['سحابة','غيوم','طقس','سماء','cloud','weather','sky','cloudy'],'Cloud',0xFFB5D4FF),
    MotionVisualAsset('mail',VisualCategory.business,['بريد','ايميل','إيميل','email','mail','inbox','newsletter'],'Envelope',0xFF7CB8FF),
    MotionVisualAsset('chart_bars',VisualCategory.business,['إحصائيات','احصائيات','نسبة','أرقام','تقرير','رسم بياني','statistics','report','analytics','numbers','percentage'],'Bar chart',0xFF7BE0B5),
    MotionVisualAsset('question',VisualCategory.abstract,['سؤال','استفهام','لغز','غموض','تساؤل','question','why','mystery','unknown','ask'],'Question mark',0xFFA79CFF),
    MotionVisualAsset('checkmark',VisualCategory.abstract,['صحيح','تأكيد','موافقة','done','correct','verified','approved','checkmark'],'Check mark',0xFF4CCB84),
  ];

  static String normalize(String value) {
    var s=value.toLowerCase().replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'),'');
    const map={'أ':'ا','إ':'ا','آ':'ا','ى':'ي','ة':'ه','ؤ':'و','ئ':'ي'};
    map.forEach((a,b){s=s.replaceAll(a,b);});
    return s.replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9\s]'),' ').replaceAll(RegExp(r'\s+'),' ').trim();
  }

  /// Light Arabic stemmer: strips a definite article / preposition prefix and
  /// a plural, possessive or feminine suffix (input is already normalised).
  static String stem(String w) {
    var s=w;
    for(final p in const <String>['وال','بال','كال','فال','لل','ال']){
      if(s.startsWith(p)&&s.length-p.length>=3){s=s.substring(p.length);break;}
    }
    for(final x in const <String>['ات','ون','ين','ها','هم','ه']){
      if(s.endsWith(x)&&s.length-x.length>=3){s=s.substring(0,s.length-x.length);break;}
    }
    return s;
  }

  static final List<_Idx> _idx=<_Idx>[for(final a in assets)_Idx(a,[for(final t in a.tags)normalize(t)])];
  static final Map<String,int> _df=_buildDf();
  static Map<String,int> _buildDf(){
    final m=<String,int>{};
    for(final e in _idx){for(final t in e.tags){m[t]=(m[t]??0)+1;}}
    return m;
  }

  static bool _isArabic(String t)=>RegExp('[\u0600-\u06FF]').hasMatch(t);
  static String _dropLead(String w)=>(w.length>3&&'وفبكل'.contains(w[0]))?w.substring(1):w;

  /// Does the normalised sentence [q] contain the normalised tag [t]? Long
  /// tags may match inside a word; short tags (3 letters or less) only match
  /// a whole word (or that word with a prefix or a short suffix), so 'ai'
  /// does not fire inside 'rain' and an Arabic 'حب' not inside 'صحبة'.
  static bool _has(String q,Set<String> words,String t) {
    if(t.contains(' '))return q.contains(t);
    if(t.length>3)return q.contains(t);
    final arabic=_isArabic(t);
    for(final w in words){
      if(w==t)return true;
      if(!arabic)continue;
      for(final f in <String>{w,stem(w),_dropLead(w),stem(_dropLead(w))}){
        if(f==t||(f.startsWith(t)&&f.length<=t.length+2))return true;
      }
    }
    return false;
  }

  static List<MotionVisualMatch> search(String sentence,{int limit=5}) {
    final q=normalize(sentence);
    if(q.isEmpty)return const <MotionVisualMatch>[];
    final words=q.split(' ').where((w)=>w.length>1).toList();
    final wordSet=words.toSet();
    final stems=<String>{for(final w in words)stem(w)};
    final raw=<MotionVisualMatch>[];
    for(final e in _idx){
      var score=0.0;
      for(final t in e.tags){
        var s=0.0;
        if(_has(q,wordSet,t)){
          s=t.contains(' ')?5.0:3.0;
        } else {
          final st=stem(t);
          if(st.length>=3&&stems.contains(st)){
            s=st.length>=4?3.0:2.4;
          } else if(st.length>=4){
            for(final w in stems){
              if(w.length>=4&&(w.startsWith(st)||st.startsWith(w))){s=.9;break;}
            }
          }
        }
        // Tags shared by many assets say less about the sentence.
        if(s>0)score+=s+.3/(_df[t]??1);
      }
      if(score>0)raw.add(MotionVisualMatch(e.asset,score));
    }
    // Context: assets whose category several other strong matches share get
    // a small bonus, so a coherent sentence keeps its theme.
    final strong=<VisualCategory,int>{};
    for(final m in raw){if(m.score>=3)strong[m.asset.category]=(strong[m.asset.category]??0)+1;}
    final results=<MotionVisualMatch>[
      for(final m in raw)
        MotionVisualMatch(m.asset,m.score+(m.score>=3?math.min(.75,.25*((strong[m.asset.category]??1)-1)):0.0)),
    ];
    results.sort((a,b)=>b.score.compareTo(a.score));
    return results.take(limit.clamp(1,20)).toList(growable:false);
  }

  /// Best matches for [sentence] where neighbouring results come from
  /// different categories whenever a nearly as good alternative exists, and
  /// ids in [avoidIds] (for example assets already shown) are left out.
  static List<MotionVisualMatch> searchDiverse(String sentence,{int limit=3,Set<String> avoidIds=const <String>{}}) {
    final pool=search(sentence,limit:20).where((m)=>!avoidIds.contains(m.asset.id)).toList();
    final out=<MotionVisualMatch>[];
    while(pool.isNotEmpty&&out.length<limit){
      var pick=pool.first;
      if(out.isNotEmpty){
        final last=out.last.asset.category;
        for(final m in pool){
          if(m.asset.category!=last&&m.score>=pool.first.score*.6){pick=m;break;}
        }
      }
      out.add(pick);
      pool.remove(pick);
    }
    return out;
  }

  static MotionVisualAsset? byId(String id) {
    for(final a in assets){if(a.id==id)return a;} return null;
  }

  static const List<int> _skins=<int>[0xFFF3CDA8,0xFFE0AC7E,0xFFB9825A,0xFF8A5A3A,0xFF5E3B26];
  static const List<int> _hairs=<int>[0xFF1B1B22,0xFF3A2416,0xFF6B4423,0xFF222831];
  static const List<int> _tints=<int>[0xFFFF8A5C,0xFF5CC8FF,0xFFB48CFF,0xFF7DE29B,0xFFFFD25C];

  /// Draws a lit, shaded, transparent illustration of asset [id]. [seed]
  /// varies skin tones, hair and the colour tint.
  static Future<Uint8List> renderPng(String id,{int size=512,int seed=0}) async {
    final asset=byId(id); if(asset==null)throw ArgumentError.value(id,'id');
    final rec=ui.PictureRecorder(); final c=ui.Canvas(rec);
    final s=size.toDouble();
    final base=ui.Color(asset.color);
    final col=seed.abs()%5==0?base:ui.Color.lerp(base,ui.Color(_tints[seed.abs()%_tints.length]),.22)!;
    const white=ui.Color(0xFFFFFFFF),ink=ui.Color(0xFF111A2B),paper=ui.Color(0xFFF3F6FF),gold=ui.Color(0xFFFFC94D),wood=ui.Color(0xFFB87942),steel=ui.Color(0xFFB8C2D6),green=ui.Color(0xFF4CCB84),red=ui.Color(0xFFFF5D6C),sky=ui.Color(0xFF69B6FF);
    final skin=ui.Color(_skins[seed.abs()%_skins.length]),hair=ui.Color(_hairs[(seed.abs()~/5)%_hairs.length]);

    ui.Color mix(ui.Color x,ui.Color y,double t)=>ui.Color.lerp(x,y,t)!;
    ui.Color lite(ui.Color x,double t)=>mix(x,white,t);
    ui.Color dim(ui.Color x,double t)=>mix(x,const ui.Color(0xFF000000),t);
    ui.Offset o(double x,double y)=>ui.Offset(s*x,s*y);
    ui.Rect rc(double x,double y,double w,double h)=>ui.Rect.fromLTWH(s*x,s*y,s*w,s*h);
    ui.Paint lin(ui.Rect r,ui.Color k,{double hi=.3,double lo=.36})=>ui.Paint()..shader=ui.Gradient.linear(r.topLeft,r.bottomRight,[lite(k,hi),k,dim(k,lo)],[0,.5,1]);
    ui.Paint fillP(ui.Color k)=>ui.Paint()..color=k;
    ui.Paint ln(double w,ui.Color k)=>ui.Paint()..color=k..style=ui.PaintingStyle.stroke..strokeWidth=s*w..strokeCap=ui.StrokeCap.round..strokeJoin=ui.StrokeJoin.round;
    void slab(double x,double y,double w,double h,ui.Color k,{double rad=.035}){
      final r=rc(x,y,w,h);final rr=ui.RRect.fromRectAndRadius(r,ui.Radius.circular(s*rad));
      c.drawRRect(rr,lin(r,k));
      c.drawRRect(rr.deflate(s*.004),ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.006..color=const ui.Color(0x44FFFFFF));
    }
    void ball(double x,double y,double r,ui.Color k){
      final ce=o(x,y);final rr=s*r;
      c.drawCircle(ce,rr,ui.Paint()..shader=ui.Gradient.radial(ce,rr,[lite(k,.55),k,dim(k,.45)],[0,.55,1],ui.TileMode.clamp,null,ce.translate(-rr*.35,-rr*.38),0));
    }
    void poly(ui.Path p,ui.Color k,{double hi=.3,double lo=.36})=>c.drawPath(p,lin(p.getBounds(),k,hi:hi,lo:lo));
    ui.Path pg(List<double> p){
      final path=ui.Path()..moveTo(s*p[0],s*p[1]);
      for(var i=2;i<p.length;i+=2){path.lineTo(s*p[i],s*p[i+1]);}
      return path..close();
    }
    void stroke(ui.Path p,ui.Color k,double w)=>c.drawPath(p,ln(w,k));
    void line(double x1,double y1,double x2,double y2,ui.Color k,double w)=>c.drawLine(o(x1,y1),o(x2,y2),ln(w,k));
    void floor(double x,double y,double rx,double ry)=>c.drawOval(rc(x-rx,y-ry,rx*2,ry*2),ui.Paint()..color=const ui.Color(0x66000000)..maskFilter=ui.MaskFilter.blur(ui.BlurStyle.normal,s*.02));
    void txt(String t,double x,double y,double fs,ui.Color k){
      final pb=ui.ParagraphBuilder(ui.ParagraphStyle(textAlign:ui.TextAlign.center,fontSize:s*fs,fontWeight:ui.FontWeight.w900))..pushStyle(ui.TextStyle(color:k,fontSize:s*fs,fontWeight:ui.FontWeight.w900))..addText(t);
      final p=pb.build()..layout(ui.ParagraphConstraints(width:s));
      c.drawParagraph(p,ui.Offset(s*x-s/2,s*y-p.height/2));
    }
    ui.Path star(double cx,double cy,double rO,double rI){
      final p=ui.Path();
      for(var i=0;i<10;i++){
        final a=-math.pi/2+i*math.pi/5,rad=i.isEven?rO:rI;
        final x=s*(cx+math.cos(a)*rad),y=s*(cy+math.sin(a)*rad);
        if(i==0){p.moveTo(x,y);}else{p.lineTo(x,y);}
      }
      return p..close();
    }
    void figure(double x,double y,double k,ui.Color body,ui.Color sk,ui.Color hr){
      final t=ui.Path()..moveTo(s*(x-.13*k),s*(y+.36*k))..quadraticBezierTo(s*(x-.13*k),s*(y+.12*k),s*x,s*(y+.10*k))..quadraticBezierTo(s*(x+.13*k),s*(y+.12*k),s*(x+.13*k),s*(y+.36*k))..close();
      poly(t,body);
      ball(x,y-.02*k,.075*k,sk);
      c.drawArc(rc(x-.075*k,y-.095*k,.15*k,.14*k),math.pi,math.pi,true,fillP(hr));
    }
    void coin(double x,double y,double r,ui.Color k){
      const th=.035;
      c.drawRect(rc(x-r,y,2*r,th),lin(rc(x-r,y,2*r,th),dim(k,.25)));
      c.drawOval(rc(x-r,y+th-r*.4,2*r,r*.8),fillP(dim(k,.4)));
      final top=rc(x-r,y-r*.4,2*r,r*.8);
      c.drawOval(top,lin(top,k,hi:.5));
      c.drawOval(rc(x-r*.72,y-r*.29,r*1.44,r*.58),ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.008..color=dim(k,.25));
    }
    ui.Path heart(){
      return ui.Path()..moveTo(s*.5,s*.80)..cubicTo(s*.08,s*.52,s*.16,s*.18,s*.38,s*.24)..cubicTo(s*.45,s*.26,s*.49,s*.31,s*.5,s*.35)..cubicTo(s*.51,s*.31,s*.55,s*.26,s*.62,s*.24)..cubicTo(s*.84,s*.18,s*.92,s*.52,s*.5,s*.80)..close();
    }
    ui.Path flame(){
      return ui.Path()..moveTo(s*.5,s*.12)..cubicTo(s*.62,s*.30,s*.82,s*.42,s*.78,s*.62)..cubicTo(s*.76,s*.78,s*.62,s*.86,s*.5,s*.86)..cubicTo(s*.38,s*.86,s*.24,s*.78,s*.22,s*.62)..cubicTo(s*.20,s*.48,s*.34,s*.42,s*.38,s*.28)..cubicTo(s*.42,s*.36,s*.46,s*.30,s*.5,s*.12)..close();
    }

    // Soft light behind the object and its shadow on the floor.
    c.drawCircle(o(.5,.5),s*.38,ui.Paint()..shader=ui.Gradient.radial(o(.5,.5),s*.38,[col.withOpacity(.28),col.withOpacity(0)]));
    floor(.5,.86,.26,.03);

    switch(id){
      case 'person':{
        poly(ui.Path()..moveTo(s*.22,s*.84)..quadraticBezierTo(s*.22,s*.56,s*.5,s*.54)..quadraticBezierTo(s*.78,s*.56,s*.78,s*.84)..close(),col);
        slab(.45,.44,.10,.12,dim(skin,.12),rad:.03);
        ball(.5,.33,.15,skin);
        c.drawArc(rc(.35,.17,.30,.27),math.pi,math.pi,true,fillP(hair));
        line(.42,.56,.5,.66,paper,.015);line(.58,.56,.5,.66,paper,.015);
      }
      case 'thinking_head':{
        poly(ui.Path()..moveTo(s*.14,s*.86)..quadraticBezierTo(s*.14,s*.62,s*.38,s*.60)..quadraticBezierTo(s*.62,s*.62,s*.62,s*.86)..close(),col);
        ball(.38,.44,.17,skin);
        c.drawArc(rc(.21,.26,.34,.30),math.pi,math.pi,true,fillP(hair));
        ball(.58,.38,.03,paper);ball(.64,.32,.045,paper);
        ball(.76,.24,.13,paper);ball(.76,.24,.06,col);
      }
      case 'crowd':{
        figure(.22,.40,.8,dim(col,.35),ui.Color(_skins[(seed.abs()+1)%5]),ink);
        figure(.78,.40,.8,dim(col,.28),ui.Color(_skins[(seed.abs()+3)%5]),ui.Color(_hairs[1]));
        figure(.5,.34,.95,lite(col,.05),ui.Color(_skins[(seed.abs()+2)%5]),ui.Color(_hairs[2]));
        figure(.32,.48,1.0,col,skin,hair);
        figure(.68,.48,1.0,mix(col,paper,.25),ui.Color(_skins[(seed.abs()+4)%5]),ink);
      }
      case 'heart':{
        poly(heart(),col,hi:.4);
        c.drawOval(rc(.24,.27,.15,.08),fillP(const ui.Color(0x66FFFFFF)));
      }
      case 'broken_heart':{
        poly(heart(),col,hi:.4);
        c.drawOval(rc(.24,.27,.15,.08),fillP(const ui.Color(0x55FFFFFF)));
        final crack=ui.Path()..moveTo(s*.5,s*.28)..lineTo(s*.44,s*.42)..lineTo(s*.56,s*.52)..lineTo(s*.45,s*.64)..lineTo(s*.54,s*.72)..lineTo(s*.5,s*.82);
        stroke(crack,ink,.034);stroke(crack,dim(col,.5),.016);
      }
      case 'hope':{
        c.save();c.clipRect(rc(0,0,1,.64));
        for(var i=0;i<9;i++){final t=math.pi+i*math.pi/8;line(.5+math.cos(t)*.25,.64+math.sin(t)*.25,.5+math.cos(t)*.38,.64+math.sin(t)*.38,lite(col,.3),.018);}
        ball(.5,.64,.2,col);
        c.restore();
        slab(.10,.64,.80,.05,dim(col,.55),rad:.02);
        poly(ui.Path()..moveTo(s*.10,s*.86)..quadraticBezierTo(s*.30,s*.66,s*.52,s*.82)..quadraticBezierTo(s*.72,s*.70,s*.90,s*.86)..close(),dim(col,.65));
      }
      case 'book':{
        slab(.10,.27,.80,.52,dim(col,.4),rad:.04);
        poly(ui.Path()..moveTo(s*.5,s*.30)..cubicTo(s*.38,s*.24,s*.22,s*.25,s*.14,s*.30)..lineTo(s*.14,s*.74)..cubicTo(s*.24,s*.70,s*.40,s*.70,s*.5,s*.78)..close(),paper,hi:.1,lo:.18);
        poly(ui.Path()..moveTo(s*.5,s*.30)..cubicTo(s*.62,s*.24,s*.78,s*.25,s*.86,s*.30)..lineTo(s*.86,s*.74)..cubicTo(s*.76,s*.70,s*.60,s*.70,s*.5,s*.78)..close(),paper,hi:.1,lo:.22);
        for(var i=0;i<4;i++){line(.20,.39+i*.07,.43,.39+i*.07,dim(steel,.1),.01);line(.57,.39+i*.07,.80,.39+i*.07,dim(steel,.1),.01);}
        line(.5,.30,.5,.78,dim(col,.5),.012);
      }
      case 'graduation':{
        poly(pg([.28,.50,.5,.60,.72,.50,.72,.66,.5,.76,.28,.66]),dim(col,.45));
        poly(pg([.5,.22,.92,.40,.5,.58,.08,.40]),mix(ink,col,.25),hi:.45);
        line(.86,.42,.86,.64,gold,.012);ball(.86,.66,.026,gold);
        ball(.5,.40,.02,gold);
      }
      case 'bulb':{
        c.drawCircle(o(.5,.40),s*.30,ui.Paint()..shader=ui.Gradient.radial(o(.5,.40),s*.30,[col.withOpacity(.45),col.withOpacity(0)]));
        for(var i=0;i<7;i++){final t=math.pi*(1.15+i*.12);line(.5+math.cos(t)*.27,.40+math.sin(t)*.27,.5+math.cos(t)*.34,.40+math.sin(t)*.34,lite(col,.3),.016);}
        ball(.5,.42,.22,mix(col,white,.25));
        stroke(ui.Path()..moveTo(s*.44,s*.60)..lineTo(s*.46,s*.44)..lineTo(s*.5,s*.50)..lineTo(s*.54,s*.44)..lineTo(s*.56,s*.60),dim(col,.55),.012);
        slab(.40,.62,.20,.05,steel);slab(.42,.67,.16,.05,dim(steel,.25));slab(.45,.72,.10,.04,dim(steel,.45));
      }
      case 'mosque':{
        slab(.10,.30,.07,.52,dim(col,.1),rad:.01);slab(.83,.30,.07,.52,dim(col,.1),rad:.01);
        poly(pg([.10,.30,.135,.20,.17,.30]),gold);poly(pg([.83,.30,.865,.20,.90,.30]),gold);
        slab(.20,.52,.60,.30,col,rad:.02);
        poly(ui.Path()..moveTo(s*.28,s*.52)..cubicTo(s*.28,s*.20,s*.72,s*.20,s*.72,s*.52)..close(),lite(col,.08));
        line(.5,.27,.5,.15,gold,.012);ball(.5,.14,.022,gold);
        poly(ui.Path()..moveTo(s*.44,s*.82)..lineTo(s*.44,s*.66)..quadraticBezierTo(s*.5,s*.56,s*.56,s*.66)..lineTo(s*.56,s*.82)..close(),ink);
        ball(.30,.64,.02,gold);ball(.70,.64,.02,gold);
      }
      case 'crescent':{
        final cres=ui.Path.combine(ui.PathOperation.difference,ui.Path()..addOval(rc(.20,.20,.52,.52)),ui.Path()..addOval(rc(.36,.14,.48,.48)));
        poly(cres,col,hi:.4);
        poly(star(.72,.64,.08,.034),gold);
      }
      case 'prayer_beads':{
        for(var i=0;i<24;i++){final t=i*math.pi*2/24+math.pi/2;ball(.5+math.cos(t)*.26,.46+math.sin(t)*.26,i%6==0?.04:.032,i%6==0?gold:mix(col,paper,i.isEven?.0:.2));}
        ball(.5,.76,.045,gold);line(.5,.79,.5,.88,gold,.014);ball(.5,.90,.022,gold);
      }
      case 'briefcase':{
        stroke(ui.Path()..moveTo(s*.38,s*.38)..lineTo(s*.38,s*.30)..lineTo(s*.62,s*.30)..lineTo(s*.62,s*.38),dim(col,.4),.03);
        slab(.16,.38,.68,.42,col,rad:.04);
        line(.16,.56,.84,.56,dim(col,.45),.012);
        slab(.45,.52,.10,.09,gold,rad:.012);
      }
      case 'store':{
        for(var i=0;i<6;i++){final x=.14+i*.12;poly(pg([x,.30,x+.12,.30,x+.13,.44,x-.01,.44]),i.isEven?col:paper,hi:.2,lo:.25);}
        slab(.18,.44,.64,.38,mix(col,paper,.55),rad:.01);
        slab(.24,.52,.26,.18,sky,rad:.012);slab(.58,.52,.16,.30,dim(col,.3),rad:.012);
        ball(.70,.68,.014,gold);
      }
      case 'handshake':{
        poly(pg([.06,.40,.30,.34,.46,.46,.40,.66,.12,.62]),mix(ink,col,.4));
        poly(pg([.94,.40,.70,.34,.54,.46,.60,.66,.88,.62]),col);
        ball(.45,.52,.12,ui.Color(_skins[(seed.abs()+1)%5]));ball(.56,.52,.12,skin);
        for(var i=0;i<4;i++){line(.43+i*.045,.50,.45+i*.045,.60,dim(skin,.25),.01);}
      }
      case 'coins':{
        coin(.36,.74,.18,col);coin(.36,.69,.18,col);coin(.36,.64,.18,col);
        coin(.62,.78,.17,col);coin(.62,.73,.17,col);
        ball(.68,.36,.15,col);
        c.drawCircle(o(.68,.36),s*.10,ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.012..color=dim(col,.35));
        txt('\$',.68,.36,.14,dim(col,.5));
      }
      case 'wallet':{
        slab(.26,.26,.44,.14,sky,rad:.02);
        slab(.14,.34,.72,.46,col,rad:.05);
        slab(.58,.52,.28,.16,dim(col,.25),rad:.04);ball(.68,.60,.03,gold);
        line(.14,.46,.58,.46,dim(col,.4),.01);
      }
      case 'growth':{
        for(var i=0;i<5;i++){final h=.14+i*.1;slab(.16+i*.14,.80-h,.10,h,i==4?green:mix(col,paper,.2),rad:.015);}
        stroke(ui.Path()..moveTo(s*.16,s*.60)..lineTo(s*.38,s*.46)..lineTo(s*.52,s*.54)..lineTo(s*.80,s*.26),paper,.028);
        poly(pg([.88,.20,.72,.24,.84,.36]),paper);
      }
      case 'phone':{
        slab(.32,.14,.36,.72,ink,rad:.06);
        slab(.35,.19,.30,.60,col,rad:.03);
        slab(.45,.20,.10,.02,ink,rad:.01);
        for(var i=0;i<4;i++){slab(.38+(i%2)*.14,.30+(i~/2)*.13,.09,.09,paper,rad:.02);}
        line(.44,.74,.56,.74,paper,.01);
      }
      case 'laptop':{
        slab(.18,.26,.64,.42,ink,rad:.03);
        slab(.21,.29,.58,.36,col,rad:.015);
        for(var i=0;i<4;i++){line(.26,.35+i*.065,.26+(i.isEven?.30:.20),.35+i*.065,paper,.012);}
        poly(pg([.10,.70,.90,.70,.96,.78,.04,.78]),steel);
        line(.44,.74,.56,.74,dim(steel,.3),.01);
      }
      case 'chip':{
        for(var i=0;i<5;i++){final p=.34+i*.075;slab(p,.18,.03,.10,steel,rad:.008);slab(p,.72,.03,.10,steel,rad:.008);slab(.18,p,.10,.03,steel,rad:.008);slab(.72,p,.10,.03,steel,rad:.008);}
        slab(.26,.26,.48,.48,mix(ink,col,.2),rad:.04);
        slab(.34,.34,.32,.32,col,rad:.02);
        txt('AI',.5,.50,.13,paper);
      }
      case 'camera':{
        slab(.30,.28,.22,.10,mix(ink,steel,.25),rad:.02);
        slab(.14,.36,.72,.42,mix(ink,steel,.25),rad:.04);
        slab(.70,.40,.10,.06,paper,rad:.01);
        ball(.5,.57,.17,steel);ball(.5,.57,.125,ink);ball(.5,.57,.075,col);ball(.46,.53,.02,white);
      }
      case 'microphone':{
        stroke(ui.Path()..addArc(rc(.30,.34,.40,.36),0,math.pi),col,.026);
        line(.5,.70,.5,.80,col,.024);slab(.38,.80,.24,.04,dim(col,.3),rad:.015);
        slab(.38,.16,.24,.40,steel,rad:.12);
        for(var i=0;i<5;i++){line(.40,.24+i*.055,.60,.24+i*.055,dim(steel,.3),.006);}
      }
      case 'clapper':{
        slab(.16,.42,.68,.40,ink,rad:.03);
        poly(pg([.14,.28,.86,.22,.88,.38,.16,.44]),paper);
        for(var i=0;i<5;i++){final x=.18+i*.14;poly(pg([x,.285,x+.07,.28,x+.09,.40,x+.02,.41]),col);}
        ball(.20,.43,.02,steel);
        line(.24,.58,.76,.58,const ui.Color(0x55FFFFFF),.01);line(.24,.68,.62,.68,const ui.Color(0x55FFFFFF),.01);
      }
      case 'airplane':{
        line(.10,.80,.34,.64,const ui.Color(0x55FFFFFF),.012);line(.04,.70,.24,.56,const ui.Color(0x33FFFFFF),.01);
        c.save();c.translate(s*.54,s*.46);c.rotate(-.5);
        poly(ui.Path()..moveTo(-s*.05,-s*.01)..lineTo(-s*.22,-s*.32)..lineTo(-s*.12,-s*.32)..lineTo(s*.14,-s*.01)..close(),col);
        poly(ui.Path()..moveTo(-s*.05,s*.01)..lineTo(-s*.22,s*.32)..lineTo(-s*.12,s*.32)..lineTo(s*.14,s*.01)..close(),dim(col,.2));
        poly(ui.Path()..moveTo(-s*.30,-s*.01)..lineTo(-s*.38,-s*.15)..lineTo(-s*.31,-s*.15)..lineTo(-s*.20,-s*.01)..close(),col);
        final fus=ui.Rect.fromLTWH(-s*.38,-s*.055,s*.76,s*.11);
        c.drawRRect(ui.RRect.fromRectAndRadius(fus,ui.Radius.circular(s*.055)),lin(fus,paper,hi:.1,lo:.2));
        for(var i=0;i<6;i++){ball(-.24+i*.06,-.005,.011,sky);}
        c.restore();
      }
      case 'mountain':{
        ball(.24,.22,.06,gold);
        poly(pg([.04,.80,.34,.30,.64,.80]),col);
        poly(pg([.27,.42,.34,.30,.41,.42,.37,.46,.34,.43,.30,.47]),paper);
        poly(pg([.34,.80,.66,.22,.98,.80]),dim(col,.15));
        poly(pg([.66,.22,.98,.80,.70,.80]),dim(col,.42));
        poly(pg([.58,.36,.66,.22,.74,.36,.70,.40,.66,.37,.61,.41]),paper);
      }
      case 'globe':{
        ball(.5,.5,.30,mix(col,sky,.4));
        c.save();c.clipPath(ui.Path()..addOval(rc(.20,.20,.60,.60)));
        poly(pg([.28,.32,.46,.28,.52,.40,.42,.52,.30,.46]),green);poly(pg([.56,.50,.74,.46,.78,.62,.62,.76,.54,.62]),green);
        c.restore();
        final grid=ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.006..color=const ui.Color(0x55FFFFFF);
        c.drawOval(rc(.35,.20,.30,.60),grid);c.drawOval(rc(.43,.20,.14,.60),grid);c.drawLine(o(.2,.5),o(.8,.5),grid);
        c.drawCircle(o(.5,.5),s*.31,ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.012..color=lite(col,.5).withOpacity(.6));
      }
      case 'tree':{
        slab(.45,.52,.10,.32,wood,rad:.02);
        ball(.34,.46,.15,mix(col,green,.4));ball(.66,.46,.15,dim(col,.15));ball(.5,.32,.20,col);
      }
      case 'water':{
        poly(ui.Path()..moveTo(s*.5,s*.12)..cubicTo(s*.5,s*.12,s*.22,s*.44,s*.22,s*.58)..cubicTo(s*.22,s*.76,s*.36,s*.82,s*.5,s*.82)..cubicTo(s*.64,s*.82,s*.78,s*.76,s*.78,s*.58)..cubicTo(s*.78,s*.44,s*.5,s*.12,s*.5,s*.12)..close(),col,hi:.4);
        c.drawOval(rc(.32,.46,.10,.20),fillP(const ui.Color(0x66FFFFFF)));
        final rip=ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.01..color=lite(col,.4).withOpacity(.7);
        c.drawOval(rc(.24,.82,.52,.07),rip);c.drawOval(rc(.14,.80,.72,.11),rip..color=lite(col,.4).withOpacity(.35));
      }
      case 'flower':{
        line(.5,.44,.5,.84,dim(green,.2),.025);
        poly(ui.Path()..moveTo(s*.5,s*.72)..quadraticBezierTo(s*.72,s*.60,s*.70,s*.74)..quadraticBezierTo(s*.60,s*.80,s*.5,s*.72)..close(),green);
        for(var i=0;i<6;i++){
          c.save();c.translate(s*.5,s*.40);c.rotate(i*math.pi/3);
          final r=ui.Rect.fromLTWH(-s*.065,-s*.23,s*.13,s*.23);c.drawOval(r,lin(r,col,hi:.4));
          c.restore();
        }
        ball(.5,.40,.07,gold);
      }
      case 'medical':{
        slab(.20,.20,.60,.60,paper,rad:.12);
        slab(.44,.30,.12,.40,col,rad:.02);slab(.30,.44,.40,.12,col,rad:.02);
      }
      case 'brain':{
        ball(.40,.46,.22,col);ball(.60,.46,.22,lite(col,.12));
        slab(.46,.62,.08,.20,dim(col,.3),rad:.03);
        line(.5,.26,.5,.66,dim(col,.4),.012);
        stroke(ui.Path()..moveTo(s*.28,s*.40)..quadraticBezierTo(s*.36,s*.30,s*.42,s*.40)..moveTo(s*.30,s*.54)..quadraticBezierTo(s*.38,s*.46,s*.44,s*.56)..moveTo(s*.58,s*.38)..quadraticBezierTo(s*.66,s*.30,s*.72,s*.40)..moveTo(s*.58,s*.54)..quadraticBezierTo(s*.66,s*.46,s*.72,s*.56),dim(col,.35),.014);
      }
      case 'apple':{
        ball(.40,.56,.21,col);ball(.60,.56,.21,col);ball(.5,.62,.2,col);
        c.drawOval(rc(.30,.42,.10,.16),fillP(const ui.Color(0x66FFFFFF)));
        line(.5,.34,.52,.22,wood,.02);
        poly(pg([.53,.30,.66,.18,.74,.26,.60,.34]),green);
      }
      case 'coffee':{
        c.drawOval(rc(.16,.74,.68,.09),lin(rc(.16,.74,.68,.09),steel,hi:.2,lo:.3));
        c.drawArc(rc(.66,.46,.20,.24),-math.pi/2,math.pi,false,ln(.03,paper));
        poly(ui.Path()..moveTo(s*.26,s*.42)..lineTo(s*.74,s*.42)..cubicTo(s*.74,s*.66,s*.64,s*.78,s*.5,s*.78)..cubicTo(s*.36,s*.78,s*.26,s*.66,s*.26,s*.42)..close(),paper,hi:.1,lo:.22);
        c.drawOval(rc(.26,.385,.48,.08),fillP(col));
        for(var i=0;i<3;i++){final x=.38+i*.12;stroke(ui.Path()..moveTo(s*x,s*.32)..cubicTo(s*(x-.04),s*.26,s*(x+.04),s*.22,s*x,s*.14),const ui.Color(0x66FFFFFF),.016);}
      }
      case 'house':{
        slab(.66,.22,.06,.16,dim(col,.3),rad:.005);
        slab(.22,.46,.56,.36,mix(col,paper,.6),rad:.01);
        poly(pg([.12,.46,.5,.16,.88,.46]),dim(col,.2));
        slab(.44,.60,.12,.22,wood,rad:.01);slab(.28,.54,.12,.12,gold,rad:.01);slab(.60,.54,.12,.12,gold,rad:.01);
      }
      case 'door':{
        c.drawPath(pg([.34,.84,.66,.84,.82,.94,.18,.94]),fillP(gold.withOpacity(.22)));
        slab(.26,.14,.48,.70,ink,rad:.02);
        slab(.30,.18,.40,.62,col,rad:.015);
        slab(.34,.24,.32,.18,dim(col,.18),rad:.01);slab(.34,.48,.32,.26,dim(col,.18),rad:.01);
        ball(.62,.52,.024,gold);
      }
      case 'key':{
        c.save();c.translate(s*.5,s*.5);c.rotate(-.7);c.translate(-s*.5,-s*.5);
        slab(.40,.375,.44,.05,col,rad:.02);slab(.68,.425,.04,.10,col,rad:.008);slab(.76,.425,.04,.07,col,rad:.008);
        c.drawCircle(o(.30,.40),s*.105,ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.065..shader=ui.Gradient.linear(o(.2,.3),o(.4,.5),[lite(col,.4),col,dim(col,.4)],[0,.5,1]));
        c.restore();
      }
      case 'clock':{
        ball(.5,.5,.30,paper);
        c.drawCircle(o(.5,.5),s*.285,ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.05..shader=ui.Gradient.linear(o(.2,.2),o(.8,.8),[lite(col,.4),col,dim(col,.4)],[0,.5,1]));
        for(var i=0;i<12;i++){final t=i*math.pi/6;line(.5+math.cos(t)*.22,.5+math.sin(t)*.22,.5+math.cos(t)*.25,.5+math.sin(t)*.25,ink,.01);}
        final ha=(seed.abs()%12)*math.pi/6-math.pi/2;
        line(.5,.5,.5+math.cos(ha)*.12,.5+math.sin(ha)*.12,ink,.026);
        line(.5,.5,.5+math.cos(ha+2.4)*.19,.5+math.sin(ha+2.4)*.19,ink,.018);
        ball(.5,.5,.022,red);
      }
      case 'shield':{
        final sh=ui.Path()..moveTo(s*.5,s*.14)..cubicTo(s*.62,s*.22,s*.76,s*.24,s*.82,s*.24)..lineTo(s*.82,s*.50)..cubicTo(s*.82,s*.68,s*.66,s*.78,s*.5,s*.86)..cubicTo(s*.34,s*.78,s*.18,s*.68,s*.18,s*.50)..lineTo(s*.18,s*.24)..cubicTo(s*.24,s*.24,s*.38,s*.22,s*.5,s*.14)..close();
        poly(sh,dim(col,.25));
        c.save();c.translate(s*.5,s*.52);c.scale(.82);c.translate(-s*.5,-s*.52);poly(sh,col,hi:.35);c.restore();
        stroke(ui.Path()..moveTo(s*.36,s*.50)..lineTo(s*.46,s*.60)..lineTo(s*.66,s*.38),paper,.045);
      }
      case 'warning':{
        final tri=pg([.5,.18,.86,.78,.14,.78]);
        c.drawPath(tri,ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.07..strokeJoin=ui.StrokeJoin.round..color=dim(col,.15));
        poly(tri,col,hi:.4);
        line(.5,.40,.5,.60,ink,.06);ball(.5,.70,.036,ink);
      }
      case 'star':{
        c.drawPath(star(.5,.52,.36,.16),ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.04..strokeJoin=ui.StrokeJoin.round..color=dim(col,.15));
        poly(star(.5,.52,.36,.16),col,hi:.45);
        c.drawOval(rc(.40,.30,.08,.05),fillP(const ui.Color(0x66FFFFFF)));
      }
      case 'target':{
        ball(.5,.5,.32,red);ball(.5,.5,.24,paper);ball(.5,.5,.17,red);ball(.5,.5,.10,paper);ball(.5,.5,.04,red);
        line(.52,.48,.86,.14,wood,.02);poly(pg([.86,.14,.95,.12,.90,.22]),paper);poly(pg([.80,.20,.88,.14,.86,.22]),dim(paper,.2));
      }
      case 'fire':{
        c.drawPath(flame(),ui.Paint()..shader=ui.Gradient.linear(o(.5,.12),o(.5,.86),[lite(col,.3),col,red]));
        c.save();c.translate(s*.5,s*.86);c.scale(.55);c.translate(-s*.5,-s*.86);
        c.drawPath(flame(),ui.Paint()..shader=ui.Gradient.linear(o(.5,.12),o(.5,.86),[const ui.Color(0xFFFFF2A8),gold,col]));
        c.restore();
      }
      case 'lightning':{
        final bolt=pg([.58,.10,.28,.54,.46,.54,.38,.90,.74,.42,.54,.42,.66,.10]);
        c.drawPath(bolt,ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.03..strokeJoin=ui.StrokeJoin.round..color=lite(col,.5));
        poly(bolt,col,hi:.4);
      }
      case 'rocket':{
        c.save();c.translate(s*.5,s*.5);c.rotate(.785);
        poly(ui.Path()..moveTo(-s*.07,s*.22)..lineTo(0,s*.46)..lineTo(s*.07,s*.22)..close(),gold);
        poly(ui.Path()..moveTo(-s*.10,s*.08)..lineTo(-s*.24,s*.26)..lineTo(-s*.09,s*.22)..close(),col);
        poly(ui.Path()..moveTo(s*.10,s*.08)..lineTo(s*.24,s*.26)..lineTo(s*.09,s*.22)..close(),col);
        poly(ui.Path()..moveTo(0,-s*.34)..cubicTo(s*.15,-s*.20,s*.15,s*.12,s*.09,s*.24)..lineTo(-s*.09,s*.24)..cubicTo(-s*.15,s*.12,-s*.15,-s*.20,0,-s*.34)..close(),paper,hi:.1,lo:.25);
        poly(ui.Path()..moveTo(0,-s*.34)..cubicTo(s*.08,-s*.27,s*.12,-s*.20,s*.13,-s*.14)..lineTo(-s*.13,-s*.14)..cubicTo(-s*.12,-s*.20,-s*.08,-s*.27,0,-s*.34)..close(),col);
        ball(0,-.02,.06,sky);
        c.restore();
      }
      case 'trophy':{
        c.drawArc(rc(.14,.22,.22,.24),math.pi/2,math.pi,false,ln(.032,dim(col,.25)));
        c.drawArc(rc(.64,.22,.22,.24),-math.pi/2,math.pi,false,ln(.032,dim(col,.25)));
        poly(ui.Path()..moveTo(s*.30,s*.20)..lineTo(s*.70,s*.20)..cubicTo(s*.70,s*.46,s*.62,s*.58,s*.5,s*.60)..cubicTo(s*.38,s*.58,s*.30,s*.46,s*.30,s*.20)..close(),col,hi:.4);
        slab(.46,.60,.08,.12,dim(col,.2),rad:.01);slab(.34,.72,.32,.07,wood,rad:.015);
        poly(star(.5,.34,.075,.032),const ui.Color(0xAAFFFFFF));
      }
      case 'gift':{
        slab(.20,.44,.60,.38,col,rad:.02);slab(.16,.34,.68,.12,lite(col,.15),rad:.02);
        slab(.46,.34,.08,.48,gold,rad:.01);
        c.drawOval(rc(.30,.20,.20,.15),lin(rc(.30,.20,.20,.15),gold));c.drawOval(rc(.50,.20,.20,.15),lin(rc(.50,.20,.20,.15),gold));
        ball(.5,.30,.04,dim(gold,.2));
      }
      case 'megaphone':{
        poly(pg([.22,.40,.60,.22,.60,.72,.22,.58]),col);
        c.drawOval(rc(.56,.20,.09,.54),lin(rc(.56,.20,.09,.54),lite(col,.2)));
        slab(.28,.58,.10,.22,dim(col,.3),rad:.02);
        c.drawArc(rc(.68,.32,.14,.30),-1.0,2.0,false,ln(.02,const ui.Color(0xAAFFFFFF)));c.drawArc(rc(.74,.24,.18,.46),-1.0,2.0,false,ln(.02,const ui.Color(0x66FFFFFF)));
      }
      case 'chat':{
        slab(.14,.20,.52,.34,col,rad:.08);poly(pg([.26,.54,.24,.68,.40,.54]),col);
        slab(.34,.42,.52,.34,mix(col,paper,.7),rad:.08);poly(pg([.74,.76,.78,.88,.62,.76]),mix(col,paper,.7));
        for(var i=0;i<3;i++){ball(.46+i*.12,.59,.024,col);}
        for(var i=0;i<3;i++){line(.24,.30+i*.06,.24+(i==2?.14:.28),.30+i*.06,paper,.012);}
      }
      case 'lock':{
        stroke(ui.Path()..moveTo(s*.36,s*.46)..lineTo(s*.36,s*.34)..cubicTo(s*.36,s*.12,s*.64,s*.12,s*.64,s*.34)..lineTo(s*.64,s*.46),steel,.05);
        slab(.26,.44,.48,.38,col,rad:.05);
        ball(.5,.60,.04,ink);line(.5,.62,.5,.71,ink,.03);
      }
      case 'magnifier':{
        line(.66,.66,.86,.86,dim(col,.4),.075);
        c.drawCircle(o(.44,.44),s*.21,fillP(sky.withOpacity(.25)));
        c.drawCircle(o(.44,.44),s*.22,ui.Paint()..style=ui.PaintingStyle.stroke..strokeWidth=s*.06..shader=ui.Gradient.linear(o(.24,.24),o(.64,.64),[lite(col,.4),col,dim(col,.4)],[0,.5,1]));
        c.drawArc(rc(.30,.30,.26,.26),3.4,1.0,false,ln(.02,const ui.Color(0xAAFFFFFF)));
      }
      case 'scales':{
        line(.5,.2,.5,.8,steel,.03);slab(.34,.80,.32,.04,dim(steel,.3),rad:.015);
        line(.2,.28,.8,.28,col,.03);ball(.5,.18,.032,col);
        for(final x in const <double>[.2,.8]){line(x,.28,x-.08,.52,steel,.01);line(x,.28,x+.08,.52,steel,.01);}
        c.drawArc(rc(.10,.46,.20,.14),0,math.pi,true,lin(rc(.10,.46,.20,.14),col));c.drawArc(rc(.70,.46,.20,.14),0,math.pi,true,lin(rc(.70,.46,.20,.14),col));
      }
      case 'calendar':{
        slab(.18,.22,.64,.58,paper,rad:.05);
        slab(.18,.22,.64,.16,col,rad:.05);slab(.18,.30,.64,.08,col,rad:.0);
        slab(.30,.16,.04,.12,steel,rad:.01);slab(.66,.16,.04,.12,steel,rad:.01);
        for(var r=0;r<3;r++){for(var k=0;k<4;k++){slab(.26+k*.14,.46+r*.1,.08,.06,(r==1&&k==2)?col:mix(steel,paper,.3),rad:.01);}}
      }
      case 'car':{
        poly(pg([.08,.64,.08,.52,.26,.46,.34,.34,.64,.34,.74,.46,.92,.50,.92,.64]),col);
        poly(pg([.34,.46,.38,.38,.50,.38,.50,.46]),sky);poly(pg([.54,.46,.54,.38,.64,.38,.70,.46]),sky);
        ball(.28,.66,.09,ink);ball(.28,.66,.045,steel);ball(.72,.66,.09,ink);ball(.72,.66,.045,steel);
        ball(.90,.54,.02,gold);
      }
      case 'music':{
        poly(pg([.52,.26,.72,.20,.72,.30,.52,.36]),dim(col,.2));
        line(.52,.70,.52,.26,col,.035);line(.72,.62,.72,.20,col,.035);
        ball(.44,.70,.10,col);ball(.64,.62,.10,col);
      }
      case 'sun':{
        c.drawCircle(o(.5,.5),s*.42,ui.Paint()..shader=ui.Gradient.radial(o(.5,.5),s*.42,[col.withOpacity(.4),col.withOpacity(0)]));
        for(var i=0;i<12;i++){final t=i*math.pi/6;line(.5+math.cos(t)*.27,.5+math.sin(t)*.27,.5+math.cos(t)*.37,.5+math.sin(t)*.37,lite(col,.2),.026);}
        ball(.5,.5,.2,col);
      }
      case 'moon_stars':{
        final cres=ui.Path.combine(ui.PathOperation.difference,ui.Path()..addOval(rc(.18,.18,.56,.56)),ui.Path()..addOval(rc(.34,.12,.52,.52)));
        poly(cres,col,hi:.4);
        poly(star(.72,.30,.06,.025),gold);poly(star(.30,.76,.045,.018),gold);poly(star(.80,.62,.035,.014),gold);
      }
      case 'cloud':{
        final cc=mix(col,paper,.5);
        slab(.22,.52,.56,.16,cc,rad:.08);ball(.36,.54,.13,cc);ball(.54,.44,.17,lite(cc,.1));ball(.68,.54,.12,cc);
      }
      case 'mail':{
        slab(.16,.28,.68,.46,paper,rad:.04);
        stroke(ui.Path()..moveTo(s*.16,s*.32)..lineTo(s*.5,s*.56)..lineTo(s*.84,s*.32),dim(col,.2),.02);
        ball(.80,.30,.07,red);txt('1',.80,.30,.08,white);
      }
      case 'chart_bars':{
        line(.2,.22,.2,.80,const ui.Color(0x88FFFFFF),.015);line(.2,.80,.84,.80,const ui.Color(0x88FFFFFF),.015);
        const hs=<double>[.22,.34,.26,.44];
        for(var i=0;i<4;i++){slab(.28+i*.14,.80-hs[i],.10,hs[i],i==3?green:mix(col,paper,i.isEven?.0:.2),rad:.012);}
      }
      case 'question':{
        ball(.5,.5,.30,col);txt('?',.5,.50,.44,paper);
      }
      case 'checkmark':{
        ball(.5,.5,.30,col);
        stroke(ui.Path()..moveTo(s*.34,s*.52)..lineTo(s*.45,s*.63)..lineTo(s*.68,s*.38),paper,.06);
      }
      default:
        ball(.5,.5,.26,col);
    }

    for(var i=0;i<3;i++){final t=(seed+i*2.1)*.7;c.drawCircle(o(.5+math.cos(t)*.39,.5+math.sin(t)*.39),s*.012,ui.Paint()..color=const ui.Color(0xFFFFD27A));}
    final pic=rec.endRecording();final image=await pic.toImage(size,size);final data=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();pic.dispose();
    if(data==null)throw StateError('PNG encoding failed');return data.buffer.asUint8List();
  }
}
