import 'dart:convert';

import 'ai_router.dart';
import 'settings.dart';

/// Turns the words spoken in a video moment into English search keywords for
/// 3D model libraries (Sketchfab, Poly Haven, ...). Those libraries do not
/// understand Arabic, so searching with the caption text finds nothing.
class ThreeDQueryPlanner {
  ThreeDQueryPlanner._();

  /// Used only when nothing else produced a keyword.
  static const List<String> fallbackKeywords = <String>[
    'lantern',
    'globe',
    'book',
    'star',
  ];

  static const Set<String> _stopWords = <String>{
    'the', 'and', 'for', 'with', 'that', 'this', 'from', 'are', 'was',
    'you', 'your', 'his', 'her', 'its', 'our', 'have', 'has', 'not',
    'but', 'all', 'can', 'will', 'just', 'about', 'what', 'when',
  };

  /// Arabic word (without "ال") -> English search keywords.
  static const Map<String, List<String>> _dictionary = <String, List<String>>{
    'مسجد': <String>['mosque'],
    'مساجد': <String>['mosque'],
    'جامع': <String>['mosque'],
    'قران': <String>['book', 'quran'],
    'كتاب': <String>['book'],
    'كتب': <String>['book'],
    'علم': <String>['book', 'globe'],
    'كعبه': <String>['kaaba', 'cube'],
    'حج': <String>['kaaba'],
    'عمره': <String>['kaaba'],
    'صلاه': <String>['prayer', 'mosque'],
    'مصلي': <String>['prayer'],
    'رمضان': <String>['lantern', 'crescent'],
    'فانوس': <String>['lantern'],
    'نور': <String>['lantern', 'lamp'],
    'ضوء': <String>['lamp', 'lantern'],
    'مصباح': <String>['lamp', 'lantern'],
    'هدايه': <String>['lantern', 'compass'],
    'قلب': <String>['heart'],
    'حب': <String>['heart'],
    'شمس': <String>['sun'],
    'قمر': <String>['moon'],
    'نجم': <String>['star'],
    'نجوم': <String>['star'],
    'سماء': <String>['cloud', 'sky'],
    'ارض': <String>['earth', 'globe'],
    'دنيا': <String>['globe', 'earth'],
    'عالم': <String>['globe', 'earth'],
    'بحر': <String>['ship', 'ocean'],
    'جبل': <String>['mountain'],
    'شجره': <String>['tree'],
    'اشجار': <String>['tree'],
    'ورده': <String>['flower', 'rose'],
    'ماء': <String>['water', 'bottle'],
    'نار': <String>['fire', 'flame'],
    'جنه': <String>['garden', 'palace'],
    'موت': <String>['hourglass', 'skull'],
    'وقت': <String>['clock', 'hourglass'],
    'ساعه': <String>['clock'],
    'صبر': <String>['hourglass'],
    'عمر': <String>['hourglass', 'clock'],
    'مال': <String>['coins', 'gold'],
    'رزق': <String>['coins', 'gold'],
    'ذهب': <String>['gold', 'coins'],
    'فلوس': <String>['coins', 'money'],
    'ميزان': <String>['scale', 'balance'],
    'عدل': <String>['scale', 'balance'],
    'طريق': <String>['road', 'path'],
    'باب': <String>['door'],
    'مفتاح': <String>['key'],
    'بيت': <String>['house'],
    'منزل': <String>['house'],
    'بيوت': <String>['house'],
    'سياره': <String>['car'],
    'طائره': <String>['airplane'],
    'كرسي': <String>['chair'],
    'طعام': <String>['food', 'fruit'],
    'هاتف': <String>['phone'],
    'جوال': <String>['phone'],
    'كاميرا': <String>['camera'],
    'فيديو': <String>['camera'],
    'ميكروفون': <String>['microphone'],
    'عقل': <String>['brain'],
    'فكر': <String>['brain', 'lamp'],
    'تكنولوجيا': <String>['robot'],
    'ذكاء': <String>['robot', 'brain'],
    'قوه': <String>['robot'],
    'سلاح': <String>['shield'],
    'حمايه': <String>['shield'],
    'تاج': <String>['crown'],
    'ملك': <String>['crown'],
  };

  static final RegExp _diacritics = RegExp(r'[\u064B-\u0652\u0640\u0670]');

  static String normalizeArabic(String input) {
    return input
        .replaceAll(_diacritics, '')
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
  }

  static bool containsArabic(String text) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  static Map<String, List<String>>? _normalizedDictionary;

  static Map<String, List<String>> get _dict {
    return _normalizedDictionary ??= <String, List<String>>{
      for (final entry in _dictionary.entries)
        normalizeArabic(entry.key): entry.value,
    };
  }

  /// Dictionary based keywords (works offline, no AI key needed).
  static List<String> localKeywords(String text) {
    final normalized = normalizeArabic(text);
    final tokens = normalized
        .split(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9]+'))
        .where((token) => token.length >= 2)
        .toList();

    final out = <String>[];
    void add(List<String> words) {
      for (final word in words) {
        if (!out.contains(word)) out.add(word);
      }
    }

    for (final token in tokens) {
      final candidates = <String>{token};
      for (final prefix in const <String>['وال', 'بال', 'لل', 'ال', 'و']) {
        if (token.startsWith(prefix) && token.length > prefix.length + 1) {
          candidates.add(token.substring(prefix.length));
        }
      }

      for (final candidate in candidates) {
        final direct = _dict[candidate];
        if (direct != null) {
          add(direct);
          break;
        }
      }
    }
    return out;
  }

  /// Keywords from text that is already (mostly) English.
  static List<String> asciiKeywords(String text) {
    final words = text
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((word) => word.length >= 3 && !_stopWords.contains(word))
        .toList();

    final out = <String>[];
    for (final word in words) {
      if (!out.contains(word)) out.add(word);
      if (out.length >= 4) break;
    }
    return out;
  }

  /// Parses `{"keywords": [...]}` (or a bare array) from a model reply.
  static List<String> parseKeywords(String raw) {
    Object? decoded;
    final objectStart = raw.indexOf('{');
    final objectEnd = raw.lastIndexOf('}');
    final arrayStart = raw.indexOf('[');
    final arrayEnd = raw.lastIndexOf(']');

    try {
      if (objectStart >= 0 && objectEnd > objectStart) {
        decoded = jsonDecode(raw.substring(objectStart, objectEnd + 1));
      } else if (arrayStart >= 0 && arrayEnd > arrayStart) {
        decoded = jsonDecode(raw.substring(arrayStart, arrayEnd + 1));
      }
    } catch (_) {
      return const <String>[];
    }

    Object? list = decoded;
    if (decoded is Map) list = decoded['keywords'];
    if (list is! List) return const <String>[];

    final valid = RegExp(r'^[a-z][a-z0-9 \-]{1,30}$');
    final out = <String>[];
    for (final item in list) {
      final word = '$item'.trim().toLowerCase();
      if (valid.hasMatch(word) && !out.contains(word)) out.add(word);
      if (out.length >= 6) break;
    }
    return out;
  }

  static Future<List<String>> _askAi(AppSettings settings, String text) async {
    final prompt = '''
Return JSON only, no explanation: {"keywords":["..."]}
Give 3 to 5 simple English search keywords (1 or 2 words each) for physical objects, places or symbols that a 3D model could show for this sentence from a short video. No people, no abstract words, no brand names. The sentence can be in any language.
Sentence: $text
''';

    final steps = <AiStep<List<String>>>[];

    List<String> parse(String raw) {
      final words = parseKeywords(raw);
      if (words.isEmpty) {
        throw AiFailure('رد', null, 'لا كلمات بحث', false);
      }
      return words;
    }

    for (final target in await AiRouter.groqTargets(settings, 'text')) {
      steps.add(
        AiStep<List<String>>(target.label, () async {
          return parse(
            await AiRouter.groq(
              target,
              <Map<String, dynamic>>[
                <String, dynamic>{'role': 'user', 'content': prompt},
              ],
              json: false,
            ),
          );
        }),
      );
    }

    for (final target in AiRouter.mistralTargets(settings)) {
      steps.add(
        AiStep<List<String>>(target.label, () async {
          return parse(
            await AiRouter.mistral(
              target,
              <Map<String, dynamic>>[
                <String, dynamic>{'role': 'user', 'content': prompt},
              ],
              json: false,
            ),
          );
        }),
      );
    }

    for (final target in await AiRouter.geminiTargets(settings)) {
      steps.add(
        AiStep<List<String>>(target.label, () async {
          return parse(
            await AiRouter.gemini(
              target,
              <Map<String, dynamic>>[
                <String, dynamic>{'text': prompt},
              ],
              json: false,
              timeoutSec: 30,
            ),
          );
        }),
      );
    }

    if (steps.isEmpty) return const <String>[];
    final result = await AiRouter.run<List<String>>(steps);
    return result.value;
  }

  /// Search keywords for [text], best first. Never empty.
  static Future<List<String>> keywords(AppSettings settings, String text) async {
    final clean = text.trim();
    final out = <String>[];
    void add(Iterable<String> words) {
      for (final word in words) {
        if (!out.contains(word)) out.add(word);
      }
    }

    if (!containsArabic(clean) && RegExp(r'[a-zA-Z]').hasMatch(clean)) {
      add(asciiKeywords(clean));
    } else {
      if (settings.hasAnyAiKey) {
        try {
          add(await _askAi(settings, clean).timeout(const Duration(seconds: 35)));
        } catch (_) {
          // The offline dictionary below still works.
        }
      }
      add(localKeywords(clean));
    }

    if (out.isEmpty) add(fallbackKeywords);
    return out.take(6).toList();
  }
}
