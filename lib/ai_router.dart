import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'settings.dart';
import 'silence_cutter.dart';

/// خطأ من مزود ذكاء اصطناعي. transient = مؤقت (يستحق إعادة المحاولة).
class AiFailure implements Exception {
  final String provider;
  final int? status;
  final String message;
  final bool transient;
  AiFailure(this.provider, this.status, this.message, this.transient);

  @override
  String toString() =>
      '$provider${status != null ? ' $status' : ''}: $message';
}

/// خطوة واحدة في السلسلة (مزود + موديل).
class AiStep<T> {
  final String label;
  final Future<T> Function() run;
  AiStep(this.label, this.run);
}

/// مفتاح + موديل Gemini (نجرب عدة مفاتيح من مشاريع مختلفة عشان الحصة)
class GeminiTarget {
  final String key;
  final String model;
  final String label;
  GeminiTarget(this.key, this.model, this.label);
}

/// مفتاح + موديل لمزود (Groq أو Mistral) مع اسم يظهر في الملاحظات
class KeyedModel {
  final String key;
  final String model;
  final String label;
  KeyedModel(this.key, this.model, this.label);
}

/// موديلات Groq المتاحة لحسابك، مصنفة حسب الوظيفة (نكتشفها من واجهة Groq نفسها)
class GroqModels {
  final List<String> stt; // تفريغ صوت (Whisper)
  final List<String> text; // نص (عنوان، وصف، أفكار B-roll)
  final List<String> vision; // مرشحة لفهم الصور
  GroqModels(this.stt, this.text, this.vision);
}

class AiResult<T> {
  final T value;
  final String label;
  final List<String> failures; // أخطاء الخطوات اللي سبقت النجاح
  AiResult(this.value, this.label, this.failures);
}

class AiRouter {
  // انتظار بين المحاولات: محاولة أولى + إعادتين فقط، بعدها ننتقل للخطوة التالية.
  static const _delays = [Duration(seconds: 2), Duration(seconds: 5)];
  static final Map<String, DateTime> _cool = {};

  static String cut(String s) => s.length > 200 ? s.substring(0, 200) : s;

  static void resetCooldowns() => _cool.clear();

  static bool _isCooling(String label) {
    final until = _cool[label];
    return until != null && until.isAfter(DateTime.now());
  }

  /// يجرب الخطوات بالترتيب. الأخطاء المؤقتة (429 / 5xx / مهلة / شبكة): إعادتين مع انتظار.
  /// الأخطاء الدائمة (404 / 401 / 400 ...): ننتقل فوراً للخطوة التالية.
  /// أي خطوة فشلت نهائياً نتخطاها 3 دقائق عشان ما نضيّع وقت في كل مقطع.
  static Future<AiResult<T>> run<T>(List<AiStep<T>> steps) async {
    if (steps.isEmpty) {
      throw Exception('ما في مفتاح ذكاء اصطناعي. ضع مفتاح واحد على الأقل في الإعدادات.');
    }
    var active = steps.where((s) => !_isCooling(s.label)).toList();
    if (active.isEmpty) active = steps;

    final failures = <String>[];
    for (final step in active) {
      for (var attempt = 0; attempt <= _delays.length; attempt++) {
        if (JobControl.cancelled) throw Exception('تم إلغاء المونتاج.');
        var transient = false;
        try {
          final value = await step.run();
          return AiResult<T>(value, step.label, failures);
        } on AiFailure catch (e) {
          failures.add('${step.label} ← ${cut(e.toString())}');
          transient = e.transient;
        } on TimeoutException {
          failures.add('${step.label} ← انتهت المهلة');
          transient = true;
        } on SocketException {
          failures.add('${step.label} ← لا يوجد اتصال');
          transient = true;
        } on http.ClientException catch (e) {
          failures.add('${step.label} ← ${cut(e.toString())}');
          transient = true;
        } catch (e) {
          failures.add('${step.label} ← ${cut(e.toString())}');
          transient = false;
        }
        if (!transient || attempt == _delays.length) {
          _cool[step.label] = DateTime.now().add(const Duration(minutes: 3));
          break;
        }
        await Future.delayed(_delays[attempt]);
      }
    }
    final tail = failures.length > 6
        ? failures.sublist(failures.length - 6)
        : failures;
    throw Exception('فشلت كل الأنظمة:\n- ${tail.join('\n- ')}');
  }

  // ---------------- Gemini ----------------

  static const _geminiBase = 'https://generativelanguage.googleapis.com/v1beta';
  static final Map<String, List<String>> _modelCache = {};

  /// موديلات Lite أولاً (حصتها المجانية أكبر بكثير: حوالي 500 طلب في اليوم)، ثم موديل المستخدم، ثم باقي flash.
  static Future<List<String>> _modelsFor(String key, String saved) async {
    final found = _modelCache[key] ?? await _discover(key);
    _modelCache[key] = found;
    final lite = found.where((m) => m.contains('lite')).toList();
    final rest = found.where((m) => !m.contains('lite')).toList();
    final out = <String>[];
    for (final m in [...lite, if (saved.isNotEmpty) saved, ...rest]) {
      if (!out.contains(m)) out.add(m);
    }
    return out.take(3).toList();
  }

  /// قائمة (مفتاح + موديل) بالترتيب: أفضل موديل لكل مفتاح أولاً، ثم الموديل التالي، وهكذا.
  static Future<List<GeminiTarget>> geminiTargets(AppSettings s) async {
    final keys = s.geminiKeys;
    if (keys.isEmpty) return [];
    final perKey = <List<String>>[];
    for (final k in keys) {
      perKey.add(await _modelsFor(k, s.geminiModel.trim()));
    }
    final out = <GeminiTarget>[];
    for (var j = 0; j < 3; j++) {
      for (var i = 0; i < keys.length; i++) {
        if (j < perKey[i].length) {
          final m = perKey[i][j];
          final tag = keys.length > 1 ? ' #${i + 1}' : '';
          out.add(GeminiTarget(keys[i], m, 'Gemini$tag $m'));
        }
      }
    }
    return out;
  }

  static Future<List<String>> _discover(String key) async {
    try {
      final r = await http
          .get(Uri.parse('$_geminiBase/models?pageSize=200'),
              headers: {'x-goog-api-key': key})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return [];
      final list = (jsonDecode(utf8.decode(r.bodyBytes))['models'] as List?) ?? [];
      final scored = <MapEntry<String, double>>[];
      final bad = RegExp(r'image|tts|live|audio|embedding|exp|robotics|computer');
      for (final m in list) {
        final methods = (m['supportedGenerationMethods'] as List?) ?? [];
        if (!methods.contains('generateContent')) continue;
        final name = '${m['name']}'.replaceFirst('models/', '');
        if (!name.startsWith('gemini-') || !name.contains('flash')) continue;
        if (bad.hasMatch(name)) continue;
        final v = RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(name);
        var score = v == null ? 0.0 : double.tryParse(v.group(1)!) ?? 0.0;
        if (name.contains('lite')) score -= 0.05;
        scored.add(MapEntry(name, score));
      }
      scored.sort((a, b) => b.value.compareTo(a.value));
      return scored.map((e) => e.key).toList();
    } catch (_) {
      return [];
    }
  }

  static AiFailure _fail(String provider, http.Response r) {
    final code = r.statusCode;
    final transient = code == 408 || code == 429 || code >= 500;
    return AiFailure(provider, code, cut(r.body), transient);
  }

  /// استدعاء Gemini. parts = أجزاء الرسالة (نص / صوت / صورة).
  static Future<String> gemini(GeminiTarget t, List<Map<String, dynamic>> parts,
      {bool json = true, int timeoutSec = 120}) async {
    final model = t.model;
    final r = await http
        .post(
          Uri.parse('$_geminiBase/models/$model:generateContent'),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': t.key,
          },
          body: jsonEncode({
            'contents': [
              {'parts': parts}
            ],
            'generationConfig': {
              if (json) 'responseMimeType': 'application/json',
              'temperature': 0.3,
            },
          }),
        )
        .timeout(Duration(seconds: timeoutSec));
    if (r.statusCode != 200) throw _fail('Gemini $model', r);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final cands = j['candidates'];
    if (cands is! List || cands.isEmpty) {
      throw AiFailure('Gemini $model', null, 'رد فارغ', false);
    }
    final ps = (cands.first['content']?['parts'] as List?) ?? [];
    final text = ps.map((p) => '${p['text'] ?? ''}').join();
    if (text.trim().isEmpty) {
      throw AiFailure('Gemini $model', null, 'رد فارغ', false);
    }
    return text;
  }

  // ---------------- Mistral / Groq (صيغة OpenAI) ----------------

  // أسماء احتياطية تُستخدم فقط لو فشل اكتشاف الموديلات من Groq
  static const _groqDefaultStt = ['whisper-large-v3-turbo', 'whisper-large-v3'];
  static const _groqDefaultText = ['openai/gpt-oss-120b', 'openai/gpt-oss-20b'];

  static final Map<String, GroqModels> _groqCache = {};

  static int _textRank(String id) {
    final low = id.toLowerCase();
    if (low.contains('120b')) return 30;
    if (low.contains('70b')) return 28;
    if (low.contains('20b')) return 20;
    return 10;
  }

  /// يجلب الموديلات المتاحة لمفتاح Groq ويصنفها. أي موديل جديد يظهر في حسابك يدخل تلقائياً.
  static Future<GroqModels> _groqModelsForKey(String key) async {
    final cached = _groqCache[key];
    if (cached != null) return cached;
    final stt = <String>[];
    final text = <String>[];
    final vision = <String>[];
    var ok = false;
    try {
      final r = await http.get(Uri.parse('https://api.groq.com/openai/v1/models'),
          headers: {'Authorization': 'Bearer $key'}).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        ok = true;
        final list = (jsonDecode(utf8.decode(r.bodyBytes))['data'] as List?) ?? [];
        for (final m in list) {
          if (m['active'] == false) continue;
          final id = '${m['id']}';
          final low = id.toLowerCase();
          if (low.contains('whisper')) {
            stt.add(id);
          } else if (RegExp(r'orpheus|guard|tts|embed|moderation').hasMatch(low)) {
            continue;
          } else {
            text.add(id);
            if (RegExp(r'scout|maverick|vision|qwen').hasMatch(low)) vision.add(id);
          }
        }
      }
    } catch (_) {}
    stt.sort((a, b) => (b.contains('turbo') ? 1 : 0) - (a.contains('turbo') ? 1 : 0));
    text.sort((a, b) => _textRank(b).compareTo(_textRank(a)));
    if (stt.isEmpty) stt.addAll(_groqDefaultStt);
    if (text.isEmpty) text.addAll(_groqDefaultText);
    final res = GroqModels(stt, text, vision);
    if (ok) _groqCache[key] = res;
    return res;
  }

  /// قائمة (مفتاح + موديل) لـ Groq بالترتيب: أفضل موديل عبر كل المفاتيح أولاً، ثم الموديل التالي.
  /// kind: 'stt' (تفريغ صوت) أو 'text' (نص) أو 'vision' (صور)
  static Future<List<KeyedModel>> groqTargets(AppSettings s, String kind) async {
    final keys = s.groqKeys;
    if (keys.isEmpty) return [];
    final lists = <List<String>>[];
    for (final k in keys) {
      final gm = await _groqModelsForKey(k);
      lists.add(kind == 'stt' ? gm.stt : (kind == 'vision' ? gm.vision : gm.text));
    }
    var maxLen = 0;
    for (final l in lists) {
      if (l.length > maxLen) maxLen = l.length;
    }
    final out = <KeyedModel>[];
    for (var j = 0; j < maxLen; j++) {
      for (var i = 0; i < keys.length; i++) {
        if (j < lists[i].length) {
          final tag = keys.length > 1 ? ' #${i + 1}' : '';
          out.add(KeyedModel(keys[i], lists[i][j], 'Groq$tag ${lists[i][j]}'));
        }
      }
    }
    return out;
  }

  /// قائمة (مفتاح + موديل) لـ Mistral، واحد لكل مفتاح.
  static List<KeyedModel> mistralTargets(AppSettings s) {
    final keys = s.mistralKeys;
    final model = s.mistralModel.trim();
    return [
      for (var i = 0; i < keys.length; i++)
        KeyedModel(keys[i], model, 'Mistral${keys.length > 1 ? ' #${i + 1}' : ''} $model'),
    ];
  }

  static Future<String> chat(String provider, String url, String key,
      String model, List<Map<String, dynamic>> messages,
      {bool json = true, int timeoutSec = 90}) async {
    final r = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${key.trim()}',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': 0.3,
            if (json) 'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(Duration(seconds: timeoutSec));
    if (r.statusCode != 200) throw _fail('$provider $model', r);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final choices = j['choices'];
    if (choices is! List || choices.isEmpty) {
      throw AiFailure('$provider $model', null, 'رد فارغ', false);
    }
    final content = choices.first['message']?['content'];
    final text = content is String ? content : '';
    if (text.trim().isEmpty) {
      throw AiFailure('$provider $model', null, 'رد فارغ', false);
    }
    return text;
  }

  static Future<String> mistral(KeyedModel t, List<Map<String, dynamic>> messages,
          {bool json = true}) =>
      chat('Mistral', 'https://api.mistral.ai/v1/chat/completions', t.key,
          t.model, messages,
          json: json);

  static Future<String> groq(KeyedModel t, List<Map<String, dynamic>> messages,
          {bool json = true}) =>
      chat('Groq', 'https://api.groq.com/openai/v1/chat/completions', t.key,
          t.model, messages,
          json: json);

  /// تحويل صوت لنص بـ Whisper على Groq. يرجع مقاطع: start / end / text
  static Future<List<Map<String, dynamic>>> groqTranscribe(
      KeyedModel t, Uint8List bytes,
      {String? language}) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'))
      ..headers['Authorization'] = 'Bearer ${t.key}'
      ..fields['model'] = t.model
      ..fields['response_format'] = 'verbose_json'
      ..fields['temperature'] = '0'
      ..fields.addAll(
          (language != null && language.isNotEmpty) ? {'language': language} : {})
      ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: 'chunk.wav'));
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200) throw _fail('Groq ${t.model}', r);
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final segs = (j['segments'] as List?) ?? [];
    return segs
        .map<Map<String, dynamic>>((e) => {
              'start': e['start'],
              'end': e['end'],
              'text': e['text'],
            })
        .toList();
  }

  /// اختبار سريع لكل مزود عنده مفتاح (للزر في الإعدادات)
  static Future<List<String>> testAll(AppSettings s) async {
    final lines = <String>[];
    const ping = 'Reply with the single word: ok';
    final keys = s.geminiKeys;
    if (keys.isNotEmpty) {
      final targets = await geminiTargets(s);
      for (var i = 0; i < keys.length; i++) {
        final tag = keys.length > 1 ? ' #${i + 1}' : '';
        final mine = targets.where((t) => t.key == keys[i]).toList();
        if (mine.isEmpty) {
          lines.add('Gemini$tag ❌ ما لقيت موديل');
          continue;
        }
        try {
          await gemini(mine.first, [
            {'text': ping}
          ], json: false, timeoutSec: 30);
          lines.add('Gemini$tag ✅ ${mine.first.model} (احتياط: ${mine.length - 1})');
        } catch (e) {
          lines.add('Gemini$tag ❌ ${cut('$e')}');
        }
      }
    } else {
      lines.add('Gemini — بدون مفتاح');
    }
    final gkeys = s.groqKeys;
    if (gkeys.isEmpty) lines.add('Groq — بدون مفتاح');
    for (var i = 0; i < gkeys.length; i++) {
      final tag = gkeys.length > 1 ? ' #${i + 1}' : '';
      try {
        final gm = await _groqModelsForKey(gkeys[i]);
        await groq(
            KeyedModel(gkeys[i], gm.text.first, ''),
            [
              {'role': 'user', 'content': ping}
            ],
            json: false);
        lines.add(
            'Groq$tag ✅ ${gm.text.first} (نص: ${gm.text.length}، تفريغ صوت: ${gm.stt.length}، صور: ${gm.vision.length})');
      } catch (e) {
        lines.add('Groq$tag ❌ ${cut('$e')}');
      }
    }
    final mkeys = mistralTargets(s);
    if (mkeys.isEmpty) lines.add('Mistral — بدون مفتاح');
    for (final t in mkeys) {
      try {
        await mistral(
            t,
            [
              {'role': 'user', 'content': ping}
            ],
            json: false);
        lines.add('${t.label} ✅');
      } catch (e) {
        lines.add('${t.label} ❌ ${cut('$e')}');
      }
    }
    return lines;
  }
}}
