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

  /// Visual styles currently implemented by TextRender.
  static const captionStyles = <String, String>{
    'classic': 'كلاسيكي أبيض',
    'bold_center': 'عريض بحدود قوية',
    'boxed': 'داخل صندوق',
    'outline': 'حدود فقط',
    'shadow': 'ظل قوي',
    'neon': 'نيون',
    'minimal': 'بسيط',
    'cinematic': 'سينمائي',
  };

  /// Fonts exposed in settings. Google Fonts loads them on demand; an
  /// offline/system fallback is used if downloading fails.
  static const captionFonts = <String, String>{
    'Cairo': 'Cairo — عربي',
    'Tajawal': 'Tajawal — عربي',
    'Noto Sans Arabic': 'Noto Sans Arabic — عربي',
    'Roboto': 'Roboto — متعدد اللغات',
    'Montserrat': 'Montserrat — متعدد اللغات',
    'Lato': 'Lato — متعدد اللغات',
  };

  /// Non-musical sound effect presets generated locally by SoundEffectGenerator.
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

  /// A generic title only; it is not a transcription of the audio.
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