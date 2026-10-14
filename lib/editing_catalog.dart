/// Selectable editing presets for Wad Alreda Studio.
/// Sound effects are generated from filtered noise, not music tracks.
class EditingCatalog {
  static const captionPositions = <String, String>{
    'middle': 'منتصف الشاشة',
    'bottom': 'أسفل الشاشة',
  };

  static const brollLayouts = <String, String>{
    'topPanel': 'B-roll في الأعلى والشخص في الأسفل',
    'fullScreen': 'B-roll يغطي الشاشة كاملة',
  };

  static const captionAnimations = <String, String>{
    'none': 'بدون حركة',
    'slideUp': 'دخول من الأسفل',
    'slideDown': 'دخول من الأعلى',
  };

  /// Visual styles for captions.
  /// These change appearance, not the words transcribed from the audio.
  static const captionStyles = <String, String>{
    'classic': 'كلاسيكي أبيض',
    'bold_center': 'عريض في المنتصف',
    'word_pop': 'بارز',
    'karaoke': 'كاريوكي',
    'boxed': 'داخل صندوق',
    'outline': 'حدود فقط',
    'shadow': 'ظل قوي',
    'neon': 'نيون',
    'minimal': 'بسيط',
    'cinematic': 'سينمائي',
    'typewriter': 'آلة كاتبة',
    'bounce': 'مرح',
    'fade': 'ناعم',
    'slide_up': 'صاعد',
    'slide_side': 'جانبي',
    'highlight_word': 'تظليل بارز',
    'underline': 'تسطير',
    'pill': 'شريط مستدير',
    'glass': 'زجاج داكن',
    'gradient': 'ذهبي',
    'double_line': 'تباين قوي',
    'large_hook': 'كبير',
    'compact': 'مضغوط',
    'lower_third': 'ثلث سفلي',
    'middle_safe': 'آمن للمنتصف',
    'split_phrase': 'عبارة بارزة',
    'soft_glow': 'وهج ناعم',
    'comic_pop': 'كوميك',
    'clean_white': 'أبيض نظيف',
    'high_contrast': 'تباين مرتفع',
  };

  /// Non-musical sound effect presets.
  /// The actual sounds are generated locally by SoundEffectGenerator.
  static const soundEffects = <String, String>{
    'whoosh_soft': 'وش ناعم',
    'whoosh_fast': 'وش سريع',
    'whoosh_low': 'وش منخفض',
    'swipe': 'سحب سريع',
    'air_rush': 'اندفاع هواء',
    'impact_soft': 'ضربة ناعمة',
    'impact_deep': 'ضربة عميقة',
    'click': 'نقرة',
    'tap': 'لمسة',
    'pop': 'فرقعة خفيفة',
    'tick': 'تكّة',
    'double_tick': 'تكّتان',
    'digital_blip': 'نبضة رقمية ضوضائية',
    'camera_shutter': 'غالق كاميرا',
    'paper_swipe': 'تقليب ورق',
    'page_flip': 'قلب صفحة',
    'transition_hit': 'ضربة انتقال',
    'flash_hit': 'ضربة وميض',
    'zoom_hit': 'ضربة تقريب',
    'cut_hit': 'ضربة قطع',
    'bubble_pop': 'فرقعة قصيرة',
    'riser_short': 'تصاعد قصير',
    'fall_short': 'هبوط قصير',
    'soft_thump': 'دقّة مكتومة',
    'dry_snap': 'طقطقة جافة',
    'cloth_swipe': 'احتكاك قماش',
    'low_thud': 'دقّة منخفضة',
    'high_tick': 'تكّة حادة',
    'short_rush': 'اندفاع قصير',
    'low_sweep': 'مسح منخفض',
    'none': 'بدون مؤثر صوتي',
  };

  /// Generic fallback hook. This is not a transcription.
  static String fallbackHook(String countryCode) {
    switch (countryCode.toUpperCase()) {
      case 'ES':
      case 'MX':
      case 'AR':
      case 'CO':
        return 'Mira hasta el final';

      case 'BR':
        return 'Assista até o fim';

      case 'PT':
        return 'Veja até ao fim';

      case 'FR':
        return 'Regardez jusqu’à la fin';

      case 'DE':
        return 'Bleib bis zum Ende';

      case 'IT':
        return 'Guarda fino alla fine';

      case 'NL':
        return 'Kijk tot het einde';

      case 'PL':
        return 'Oglądaj do końca';

      case 'SE':
        return 'Titta till slutet';

      case 'GR':
        return 'Δες μέχρι το τέλος';

      case 'RU':
        return 'Смотри до конца';

      case 'TR':
        return 'Sonuna kadar izle';

      default:
        return 'خليك للنهاية';
    }
  }
}
