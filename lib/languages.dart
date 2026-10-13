/// الدول واللغات. اختيار الدولة يحدد لغة التفريغ والكابشن ولهجته.
class Country {
  final String code;
  final String name; // اسم الدولة (يظهر في القائمة)
  final String lang; // رمز اللغة ISO-639-1 (يستخدمه Whisper)
  final String langName; // اسم اللغة للشرح
  final String dialect; // وصف اللهجة (للعربية)
  const Country(this.code, this.name, this.lang, this.langName, [this.dialect = '']);
}

class Languages {
  static const countries = <Country>[
    // ---- الدول العربية ----
    Country('SD', 'السودان', 'ar', 'العربية', 'بلهجة سودانية'),
    Country('EG', 'مصر', 'ar', 'العربية', 'بلهجة مصرية'),
    Country('SA', 'السعودية', 'ar', 'العربية', 'بلهجة سعودية'),
    Country('AE', 'الإمارات', 'ar', 'العربية', 'بلهجة خليجية'),
    Country('QA', 'قطر', 'ar', 'العربية', 'بلهجة خليجية'),
    Country('KW', 'الكويت', 'ar', 'العربية', 'بلهجة خليجية'),
    Country('IQ', 'العراق', 'ar', 'العربية', 'بلهجة عراقية'),
    Country('JO', 'الأردن', 'ar', 'العربية', 'بلهجة شامية'),
    Country('PS', 'فلسطين', 'ar', 'العربية', 'بلهجة شامية'),
    Country('LB', 'لبنان', 'ar', 'العربية', 'بلهجة شامية'),
    Country('SY', 'سوريا', 'ar', 'العربية', 'بلهجة شامية'),
    Country('YE', 'اليمن', 'ar', 'العربية', 'بلهجة يمنية'),
    Country('LY', 'ليبيا', 'ar', 'العربية', 'بلهجة ليبية'),
    Country('TN', 'تونس', 'ar', 'العربية', 'بلهجة تونسية'),
    Country('DZ', 'الجزائر', 'ar', 'العربية', 'بلهجة جزائرية'),
    Country('MA', 'المغرب', 'ar', 'العربية', 'بالدارجة المغربية'),
    Country('MR', 'موريتانيا', 'ar', 'العربية', 'بلهجة حسانية'),
    // ---- الإنجليزية ----
    Country('US', 'أمريكا (English)', 'en', 'الإنجليزية', 'American English'),
    Country('GB', 'بريطانيا (English)', 'en', 'الإنجليزية', 'British English'),
    Country('AU', 'أستراليا (English)', 'en', 'الإنجليزية', 'Australian English'),
    Country('CA', 'كندا (English)', 'en', 'الإنجليزية', 'Canadian English'),
    // ---- أمريكا اللاتينية وإسبانيا ----
    Country('ES', 'إسبانيا (Español)', 'es', 'الإسبانية', 'español de España'),
    Country('MX', 'المكسيك (Español)', 'es', 'الإسبانية', 'español latinoamericano'),
    Country('AR', 'الأرجنتين (Español)', 'es', 'الإسبانية', 'español latinoamericano'),
    Country('CO', 'كولومبيا (Español)', 'es', 'الإسبانية', 'español latinoamericano'),
    Country('BR', 'البرازيل (Português)', 'pt', 'البرتغالية', 'português do Brasil'),
    // ---- أوروبا ----
    Country('PT', 'البرتغال (Português)', 'pt', 'البرتغالية', 'português de Portugal'),
    Country('FR', 'فرنسا (Français)', 'fr', 'الفرنسية'),
    Country('DE', 'ألمانيا (Deutsch)', 'de', 'الألمانية'),
    Country('IT', 'إيطاليا (Italiano)', 'it', 'الإيطالية'),
    Country('NL', 'هولندا (Nederlands)', 'nl', 'الهولندية'),
    Country('PL', 'بولندا (Polski)', 'pl', 'البولندية'),
    Country('SE', 'السويد (Svenska)', 'sv', 'السويدية'),
    Country('GR', 'اليونان (Ελληνικά)', 'el', 'اليونانية'),
    Country('RU', 'روسيا (Русский)', 'ru', 'الروسية'),
    Country('TR', 'تركيا (Türkçe)', 'tr', 'التركية'),
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
