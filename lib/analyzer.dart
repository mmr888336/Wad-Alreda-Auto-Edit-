import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'ai_router.dart';
import 'languages.dart';
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

  Analysis(
    this.captions,
    this.title,
    this.description,
    this.hashtags,
    this.broll, [
    this.notes = const [],
  ]);
}

/// تحليل الفيديو بالذكاء الاصطناعي.
class Analyzer {
  static const double _chunkTarget = 120;
  static const double _chunkMax = 170;

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

  static Map<String, dynamic> _json(String text) {
    final a = text.indexOf('{');
    final b = text.lastIndexOf('}');

    if (a < 0 || b <= a) {
      throw AiFailure(
        'رد',
        null,
        'رد غير مفهوم من الذكاء الاصطناعي',
        false,
      );
    }

    try {
      return jsonDecode(text.substring(a, b + 1))
          as Map<String, dynamic>;
    } catch (_) {
      throw AiFailure('رد', null, 'JSON غير صالح', false);
    }
  }

  /// يقسم مدة الصوت إلى مقاطع عند نقاط القص الطبيعية.
  static List<List<double>> _chunks(
    double dur,
    List<double> breaks,
  ) {
    final res = <List<double>>[];
    var st = 0.0;

    final pts =
        breaks.where((b) => b > 0 && b < dur).toList()..sort();

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

    final out = <List<double>>[];

    for (final c in res) {
      final len = c[1] - c[0];

      if (len <= _chunkMax) {
        out.add(c);
      } else {
        final n = (len / 120).ceil();
        final step = len / n;

        for (var i = 0; i < n; i++) {
          out.add([
            c[0] + step * i,
            i == n - 1
                ? c[1]
                : c[0] + step * (i + 1),
          ]);
        }
      }
    }

    return out;
  }

  static Future<String> _cutWav(
    String wav,
    double start,
    double len,
    String out,
  ) async {
    final session = await FFmpegKit.execute(
      '-y -ss ${start.toStringAsFixed(3)} '
      '-i "$wav" '
      '-t ${len.toStringAsFixed(3)} '
      '-c:a pcm_s16le "$out"',
    );

    final ok =
        ReturnCode.isSuccess(await session.getReturnCode());

    if (!ok || !File(out).existsSync()) {
      throw Exception('تعذر تقطيع الصوت.');
    }

    return out;
  }

  /// يقسم الجملة الطويلة إلى عبارات قصيرة بتوقيت تقريبي.
  static List<Caption> _splitPhrase(
    double st,
    double en,
    String text,
  ) {
    final words = text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.isEmpty || en <= st) return [];

    const per = 3;
    final groups = <String>[];

    for (var i = 0; i < words.length; i += per) {
      groups.add(
        words
            .sublist(
              i,
              i + per > words.length ? words.length : i + per,
            )
            .join(' '),
      );
    }

    final totalChars =
        groups.fold<int>(0, (a, g) => a + g.length);

    final out = <Caption>[];
    var t = st;

    for (var i = 0; i < groups.length; i++) {
      final share = (en - st) *
          (groups[i].length /
              (totalChars == 0 ? 1 : totalChars));

      final e = i == groups.length - 1 ? en : t + share;

      out.add(Caption(t, e, groups[i]));
      t = e;
    }

    return out;
  }

  static String _audioPrompt(
    AppSettings s,
    double dur,
  ) =>
      '''
أنت محرر فيديوهات قصيرة (ريلز / تيك توك). استمع للصوت المرفق. ${Languages.audioHint(s.country)} مدة الصوت ${dur.toStringAsFixed(1)} ثانية.
أرجع JSON فقط، بدون أي شرح وبدون علامات markdown، بهذا الشكل بالضبط:
{"segments":[{"start":0.0,"end":1.6,"text":"..."}]}
القواعد:
- segments: قسّم الكلام لمقاطع قصيرة (من 2 إلى 5 كلمات). وقت البداية والنهاية بالثواني العشرية (مثل 12.4) وليس بصيغة دقائق:ثواني، والبداية من 0 في أول هذا المقطع الصوتي. اكتب الكلام بنفس لغة المتحدث ولهجته كما نطقه، بدون تحويله للفصحى أو لغة ثانية، وبدون علامات ترقيم. لا تكتب شيئاً في فترات الصمت أو الموسيقى.
''';

  /// تفريغ مقطع صوتي واحد.
  static Future<AiResult<List<Caption>>> _transcribeChunk(
    AppSettings s,
    Uint8List bytes,
    List<GeminiTarget> targets,
    List<KeyedModel> groqStt,
    double dur,
  ) async {
    final steps = <AiStep<List<Caption>>>[];

    // 1) Groq Whisper أولاً.
    for (final gt in groqStt) {
      steps.add(
        AiStep(gt.label, () async {
          final segs = await AiRouter.groqTranscribe(
            gt,
            bytes,
            language: s.lang,
          );

          final caps = <Caption>[];

          for (final e in segs) {
            final st = _num(e['start']);
            var en = _num(e['end']);

            if (en > dur) en = dur;

            caps.addAll(
              _splitPhrase(st, en, '${e['text'] ?? ''}'),
            );
          }

          return caps;
        }),
      );
    }

    // 2) Gemini احتياط.
    for (final t in targets) {
      steps.add(
        AiStep(t.label, () async {
          final text = await AiRouter.gemini(
            t,
            [
              {
                'inline_data': {
                  'mime_type': 'audio/wav',
                  'data': base64Encode(bytes),
                }
              },
              {'text': _audioPrompt(s, dur)},
            ],
          );

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
        }),
      );
    }

    return AiRouter.run<List<Caption>>(steps);
  }

  /// إنشاء العنوان والوصف والهاشتاقات وأفكار B-roll.
  static Future<AiResult<Map<String, dynamic>>> _metadata(
    AppSettings s,
    List<GeminiTarget> targets,
    List<KeyedModel> groqText,
    List<KeyedModel> mistralT,
    String transcript,
    double dur,
  ) async {
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

    for (final gt in groqText) {
      steps.add(
        AiStep(gt.label, () async {
          final t = await AiRouter.groq(
            gt,
            [
              {'role': 'user', 'content': prompt}
            ],
            json: false,
          );

          return _json(t);
        }),
      );
    }

    for (final mt in mistralT) {
      steps.add(
        AiStep(mt.label, () async {
          final t = await AiRouter.mistral(
            mt,
            [
              {'role': 'user', 'content': prompt}
            ],
          );

          return _json(t);
        }),
      );
    }

    for (final tg in targets) {
      steps.add(
        AiStep(tg.label, () async {
          final t = await AiRouter.gemini(
            tg,
            [
              {'text': prompt}
            ],
          );

          return _json(t);
        }),
      );
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
      throw Exception(
        'ما في مفتاح ذكاء اصطناعي. ضع مفتاح واحد على الأقل في الإعدادات.',
      );
    }

    AiRouter.resetCooldowns();

    final notes = <String>[];
    final targets = await AiRouter.geminiTargets(s);
    final groqStt = await AiRouter.groqTargets(s, 'stt');
    final groqText = await AiRouter.groqTargets(s, 'text');
    final mistralT = AiRouter.mistralTargets(s);

    // ---- 1) تفريغ الصوت مقطعاً بمقطع ----
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

        onStatus?.call(
          'جاري تفريغ الصوت (${i + 1}/${chunks.length})...',
        );

        try {
          final chunkPath =
              '$dir/${wavPath.split('/').last}_c$i.wav';

          temps.add(chunkPath);

          await _cutWav(wavPath, st, len, chunkPath);

          final bytes = await File(chunkPath).readAsBytes();

          final res = await _transcribeChunk(
            s,
            bytes,
            targets,
            groqStt,
            len,
          );

          used[res.label] = (used[res.label] ?? 0) + 1;

          if (res.failures.isNotEmpty) {
            notes.add(
              'المقطع ${i + 1}: تم التبديل إلى '
              '${res.label} (${res.failures.last})',
            );
          }

          for (final c in res.value) {
            all.add(
              Caption(c.start + st, c.end + st, c.text),
            );
          }
        } catch (e) {
          if (JobControl.cancelled) rethrow;

          failedChunks++;

          notes.add(
            'المقطع ${i + 1} من ${chunks.length}: '
            'بدون كابشن. $e',
          );
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
      throw Exception(
        'فشل تفريغ الصوت في كل المقاطع.\n${notes.join('\n')}',
      );
    }

    if (used.isNotEmpty) {
      notes.add(
        'الكابشن: ${used.entries.map((e) => '${e.key} (${e.value} مقطع)').join('، ')}',
      );
    }

    all.sort((x, y) => x.start.compareTo(y.start));

    for (var i = 0; i < all.length - 1; i++) {
      if (all[i].end > all[i + 1].start) {
        all[i].end = all[i + 1].start;
      }
    }

    all.removeWhere(
      (c) =>
          c.end - c.start < 0.15 ||
          c.start >= durationSec ||
          c.text.trim().isEmpty,
    );

    if (all.isEmpty) {
      return Analysis([], '', '', [], [], notes);
    }

    // ---- 2) العنوان والوصف والهاشتاقات وB-roll ----
    onStatus?.call(
      'جاري كتابة العنوان والوصف واختيار B-roll...',
    );

    var title = '';
    var description = '';
    var tags = <String>[];
    final broll = <BrollIdea>[];

    try {
      var transcript = all
          .map((c) => '[${c.start.toStringAsFixed(1)}] ${c.text}')
          .join('\n');

      if (transcript.length > 7000) {
        transcript = transcript.substring(0, 7000);
      }

      final res = await _metadata(
        s,
        targets,
        groqText,
        mistralT,
        transcript,
        durationSec,
      );

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

        broll.add(
          BrollIdea(
            _num(e['start']),
            _num(e['end']),
            q,
          ),
        );
      }

      notes.add('العنوان والوصف: ${res.label}');
    } catch (e) {
      if (JobControl.cancelled) rethrow;

      notes.add('تعذر كتابة العنوان والوصف وB-roll: $e');
    }

    return Analysis(
      all,
      title,
      description,
      tags,
      broll,
      notes,
    );
  }

  /// فحص صورة واحدة للتوافق مع Enhancer.
  /// ترجع true إذا اكتشف النظام امرأة أو فتاة.
  static Future<bool> containsWoman(
    AppSettings s,
    String imagePath,
  ) async {
    final results = await containsWomanBatch(s, [imagePath]);

    return results.isNotEmpty && results.first;
  }

  /// فحص بصري لعدة صور في طلب واحد.
  /// يرجع قائمة بنفس ترتيب الصور.
  static Future<List<bool>> containsWomanBatch(
    AppSettings s,
    List<String> imagePaths,
  ) async {
    final n = imagePaths.length;

    if (n == 0) return [];

    final b64s = <String>[];

    for (final p in imagePaths) {
      b64s.add(base64Encode(await File(p).readAsBytes()));
    }

    final q =
        'You are given $n images in order. For each image decide whether it shows a woman, a girl, or any female person (face or body). Reply with JSON only, with exactly $n booleans in the same order, like {"women":[true,false]}';

    List<bool> parse(String text) {
      final m = _json(text);
      final list = (m['women'] as List?) ?? [];

      if (list.length != n) {
        throw AiFailure(
          'رد',
          null,
          'عدد النتائج غير مطابق',
          false,
        );
      }

      return list
          .map<bool>(
            (e) => e == true || '$e'.toLowerCase() == 'true',
          )
          .toList();
    }

    final steps = <AiStep<List<bool>>>[];

    for (final tg in await AiRouter.geminiTargets(s)) {
      steps.add(
        AiStep(tg.label, () async {
          final parts = <Map<String, dynamic>>[
            for (final b in b64s)
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': b,
                }
              },
            {'text': q},
          ];

          return parse(
            await AiRouter.gemini(
              tg,
              parts,
              timeoutSec: 60,
            ),
          );
        }),
      );
    }

    for (final gt in await AiRouter.groqTargets(s, 'vision')) {
      steps.add(
        AiStep(gt.label, () async {
          final content = <Map<String, dynamic>>[
            {'type': 'text', 'text': q},
            for (final b in b64s)
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$b',
                }
              },
          ];

          final t = await AiRouter.groq(
            gt,
            [
              {'role': 'user', 'content': content}
            ],
            json: false,
          );

          return parse(t);
        }),
      );
    }

    for (final mt in AiRouter.mistralTargets(s)) {
      steps.add(
        AiStep(mt.label, () async {
          final content = <Map<String, dynamic>>[
            {'type': 'text', 'text': q},
            for (final b in b64s)
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$b',
                }
              },
          ];

          final t = await AiRouter.mistral(
            mt,
            [
              {'role': 'user', 'content': content}
            ],
            json: false,
          );

          return parse(t);
        }),
      );
    }

    final res = await AiRouter.run<List<bool>>(steps);

    return res.value;
  }
}