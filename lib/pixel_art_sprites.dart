/// Code-generated pixel-art sprites (no downloads, no licensing, no network).
///
/// Every sprite is a small character grid plus a palette, so the shape is
/// always identical between exports. Sprites render to raw RGBA or to a PNG
/// that FFmpeg can overlay (use nearest-neighbour scaling, never smoothing).
///
/// Grid rule: '.' is always transparent; any other character must exist in
/// the sprite palette. Palette values are 0xAARRGGBB.
library;

import 'dart:io' show File, zlib;
import 'dart:typed_data';

class PixelSprite {
  final String key;
  final Map<String, int> palette;
  final List<String> rows;

  const PixelSprite({
    required this.key,
    required this.palette,
    required this.rows,
  });

  int get width => rows.isEmpty ? 0 : rows.first.length;
  int get height => rows.length;

  /// Throws [StateError] when the grid is empty, ragged or uses a character
  /// that is missing from the palette.
  void validate() {
    if (rows.isEmpty || width == 0) {
      throw StateError('Sprite $key has no pixels.');
    }
    for (var y = 0; y < rows.length; y++) {
      if (rows[y].length != width) {
        throw StateError(
          'Sprite $key row $y has width ${rows[y].length}, expected $width.',
        );
      }
      for (var x = 0; x < width; x++) {
        final c = rows[y][x];
        if (c != '.' && !palette.containsKey(c)) {
          throw StateError("Sprite $key uses unknown palette char '$c'.");
        }
      }
    }
  }

  /// Raw RGBA bytes, nearest-neighbour upscaled by [scale].
  Uint8List toRgba({int scale = 1}) {
    if (scale < 1) {
      throw ArgumentError.value(scale, 'scale', 'Scale must be at least 1.');
    }
    validate();
    final outW = width * scale;
    final outH = height * scale;
    final out = Uint8List(outW * outH * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final c = rows[y][x];
        if (c == '.') continue;
        final argb = palette[c]!;
        final a = (argb >> 24) & 0xFF;
        final r = (argb >> 16) & 0xFF;
        final g = (argb >> 8) & 0xFF;
        final b = argb & 0xFF;
        for (var dy = 0; dy < scale; dy++) {
          for (var dx = 0; dx < scale; dx++) {
            final i = (((y * scale + dy) * outW) + (x * scale + dx)) * 4;
            out[i] = r;
            out[i + 1] = g;
            out[i + 2] = b;
            out[i + 3] = a;
          }
        }
      }
    }
    return out;
  }

  /// Transparent PNG bytes, nearest-neighbour upscaled by [scale].
  Uint8List toPng({int scale = 1}) {
    final rgba = toRgba(scale: scale);
    return PixelPngEncoder.encodeRgba(
      rgba,
      width: width * scale,
      height: height * scale,
    );
  }

  /// Writes the PNG to [path] and returns the same path.
  Future<String> writePng(String path, {int scale = 1}) async {
    await File(path).writeAsBytes(toPng(scale: scale));
    return path;
  }
}

/// Minimal dependency-free PNG writer (8-bit RGBA, no interlace).
class PixelPngEncoder {
  PixelPngEncoder._();

  static List<int>? _crcTable;

  static List<int> _table() {
    final cached = _crcTable;
    if (cached != null) return cached;
    final table = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    _crcTable = table;
    return table;
  }

  static int _crc32(List<int> bytes) {
    final table = _table();
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static void _u32(BytesBuilder out, int value) {
    out.addByte((value >> 24) & 0xFF);
    out.addByte((value >> 16) & 0xFF);
    out.addByte((value >> 8) & 0xFF);
    out.addByte(value & 0xFF);
  }

  static void _chunk(BytesBuilder out, String type, List<int> data) {
    final typeBytes = type.codeUnits;
    _u32(out, data.length);
    out.add(typeBytes);
    out.add(data);
    _u32(out, _crc32(<int>[...typeBytes, ...data]));
  }

  static Uint8List encodeRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('PNG dimensions must be positive.');
    }
    if (rgba.length != width * height * 4) {
      throw ArgumentError('RGBA buffer does not match $width x $height.');
    }
    final raw = BytesBuilder(copy: false);
    final stride = width * 4;
    for (var y = 0; y < height; y++) {
      raw.addByte(0); // filter: none
      raw.add(Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
    }
    final ihdr = BytesBuilder();
    _u32(ihdr, width);
    _u32(ihdr, height);
    ihdr.add(const <int>[8, 6, 0, 0, 0]);

    final out = BytesBuilder();
    out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    _chunk(out, 'IHDR', ihdr.toBytes());
    _chunk(out, 'IDAT', zlib.encode(raw.toBytes()));
    _chunk(out, 'IEND', const <int>[]);
    return out.toBytes();
  }
}

/// The fixed sprite set. Keys match the asset keys used by the Motion Smith
/// reference blueprints (pixel_camera, pixel_red_heart, ...).
class PixelSprites {
  PixelSprites._();

  static const List<String> _mascotRows = <String>[
    '................',
    '................',
    '...oooooooooo...',
    '..oLLLLLLLLLLo..',
    '..oLOOOOOOOOLo..',
    '..oLOkkOOkkOLo..',
    '..oLOkwOOkwOLo..',
    '..oLOOOOOOOOLo..',
    '..oLOOmmmmOOLo..',
    '..oLOOOOOOOOLo..',
    '..oDDDDDDDDDDo..',
    '...oooooooooo...',
    '....ff....ff....',
    '...fff....fff...',
    '................',
    '................',
  ];
  static const List<String> _mascotBlinkRows = <String>[
    '................',
    '................',
    '...oooooooooo...',
    '..oLLLLLLLLLLo..',
    '..oLOOOOOOOOLo..',
    '..oLOOOOOOOOLo..',
    '..oLOkkOOkkOLo..',
    '..oLOOOOOOOOLo..',
    '..oLOOmmmmOOLo..',
    '..oLOOOOOOOOLo..',
    '..oDDDDDDDDDDo..',
    '...oooooooooo...',
    '....ff....ff....',
    '...fff....fff...',
    '................',
    '................',
  ];
  static const List<String> _cameraRows = <String>[
    '................',
    '................',
    '....gggg........',
    '..bbbbbbbbbbbb..',
    '.bbggggggggggbb.',
    '.bbgwwwwwwwwgbb.',
    '.bbgwkkkkkkwgbb.',
    '.bbgwkLLLLkwgbb.',
    '.bbgwkLLLLkwgbb.',
    '.bbgwkkkkkkwgbb.',
    '.bbgwwwwwwwwgbb.',
    '.bbggggggggggbb.',
    '..bbbbbbbbbbbb..',
    '................',
    '................',
    '................',
  ];
  static const List<String> _heartRows = <String>[
    '................',
    '................',
    '..rrrr....rrrr..',
    '.rRRRRr..rRRRRr.',
    'rRRwRRRrrRRRRRRr',
    'rRRRRRRRRRRRRRRr',
    'rRRRRRRRRRRRRRRr',
    '.rRRRRRRRRRRRRr.',
    '..rRRRRRRRRRRr..',
    '...rRRRRRRRRr...',
    '....rRRRRRRr....',
    '.....rRRRRr.....',
    '......rRRr......',
    '.......rr.......',
    '................',
    '................',
  ];
  static const List<String> _coinRows = <String>[
    '................',
    '................',
    '.....oooooo.....',
    '....oYYYYYYo....',
    '...oYYyyyyYYo...',
    '..oYYyYYYYyYYo..',
    '..oYyYYhhYYyYo..',
    '..oYyYYhhYYyYo..',
    '..oYyYYhhYYyYo..',
    '..oYyYYhhYYyYo..',
    '..oYYyYYYYyYYo..',
    '...oYYyyyyYYo...',
    '....oYYYYYYo....',
    '.....oooooo.....',
    '................',
    '................',
  ];
  static const List<String> _plantRows = <String>[
    '................',
    '....gg....gg....',
    '...gGGg..gGGg...',
    '..gGGGGggGGGGg..',
    '..gGGGGGGGGGGg..',
    '...gGGGGGGGGg...',
    '....gGGgGGGg....',
    '.....ggGGgg.....',
    '......gGg.......',
    '...tttttttttt...',
    '...tPPPPPPPPt...',
    '....tPPPPPPt....',
    '....tPPPPPPt....',
    '.....tPPPPt.....',
    '.....tttttt.....',
    '................',
  ];
  static const List<String> _controllerRows = <String>[
    '................',
    '................',
    '................',
    '..kkkkkkkkkkkk..',
    '.kGGGGGGGGGGGGk.',
    '.kGgGGGGGGGGrGk.',
    '.kgggGGGGGGrrrk.',
    '.kGgGGGGGGGGrGk.',
    '.kGGGGGGGGGGGGk.',
    '.kGGkkGGGGkkGGk.',
    '.kGkkGGGGGGkkGk.',
    '..kk..kkkk..kk..',
    '................',
    '................',
    '................',
    '................',
  ];

  static const Map<String, int> _mascotPalette = <String, int>{
    'o': 0xFF24150F,
    'L': 0xFFFFB866,
    'O': 0xFFFF9A32,
    'D': 0xFFD9741A,
    'k': 0xFF08090D,
    'w': 0xFFF7F5F2,
    'm': 0xFF08090D,
    'f': 0xFF24150F,
  };
  static const Map<String, int> _cameraPalette = <String, int>{
    'g': 0xFF4A4A56,
    'b': 0xFF2B2B33,
    'w': 0xFFF7F5F2,
    'k': 0xFF08090D,
    'L': 0xFF16E0C2,
  };
  static const Map<String, int> _heartPalette = <String, int>{
    'r': 0xFF8F0A1A,
    'R': 0xFFFF1838,
    'w': 0xFFFFB3BC,
  };
  static const Map<String, int> _coinPalette = <String, int>{
    'o': 0xFF5A3A08,
    'Y': 0xFFFFC93A,
    'y': 0xFFE0A010,
    'h': 0xFFFFF0A8,
  };
  static const Map<String, int> _plantPalette = <String, int>{
    'g': 0xFF1F6B3A,
    'G': 0xFF39B35B,
    't': 0xFF5A2E14,
    'P': 0xFFA85A2A,
  };
  static const Map<String, int> _controllerPalette = <String, int>{
    'k': 0xFF08090D,
    'G': 0xFF5C5F70,
    'g': 0xFF9A9DB0,
    'r': 0xFFE20D22,
  };

  static const PixelSprite orangeMascot = PixelSprite(
    key: 'pixel_orange_mascot',
    palette: _mascotPalette,
    rows: _mascotRows,
  );

  /// Same mascot with closed eyes, for blink / idle animation.
  static const PixelSprite orangeMascotBlink = PixelSprite(
    key: 'pixel_orange_mascot_blink',
    palette: _mascotPalette,
    rows: _mascotBlinkRows,
  );

  static const PixelSprite camera = PixelSprite(
    key: 'pixel_camera',
    palette: _cameraPalette,
    rows: _cameraRows,
  );

  static const PixelSprite redHeart = PixelSprite(
    key: 'pixel_red_heart',
    palette: _heartPalette,
    rows: _heartRows,
  );

  static const PixelSprite goldCoin = PixelSprite(
    key: 'pixel_gold_coin',
    palette: _coinPalette,
    rows: _coinRows,
  );

  static const PixelSprite pottedPlant = PixelSprite(
    key: 'pixel_potted_plant',
    palette: _plantPalette,
    rows: _plantRows,
  );

  static const PixelSprite gameController = PixelSprite(
    key: 'pixel_game_controller',
    palette: _controllerPalette,
    rows: _controllerRows,
  );

  static const List<PixelSprite> all = <PixelSprite>[
    orangeMascot,
    orangeMascotBlink,
    camera,
    redHeart,
    goldCoin,
    pottedPlant,
    gameController,
  ];

  /// Returns the sprite for [key], or null when the key is unknown.
  static PixelSprite? byKey(String key) {
    for (final sprite in all) {
      if (sprite.key == key) return sprite;
    }
    return null;
  }
}
