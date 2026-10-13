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

  /// موديل المستخدم أولاً، ثم أحدث موديلات flash المتاحة لمفتاحه (نكتشفها من جوجل).
  static Future<List<String>> geminiCandidates(AppSettings s) async {
    final key = s.geminiKey.trim();
    if (key.isEmpty) return [];
    final out = <String>[];
    final saved = s.geminiModel.trim();
    if (saved.isNotEmpty) out.add(saved);
    final found = _modelCache[key] ?? await _discover(key);
    _modelCache[key] = found;
    for (final m in found) {
      if (!out.contains(m)) out.add(m);
    }
    return out.take(4).toList();
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
  static Future<String> gemini(AppSettings s, String model,
      List<Map<String, dynamic>> parts,
      {bool json = true, int timeoutSec = 120}) async {
    final r = await http
        .post(
          Uri.parse('$_geminiBase/models/$model:generateContent'),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': s.geminiKey.trim(),
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

  static const groqChatModel = 'llama-3.3-70b-versatile';
  static const groqVisionModel = 'meta-llama/llama-4-scout-17b-16e-instruct';
  static const groqWhisperTurbo = 'whisper-large-v3-turbo';
  static const groqWhisperV3 = 'whisper-large-v3';

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

  static Future<String> mistral(AppSettings s, List<Map<String, dynamic>> messages,
          {bool json = true}) =>
      chat('Mistral', 'https://api.mistral.ai/v1/chat/completions',
          s.mistralKey, s.mistralModel.trim(), messages,
          json: json);

  static Future<String> groq(AppSettings s, String model,
          List<Map<String, dynamic>> messages,
          {bool json = true}) =>
      chat('Groq', 'https://api.groq.com/openai/v1/chat/completions',
          s.groqKey, model, messages,
          json: json);

  /// تحويل صوت لنص بـ Whisper على Groq. يرجع مقاطع: start / end / text
  static Future<List<Map<String, dynamic>>> groqTranscribe(
      AppSettings s, String model, Uint8List bytes) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'))
      ..headers['Authorization'] = 'Bearer ${s.groqKey.trim()}'
      ..fields['model'] = model
      ..fields['response_format'] = 'verbose_json'
      ..fields['temperature'] = '0'
      ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: 'chunk.wav'));
    final streamed = await req.send().timeout(const Duration(seconds: 120));
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 200) throw _fail('Groq $model', r);
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
    if (s.geminiKey.trim().isNotEmpty) {
      final models = await geminiCandidates(s);
      if (models.isEmpty) {
        lines.add('Gemini ❌ ما لقيت موديل');
      } else {
        try {
          await gemini(s, models.first, [
            {'text': ping}
          ], json: false, timeoutSec: 30);
          lines.add('Gemini ✅ ${models.first} (احتياط: ${models.length - 1})');
        } catch (e) {
          lines.add('Gemini ❌ ${cut('$e')}');
        }
      }
    } else {
      lines.add('Gemini — بدون مفتاح');
    }
    if (s.groqKey.trim().isNotEmpty) {
      try {
        await groq(
            s,
            groqChatModel,
            [
              {'role': 'user', 'content': ping}
            ],
            json: false);
        lines.add('Groq ✅');
      } catch (e) {
        lines.add('Groq ❌ ${cut('$e')}');
      }
    } else {
      lines.add('Groq — بدون مفتاح');
    }
    if (s.mistralKey.trim().isNotEmpty) {
      try {
        await mistral(
            s,
            [
              {'role': 'user', 'content': ping}
            ],
            json: false);
        lines.add('Mistral ✅');
      } catch (e) {
        lines.add('Mistral ❌ ${cut('$e')}');
      }
    } else {
      lines.add('Mistral — بدون مفتاح');
    }
    return lines;
  }
}
