// Domain story packs: the vocabulary and visual grammar of one subject area.
//
// StoryUnderstanding routes every spoken segment to a domain pack (see
// StoryUnderstanding.route). The pack tells the planner what the words of
// that domain mean, which environments and objects belong to it, and which
// shot grammar and transitions suit it. The everyday pack is the fallback
// when no domain word is found.
//
// This is a data registry, not a second story engine: the planner in
// story_understanding.dart owns the planning, the packs only describe the
// domain. Pure Dart, no I/O, no network, no dependency on the planner (so
// there is no circular import).

/// One domain of the story packs.
class DomainStoryPack {
  /// Stable id (`history_archaeology`, `religion_spirituality`, ...).
  final String id;

  /// Human label (Arabic) for diagnostics.
  final String label;

  /// Subdomains of this pack (free-form ids).
  final List<String> subdomains;

  /// Trigger words (Arabic and English) that route a segment to this pack.
  final List<String> triggers;

  /// Environment ids that belong to the domain, best first. The ids match
  /// `StoryEnvironment` names in `story_understanding.dart` (`office`,
  /// `room`, `library`, `street`, `studio`, `outdoors`, `bathroom`,
  /// `kitchen`, `bedroom`, `livingRoom`, `hallway`).
  final List<String> environments;

  /// Objects that belong to the domain (asset-style keys).
  final List<String> objects;

  /// Shot grammar of the domain, best first. The ids match `StoryShotKind`
  /// names in `story_understanding.dart` (`establishing`, `medium`,
  /// `closeUp`, `detail`, `reveal`).
  final List<String> shotGrammar;

  /// Intents the domain usually uses. The ids match `StoryIntent` names in
  /// `story_understanding.dart` (`explain`, `compare`, `story`, `warn`,
  /// `metaphor`).
  final List<String> intents;

  /// Mood the domain usually carries. The id matches `StoryMood` names in
  /// `story_understanding.dart` (`calm`, `energetic`, `tense`).
  final String mood;

  /// True when the domain needs a verified source before a documentary-looking
  /// depiction (history, religion, news, medicine...).
  final bool requiresSource;

  /// True when the domain must never fabricate a real event or a real person.
  final bool noFabricatedEvents;

  const DomainStoryPack({
    required this.id,
    required this.label,
    this.subdomains = const <String>[],
    required this.triggers,
    required this.environments,
    this.objects = const <String>[],
    this.shotGrammar = const <String>[
      'establishing',
      'medium',
      'closeUp',
    ],
    this.intents = const <String>['explain'],
    this.mood = 'calm',
    this.requiresSource = false,
    this.noFabricatedEvents = false,
  });
}

/// The registry of every domain pack.
class DomainStoryPacks {
  DomainStoryPacks._();

  /// The fallback pack, used when no domain word is found.
  static const String fallbackId = 'everyday_explainer';

  static const List<DomainStoryPack> all = <DomainStoryPack>[
    DomainStoryPack(
      id: 'history_archaeology',
      label: 'التاريخ والآثار',
      subdomains: <String>['ancient', 'medieval', 'modern', 'archaeology'],
      triggers: <String>[
        'تاريخ', 'حضارة', 'حضاره', 'عصر', 'عصور', 'قديم', 'قديمه', 'آثار',
        'اثار', 'مملكة', 'مملكه', 'دولة', 'دوله', 'حضارات', 'فرعون',
        'رومان', 'روم', 'إغريق', 'اغريق', 'بابل', 'آشور', 'اشور',
        'history', 'ancient', 'civilization', 'empire', 'archaeology',
        'medieval', 'pharaoh', 'roman', 'greek',
      ],
      environments: <String>['library', 'outdoors', 'street'],
      objects: <String>['books', 'map', 'artifact', 'column', 'scroll'],
      shotGrammar: <String>['establishing', 'detail', 'reveal', 'medium'],
      intents: <String>['explain', 'story'],
      mood: 'calm',
      requiresSource: true,
      noFabricatedEvents: true,
    ),
    DomainStoryPack(
      id: 'religion_spirituality',
      label: 'الدين والروحانيات',
      subdomains: <String>['islam', 'comparative', 'spirituality'],
      triggers: <String>[
        'دين', 'إسلام', 'اسلام', 'مسلم', 'مسلمين', 'قرآن', 'قران', 'سنة',
        'سنه', 'حديث', 'صلاة', 'صلاه', 'صوم', 'زكاة', 'زكاه', 'حج', 'عمرة',
        'عمره', 'نبي', 'رسول', 'صحابة', 'صحابه', 'إيمان', 'ايمان', 'تقوى',
        'بركة', 'بركه', 'دعاء', 'ذكر', 'تسبيح', 'رمضان', 'عيد',
        'islam', 'muslim', 'quran', 'prayer', 'faith', 'religion',
        'ramadan', 'prophet', 'spiritual',
      ],
      environments: <String>['room', 'library', 'outdoors'],
      objects: <String>['lantern', 'crescent', 'prayer_beads', 'books'],
      shotGrammar: <String>['establishing', 'medium', 'closeUp'],
      intents: <String>['explain', 'story'],
      mood: 'calm',
      requiresSource: true,
      noFabricatedEvents: true,
    ),
    DomainStoryPack(
      id: 'science_nature',
      label: 'العلوم والطبيعة',
      subdomains: <String>['physics', 'chemistry', 'biology', 'environment'],
      triggers: <String>[
        'علم', 'علوم', 'فيزياء', 'كيمياء', 'أحياء', 'احياء', 'خلية', 'خليه',
        'ذرة', 'ذره', 'جزيء', 'طاقة', 'طاقه', 'قوة', 'قوه', 'حركة',
        'حركه', 'ضوء', 'صوت', 'مادة', 'ماده', 'تفاعل', 'تجربة', 'تجربه',
        'science', 'physics', 'chemistry', 'biology', 'atom', 'molecule',
        'energy', 'experiment',
      ],
      environments: <String>['studio', 'library', 'outdoors'],
      objects: <String>['atom', 'molecule', 'chart', 'microscope', 'flask'],
      shotGrammar: <String>['detail', 'closeUp', 'medium'],
      intents: <String>['explain', 'compare'],
      mood: 'calm',
      requiresSource: true,
    ),
    DomainStoryPack(
      id: 'sports',
      label: 'الرياضة',
      subdomains: <String>['football', 'basketball', 'tennis', 'fitness'],
      triggers: <String>[
        'رياضة', 'رياضه', 'كرة', 'كره', 'قدم', 'ملعب', 'لاعب', 'لاعبين',
        'فريق', 'هدف', 'مباراة', 'مباراه', 'بطولة', 'بطوله', 'تدريب',
        'لياقة', 'لياقه', 'جري', 'سباق', 'فوز', 'خسارة', 'خساره',
        'sport', 'football', 'soccer', 'basketball', 'tennis', 'fitness',
        'match', 'team', 'goal', 'training',
      ],
      environments: <String>['outdoors', 'studio'],
      objects: <String>['ball', 'trophy', 'field', 'whistle'],
      shotGrammar: <String>['establishing', 'medium', 'detail', 'reveal'],
      intents: <String>['explain', 'story'],
      mood: 'energetic',
    ),
    DomainStoryPack(
      id: 'medicine_health',
      label: 'الطب والصحة',
      subdomains: <String>['anatomy', 'physiology', 'wellness'],
      triggers: <String>[
        'طب', 'طبي', 'صحة', 'صحه', 'مرض', 'مرضى', 'علاج', 'دواء', 'دوا',
        'طبيب', 'مستشفى', 'قلب', 'دماغ', 'مخ', 'عظام', 'عضلات', 'عضله',
        'فيتامين', 'مناعة', 'مناعه', 'تغذية', 'تغذيه',
        'medicine', 'health', 'doctor', 'hospital', 'anatomy', 'disease',
        'treatment', 'vitamin',
      ],
      environments: <String>['studio', 'room'],
      objects: <String>['medical', 'brain', 'heart', 'pill'],
      shotGrammar: <String>['detail', 'closeUp', 'medium'],
      intents: <String>['explain', 'warn'],
      mood: 'calm',
      requiresSource: true,
    ),
    DomainStoryPack(
      id: 'education_study',
      label: 'التعليم والدراسة',
      subdomains: <String>['school', 'university', 'self_learning'],
      triggers: <String>[
        'تعليم', 'دراسة', 'دراسه', 'مدرسة', 'مدرسه', 'جامعة', 'جامعه',
        'طالب', 'طلاب', 'درس', 'دروس', 'امتحان', 'اختبار', 'مذاكرة',
        'مذاكره', 'شرح', 'معرفة', 'معرفه', 'تعلم',
        'education', 'study', 'school', 'university', 'student', 'exam',
        'learn', 'lesson',
      ],
      environments: <String>['library', 'room', 'studio'],
      objects: <String>['books', 'notebook', 'graduation', 'bulb'],
      shotGrammar: <String>['establishing', 'medium', 'closeUp'],
      intents: <String>['explain'],
      mood: 'calm',
    ),
    DomainStoryPack(
      id: 'technology_ai',
      label: 'التقنية والذكاء الاصطناعي',
      subdomains: <String>['software', 'hardware', 'ai', 'networks'],
      triggers: <String>[
        'تقنية', 'تقنيه', 'تكنولوجيا', 'حاسوب', 'كمبيوتر', 'برمجة', 'برمجه',
        'كود', 'تطبيق', 'تطبيقات', 'هاتف', 'جوال', 'موبايل', 'إنترنت',
        'انترنت', 'شبكة', 'شبكه', 'ذكاء', 'اصطناعي', 'روبوت', 'بيانات',
        'technology', 'tech', 'software', 'hardware', 'ai', 'robot',
        'computer', 'code', 'app', 'internet', 'data',
      ],
      environments: <String>['studio', 'office'],
      objects: <String>['laptop', 'phone', 'chip', 'screen'],
      shotGrammar: <String>['detail', 'closeUp', 'medium'],
      intents: <String>['explain', 'compare'],
      mood: 'energetic',
    ),
    DomainStoryPack(
      id: 'business_economics',
      label: 'الأعمال والاقتصاد',
      subdomains: <String>['business', 'economics', 'entrepreneurship'],
      triggers: <String>[
        'أعمال', 'اعمال', 'تجارة', 'تجاره', 'اقتصاد', 'شركة', 'شركه',
        'مشروع', 'استثمار', 'سوق', 'أسواق', 'اسواق', 'ربح', 'أرباح',
        'ارباح', 'خسارة', 'خساره', 'مبيعات', 'تسويق', 'ريادة', 'رياده',
        'business', 'economics', 'company', 'market', 'profit', 'invest',
        'startup', 'sales', 'marketing',
      ],
      environments: <String>['office', 'studio'],
      objects: <String>['chart', 'coins', 'briefcase', 'handshake'],
      shotGrammar: <String>['establishing', 'medium', 'detail'],
      intents: <String>['explain', 'compare'],
      mood: 'energetic',
    ),
    DomainStoryPack(
      id: 'geography_travel',
      label: 'الجغرافيا والسفر',
      subdomains: <String>['countries', 'cities', 'landmarks', 'travel'],
      triggers: <String>[
        'جغرافيا', 'سفر', 'رحلة', 'رحله', 'سياحة', 'سياحه', 'بلد', 'بلاد',
        'دولة', 'دوله', 'مدينة', 'مدينه', 'خريطة', 'خريطه', 'قارة', 'قاره',
        'محيط', 'بحر', 'جبل', 'جبال', 'صحراء', 'نهر',
        'geography', 'travel', 'country', 'city', 'map', 'landmark',
        'ocean', 'mountain', 'desert', 'river',
      ],
      environments: <String>['outdoors', 'street'],
      objects: <String>['globe', 'map', 'airplane', 'mountain'],
      shotGrammar: <String>['establishing', 'reveal', 'medium'],
      intents: <String>['explain', 'story'],
      mood: 'energetic',
    ),
    DomainStoryPack(
      id: 'biography_people',
      label: 'السير والشخصيات',
      subdomains: <String>['historical_figures', 'contemporary'],
      triggers: <String>[
        'سيرة', 'سيره', 'شخصية', 'شخصيه', 'شخصيات', 'حياة', 'حياه',
        'ولد', 'وُلد', 'توفي', 'توفى', 'نشأة', 'نشأه', 'قصة حياة',
        'biography', 'life', 'born', 'died', 'figure',
      ],
      environments: <String>['library', 'room', 'outdoors'],
      objects: <String>['books', 'frame', 'map'],
      shotGrammar: <String>['establishing', 'medium', 'closeUp'],
      intents: <String>['story', 'explain'],
      mood: 'calm',
      requiresSource: true,
      noFabricatedEvents: true,
    ),
    DomainStoryPack(
      id: 'culture_heritage',
      label: 'الثقافة والتراث',
      subdomains: <String>['traditions', 'crafts', 'architecture'],
      triggers: <String>[
        'ثقافة', 'ثقافه', 'تراث', 'عادات', 'تقاليد', 'حرف', 'حرفة', 'حرفه',
        'فنون شعبية', 'فن شعبي', 'زي', 'أزياء', 'ازياء', 'مطبخ', 'لهجة',
        'لهجه', 'تراثي',
        'culture', 'heritage', 'tradition', 'craft', 'custom',
      ],
      environments: <String>['street', 'room', 'outdoors'],
      objects: <String>['rug', 'lantern', 'books'],
      shotGrammar: <String>['establishing', 'detail', 'medium'],
      intents: <String>['explain', 'story'],
      mood: 'calm',
    ),
    DomainStoryPack(
      id: 'space_astronomy',
      label: 'الفضاء والفلك',
      subdomains: <String>['planets', 'stars', 'spacecraft'],
      triggers: <String>[
        'فضاء', 'فلك', 'كوكب', 'كواكب', 'نجم', 'نجوم', 'شمس', 'قمر',
        'مجرة', 'مجره', 'مجرات', 'صاروخ', 'مركبة', 'مركبه', 'رائد فضاء',
        'ناسا', 'مريخ', 'زحل', 'المشتري',
        'space', 'astronomy', 'planet', 'star', 'moon', 'galaxy',
        'rocket', 'nasa', 'mars',
      ],
      environments: <String>['studio', 'outdoors'],
      objects: <String>['rocket', 'moon_stars', 'globe', 'sun'],
      shotGrammar: <String>['establishing', 'reveal', 'detail'],
      intents: <String>['explain'],
      mood: 'calm',
      requiresSource: true,
    ),
    DomainStoryPack(
      id: 'engineering_inventions',
      label: 'الهندسة والاختراعات',
      subdomains: <String>['machines', 'bridges', 'engines'],
      triggers: <String>[
        'هندسة', 'هندسه', 'اختراع', 'اختراعات', 'آلة', 'اله', 'محرك',
        'محركات', 'جسر', 'جسور', 'بناء', 'تصميم', 'ميكانيكا', 'كهرباء',
        'engineering', 'invention', 'machine', 'engine', 'bridge',
        'design', 'mechanics',
      ],
      environments: <String>['studio', 'outdoors'],
      objects: <String>['gear', 'bulb', 'chart'],
      shotGrammar: <String>['detail', 'closeUp', 'medium'],
      intents: <String>['explain'],
      mood: 'calm',
    ),
    DomainStoryPack(
      id: 'law_civics',
      label: 'القانون والحقوق',
      subdomains: <String>['law', 'rights', 'civics'],
      triggers: <String>[
        'قانون', 'قوانين', 'محكمة', 'محكمه', 'قاضي', 'قاضيه', 'حقوق',
        'حق', 'دستور', 'مواطنة', 'مواطنه', 'عدالة', 'عداله', 'جريمة',
        'جريمه', 'عقوبة', 'عقوبه',
        'law', 'court', 'rights', 'justice', 'constitution', 'crime',
      ],
      environments: <String>['office', 'library'],
      objects: <String>['scales', 'books', 'shield'],
      shotGrammar: <String>['establishing', 'medium', 'detail'],
      intents: <String>['explain', 'warn'],
      mood: 'tense',
      requiresSource: true,
    ),
    DomainStoryPack(
      id: 'environment_climate',
      label: 'البيئة والمناخ',
      subdomains: <String>['climate', 'water', 'energy', 'pollution'],
      triggers: <String>[
        'بيئة', 'بيئه', 'مناخ', 'تغير مناخي', 'احتباس حراري', 'تلوث',
        'مياه', 'طاقة متجددة', 'طاقه متجدده', 'شمسية', 'شمسيه', 'رياح',
        'زراعة', 'زراعه', 'غابات', 'غابه', 'انبعاثات',
        'environment', 'climate', 'pollution', 'water', 'energy',
        'renewable', 'forest',
      ],
      environments: <String>['outdoors', 'street'],
      objects: <String>['tree', 'water', 'sun', 'cloud'],
      shotGrammar: <String>['establishing', 'reveal', 'detail'],
      intents: <String>['explain', 'warn'],
      mood: 'calm',
      requiresSource: true,
    ),
    DomainStoryPack(
      id: 'food_cooking',
      label: 'الطعام والطبخ',
      subdomains: <String>['recipes', 'ingredients', 'cuisines'],
      triggers: <String>[
        'طعام', 'أكل', 'اكل', 'طبخ', 'مطبخ', 'وصفة', 'وصفه', 'وصفات',
        'مكونات', 'مكون', 'حلويات', 'حلو', 'قهوة', 'قهوه', 'شاي',
        'فطور', 'غداء', 'عشاء',
        'food', 'cooking', 'recipe', 'ingredient', 'cuisine', 'coffee',
        'tea', 'meal',
      ],
      environments: <String>['room', 'studio'],
      objects: <String>['coffee', 'apple', 'plate'],
      shotGrammar: <String>['detail', 'closeUp', 'medium'],
      intents: <String>['explain', 'story'],
      mood: 'calm',
    ),
    DomainStoryPack(
      id: 'psychology_society',
      label: 'النفس والمجتمع',
      subdomains: <String>['psychology', 'society', 'relationships'],
      triggers: <String>[
        'نفس', 'نفسي', 'نفسيه', 'سلوك', 'سلوكي', 'مشاعر', 'علاقات',
        'علاقه', 'مجتمع', 'اجتماعي', 'اجتماعيه', 'أسرة', 'اسره', 'أسري',
        'اسري', 'صحة نفسية', 'صحه نفسيه', 'قلق', 'اكتئاب',
        'psychology', 'society', 'relationship', 'behavior', 'emotion',
        'family', 'anxiety',
      ],
      environments: <String>['room', 'studio'],
      objects: <String>['heart', 'chat', 'people'],
      shotGrammar: <String>['medium', 'closeUp', 'detail'],
      intents: <String>['explain', 'story'],
      mood: 'calm',
      requiresSource: true,
    ),
    DomainStoryPack(
      id: 'news_current_affairs',
      label: 'الأخبار والشأن الجاري',
      subdomains: <String>['politics', 'economy', 'world'],
      triggers: <String>[
        'خبر', 'أخبار', 'اخبار', 'حدث', 'أحداث', 'احداث', 'اليوم',
        'الآن', 'الان', 'عاجل', 'سياسة', 'سياسه', 'انتخابات', 'حكومة',
        'حكومه', 'رئيس', 'وزير',
        'news', 'breaking', 'politics', 'election', 'government',
        'president',
      ],
      environments: <String>['studio', 'street'],
      objects: <String>['megaphone', 'globe', 'chart'],
      shotGrammar: <String>['establishing', 'medium', 'detail'],
      intents: <String>['explain', 'warn'],
      mood: 'tense',
      requiresSource: true,
      noFabricatedEvents: true,
    ),
    DomainStoryPack(
      id: 'conflict_military_history',
      label: 'التاريخ العسكري',
      subdomains: <String>['wars', 'military', 'geopolitics'],
      triggers: <String>[
        'حرب', 'حروب', 'معركة', 'معركه', 'جيش', 'جيوش', 'عسكري',
        'عسكريه', 'سلاح', 'أسلحة', 'اسلحه', 'دفاع', 'غزو', 'احتلال',
        'war', 'battle', 'military', 'army', 'weapon', 'defense',
      ],
      environments: <String>['outdoors', 'library'],
      objects: <String>['shield', 'map', 'flag'],
      shotGrammar: <String>['establishing', 'detail', 'medium'],
      intents: <String>['explain', 'story'],
      mood: 'tense',
      requiresSource: true,
      noFabricatedEvents: true,
    ),
    DomainStoryPack(
      id: 'arts_media_entertainment',
      label: 'الفنون والإعلام',
      subdomains: <String>['cinema', 'music', 'design', 'games'],
      triggers: <String>[
        'فن', 'فنون', 'سينما', 'فيلم', 'أفلام', 'افلام', 'موسيقى',
        'موسيقي', 'أغنية', 'اغنيه', 'تصميم', 'رسم', 'ألعاب', 'العاب',
        'لعبة', 'لعبه', 'مسرح', 'مسرحية', 'مسرحيه',
        'art', 'cinema', 'film', 'music', 'song', 'design', 'game',
        'theater',
      ],
      environments: <String>['studio', 'room'],
      objects: <String>['camera', 'music', 'clapper', 'palette'],
      shotGrammar: <String>['establishing', 'detail', 'reveal'],
      intents: <String>['explain', 'story'],
      mood: 'energetic',
    ),
    DomainStoryPack(
      id: 'architecture_real_estate',
      label: 'العمارة والعقار',
      subdomains: <String>['architecture', 'interiors', 'real_estate'],
      triggers: <String>[
        'عمارة', 'عماره', 'معمار', 'معماري', 'مبنى', 'مباني', 'بيت',
        'منزل', 'شقة', 'شقه', 'عقار', 'تصميم داخلي', 'غرفة', 'غرفه',
        'مطبخ', 'حمام', 'صالة', 'صاله',
        'architecture', 'building', 'house', 'apartment', 'interior',
        'room', 'kitchen', 'bathroom',
      ],
      environments: <String>[
        'room', 'livingRoom', 'bedroom', 'kitchen', 'bathroom', 'hallway',
        'outdoors', 'street',
      ],
      objects: <String>['house', 'door', 'window', 'sofa'],
      shotGrammar: <String>['establishing', 'reveal', 'detail'],
      intents: <String>['explain'],
      mood: 'calm',
    ),
    DomainStoryPack(
      id: 'everyday_explainer',
      label: 'شرح الحياة اليومية',
      subdomains: <String>['mixed', 'general'],
      triggers: <String>[],
      environments: <String>['room', 'office', 'studio'],
      objects: <String>['clock', 'notebook', 'bulb'],
      shotGrammar: <String>['establishing', 'medium', 'closeUp'],
      intents: <String>['explain'],
      mood: 'calm',
    ),
  ];

  /// The pack with [id], or null when there is none.
  static DomainStoryPack? byId(String id) {
    for (final pack in all) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  /// The fallback pack (never null).
  static DomainStoryPack get fallback => byId(fallbackId)!;
}
