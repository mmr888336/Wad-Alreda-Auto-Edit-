/// Topic-aware editing profiles for Wad Alreda AutoEdit.
///
/// Automatic mode uses local keyword scoring over the AI analysis already
/// available (title, description, captions and B-roll queries).
enum EditTopic {
  religious,
  educational,
  product,
  storytelling,
  travel,
  general,
}

class EditingProfile {
  final EditTopic topic;
  final String label;
  final String visualStyle;
  final String captionStyle;
  final bool punchZoom;
  final bool flashTransitions;
  final int maxBroll;
  final bool isAutomatic;

  const EditingProfile({
    required this.topic,
    required this.label,
    required this.visualStyle,
    required this.captionStyle,
    required this.punchZoom,
    required this.flashTransitions,
    required this.maxBroll,
    required this.isAutomatic,
  });
}

class EditingEngine {
  static const _profiles = <EditTopic, EditingProfile>{
    EditTopic.religious: EditingProfile(
      topic: EditTopic.religious,
      label: 'ديني وتأملي',
      visualStyle: 'clean',
      captionStyle: 'cinematic',
      punchZoom: false,
      flashTransitions: false,
      maxBroll: 3,
      isAutomatic: true,
    ),
    EditTopic.educational: EditingProfile(
      topic: EditTopic.educational,
      label: 'تعليمي وتوضيحي',
      visualStyle: 'clean',
      captionStyle: 'classic',
      punchZoom: false,
      flashTransitions: false,
      maxBroll: 4,
      isAutomatic: true,
    ),
    EditTopic.product: EditingProfile(
      topic: EditTopic.product,
      label: 'منتج وتقنية',
      visualStyle: 'vivid',
      captionStyle: 'bold_center',
      punchZoom: true,
      flashTransitions: true,
      maxBroll: 5,
      isAutomatic: true,
    ),
    EditTopic.storytelling: EditingProfile(
      topic: EditTopic.storytelling,
      label: 'قصة وتجربة',
      visualStyle: 'cinematic',
      captionStyle: 'cinematic',
      punchZoom: true,
      flashTransitions: false,
      maxBroll: 4,
      isAutomatic: true,
    ),
    EditTopic.travel: EditingProfile(
      topic: EditTopic.travel,
      label: 'سفر وطبيعة',
      visualStyle: 'vivid',
      captionStyle: 'bold_center',
      punchZoom: true,
      flashTransitions: true,
      maxBroll: 5,
      isAutomatic: true,
    ),
    EditTopic.general: EditingProfile(
      topic: EditTopic.general,
      label: 'متوازن عام',
      visualStyle: 'cinematic',
      captionStyle: 'classic',
      punchZoom: true,
      flashTransitions: false,
      maxBroll: 4,
      isAutomatic: true,
    ),
  };

  static const supportedVisualStyles = <String>{
    'clean',
    'cinematic',
    'vivid',
    'warm',
    'cool',
    'moody',
    'vintage',
    'mono',
    'dreamy',
  };

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _score(String text, List<String> terms) {
    var score = 0;
    for (final term in terms) {
      if (text.contains(term)) score++;
    }
    return score;
  }

  /// Manual local filters always override automatic topic selection.
  static EditingProfile select({
    required String content,
    required String requestedStyle,
  }) {
    if (requestedStyle != 'auto') {
      final style = supportedVisualStyles.contains(requestedStyle)
          ? requestedStyle
          : 'cinematic';
      return EditingProfile(
        topic: EditTopic.general,
        label: 'النمط اليدوي',
        visualStyle: style,
        captionStyle: 'classic',
        punchZoom: true,
        flashTransitions: true,
        maxBroll: 4,
        isAutomatic: false,
      );
    }

    final text = _normalize(content);
    final scores = <MapEntry<EditTopic, int>>[
      MapEntry(EditTopic.religious, _score(text, const [
        'اسلام', 'إسلام', 'ديني', 'القران', 'قران', 'حديث', 'الصلاة',
        'صلاة', 'النبي', 'الرسول', 'سيرة', 'سيره', 'الصحابة',
        'الصحابه', 'الله', 'توكل', 'رزق', 'ذنب', 'توبة', 'توبه',
        'الجنة', 'الجنه', 'النار', 'عبادة', 'عباده', 'إيمان', 'ايمان',
      ])),
      MapEntry(EditTopic.educational, _score(text, const [
        'تعليم', 'شرح', 'درس', 'معلومة', 'معلومه', 'دراسة', 'دراسه',
        'جامعة', 'جامعه', 'طالب', 'فسيولوجي', 'طب', 'طبي', 'كورس',
        'tutorial', 'explain', 'lesson', 'education', 'study', 'science',
        'medical',
      ])),
      MapEntry(EditTopic.product, _score(text, const [
        'منتج', 'شراء', 'متجر', 'سعر', 'عرض', 'متوفر', 'مايك',
        'مايكروفون', 'سماعة', 'سماعه', 'هاتف', 'جهاز', 'تسوق',
        'product', 'review', 'unboxing', 'buy', 'shop', 'sale',
        'gadget', 'microphone', 'smart', 'phone', 'laptop',
      ])),
      MapEntry(EditTopic.storytelling, _score(text, const [
        'قصة', 'قصه', 'حكاية', 'حكايه', 'تجربة', 'تجربه', 'موقف',
        'رحلة شخصية', 'حدث', 'يوم', 'story', 'journey', 'personal',
        'experience', 'documentary',
      ])),
      MapEntry(EditTopic.travel, _score(text, const [
        'سفر', 'سياحة', 'سياحه', 'مكان', 'مدينة', 'مدينه', 'بلد',
        'طبيعة', 'طبيعه', 'مناظر', 'travel', 'tourism', 'city',
        'nature', 'landscape', 'beach', 'mountain',
      ])),
    ];

    var bestTopic = EditTopic.general;
    var bestScore = 0;
    for (final entry in scores) {
      if (entry.value > bestScore) {
        bestTopic = entry.key;
        bestScore = entry.value;
      }
    }
    return _profiles[bestTopic]!;
  }
}
