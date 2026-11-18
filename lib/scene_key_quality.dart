import 'dart:typed_data';

/// How cleanly the flat background of a rendered 3D scene can be keyed out.
class KeyQuality {
  /// Share (0..1) of the pixels that are not background.
  final double foregroundShare;

  /// Share (0..1) of the non-background pixels held by the largest connected
  /// blob. A model keyed cleanly is one blob; a model whose dark parts were
  /// eaten by the key falls apart into scattered fragments.
  final double largestShare;

  /// Number of separate non-background blobs.
  final int blobCount;

  const KeyQuality({
    required this.foregroundShare,
    required this.largestShare,
    required this.blobCount,
  });

  /// True when the key leaves one solid subject of a useful size.
  bool get isClean =>
      foregroundShare >= SceneKeyQuality.minForegroundShare &&
      largestShare >= SceneKeyQuality.minLargestShare;
}

/// Checks a color key before it is used, so a scene that would leave
/// fragments of the model floating over the speaker is not keyed at all.
/// Pure Dart, no I/O.
class SceneKeyQuality {
  SceneKeyQuality._();

  /// Per-channel distance (0..255) at which a pixel still counts as the
  /// background; close to the key similarity used by the compositor.
  static const int tolerance = 31;

  /// Pixels with less alpha than this count as background.
  static const int minAlpha = 16;

  /// Less than this share of subject left means there is nothing to show.
  static const double minForegroundShare = 0.04;

  /// The largest blob must hold at least this share of the subject.
  static const double minLargestShare = 0.6;

  /// Parses `0xRRGGBB` (or `RRGGBB`) into an integer, or null if invalid.
  static int? parseColor(String value) {
    final text = value.startsWith('0x') || value.startsWith('0X')
        ? value.substring(2)
        : value;
    if (text.length != 6) return null;
    return int.tryParse(text, radix: 16);
  }

  /// Measures the subject that stays after keying [keyColors] out of an RGBA
  /// image. Without any valid key color nothing is removed.
  static KeyQuality measure(
    Uint8List rgba,
    int width,
    int height,
    List<String> keyColors,
  ) {
    final total = width * height;
    if (width <= 0 || height <= 0 || rgba.length < total * 4) {
      return const KeyQuality(
        foregroundShare: 0,
        largestShare: 0,
        blobCount: 0,
      );
    }

    final keys = <int>[
      for (final color in keyColors)
        if (parseColor(color) != null) parseColor(color)!,
    ];

    final subject = Uint8List(total);
    var subjectCount = 0;
    for (var i = 0; i < total; i++) {
      final o = i * 4;
      final r = rgba[o];
      final g = rgba[o + 1];
      final b = rgba[o + 2];
      final a = rgba[o + 3];
      var background = a < minAlpha;
      if (!background) {
        for (final key in keys) {
          if ((r - ((key >> 16) & 0xFF)).abs() <= tolerance &&
              (g - ((key >> 8) & 0xFF)).abs() <= tolerance &&
              (b - (key & 0xFF)).abs() <= tolerance) {
            background = true;
            break;
          }
        }
      }
      if (!background) {
        subject[i] = 1;
        subjectCount++;
      }
    }

    if (subjectCount == 0) {
      return const KeyQuality(
        foregroundShare: 0,
        largestShare: 0,
        blobCount: 0,
      );
    }

    // 4-connected blobs of subject pixels, found without recursion.
    final seen = Uint8List(total);
    final stack = <int>[];
    var largest = 0;
    var blobs = 0;
    for (var start = 0; start < total; start++) {
      if (subject[start] == 0 || seen[start] == 1) continue;
      blobs++;
      var size = 0;
      seen[start] = 1;
      stack.add(start);
      while (stack.isNotEmpty) {
        final index = stack.removeLast();
        size++;
        final x = index % width;
        final y = index ~/ width;
        if (x > 0) _visit(index - 1, subject, seen, stack);
        if (x < width - 1) _visit(index + 1, subject, seen, stack);
        if (y > 0) _visit(index - width, subject, seen, stack);
        if (y < height - 1) _visit(index + width, subject, seen, stack);
      }
      if (size > largest) largest = size;
    }

    return KeyQuality(
      foregroundShare: subjectCount / total,
      largestShare: largest / subjectCount,
      blobCount: blobs,
    );
  }

  static void _visit(
    int index,
    Uint8List subject,
    Uint8List seen,
    List<int> stack,
  ) {
    if (subject[index] == 1 && seen[index] == 0) {
      seen[index] = 1;
      stack.add(index);
    }
  }

  /// Returns [keyColors] when keying them out leaves one solid subject, and an
  /// empty list ("do not key") when it would leave fragments or nothing.
  static List<String> keepIfClean(
    Uint8List rgba,
    int width,
    int height,
    List<String> keyColors,
  ) {
    if (keyColors.isEmpty) return const <String>[];
    final quality = measure(rgba, width, height, keyColors);
    return quality.isClean ? keyColors : const <String>[];
  }
}
