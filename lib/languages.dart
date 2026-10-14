/// الدول واللغات. اختيار الدولة يحدد لغة التفريغ والكابشن ولهجته. الافتراضي: English.
class Country {
  final String code;
  final String name; // اسم الدولة (يظهر في القائمة)
  final String lang; // رمز اللغة ISO-639-1 (يستخدمه Whisper)
  final String langName; // اسم اللغة للشرح
  final String dialect; // وصف اللهجة
  const Country(this.code, this.name, this.lang, this.langName, [this.dialect = '']);
}

class Languages {
  static const defaultCode = 'US';

  static const countries = <Country>[
    // ---- الإنجليزية (الافتراضي) ----
    Country('US', 'English (USA)', 'en', 'الإنجليزية', 'American English'),
    Country('GB', 'English (UK)', 'en', 'الإنجليزية', 'British English'),
    Country('AU', 'English (Australia)', 'en', 'الإنجليزية', 'Australian English'),
    Country('CA', 'English (Canada)', 'en', 'الإنجليزية', 'Canadian English'),
    // ---- الدول العربية ----
    Country('SD', 'العربية - السودان', 'ar', 'العربية', 'بلهجة سودانية'),
    Country('EG', 'العربية - مصر', 'ar', 'العربية', 'بلهجة مصرية'),
    Country('SA', 'العربية - السعودية', 'ar', 'العربية', 'بلهجة سعودية'),
    Country('AE', 'العربية - الإمارات', 'ar', 'العربية', 'بلهجة خليجية'),
    Country('QA', 'العربية - قطر', 'ar', 'العربية', 'بلهجة خليجية'),
    Country('KW', 'العربية - الكويت', 'ar', 'العربية', 'بلهجة خليجية'),
    Country('IQ', 'العربية - العراق', 'ar', 'العربية', 'بلهجة عراقية'),
    Country('JO', 'العربية - الأردن', 'ar', 'العربية', 'بلهجة شامية'),
    Country('PS', 'العربية - فلسطين', 'ar', 'العربية', 'بلهجة شامية'),
    Country('LB', 'العربية - لبنان', 'ar', 'العربية', 'بلهجة شامية'),
    Country('SY', 'العربية - سوريا', 'ar', 'العربية', 'بلهجة شامية'),
    Country('YE', 'العربية - اليمن', 'ar', 'العربية', 'بلهجة يمنية'),
    Country('LY', 'العربية - ليبيا', 'ar', 'العربية', 'بلهجة ليبية'),
    Country('TN', 'العربية - تونس', 'ar', 'العربية', 'بلهجة تونسية'),
    Country('DZ', 'العربية - الجزائر', 'ar', 'العربية', 'بلهجة جزائرية'),
    Country('MA', 'العربية - المغرب', 'ar', 'العربية', 'بالدارجة المغربية'),
    Country('MR', 'العربية - موريتانيا', 'ar', 'العربية', 'بلهجة حسانية'),
    // ---- أمريكا اللاتينية وإسبانيا ----
    Country('ES', 'Español (España)', 'es', 'الإسبانية', 'español de España'),
    Country('MX', 'Español (México)', 'es', 'الإسبانية', 'español latinoamericano'),
    Country('AR', 'Español (Argentina)', 'es', 'الإسبانية', 'español latinoamericano'),
    Country('CO', 'Español (Colombia)', 'es', 'الإسبانية', 'español latinoamericano'),
    Country('BR', 'Português (Brasil)', 'pt', 'البرتغالية', 'português do Brasil'),
    Country('PT', 'Português (Portugal)', 'pt', 'البرتغالية', 'português de Portugal'),
    // ---- أوروبا ----
    Country('FR', 'Français', 'fr', 'الفرنسية'),
    Country('DE', 'Deutsch', 'de', 'الألمانية'),
    Country('IT', 'Italiano', 'it', 'الإيطالية'),
    Country('NL', 'Nederlands', 'nl', 'الهولندية'),
    Country('PL', 'Polski', 'pl', 'البولندية'),
    Country('SE', 'Svenska', 'sv', 'السويدية'),
    Country('GR', 'Ελληνικά', 'el', 'اليونانية'),
    Country('RU', 'Русский', 'ru', 'الروسية'),
    Country('TR', 'Türkçe', 'tr', 'التركية'),
  ];

  static Country byCode(String code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return countries.first;
  }

  static bool isRtl(String lang) => lang == 'ar' || lang == 'he' || lang == 'fa' || lang == 'ur';

  /// وصف يُضاف لتعليمات التفريغ (للتلميح فقط، ولو الكلام بلغة ثانية يكتبه بلغته)
  static String audioHint(String code) {
    final c = byCode(code);
    final d = c.dialect.isEmpty ? '' : ' ${c.dialect}';
    return 'اللغة المتوقعة: ${c.langName}$d. (لو كان الكلام بلغة أخرى اكتبه كما نطقه بلغته).';
  }
}
