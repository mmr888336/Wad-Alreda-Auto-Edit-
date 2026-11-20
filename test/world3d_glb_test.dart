import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/glb_inspector.dart';
import 'package:auto_edit/story_understanding.dart';
import 'package:auto_edit/world3d_glb_builder.dart';
import 'package:auto_edit/world3d_model.dart';
import 'package:auto_edit/world3d_planner.dart';
import 'package:flutter_test/flutter_test.dart';

WorldScene _scene() {
  return WorldScene(
    beatIndex: 0,
    environment: StoryEnvironment.office,
    continuesPreviousScene: false,
    look: CinematicWorld.lookFor(
      StoryEnvironment.office,
      StoryMood.calm,
      const WorldPalette(),
    ),
    layers: const <WorldLayerSpec>[
      WorldLayerSpec(
        id: 'w0_backdrop',
        assetKey: 'bg:office',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.0,
        zIndex: 0,
      ),
      WorldLayerSpec(
        id: 'w0_set0',
        assetKey: 'decor:desk',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.12,
        zIndex: 1,
      ),
      WorldLayerSpec(
        id: 'w0_set1',
        assetKey: 'decor:window',
        x: 0.5,
        y: 0.5,
        scale: 1.0,
        depth: 0.18,
        zIndex: 2,
      ),
      WorldLayerSpec(
        id: 'w0_hero',
        assetKey: 'sprite:hero',
        x: 0.5,
        y: 0.62,
        scale: 0.42,
        depth: 0.62,
        zIndex: 20,
      ),
      WorldLayerSpec(
        id: 'w0_prop0',
        assetKey: 'decor:coins',
        x: 0.2,
        y: 0.74,
        scale: 0.2,
        depth: 0.38,
        zIndex: 10,
      ),
    ],
  );
}

/// Only the signature and the IHDR size matter to the builder and to the
/// inspector, so a header is enough for these tests.
Uint8List _pngHeader() {
  final bytes = Uint8List(33);
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    bytes[i] = signature[i];
  }
  final data = ByteData.sublistView(bytes);
  data.setUint32(8, 13, Endian.big);
  data.setUint32(12, 0x49484452, Endian.big);
  data.setUint32(16, 64, Endian.big);
  data.setUint32(20, 64, Endian.big);
  return bytes;
}

Map<String, dynamic> _json(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final length = data.getUint32(12, Endian.little);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
      as Map<String, dynamic>;
}

const World3DObject _redBox = World3DObject(
  id: 'a',
  role: World3DRole.setPiece,
  shape: World3DShape.box,
  position: Vec3(0, 1, -2),
  size: Vec3(1, 2, 3),
  color: '#D7263D',
);

void main() {
  group('GLB file', () {
    test('the inspector accepts it and the numbers match', () {
      final scene = World3DPlanner.plan(_scene());
      final glb = World3DGlbBuilder.build(scene);
      final report = GlbInspector.inspect(glb.bytes);
      expect(report.isSafe, isTrue, reason: report.rejection);
      expect(report.byteLength, glb.bytes.length);
      expect(report.vertexCount, glb.vertexCount);
      expect(report.imageCount, 0);
      expect(report.extensionsRequired, isEmpty);
      expect(report.animationCount, 0);
    });

    test('every object gets a node; a prop without a picture is skipped', () {
      final scene = World3DPlanner.plan(_scene());
      final glb = World3DGlbBuilder.build(scene);
      expect(scene.objects, hasLength(6));
      expect(glb.objectCount, 5);
      expect(glb.skipped, hasLength(1));
      expect(glb.skipped.single, startsWith('w0_prop0'));
      final json = _json(glb.bytes);
      expect((json['nodes'] as List), hasLength(5));
      expect((json['scenes'] as List).single['nodes'], <int>[0, 1, 2, 3, 4]);
    });

    test('the structure is valid glTF 2.0', () {
      final glb = World3DGlbBuilder.build(World3DPlanner.plan(_scene()));
      final bytes = glb.bytes;
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(0, Endian.little), 0x46546C67);
      expect(data.getUint32(4, Endian.little), 2);
      expect(data.getUint32(8, Endian.little), bytes.length);
      expect(data.getUint32(12, Endian.little) % 4, 0);

      final jsonLength = data.getUint32(12, Endian.little);
      final binLength = data.getUint32(20 + jsonLength, Endian.little);
      expect(data.getUint32(24 + jsonLength, Endian.little), 0x004E4942);
      expect(binLength % 4, 0);
      expect(28 + jsonLength + binLength, bytes.length);

      final json = _json(bytes);
      expect(json['asset']['version'], '2.0');
      expect(json['buffers'][0]['byteLength'], binLength);

      final views = json['bufferViews'] as List;
      for (final view in views) {
        expect(view['byteOffset'] % 4, 0);
        expect(view['byteOffset'] + view['byteLength'], lessThanOrEqualTo(binLength));
      }

      final accessors = json['accessors'] as List;
      final meshes = json['meshes'] as List;
      final materials = json['materials'] as List;
      for (final mesh in meshes) {
        for (final primitive in mesh['primitives']) {
          final attributes = primitive['attributes'] as Map;
          final position = accessors[attributes['POSITION']];
          final normal = accessors[attributes['NORMAL']];
          final indices = accessors[primitive['indices']];
          expect(position['type'], 'VEC3');
          expect(position['min'], hasLength(3));
          expect(position['max'], hasLength(3));
          expect(normal['count'], position['count']);
          expect(indices['count'] % 3, 0);
          expect(indices['componentType'], 5123);
          expect(views[position['bufferView']]['target'], 34962);
          expect(views[indices['bufferView']]['target'], 34963);
          expect(primitive['material'], lessThan(materials.length));
        }
      }
    });

    test('the character is built from six parts with three materials', () {
      final glb = World3DGlbBuilder.build(World3DPlanner.plan(_scene()));
      final json = _json(glb.bytes);
      final nodes = json['nodes'] as List;
      final hero = nodes.firstWhere((n) => n['name'] == 'w0_hero');
      final mesh = (json['meshes'] as List)[hero['mesh']];
      final primitives = mesh['primitives'] as List;
      expect(primitives, hasLength(6));
      final used = <int>{for (final p in primitives) p['material'] as int};
      expect(used, hasLength(3));
    });

    test('the position is baked into the vertices, not into the node', () {
      final glb = World3DGlbBuilder.buildObjects(<World3DObject>[_redBox]);
      final json = _json(glb.bytes);
      final node = (json['nodes'] as List).single as Map;
      expect(node.containsKey('translation'), isFalse);
      expect(node.containsKey('rotation'), isFalse);
      expect(node.containsKey('scale'), isFalse);
      final position = (json['accessors'] as List).first as Map;
      expect(position['min'], <double>[-0.5, 0.0, -3.5]);
      expect(position['max'], <double>[0.5, 2.0, -0.5]);
    });

    test('the bounds cover every object', () {
      final glb = World3DGlbBuilder.buildObjects(<World3DObject>[_redBox]);
      expect(glb.bounds.min.x, closeTo(-0.5, 1e-9));
      expect(glb.bounds.min.y, closeTo(0.0, 1e-9));
      expect(glb.bounds.min.z, closeTo(-3.5, 1e-9));
      expect(glb.bounds.max.x, closeTo(0.5, 1e-9));
      expect(glb.bounds.max.y, closeTo(2.0, 1e-9));
      expect(glb.bounds.max.z, closeTo(-0.5, 1e-9));
      expect(glb.bounds.maxExtent, closeTo(3.0, 1e-9));
      expect(glb.animated, isFalse);
      expect(glb.animationSeconds, 0);
    });

    test('materials of the same colour are shared and colours are linear', () {
      const twin = World3DObject(
        id: 'b',
        role: World3DRole.setPiece,
        shape: World3DShape.box,
        position: Vec3(1, 1, 0),
        size: Vec3(1, 1, 1),
        color: '#D7263D',
      );
      final glb = World3DGlbBuilder.buildObjects(<World3DObject>[_redBox, twin]);
      final materials = _json(glb.bytes)['materials'] as List;
      expect(materials, hasLength(1));
      final factor =
          materials.single['pbrMetallicRoughness']['baseColorFactor'] as List;
      // 0xD7 = 215 -> sRGB 0.843 -> linear 0.680.
      expect(factor[0], closeTo(0.680, 0.002));
      expect(factor[3], 1.0);
    });

    test('windows glow', () {
      const window = World3DObject(
        id: 'win',
        role: World3DRole.setPiece,
        shape: World3DShape.box,
        assetKey: 'decor:window',
        position: Vec3(0, 1, -4),
        size: Vec3(1, 1, 0.1),
        color: '#8EC5E8',
      );
      final glb = World3DGlbBuilder.buildObjects(<World3DObject>[window]);
      final material = (_json(glb.bytes)['materials'] as List).single;
      expect(material['emissiveFactor'], hasLength(3));
    });
  });

  group('pictures', () {
    test('a prop with a PNG becomes a textured quad', () {
      final scene = World3DPlanner.plan(_scene());
      final glb = World3DGlbBuilder.build(
        scene,
        billboardImages: <String, Uint8List>{'decor:coins': _pngHeader()},
      );
      expect(glb.skipped, isEmpty);
      expect(glb.objectCount, 6);
      expect(glb.textureCount, 1);

      final report = GlbInspector.inspect(glb.bytes);
      expect(report.isSafe, isTrue, reason: report.rejection);
      expect(report.imageCount, 1);
      expect(report.vertexCount, glb.vertexCount);

      final json = _json(glb.bytes);
      expect(json['images'], hasLength(1));
      expect(json['images'][0]['mimeType'], 'image/png');
      expect(json['textures'][0]['source'], 0);
      expect(json['samplers'], hasLength(1));
      final textured = (json['materials'] as List).firstWhere(
        (m) => (m['pbrMetallicRoughness'] as Map).containsKey('baseColorTexture'),
      );
      expect(textured['alphaMode'], 'BLEND');
      expect(textured['doubleSided'], true);

      final nodes = json['nodes'] as List;
      final prop = nodes.firstWhere((n) => n['name'] == 'w0_prop0');
      final primitive = (json['meshes'] as List)[prop['mesh']]['primitives'][0];
      expect((primitive['attributes'] as Map).containsKey('TEXCOORD_0'), isTrue);
    });

    test('bytes that are not a PNG are skipped', () {
      final scene = World3DPlanner.plan(_scene());
      final glb = World3DGlbBuilder.build(
        scene,
        billboardImages: <String, Uint8List>{
          'decor:coins': Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]),
        },
      );
      expect(glb.textureCount, 0);
      expect(glb.skipped.single, contains('not a PNG'));
    });
  });

  group('safety', () {
    test('nothing drawable throws, so the caller keeps 2.5D', () {
      expect(
        () => World3DGlbBuilder.buildObjects(const <World3DObject>[]),
        throwsStateError,
      );
    });

    test('an invalid object is skipped, the rest is written', () {
      final broken = World3DObject(
        id: 'broken',
        role: World3DRole.setPiece,
        shape: World3DShape.box,
        position: const Vec3(0, 0, 0),
        size: Vec3(double.nan, 1, 1),
        color: '#FFFFFF',
      );
      const flat = World3DObject(
        id: 'flat',
        role: World3DRole.setPiece,
        shape: World3DShape.box,
        position: Vec3(0, 0, 0),
        size: Vec3(1, 0, 1),
        color: '#FFFFFF',
      );
      final glb = World3DGlbBuilder.buildObjects(
        <World3DObject>[broken, flat, _redBox],
      );
      expect(glb.objectCount, 1);
      expect(glb.skipped, hasLength(2));
      expect(GlbInspector.inspect(glb.bytes).isSafe, isTrue);
    });

    test('the segment count is kept in a safe range', () {
      const sphere = World3DObject(
        id: 's',
        role: World3DRole.setPiece,
        shape: World3DShape.sphere,
        position: Vec3(0, 1, 0),
        size: Vec3(1, 1, 1),
        color: '#F5A524',
      );
      final coarse =
          World3DGlbBuilder.buildObjects(<World3DObject>[sphere], segments: 1);
      final fine =
          World3DGlbBuilder.buildObjects(<World3DObject>[sphere], segments: 9999);
      expect(coarse.vertexCount, greaterThan(0));
      expect(fine.vertexCount, greaterThan(coarse.vertexCount));
      expect(fine.vertexCount, lessThan(65535));
    });
  });

  group('meshes', () {
    const size = Vec3(2, 4, 6);

    ({List<double> lo, List<double> hi}) extent(List<double> p) {
      final lo = <double>[double.infinity, double.infinity, double.infinity];
      final hi = <double>[
        double.negativeInfinity,
        double.negativeInfinity,
        double.negativeInfinity,
      ];
      for (var i = 0; i < p.length; i += 3) {
        for (var a = 0; a < 3; a++) {
          lo[a] = math.min(lo[a], p[i + a]);
          hi[a] = math.max(hi[a], p[i + a]);
        }
      }
      return (lo: lo, hi: hi);
    }

    for (final shape in <World3DShape>[
      World3DShape.box,
      World3DShape.sphere,
      World3DShape.cylinder,
      World3DShape.billboard,
    ]) {
      test('$shape: unit normals and triangles that face outward', () {
        final mesh = World3DGlbBuilder.debugMesh(shape, size);
        final p = mesh.positions;
        final n = mesh.normals;
        expect(p.length, n.length);
        expect(mesh.indices.length % 3, 0);

        for (var i = 0; i < n.length; i += 3) {
          final length =
              math.sqrt(n[i] * n[i] + n[i + 1] * n[i + 1] + n[i + 2] * n[i + 2]);
          expect(length, closeTo(1.0, 1e-9));
        }

        var checked = 0;
        for (var t = 0; t < mesh.indices.length; t += 3) {
          final a = mesh.indices[t] * 3;
          final b = mesh.indices[t + 1] * 3;
          final c = mesh.indices[t + 2] * 3;
          final e1 = <double>[p[b] - p[a], p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]];
          final e2 = <double>[p[c] - p[a], p[c + 1] - p[a + 1], p[c + 2] - p[a + 2]];
          final cross = <double>[
            e1[1] * e2[2] - e1[2] * e2[1],
            e1[2] * e2[0] - e1[0] * e2[2],
            e1[0] * e2[1] - e1[1] * e2[0],
          ];
          final area = math.sqrt(
            cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2],
          );
          if (area < 1e-9) continue;
          final average = <double>[
            n[a] + n[b] + n[c],
            n[a + 1] + n[b + 1] + n[c + 1],
            n[a + 2] + n[b + 2] + n[c + 2],
          ];
          final dot = cross[0] * average[0] +
              cross[1] * average[1] +
              cross[2] * average[2];
          expect(dot, greaterThan(0), reason: 'triangle $t faces inward');
          checked++;
        }
        expect(checked, greaterThan(0));
      });
    }

    test('the box fills its size exactly', () {
      final e = extent(World3DGlbBuilder.debugMesh(World3DShape.box, size).positions);
      expect(e.lo, <double>[-1, -2, -3]);
      expect(e.hi, <double>[1, 2, 3]);
    });

    test('the sphere is an ellipsoid of its size', () {
      final e =
          extent(World3DGlbBuilder.debugMesh(World3DShape.sphere, size).positions);
      for (var a = 0; a < 3; a++) {
        expect(e.hi[a], closeTo(size.x * (a == 0 ? 0.5 : a == 1 ? 1.0 : 1.5), 1e-9));
        expect(e.lo[a], closeTo(-e.hi[a], 1e-9));
      }
    });

    test('the cylinder is as tall as size.y with an elliptical section', () {
      final e = extent(
        World3DGlbBuilder.debugMesh(World3DShape.cylinder, size).positions,
      );
      expect(e.hi[1], closeTo(2.0, 1e-9));
      expect(e.lo[1], closeTo(-2.0, 1e-9));
      expect(e.hi[0], closeTo(1.0, 1e-9));
      expect(e.hi[2], closeTo(3.0, 1e-9));
    });
  });
}
