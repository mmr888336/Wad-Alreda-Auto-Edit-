import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'ai_router.dart';
import 'settings.dart';
import 'silence_cutter.dart';

class Caption {
  final double start;
  double end;
  final String text;
  Caption(this.start, this.end, this.text);
}

class BrollIdea {
  final double start;
  final double end;
  final String query;
  BrollIdea(this.start, this.end, this.query);
}

class Analysis {
  final List<Caption> captions;
  final String title;
  final String description;
  final List<String> hashtags;
  final List<BrollIdea> broll;
  final List<String> notes;
  Analysis(this.captions, this.title, this.description, this.hashtags, this.broll,
      [this.notes = const []]);
}

/// تحليل الفيديو بالذكاء الاصطناعي:
/// 1) الصوت يتقسم لمقاطع (حوالي 45 ثانية) ويتحول لنص مقطع بمقطع. لو مزود وقف في النص، المقطع نفسه
///    يروح للمزود اللي بعده ونكمل بدون ما نعيد المقاطع اللي خلصت.
/// 2) من النص الكامل نطلع العنوان والوصف والهاشتاقات وأفكار B-roll.
class Analyzer {
  static const double _chunkTarget = 45;
  static const double _chunkMax = 90;

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

  static Map<String, dynamic> _json(String text) {
    final a = text.indexOf('{');
    final b = text.lastIndexOf('}');
    if (a < 0 || b <= a) {
      throw AiFailure('رد', null, 'رد غير مفهوم من الذكاء الاصطناعي', false);
    }
    try {
      return jsonDecode(text.substring(a, b + 1)) as Map<String, dynamic>;
    } catch (_) {
      throw AiFailure('رد', null, 'JSON غير صالح', false);
    }
  }

  /// يقسم المدة لمقاطع عند نقاط القص الطبيعية (breaks) قدر الإمكان.
  static List<List<double>> _chunks(double dur, List<double> breaks) {
    final res = <List<double>>[];
    var st = 0.0;
    final pts = breaks.where((b) => b > 0 && b < dur).toList()..sort();
    for (final b in pts) {
      if (b - st >= _chunkTarget) {
        res.add([st, b]);
        st = b;
      }
    }
    if (dur - st < 8 && res.isNotEmpty) {
      res.last[1] = dur;
    } else {
      res.add([st, dur]);
    }
    // أي مقطع أطول من الحد بدون نقاط قص: نقسمه بالتساوي
    final out = <List<double>>[];
    for (final c in res) {
      final len = c[1] - c[0];
      if (len <= _chunkMax) {
        out.add(c);
      } else {
        final n = (len / 60).ceil();
        final step = len / n;
        for (var i = 0; i < n; i++) {
          out.add([c[0] + step * i, i == n - 1 ? c[1] : c[0] + step * (i + 1)]);
        }
      }
    }
    return out;
  }

  static Future<String> _cutWav(
      String wav, double start, double len, String out) async {
    final session = await FFmpegKit.execute(
        '-y -ss ${start.toStringAsFixed(3)} -i "$wav" -t ${len.toStringAsFixed(3)} -c:a pcm_s16le "$out"');
    final ok = ReturnCode.isSuccess(await session.getReturnCode());
    if (!ok || !File(out).existsSync()) {
      throw Exception('تعذر تقطيع الصوت.');
    }
    return out;
  }

  /// يقسم جملة طويلة (من Whisper) لعبارات قصيرة (3 كلمات) بتوقيت تقريبي.
  static List<Caption> _splitPhrase(double st, double en, String text) {
    final words =
        text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || en <= st) return [];
    const per = 3;
    final groups = <String>[];
    for (var i = 0; i < words.length; i += per) {
      groups.add(words.sublist(i, i + per > words.length ? words.length : i + per).join(' '));
    }
    final totalChars = groups.fold<int>(0, (a, g) => a + g.length);
    final out = <Caption>[];
    var t = st;
    for (var i = 0; i < groups.length; i++) {
      final share = (en - st) * (groups[i].length / (totalChars == 0 ? 1 : totalChars));
      final e = i == groups.length - 1 ? en : t + share;
      out.add(Caption(t, e, groups[i]));
      t = e;
    }
    return out;
  }

  static String _audioPrompt(double dur) => '''
أنت محرر فيديوهات قصيرة (ريلز / تيك توك). استمع للصوت المرفق (غالباً كلام عربي بلهجة سودانية أو عامية). مدة الصوت ${dur.toStringAsFixed(1)} ثانية.
أرجع JSON فقط، بدون أي شرح وبدون علامات markdown، بهذا الشكل بالضبط:
{"segments":[{"start":0.0,"end":1.6,"text":"..."}]}
القواعد:
- segments: قسّم الكلام لمقاطع قصيرة (من 2 إلى 5 كلمات). وقت البداية والنهاية بالثواني العشرية (مثل 12.4) وليس بصيغة دقائق:ثواني، والبداية من 0 في أول هذا المقطع الصوتي. اكتب الكلام بنفس لهجة المتحدث كما نطقه بدون تحويله للفصحى وبدون علامات ترقيم. لا تكتب شيئاً في فترات الصمت أو الموسيقى.
''';

  /// تفريغ مقطع صوتي واحد (توقيت نسبي لبداية المقطع).
  static Future<AiResult<List<Caption>>> _transcribeChunk(AppSettings s,
      Uint8List bytes, List<String> geminiModels, double dur) async {
    final steps = <AiStep<List<Caption>>>[];

    for (final model in geminiModels) {
      steps.add(AiStep('Gemini $model', () async {
        final text = await AiRouter.gemini(s, model, [
          {
            'inline_data': {
              'mime_type': 'audio/wav',
              'data': base64Encode(bytes),
            }
          },
          {'text': _audioPrompt(dur)},
        ]);
        final m = _json(text);
        final caps = <Caption>[];
        for (final e in (m['segments'] as List? ?? [])) {
          final st = _num(e['start']);
          var en = _num(e['end']);
          final t = '${e['text'] ?? ''}'.trim();
          if (t.isEmpty || st < 0 || st >= dur) continue;
          if (en > dur) en = dur;
          if (en - st < 0.2) continue;
          caps.add(Caption(st, en, t));
        }
        return caps;
      }));
    }

    if (s.groqKey.trim().isNotEmpty) {
      for (final model in [AiRouter.groqWhisperTurbo, AiRouter.groqWhisperV3]) {
        steps.add(AiStep('Groq $model', () async {
          final segs = await AiRouter.groqTranscribe(s, model, bytes);
          final caps = <Caption>[];
          for (final e in segs) {
            final st = _num(e['start']);
            var en = _num(e['end']);
            if (en > dur) en = dur;
            caps.addAll(_splitPhrase(st, en, '${e['text'] ?? ''}'));
          }
          return caps;
        }));
      }
    }
    return AiRouter.run<List<Caption>>(steps);
  }

  /// العنوان والوصف والهاشتاقات وأفكار B-roll من النص الكامل (بدون صوت، فأي موديل نصي ينفع).
  static Future<AiResult<Map<String, dynamic>>> _metadata(
      AppSettings s, List<String> geminiModels, String transcript, double dur) async {
    final prompt = '''
أنت محرر فيديوهات قصيرة (ريلز / تيك توك). هذا نص كلام الفيديو مع وقت بداية كل عبارة بالثواني. مدة الفيديو ${dur.toStringAsFixed(1)} ثانية.
أرجع JSON فقط، بدون أي شرح وبدون علامات markdown، بهذا الشكل بالضبط:
{"title":"...","description":"...","hashtags":["..."],"broll":[{"start":5.0,"end":7.5,"query":"..."}]}
القواعد:
- title: عنوان جذاب يشد الانتباه في أول 3 ثواني، من 3 إلى 7 كلمات، بنفس لغة الفيديو.
- description: وصف قصير للنشر (سطرين على الأكثر).
- hashtags: من 5 إلى 8 هاشتاقات بدون علامة #.
- broll: من 2 إلى 4 لحظات يناسبها مقطع توضيحي (B-roll) بعد الثانية 4، كل واحدة بين 2 و3 ثواني. اجعل المقطع مرتبطاً بمعنى الكلام في تلك اللحظة تحديداً (فكرة مختلفة لكل لحظة). query كلمات بحث إنجليزية بسيطة (من 1 إلى 3 كلمات). مهم جداً: اختر مشاهد وأشياء وأماكن وطبيعة ومفاهيم (مثل money, city night, laptop, sunrise, shopping, phone, ocean, graph) ولا تذكر أشخاصاً ولا نساء ولا وجوهاً في الكلمات. لو ما في لحظات مناسبة اترك المصفوفة فاضية.

النص:
$transcript
''';
    final steps = <AiStep<Map<String, dynamic>>>[];
    for (final model in geminiModels) {
      steps.add(AiStep('Gemini $model', () async {
        final t = await AiRouter.gemini(s, model, [
          {'text': prompt}
        ]);
        return _json(t);
      }));
    }
    if (s.groqKey.trim().isNotEmpty) {
      steps.add(AiStep('Groq ${AiRouter.groqChatModel}', () async {
        final t = await AiRouter.groq(s, AiRouter.groqChatModel, [
          {'role': 'user', 'content': prompt}
        ]);
        return _json(t);
      }));
    }
    if (s.mistralKey.trim().isNotEmpty) {
      steps.add(AiStep('Mistral ${s.mistralModel.trim()}', () async {
        final t = await AiRouter.mistral(s, [
          {'role': 'user', 'content': prompt}
        ]);
        return _json(t);
      }));
    }
    return AiRouter.run<Map<String, dynamic>>(steps);
  }

  static Future<Analysis> run(
    AppSettings s,
    String wavPath,
    double durationSec, {
    List<double> cutTimes = const [],
    void Function(String)? onStatus,
  }) async {
    if (!s.hasAnyAiKey) {
      throw Exception('ما في مفتاح ذكاء اصطناعي. ضع مفتاح واحد على الأقل في الإعدادات.');
    }
    AiRouter.resetCooldowns();
    final notes = <String>[];
    final geminiModels = await AiRouter.geminiCandidates(s);

    // ---- 1) تفريغ الصوت مقطع بمقطع ----
    final chunks = _chunks(durationSec, cutTimes);
    final dir = File(wavPath).parent.path;
    final all = <Caption>[];
    final used = <String, int>{};
    final temps = <String>[];
    var failedChunks = 0;
    try {
      for (var i = 0; i < chunks.length; i++) {
        final st = chunks[i][0];
        final len = chunks[i][1] - st;
        onStatus?.call('جاري تفريغ الصوت (${i + 1}/${chunks.length})...');
        try {
          final chunkPath = '$dir/${wavPath.split('/').last}_c$i.wav';
          temps.add(chunkPath);
          await _cutWav(wavPath, st, len, chunkPath);
          final bytes = await File(chunkPath).readAsBytes();
          final res = await _transcribeChunk(s, bytes, geminiModels, len);
          used[res.label] = (used[res.label] ?? 0) + 1;
          if (res.failures.isNotEmpty) {
            notes.add('المقطع ${i + 1}: تم التبديل إلى ${res.label} (${res.failures.last})');
          }
          for (final c in res.value) {
            all.add(Caption(c.start + st, c.end + st, c.text));
          }
        } catch (e) {
          if (JobControl.cancelled) rethrow;
          failedChunks++;
          notes.add('المقطع ${i + 1} من ${chunks.length}: بدون كابشن. $e');
        }
      }
    } finally {
      for (final p in temps) {
        try {
          File(p).deleteSync();
        } catch (_) {}
      }
    }
    if (failedChunks == chunks.length) {
      throw Exception('فشل تفريغ الصوت في كل المقاطع.\n${notes.join('\n')}');
    }
    if (used.isNotEmpty) {
      notes.add('الكابشن: ${used.entries.map((e) => '${e.key} (${e.value} مقطع)').join('، ')}');
    }

    all.sort((x, y) => x.start.compareTo(y.start));
    for (var i = 0; i < all.length - 1; i++) {
      if (all[i].end > all[i + 1].start) all[i].end = all[i + 1].start;
    }
    all.removeWhere((c) =>
        c.end - c.start < 0.15 || c.start >= durationSec || c.text.trim().isEmpty);

    if (all.isEmpty) {
      return Analysis([], '', '', [], [], notes);
    }

    // ---- 2) العنوان والوصف والهاشتاقات وB-roll ----
    onStatus?.call('جاري كتابة العنوان والوصف واختيار B-roll...');
    var title = '';
    var description = '';
    var tags = <String>[];
    final broll = <BrollIdea>[];
    try {
      var transcript = all
          .map((c) => '[${c.start.toStringAsFixed(1)}] ${c.text}')
          .join('\n');
      if (transcript.length > 7000) transcript = transcript.substring(0, 7000);
      final res = await _metadata(s, geminiModels, transcript, durationSec);
      final m = res.value;
      title = '${m['title'] ?? ''}'.trim();
      description = '${m['description'] ?? ''}'.trim();
      tags = (m['hashtags'] as List? ?? [])
          .map((e) => '$e'.replaceAll('#', '').trim())
          .where((e) => e.isNotEmpty)
          .toList();
      for (final e in (m['broll'] as List? ?? [])) {
        final q = '${e['query'] ?? ''}'.trim();
        if (q.isEmpty) continue;
        broll.add(BrollIdea(_num(e['start']), _num(e['end']), q));
      }
      notes.add('العنوان والوصف: ${res.label}');
    } catch (e) {
      if (JobControl.cancelled) rethrow;
      notes.add('تعذر كتابة العنوان والوصف وB-roll: $e');
    }

    return Analysis(all, title, description, tags, broll, notes);
  }

  /// فحص بصري: هل في الصورة امرأة أو فتاة؟ (يرمي خطأ لو ما قدر أي نظام يفحص)
  static Future<bool> containsWoman(AppSettings s, String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final b64 = base64Encode(bytes);
    const q =
        'Does this image show a woman, a girl, or any female person (face or body)? Answer with exactly one word: YES or NO.';
    final steps = <AiStep<bool>>[];
    for (final model in await AiRouter.geminiCandidates(s)) {
      steps.add(AiStep('Gemini $model', () async {
        final t = await AiRouter.gemini(
            s,
            model,
            [
              {
                'inline_data': {'mime_type': 'image/jpeg', 'data': b64}
              },
              {'text': q},
            ],
            json: false,
            timeoutSec: 40);
        return t.toUpperCase().contains('YES');
      }));
    }
    final msg = [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': q},
          {
            'type': 'image_url',
            'image_url': 'data:image/jpeg;base64,$b64',
          },
        ],
      }
    ];
    if (s.mistralKey.trim().isNotEmpty) {
      steps.add(AiStep('Mistral ${s.mistralModel.trim()}', () async {
        final t = await AiRouter.mistral(s, msg, json: false);
        return t.toUpperCase().contains('YES');
      }));
    }
    if (s.groqKey.trim().isNotEmpty) {
      steps.add(AiStep('Groq ${AiRouter.groqVisionModel}', () async {
        final msgGroq = [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': q},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$b64'},
              },
            ],
          }
        ];
        final t = await AiRouter.groq(s, AiRouter.groqVisionModel, msgGroq,
            json: false);
        return t.toUpperCase().contains('YES');
      }));
    }
    final res = await AiRouter.run<bool>(steps);
    return res.value;
  }
}
