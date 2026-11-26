import 'package:auto_edit/glb_inspector.dart';
import 'package:auto_edit/world3d_glb_builder.dart';
import 'package:auto_edit/world3d_model.dart';
import 'package:auto_edit/world3d_set_pieces.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:typed_data';

Map<String, dynamic> _json(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final length = data.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
      as Map<String, dynamic>;
}

int _primitiveCount(Uint8List bytes) {
  final json = _json(bytes);
  var count = 0;
  for (final mesh in json['meshes'] as List) {
    count += (mesh['primitives'] as List).length;
  }
  return count;
}

const double _w = 2.0;
const double _h = 1.0;
const double _d = 0.6;

void main() {
  group('parts', () {
    for (final name in World3DSetPieces.names) {
      test('$name: several parts, all inside the box of the piece', () {
        final parts = World3DSetPieces.partsFor(name, _w, _h, _d, '#6B4A2F')!;
        expect(parts.length, greaterThan(1));
        const tolerance = 1e-9;
        for (final p in parts) {
          expect(p.sx, greaterThan(0));
          expect(p.sy, greaterThan(0));
          expect(p.sz, greaterThan(0));
          expect(p.cx - p.sx / 2, greaterThanOrEqualTo(-_w / 2 - tolerance));
          expect(p.cx + p.sx / 2, lessThanOrEqualTo(_w / 2 + tolerance));
          expect(p.cy - p.sy / 2, greaterThanOrEqualTo(-_h / 2 - tolerance));
          expect(p.cy + p.sy / 2, lessThanOrEqualTo(_h / 2 + tolerance));
          expect(p.cz - p.sz / 2, greaterThanOrEqualTo(-_d / 2 - tolerance));
          expect(p.cz + p.sz / 2, lessThanOrEqualTo(_d / 2 + tolerance));
        }
      });
    }

    test('a name without a detailed version gives null', () {
      expect(World3DSetPieces.partsFor('cable_tray', _w, _h, _d, '#2B2F36'),
          isNull);
      expect(World3DSetPieces.partsFor('sun', _w, _h, _d, '#F5A524'), isNull);
      expect(World3DSetPieces.partsFor('nothing', _w, _h, _d, '#FFFFFF'),
          isNull);
    });

    test('the desk has a top, four legs, an apron, a drawer and a handle', () {
      final parts = World3DSetPieces.partsFor('desk', _w, _h, _d, '#6B4A2F')!;
      expect(parts, hasLength(8));
      final legs = parts.where(
        (p) => (p.sy - 0.78 * _h).abs() < 1e-9 && p.sx < 0.1 * _w,
      );
      expect(legs, hasLength(4));
    });

    test('the bookshelf holds many books of different colours', () {
      final parts =
          World3DSetPieces.partsFor('bookshelf_left', _w, _h, _d, '#5B3A22')!;
      expect(parts.length, greaterThanOrEqualTo(28));
      expect(parts.map((p) => p.color).toSet().length, greaterThanOrEqualTo(6));
    });

    test('the window glass glows, its frame does not', () {
      final parts = World3DSetPieces.partsFor('window', _w, _h, _d, '#8EC5E8')!;
      final glowing = parts.where((p) => p.glow).toList();
      expect(glowing, hasLength(1));
      expect(glowing.single.color, '#8EC5E8');
      expect(parts.where((p) => !p.glow).length, greaterThanOrEqualTo(6));
    });

    test('the buildings have lit windows that glow and dark ones that do not',
        () {
      final parts =
          World3DSetPieces.partsFor('building_row', _w, _h, _d, '#2C3E4C')!;
      expect(parts.where((p) => p.glow && p.color == '#F7D774'), isNotEmpty);
      expect(parts.where((p) => !p.glow && p.color == '#1B2733'), isNotEmpty);
      expect(parts.length, greaterThan(20));
    });

    test('the lamps are cylinders and the shade glows', () {
      final lamp = World3DSetPieces.partsFor('lamp_floor', _w, _h, _d, '#F5A524')!;
      expect(lamp.every((p) => p.shape == SetPieceShape.cylinder), isTrue);
      expect(lamp.where((p) => p.glow), hasLength(1));
      final street =
          World3DSetPieces.partsFor('street_lamp', _w, _h, _d, '#C9C9C9')!;
      expect(street.every((p) => p.shape == SetPieceShape.cylinder), isTrue);
      expect(street.where((p) => p.glow), hasLength(1));
    });

    test('shade darkens a colour and a malformed one gives black', () {
      expect(World3DSetPieces.shade('#FFFFFF', 0.5), '#808080');
      expect(World3DSetPieces.shade('#6B4A2F', 1.0), '#6B4A2F');
      expect(World3DSetPieces.shade('nope', 0.5), '#000000');
    });
  });

  group('in the GLB', () {
    const cylinders = <String>{'lamp_floor', 'street_lamp'};

    for (final name in World3DSetPieces.names) {
      test('$name: many primitives, same bounds as its box, a safe file', () {
        final piece = World3DObject(
          id: 'p',
          role: World3DRole.setPiece,
          shape: cylinders.contains(name)
              ? World3DShape.cylinder
              : World3DShape.box,
          assetKey: 'decor:$name',
          position: const Vec3(0, 1, -2),
          size: const Vec3(_w, _h, _d),
          color: '#6B4A2F',
        );
        final glb = World3DGlbBuilder.buildObjects(<World3DObject>[piece]);

        expect(_primitiveCount(glb.bytes), greaterThan(1));
        expect(glb.objectCount, 1);

        const tolerance = 1e-6;
        expect(glb.bounds.min.x, greaterThanOrEqualTo(-_w / 2 - tolerance));
        expect(glb.bounds.max.x, lessThanOrEqualTo(_w / 2 + tolerance));
        expect(glb.bounds.min.y, greaterThanOrEqualTo(1 - _h / 2 - tolerance));
        expect(glb.bounds.max.y, lessThanOrEqualTo(1 + _h / 2 + tolerance));
        expect(glb.bounds.min.z, greaterThanOrEqualTo(-2 - _d / 2 - tolerance));
        expect(glb.bounds.max.z, lessThanOrEqualTo(-2 + _d / 2 + tolerance));

        final report = GlbInspector.inspect(glb.bytes);
        expect(report.isSafe, isTrue, reason: report.rejection);
      });
    }

    test('a piece without a detailed version stays one primitive', () {
      const tray = World3DObject(
        id: 'tray',
        role: World3DRole.setPiece,
        shape: World3DShape.box,
        assetKey: 'decor:cable_tray',
        position: Vec3(0, 0, 0),
        size: Vec3(1, 0.1, 0.3),
        color: '#2B2F36',
      );
      final glb = World3DGlbBuilder.buildObjects(<World3DObject>[tray]);
      expect(_primitiveCount(glb.bytes), 1);
    });

    test('a sphere set piece (the sun) stays one primitive', () {
      const sun = World3DObject(
        id: 'sun',
        role: World3DRole.setPiece,
        shape: World3DShape.sphere,
        assetKey: 'decor:sun',
        position: Vec3(0, 3, -5),
        size: Vec3(1, 1, 1),
        color: '#F5A524',
      );
      final glb = World3DGlbBuilder.buildObjects(<World3DObject>[sun]);
      expect(_primitiveCount(glb.bytes), 1);
    });

    test('a plain box without an asset key is unchanged', () {
      const box = World3DObject(
        id: 'b',
        role: World3DRole.setPiece,
        shape: World3DShape.box,
        position: Vec3(0, 1, 0),
        size: Vec3(1, 1, 1),
        color: '#D7263D',
      );
      final glb = World3DGlbBuilder.buildObjects(<World3DObject>[box]);
      expect(_primitiveCount(glb.bytes), 1);
    });
  });
}
