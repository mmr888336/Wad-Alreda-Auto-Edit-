/// Detailed set pieces of the 3D world.
///
/// The planner gives every set piece (desk, window, bookshelf...) ONE
/// primitive: a plain box or cylinder. This file describes what each known
/// piece is made of (a desk has a top, legs, an apron and a drawer; a window
/// has a frame, a glowing glass and mullions; a bookshelf has boards and
/// books...). Every part lives INSIDE the box of the piece (centre at the
/// origin, size [w] x [h] x [d]), so the bounds of the scene and the camera
/// framing never change. A piece that is not listed here returns null and
/// stays one primitive.
///
/// Pure Dart, no I/O: the GLB builder turns the parts into meshes.
library;

/// The two primitives the parts are made of.
enum SetPieceShape { box, cylinder }

/// One part of a set piece, in the local space of the piece (origin = the
/// centre of its box). A box has the full size ([sx], [sy], [sz]); a cylinder
/// has an elliptical section of diameters [sx] and [sz] and the height [sy]
/// (its axis is y).
class SetPiecePart {
  final SetPieceShape shape;
  final double cx;
  final double cy;
  final double cz;
  final double sx;
  final double sy;
  final double sz;
  final String color;
  final bool glow;

  const SetPiecePart(
    this.shape,
    this.cx,
    this.cy,
    this.cz,
    this.sx,
    this.sy,
    this.sz,
    this.color, {
    this.glow = false,
  });
}

class World3DSetPieces {
  World3DSetPieces._();

  /// The names (without the `decor:` prefix) that have detailed parts.
  static const Set<String> names = <String>{
    'desk',
    'window',
    'wall_clock',
    'bookshelf_left',
    'bookshelf_right',
    'ladder',
    'lamp_floor',
    'street_lamp',
    'building_row',
    'monitor_wall',
    'light_panel',
    'rug',
  };

  static const List<String> _bookColors = <String>[
    '#B5483B',
    '#2F6F8F',
    '#D9A441',
    '#4F7A4B',
    '#7B4F8F',
    '#C9C1B0',
  ];

  static const List<String> _screenColors = <String>[
    '#2AA9E0',
    '#1F7A8C',
    '#3AC6A8',
    '#2A6FDB',
    '#5AD1E6',
    '#1F9D8B',
  ];

  /// [hex] darkened by [factor] (0..1). A malformed colour gives black.
  static String shade(String hex, double factor) {
    if (hex.length != 7 || !hex.startsWith('#')) return '#000000';
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) return '#000000';
    String channel(int shift) => (((value >> shift) & 0xFF) * factor)
        .round()
        .clamp(0, 255)
        .toInt()
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return '#${channel(16)}${channel(8)}${channel(0)}';
  }

  /// The parts of the piece called [name] inside a box of [w] x [h] x [d]
  /// (the piece's own [color] is the main colour), or null when [name] has no
  /// detailed version.
  static List<SetPiecePart>? partsFor(
    String name,
    double w,
    double h,
    double d,
    String color,
  ) {
    switch (name) {
      case 'desk':
        return _desk(w, h, d, color);
      case 'window':
        return _window(w, h, d, color);
      case 'wall_clock':
        return _wallClock(w, h, d, color);
      case 'bookshelf_left':
      case 'bookshelf_right':
        return _bookshelf(w, h, d, color);
      case 'ladder':
        return _ladder(w, h, d, color);
      case 'lamp_floor':
        return _floorLamp(w, h, d, color);
      case 'street_lamp':
        return _streetLamp(w, h, d, color);
      case 'building_row':
        return _buildingRow(w, h, d, color);
      case 'monitor_wall':
        return _monitorWall(w, h, d, color);
      case 'light_panel':
        return _lightPanel(w, h, d, color);
      case 'rug':
        return _rug(w, h, d, color);
    }
    return null;
  }

  static SetPiecePart _box(
    double sx,
    double sy,
    double sz,
    double cx,
    double cy,
    double cz,
    String color, {
    bool glow = false,
  }) =>
      SetPiecePart(SetPieceShape.box, cx, cy, cz, sx, sy, sz, color, glow: glow);

  static SetPiecePart _cylinder(
    double sx,
    double sy,
    double sz,
    double cx,
    double cy,
    double cz,
    String color, {
    bool glow = false,
  }) =>
      SetPiecePart(
        SetPieceShape.cylinder,
        cx,
        cy,
        cz,
        sx,
        sy,
        sz,
        color,
        glow: glow,
      );

  // A top slab, four legs, an apron under the top and a drawer with a handle.
  static List<SetPiecePart> _desk(double w, double h, double d, String c) {
    final top = 0.22 * h;
    final legHeight = h - top;
    final apronCenterY = h / 2 - top - 0.06 * h;
    return <SetPiecePart>[
      _box(w, top, d, 0, h / 2 - top / 2, 0, c),
      for (final sx in <double>[-1, 1])
        for (final sz in <double>[-1, 1])
          _box(
            0.05 * w,
            legHeight,
            0.08 * d,
            sx * 0.475 * w,
            -h / 2 + legHeight / 2,
            sz * 0.46 * d,
            shade(c, 0.75),
          ),
      _box(0.9 * w, 0.12 * h, 0.92 * d, 0, apronCenterY, 0, shade(c, 0.85)),
      _box(0.3 * w, 0.09 * h, 0.02 * d, 0.22 * w, apronCenterY, 0.47 * d,
          shade(c, 0.7)),
      _box(0.08 * w, 0.03 * h, 0.02 * d, 0.22 * w, apronCenterY, 0.485 * d,
          '#C9B27A'),
    ];
  }

  // A frame (four bars), a glowing glass and a cross of mullions.
  static List<SetPiecePart> _window(double w, double h, double d, String c) {
    const frame = '#E8E2D5';
    final innerH = h - 0.16 * h;
    final innerW = w - 0.12 * w;
    return <SetPiecePart>[
      _box(w, 0.08 * h, d, 0, h / 2 - 0.04 * h, 0, frame),
      _box(w, 0.08 * h, d, 0, -h / 2 + 0.04 * h, 0, frame),
      _box(0.06 * w, innerH, d, -w / 2 + 0.03 * w, 0, 0, frame),
      _box(0.06 * w, innerH, d, w / 2 - 0.03 * w, 0, 0, frame),
      _box(innerW, innerH, 0.3 * d, 0, 0, 0, c, glow: true),
      _box(0.03 * w, innerH, 0.6 * d, 0, 0, 0, frame),
      _box(innerW, 0.04 * h, 0.6 * d, 0, 0, 0, frame),
    ];
  }

  // A dark bezel, a face set into its front and two hands.
  static List<SetPiecePart> _wallClock(
    double w,
    double h,
    double d,
    String c,
  ) {
    const dark = '#1B1B1F';
    return <SetPiecePart>[
      _box(w, h, 0.8 * d, 0, 0, -0.1 * d, '#2B2F36'),
      _box(0.86 * w, 0.76 * h, 0.2 * d, 0, 0, 0.4 * d, c),
      _box(0.05 * w, 0.32 * h, 0.1 * d, 0, 0.14 * h, 0.45 * d, dark),
      _box(0.26 * w, 0.07 * h, 0.1 * d, 0.1 * w, 0, 0.45 * d, dark),
    ];
  }

  // Two sides, a back, boards and rows of books of different heights.
  static List<SetPiecePart> _bookshelf(
    double w,
    double h,
    double d,
    String c,
  ) {
    final board = 0.03 * h;
    final innerWidth = 0.86 * w;
    final boardCenters = <double>[
      -h / 2 + board / 2,
      -h / 2 + 0.25 * h + board / 2,
      -h / 2 + 0.50 * h + board / 2,
      -h / 2 + 0.75 * h + board / 2,
      h / 2 - board / 2,
    ];

    final parts = <SetPiecePart>[
      _box(0.07 * w, h, d, -0.465 * w, 0, 0, c),
      _box(0.07 * w, h, d, 0.465 * w, 0, 0, c),
      _box(w, h, 0.05 * d, 0, 0, -0.475 * d, shade(c, 0.7)),
      for (final y in boardCenters)
        _box(innerWidth, board, 0.95 * d, 0, y, 0.025 * d, shade(c, 0.9)),
    ];

    const widths = <double>[0.15, 0.11, 0.17, 0.12, 0.14];
    const heights = <double>[0.82, 0.70, 0.90, 0.76, 0.85];
    for (var row = 0; row < 4; row++) {
      final bottom = boardCenters[row] + board / 2;
      final top = boardCenters[row + 1] - board / 2;
      final room = top - bottom;
      var x = -innerWidth / 2 + 0.04 * innerWidth;
      for (var k = 0; k < widths.length; k++) {
        final bookWidth = innerWidth * widths[k];
        final bookHeight = room * heights[k];
        parts.add(
          _box(
            bookWidth,
            bookHeight,
            0.7 * d,
            x + bookWidth / 2,
            bottom + bookHeight / 2,
            0,
            _bookColors[(row * widths.length + k) % _bookColors.length],
          ),
        );
        x += bookWidth;
      }
    }
    return parts;
  }

  // Two rails and seven rungs.
  static List<SetPiecePart> _ladder(double w, double h, double d, String c) {
    const rungs = 7;
    return <SetPiecePart>[
      _box(0.14 * w, h, d, -0.43 * w, 0, 0, shade(c, 0.9)),
      _box(0.14 * w, h, d, 0.43 * w, 0, 0, shade(c, 0.9)),
      for (var k = 0; k < rungs; k++)
        _box(0.72 * w, 0.05 * h, 0.6 * d, 0, -h / 2 + (k + 0.5) * h / rungs, 0, c),
    ];
  }

  // A base, a thin pole and a glowing shade.
  static List<SetPiecePart> _floorLamp(
    double w,
    double h,
    double d,
    String c,
  ) {
    const metal = '#2B2F36';
    return <SetPiecePart>[
      _cylinder(w, 0.04 * h, d, 0, -h / 2 + 0.02 * h, 0, metal),
      _cylinder(0.2 * w, 0.7 * h, 0.2 * d, 0, -h / 2 + 0.39 * h, 0, metal),
      _cylinder(w, 0.26 * h, d, 0, h / 2 - 0.13 * h, 0, c, glow: true),
    ];
  }

  // A base, a pole and a glowing head.
  static List<SetPiecePart> _streetLamp(
    double w,
    double h,
    double d,
    String c,
  ) {
    return <SetPiecePart>[
      _cylinder(w, 0.06 * h, d, 0, -h / 2 + 0.03 * h, 0, shade(c, 0.6)),
      _cylinder(0.5 * w, 0.94 * h, 0.5 * d, 0, -h / 2 + 0.47 * h, 0, shade(c, 0.8)),
      _cylinder(w, 0.06 * h, d, 0, h / 2 - 0.03 * h, 0, '#FFE9A8', glow: true),
    ];
  }

  // Four buildings of different heights with lit and dark windows.
  static List<SetPiecePart> _buildingRow(
    double w,
    double h,
    double d,
    String c,
  ) {
    const heights = <double>[0.75, 1.0, 0.85, 0.65];
    const tones = <double>[1.0, 0.85, 0.95, 0.75];
    final parts = <SetPiecePart>[];

    for (var i = 0; i < heights.length; i++) {
      final buildingHeight = heights[i] * h;
      final centerX = (-0.375 + 0.25 * i) * w;
      parts.add(
        _box(
          0.245 * w,
          buildingHeight,
          0.96 * d,
          centerX,
          -h / 2 + buildingHeight / 2,
          -0.02 * d,
          shade(c, tones[i]),
        ),
      );

      final rows = (heights[i] * 5).floor();
      final rowStep = buildingHeight / (rows + 1);
      for (var r = 0; r < rows; r++) {
        for (var col = 0; col < 2; col++) {
          final lit = (i * 3 + r * 2 + col) % 3 != 0;
          parts.add(
            _box(
              0.05 * w,
              0.05 * h,
              0.04 * d,
              centerX + (col == 0 ? -0.055 : 0.055) * w,
              -h / 2 + rowStep * (r + 1),
              0.48 * d,
              lit ? '#F7D774' : '#1B2733',
              glow: lit,
            ),
          );
        }
      }
    }
    return parts;
  }

  // A bezel with two rows of three glowing screens.
  static List<SetPiecePart> _monitorWall(
    double w,
    double h,
    double d,
    String c,
  ) {
    final parts = <SetPiecePart>[_box(w, h, 0.7 * d, 0, 0, -0.15 * d, c)];
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 3; col++) {
        parts.add(
          _box(
            0.29 * w,
            0.4 * h,
            0.3 * d,
            (-0.31 + 0.31 * col) * w,
            (row == 0 ? 0.23 : -0.23) * h,
            0.35 * d,
            _screenColors[(row * 3 + col) % _screenColors.length],
            glow: true,
          ),
        );
      }
    }
    return parts;
  }

  // A dark frame with a glowing panel set into it.
  static List<SetPiecePart> _lightPanel(
    double w,
    double h,
    double d,
    String c,
  ) {
    return <SetPiecePart>[
      _box(w, h, 0.7 * d, 0, 0, -0.15 * d, '#2B2F36'),
      _box(0.88 * w, 0.8 * h, 0.3 * d, 0, 0, 0.35 * d, c, glow: true),
    ];
  }

  // A darker border layer under a lighter pattern layer.
  static List<SetPiecePart> _rug(double w, double h, double d, String c) {
    return <SetPiecePart>[
      _box(w, 0.6 * h, d, 0, -0.2 * h, 0, shade(c, 0.8)),
      _box(0.86 * w, 0.4 * h, 0.86 * d, 0, 0.3 * h, 0, c),
    ];
  }
}
