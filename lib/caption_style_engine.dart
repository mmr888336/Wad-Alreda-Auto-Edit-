/// Keeps one caption identity for an entire export.
///
/// Automatic mode resolves once from the topic profile. Explicit styles remain
/// unchanged from the first caption to the last caption in the same video.
class CaptionStyleEngine {
  CaptionStyleEngine._();

  static const styles = <String>{
    'classic',
    'cinematic',
    'bold_center',
    'boxed',
    'outline',
    'neon',
  };

  static String normalize(String value) {
    // Migrate legacy values saved by older app versions.
    switch (value) {
      case 'shadow':
        return 'boxed';
      case 'minimal':
        return 'classic';
      case 'classic':
      case 'cinematic':
      case 'bold_center':
      case 'boxed':
      case 'outline':
      case 'neon':
        return value;
      default:
        return 'classic';
    }
  }

  static String resolve({
    required String requestedStyle,
    required String automaticStyle,
  }) {
    if (requestedStyle == 'auto') {
      return normalize(automaticStyle);
    }
    return normalize(requestedStyle);
  }

  /// Multilingual default: Arabic uses an Arabic-first family; Latin,
  /// Cyrillic and Greek languages use a broad multilingual family.
  static String fontForLanguage(String requestedFont, String language) {
    if (requestedFont.isNotEmpty && requestedFont != 'auto') {
      return requestedFont;
    }
    return language.toLowerCase() == 'ar' ? 'Noto Sans Arabic' : 'Roboto';
  }
}
