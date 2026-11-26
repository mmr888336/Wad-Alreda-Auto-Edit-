/// World 3D GLB builder: writes a real 3D scene as ONE binary glTF (GLB).
///
/// The Filament plugin loads a GLB file with `loadModelFromFile`, so a 3D
/// world built here (back wall, floor, set pieces, the recurring character,
/// props) is rendered by the plugin that already exists, with no native change.
///
///  * box, sphere and cylinder set pieces become real meshes with normals;
///    the known ones (desk, window, bookshelf, lamps, buildings...) are built
///    from several detailed parts that stay inside the box of the piece (see
///    world3d_set_pieces.dart);
///  * the character is assembled from rounded parts (shoes, legs, belt, torso,
///    shoulders, arms, hands, neck, head, hair and a face with eyes, nose and
///    mouth), each with its own material;
///  * a prop (billboard) becomes a textured quad when the caller supplies its
///    picture (PNG bytes, keyed by the asset key of the layer); without a
///    picture it is skipped and listed in [World3DGlb.skipped];
///  * windows, the sun, light panels, lamps and lit windows glow (emissive);
///  * materials with the same colour are shared;
///  * object positions are baked into the vertices, so the bounds the native
///    loader computes (and rescales to a unit cube) never depend on node
///    transforms;
///  * with a camera path ([World3DCameraPath]) and a duration, the whole world
///    hangs under one "world_rig" node that carries a translation + rotation
///    animation: the inverse of the camera move (see world3d_rig.dart). The
///    fixed native camera then sees a real 3D camera move.
///
/// The file is plain glTF 2.0 (no extensions), so [GlbInspector] and the
/// native engine accept it. A scene with nothing drawable throws a
/// [StateError]: the caller then keeps the 2.5D scene (see RenderRouter).
/// Pure Dart, no I/O.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'world3d_model.dart';
import 'world3d_planner.dart' show World3DScene;
import 'world3d_rig.dart';
import 'world3d_set_pieces.dart';

/// A finished GLB and what went into it.
class World3DGlb {
  final Uint8List bytes;

  /// Objects written to the file (one node each).
  final int objectCount;
  final int vertexCount;
  final int triangleCount;
  final int textureCount;

  /// Objects left out, each as `id: reason`.
  final List<String> skipped;

  /// Bounds of everything in the file, in world units.
  final World3DBounds bounds;

  /// True when the file carries the camera rig animation.
  final bool animated;

  /// Length of the rig animation including its holds (0 when not animated).
  final double animationSeconds;

  const World3DGlb({
    required this.bytes,
    required this.objectCount,
    required this.vertexCount,
    required this.triangleCount,
    required this.textureCount,
    required this.skipped,
    required this.bounds,
    this.animated = false,
    this.animationSeconds = 0,
  });
}

class _Mesh {
  final List<double> positions = <double>[];
  final List<double> normals = <double>[];
  final List<double> uvs = <double>[];
  final List<int> indices = <int>[];

  int get vertexCount => positions.length ~/ 3;

  bool get hasUvs => uvs.isNotEmpty;

  void vertex(
    double x,
    double y,
    double z,
    double nx,
    double ny,
    double nz, {
    double? u,
    double? v,
  }) {
    positions
      ..add(x)
      ..add(y)
      ..add(z);
    normals
      ..add(nx)
      ..add(ny)
      ..add(nz);
    if (u != null && v != null) {
      uvs
        ..add(u)
        ..add(v);
    }
  }

  void triangle(int a, int b, int c) {
    indices
      ..add(a)
      ..add(b)
      ..add(c);
  }

  void shift(double dx, double dy, double dz) {
    for (var i = 0; i < positions.length; i += 3) {
      positions[i] += dx;
      positions[i + 1] += dy;
      positions[i + 2] += dz;
    }
  }
}

class _Part {
  final _Mesh mesh;
  final String color;
  final bool glow;
  final String? imageKey;
  final Uint8List? png;

  const _Part(
    this.mesh,
    this.color, {
    this.glow = false,
    this.imageKey,
    this.png,
  });
}

/// Growing binary buffer: every view starts on a 4-byte boundary.
class _Bin {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final List<Map<String, Object>> views = <Map<String, Object>>[];

  int addView(Uint8List data, {int? target}) {
    while (_bytes.length % 4 != 0) {
      _bytes.addByte(0);
    }
    final offset = _bytes.length;
    _bytes.add(data);
    views.add(<String, Object>{
      'buffer': 0,
      'byteOffset': offset,
      'byteLength': data.length,
      if (target != null) 'target': target,
    });
    return views.length - 1;
  }

  Uint8List finish() {
    while (_bytes.length % 4 != 0) {
      _bytes.addByte(0);
    }
    return _bytes.takeBytes();
  }
}

class World3DGlbBuilder {
  World3DGlbBuilder._();

  /// Pictures glow instead of only reflecting light.
  static const Set<String> _glowKeys = <String>{
    'decor:window',
    'decor:sun',
    'decor:light_panel',
  };

  static const String _skin = '#F1C7A1';
  static const String _hair = '#2B1B12';
  static const String _shoe = '#23232B';
  static const String _eye = '#14121A';
  static const String _mouth = '#A5524A';

  /// The GLB of [scene]. [billboardImages] maps the asset key of a prop layer
  /// (`decor:coins`) to the PNG bytes of its picture. With [cameraSeconds] the
  /// file also carries the camera move of the scene as a rig animation.
  static World3DGlb build(
    World3DScene scene, {
    Map<String, Uint8List> billboardImages = const <String, Uint8List>{},
    int segments = 20,
    double? cameraSeconds,
    double holdStart = 0.5,
    double holdEnd = 0.5,
    int cameraFps = 30,
  }) {
    return buildObjects(
      scene.objects,
      billboardImages: billboardImages,
      segments: segments,
      camera: cameraSeconds == null ? null : scene.camera,
      cameraSeconds: cameraSeconds,
      holdStart: holdStart,
      holdEnd: holdEnd,
      cameraFps: cameraFps,
    );
  }

  /// The GLB of [objects]. Throws [StateError] when none can be drawn.
  ///
  /// The rig animation is written only when [camera] is active and
  /// [cameraSeconds] is given.
  static World3DGlb buildObjects(
    List<World3DObject> objects, {
    Map<String, Uint8List> billboardImages = const <String, Uint8List>{},
    int segments = 20,
    World3DCameraPath? camera,
    double? cameraSeconds,
    double holdStart = 0.5,
    double holdEnd = 0.5,
    int cameraFps = 30,
  }) {
    final seg = segments < 6 ? 6 : (segments > 48 ? 48 : segments);
    final bin = _Bin();
    final accessors = <Map<String, Object>>[];
    final materials = <Map<String, Object>>[];
    final materialIndex = <String, int>{};
    final images = <Map<String, Object>>[];
    final imageIndex = <String, int>{};
    final meshes = <Map<String, Object>>[];
    final nodes = <Map<String, Object>>[];
    final skipped = <String>[];
    var vertexTotal = 0;
    var triangleTotal = 0;

    final boundsLo = <double>[double.infinity, double.infinity, double.infinity];
    final boundsHi = <double>[
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    ];

    int addAccessor(Map<String, Object> accessor) {
      accessors.add(accessor);
      return accessors.length - 1;
    }

    int imageFor(String key, Uint8List png) {
      return imageIndex.putIfAbsent(key, () {
        final view = bin.addView(png);
        images.add(<String, Object>{
          'bufferView': view,
          'mimeType': 'image/png',
        });
        return images.length - 1;
      });
    }

    int materialFor(_Part part) {
      final key = '${part.color}|${part.glow}|${part.imageKey ?? ''}';
      final existing = materialIndex[key];
      if (existing != null) return existing;

      final linear = _linearRgb(part.color);
      final textured = part.imageKey != null && part.png != null;
      final pbr = <String, Object>{
        'baseColorFactor': textured
            ? <double>[1.0, 1.0, 1.0, 1.0]
            : <double>[linear[0], linear[1], linear[2], 1.0],
        'metallicFactor': 0.0,
        'roughnessFactor': 0.9,
      };
      if (textured) {
        pbr['baseColorTexture'] = <String, Object>{
          'index': imageFor(part.imageKey!, part.png!),
        };
      }
      final material = <String, Object>{
        'name': key,
        'pbrMetallicRoughness': pbr,
      };
      if (part.glow) {
        material['emissiveFactor'] = <double>[
          linear[0] * 0.55,
          linear[1] * 0.55,
          linear[2] * 0.55,
        ];
      }
      if (textured) {
        material['alphaMode'] = 'BLEND';
        material['doubleSided'] = true;
      }
      materials.add(material);
      materialIndex[key] = materials.length - 1;
      return materials.length - 1;
    }

    for (final object in objects) {
      if (!_valid(object)) {
        skipped.add('${object.id}: invalid position or size');
        continue;
      }
      final parts = _partsOf(object, seg, billboardImages, skipped);
      if (parts.isEmpty) continue;

      final primitives = <Map<String, Object>>[];
      for (final part in parts) {
        final mesh = part.mesh;
        final count = mesh.vertexCount;
        if (count == 0 || count > 65535 || mesh.indices.isEmpty) continue;

        // The position is baked into the vertices.
        mesh.shift(object.position.x, object.position.y, object.position.z);

        final lo = <double>[double.infinity, double.infinity, double.infinity];
        final hi = <double>[
          double.negativeInfinity,
          double.negativeInfinity,
          double.negativeInfinity,
        ];
        for (var i = 0; i < mesh.positions.length; i += 3) {
          for (var axis = 0; axis < 3; axis++) {
            final value = mesh.positions[i + axis];
            if (value < lo[axis]) lo[axis] = value;
            if (value > hi[axis]) hi[axis] = value;
          }
        }
        for (var axis = 0; axis < 3; axis++) {
          if (lo[axis] < boundsLo[axis]) boundsLo[axis] = lo[axis];
          if (hi[axis] > boundsHi[axis]) boundsHi[axis] = hi[axis];
        }

        final positionView =
            bin.addView(_floats(mesh.positions), target: 34962);
        final normalView = bin.addView(_floats(mesh.normals), target: 34962);
        final attributes = <String, Object>{
          'POSITION': addAccessor(<String, Object>{
            'bufferView': positionView,
            'componentType': 5126,
            'count': count,
            'type': 'VEC3',
            'min': lo,
            'max': hi,
          }),
          'NORMAL': addAccessor(<String, Object>{
            'bufferView': normalView,
            'componentType': 5126,
            'count': count,
            'type': 'VEC3',
          }),
        };
        if (mesh.hasUvs) {
          final uvView = bin.addView(_floats(mesh.uvs), target: 34962);
          attributes['TEXCOORD_0'] = addAccessor(<String, Object>{
            'bufferView': uvView,
            'componentType': 5126,
            'count': count,
            'type': 'VEC2',
          });
        }
        final indexView =
            bin.addView(_shorts(mesh.indices), target: 34963);
        final indices = addAccessor(<String, Object>{
          'bufferView': indexView,
          'componentType': 5123,
          'count': mesh.indices.length,
          'type': 'SCALAR',
        });

        primitives.add(<String, Object>{
          'attributes': attributes,
          'indices': indices,
          'material': materialFor(part),
          'mode': 4,
        });
        vertexTotal += count;
        triangleTotal += mesh.indices.length ~/ 3;
      }
      if (primitives.isEmpty) {
        skipped.add('${object.id}: empty geometry');
        continue;
      }

      meshes.add(<String, Object>{
        'name': object.id,
        'primitives': primitives,
      });
      nodes.add(<String, Object>{
        'name': object.id,
        'mesh': meshes.length - 1,
      });
    }

    if (nodes.isEmpty) {
      throw StateError('World3D scene has no drawable object.');
    }

    final objectNodes = nodes.length;
    final bounds = World3DBounds(
      Vec3(boundsLo[0], boundsLo[1], boundsLo[2]),
      Vec3(boundsHi[0], boundsHi[1], boundsHi[2]),
    );

    // Camera rig: one parent node moved by the inverse of the camera move.
    List<Object>? animations;
    var sceneNodes = <int>[for (var i = 0; i < objectNodes; i++) i];
    var animationSeconds = 0.0;
    final path = camera;
    final seconds = cameraSeconds;
    if (path != null && seconds != null && path.isActive) {
      final animation = World3DRig.build(
        path: path,
        bounds: bounds,
        duration: seconds,
        holdStart: holdStart,
        holdEnd: holdEnd,
        fps: cameraFps,
      );
      if (animation.length >= 2) {
        nodes.add(<String, Object>{
          'name': 'world_rig',
          'children': <int>[for (var i = 0; i < objectNodes; i++) i],
        });
        final rigIndex = nodes.length - 1;
        sceneNodes = <int>[rigIndex];
        animationSeconds = animation.duration;

        final times = animation.times;
        final timeAccessor = addAccessor(<String, Object>{
          'bufferView': bin.addView(_floats(times)),
          'componentType': 5126,
          'count': times.length,
          'type': 'SCALAR',
          'min': <double>[times.first],
          'max': <double>[times.last],
        });
        final translationValues = <double>[
          for (final t in animation.translations) ...<double>[t.x, t.y, t.z],
        ];
        final translationAccessor = addAccessor(<String, Object>{
          'bufferView': bin.addView(_floats(translationValues)),
          'componentType': 5126,
          'count': times.length,
          'type': 'VEC3',
        });
        final rotationValues = <double>[
          for (final q in animation.rotations) ...q,
        ];
        final rotationAccessor = addAccessor(<String, Object>{
          'bufferView': bin.addView(_floats(rotationValues)),
          'componentType': 5126,
          'count': times.length,
          'type': 'VEC4',
        });

        animations = <Object>[
          <String, Object>{
            'name': 'camera_rig',
            'samplers': <Object>[
              <String, Object>{
                'input': timeAccessor,
                'output': translationAccessor,
                'interpolation': 'LINEAR',
              },
              <String, Object>{
                'input': timeAccessor,
                'output': rotationAccessor,
                'interpolation': 'LINEAR',
              },
            ],
            'channels': <Object>[
              <String, Object>{
                'sampler': 0,
                'target': <String, Object>{
                  'node': rigIndex,
                  'path': 'translation',
                },
              },
              <String, Object>{
                'sampler': 1,
                'target': <String, Object>{
                  'node': rigIndex,
                  'path': 'rotation',
                },
              },
            ],
          },
        ];
      }
    }

    final binary = bin.finish();
    final root = <String, Object>{
      'asset': <String, Object>{
        'version': '2.0',
        'generator': 'Wad Alreda World3DGlbBuilder',
      },
      'scene': 0,
      'scenes': <Object>[
        <String, Object>{'nodes': sceneNodes},
      ],
      'nodes': nodes,
      'meshes': meshes,
      'materials': materials,
      'accessors': accessors,
      'bufferViews': bin.views,
      'buffers': <Object>[
        <String, Object>{'byteLength': binary.length},
      ],
    };
    if (animations != null) {
      root['animations'] = animations;
    }
    if (images.isNotEmpty) {
      root['images'] = images;
      root['textures'] = <Object>[
        for (var i = 0; i < images.length; i++)
          <String, Object>{'source': i, 'sampler': 0},
      ];
      root['samplers'] = <Object>[
        <String, Object>{
          'magFilter': 9729,
          'minFilter': 9729,
          'wrapS': 33071,
          'wrapT': 33071,
        },
      ];
    }

    return World3DGlb(
      bytes: _glb(utf8.encode(jsonEncode(root)), binary),
      objectCount: objectNodes,
      vertexCount: vertexTotal,
      triangleCount: triangleTotal,
      textureCount: images.length,
      skipped: skipped,
      bounds: bounds,
      animated: animations != null,
      animationSeconds: animationSeconds,
    );
  }

  /// The raw mesh of one shape, for tests.
  @visibleForTesting
  static ({List<double> positions, List<double> normals, List<int> indices})
      debugMesh(World3DShape shape, Vec3 size, {int segments = 20}) {
    final mesh = _meshFor(shape, size, segments);
    return (
      positions: mesh.positions,
      normals: mesh.normals,
      indices: mesh.indices,
    );
  }

  // ---------------------------------------------------------------- parts

  static bool _valid(World3DObject o) {
    final values = <double>[
      o.position.x,
      o.position.y,
      o.position.z,
      o.size.x,
      o.size.y,
      o.size.z,
    ];
    for (final value in values) {
      if (!value.isFinite) return false;
    }
    if (o.size.x <= 0 || o.size.y <= 0) return false;
    if (o.shape != World3DShape.billboard && o.size.z <= 0) return false;
    return true;
  }

  static bool _isPng(Uint8List bytes) {
    const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  static List<_Part> _partsOf(
    World3DObject o,
    int seg,
    Map<String, Uint8List> images,
    List<String> skipped,
  ) {
    switch (o.shape) {
      case World3DShape.billboard:
        final png = o.assetKey == null ? null : images[o.assetKey];
        if (png == null) {
          skipped.add('${o.id}: no picture for ${o.assetKey}');
          return const <_Part>[];
        }
        if (!_isPng(png)) {
          skipped.add('${o.id}: the picture is not a PNG');
          return const <_Part>[];
        }
        return <_Part>[
          _Part(
            _Geometry.quad(o.size.x, o.size.y),
            '#FFFFFF',
            imageKey: o.assetKey,
            png: png,
          ),
        ];
      case World3DShape.character:
        return _characterParts(o);
      case World3DShape.box:
      case World3DShape.sphere:
      case World3DShape.cylinder:
        final detailed = _setPieceParts(o);
        if (detailed != null) return detailed;
        return <_Part>[
          _Part(
            _meshFor(o.shape, o.size, seg),
            o.color,
            glow: _glowKeys.contains(o.assetKey),
          ),
        ];
    }
  }

  /// The detailed parts of a known set piece (see world3d_set_pieces.dart), or
  /// null when the object is not one, is a sphere (hills, sun) or has no
  /// detailed version: it then stays one primitive.
  static List<_Part>? _setPieceParts(World3DObject o) {
    final key = o.assetKey;
    if (key == null || !key.startsWith('decor:')) return null;
    if (o.shape == World3DShape.sphere) return null;

    final parts = World3DSetPieces.partsFor(
      key.substring('decor:'.length),
      o.size.x,
      o.size.y,
      o.size.z,
      o.color,
    );
    if (parts == null) return null;

    return <_Part>[
      for (final part in parts)
        _Part(_meshOfSetPiecePart(part), part.color, glow: part.glow),
    ];
  }

  static _Mesh _meshOfSetPiecePart(SetPiecePart part) {
    final mesh = part.shape == SetPieceShape.cylinder
        ? _Geometry.cylinder(part.sx / 2, part.sy, part.sz / 2, 14)
        : _Geometry.box(part.sx, part.sy, part.sz);
    mesh.shift(part.cx, part.cy, part.cz);
    return mesh;
  }

  static _Mesh _meshFor(World3DShape shape, Vec3 size, int seg) {
    switch (shape) {
      case World3DShape.sphere:
        return _Geometry.sphere(size.x / 2, size.y / 2, size.z / 2, seg);
      case World3DShape.cylinder:
        return _Geometry.cylinder(size.x / 2, size.y, size.z / 2, seg);
      case World3DShape.billboard:
        return _Geometry.quad(size.x, size.y);
      case World3DShape.box:
      case World3DShape.character:
        return _Geometry.box(size.x, size.y, size.z);
    }
  }

  /// The hero, built from rounded parts inside the box [o.size], centred on the
  /// object position and facing +z: shoes, legs, belt, waist, chest, shoulders,
  /// arms with sleeves, hands, neck, head, hair and a face (eyes, nose, mouth).
  /// Every part is an ellipsoid or an elliptical cylinder, so the figure has no
  /// hard box corners. The whole figure stays inside the width, height and
  /// depth of the box (it rests on the bottom of it), so the camera framing of
  /// the scene does not change.
  static List<_Part> _characterParts(World3DObject o) {
    final w = o.size.x;
    final h = o.size.y;
    final d = o.size.z;
    final body = o.color;
    final legs = _shadeHex(body, 0.55);
    final belt = _shadeHex(body, 0.35);
    final noseColor = _shadeHex(_skin, 0.92);

    double y(double fromBottom) => -h / 2 + fromBottom * h;

    _Mesh ellipsoid(
      double rx,
      double ry,
      double rz,
      double cx,
      double cy,
      double cz,
    ) {
      final mesh = _Geometry.sphere(rx, ry, rz, 16);
      mesh.shift(cx, cy, cz);
      return mesh;
    }

    _Mesh column(
      double rx,
      double height,
      double rz,
      double cx,
      double cy,
      double cz,
    ) {
      final mesh = _Geometry.cylinder(rx, height, rz, 14);
      mesh.shift(cx, cy, cz);
      return mesh;
    }

    return <_Part>[
      // Shoes: flat ellipsoids, longer toward the front.
      _Part(ellipsoid(0.15 * w, 0.035 * h, 0.30 * d, -0.2 * w, y(0.035), 0.1 * d), _shoe),
      _Part(ellipsoid(0.15 * w, 0.035 * h, 0.30 * d, 0.2 * w, y(0.035), 0.1 * d), _shoe),
      // Legs.
      _Part(column(0.125 * w, 0.34 * h, 0.22 * d, -0.2 * w, y(0.21), 0), legs),
      _Part(column(0.125 * w, 0.34 * h, 0.22 * d, 0.2 * w, y(0.21), 0), legs),
      // Belt, waist and chest.
      _Part(column(0.30 * w, 0.04 * h, 0.26 * d, 0, y(0.405), 0), belt),
      _Part(column(0.29 * w, 0.16 * h, 0.25 * d, 0, y(0.49), 0), body),
      _Part(ellipsoid(0.34 * w, 0.17 * h, 0.29 * d, 0, y(0.62), 0), body),
      // Shoulders and sleeves.
      _Part(ellipsoid(0.10 * w, 0.075 * h, 0.14 * d, -0.385 * w, y(0.70), 0), body),
      _Part(ellipsoid(0.10 * w, 0.075 * h, 0.14 * d, 0.385 * w, y(0.70), 0), body),
      _Part(column(0.07 * w, 0.27 * h, 0.11 * d, -0.425 * w, y(0.55), 0), body),
      _Part(column(0.07 * w, 0.27 * h, 0.11 * d, 0.425 * w, y(0.55), 0), body),
      // Hands.
      _Part(ellipsoid(0.065 * w, 0.045 * h, 0.085 * d, -0.425 * w, y(0.39), 0), _skin),
      _Part(ellipsoid(0.065 * w, 0.045 * h, 0.085 * d, 0.425 * w, y(0.39), 0), _skin),
      // Neck and head.
      _Part(column(0.07 * w, 0.06 * h, 0.08 * d, 0, y(0.80), 0), _skin),
      _Part(ellipsoid(0.2 * w, 0.11 * h, 0.25 * d, 0, y(0.89), 0), _skin),
      // Hair: a slightly bigger cap, raised and set back so the face stays
      // free and the hairline sits on the forehead.
      _Part(ellipsoid(0.215 * w, 0.095 * h, 0.265 * d, 0, y(0.905), -0.02 * d), _hair),
      // Face: eyes, nose and mouth sit on the front of the head.
      _Part(ellipsoid(0.03 * w, 0.018 * h, 0.02 * d, -0.075 * w, y(0.895), 0.235 * d), _eye),
      _Part(ellipsoid(0.03 * w, 0.018 * h, 0.02 * d, 0.075 * w, y(0.895), 0.235 * d), _eye),
      _Part(ellipsoid(0.025 * w, 0.02 * h, 0.03 * d, 0, y(0.875), 0.25 * d), noseColor),
      _Part(ellipsoid(0.04 * w, 0.008 * h, 0.015 * d, 0, y(0.845), 0.238 * d), _mouth),
    ];
  }

  // --------------------------------------------------------------- colour

  static List<double> _srgb(String hex) {
    if (hex.length != 7 || !hex.startsWith('#')) {
      return const <double>[0.33, 0.35, 0.4];
    }
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) return const <double>[0.33, 0.35, 0.4];
    return <double>[
      ((value >> 16) & 0xFF) / 255.0,
      ((value >> 8) & 0xFF) / 255.0,
      (value & 0xFF) / 255.0,
    ];
  }

  static double _toLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  /// glTF colours are linear.
  static List<double> _linearRgb(String hex) =>
      <double>[for (final c in _srgb(hex)) _toLinear(c)];

  static String _shadeHex(String hex, double factor) {
    final rgb = _srgb(hex);
    String channel(double c) => (c * factor * 255)
        .round()
        .clamp(0, 255)
        .toInt()
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return '#${channel(rgb[0])}${channel(rgb[1])}${channel(rgb[2])}';
  }

  // --------------------------------------------------------------- binary

  static Uint8List _floats(List<double> values) {
    final data = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      data.setFloat32(i * 4, values[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Uint8List _shorts(List<int> values) {
    final data = ByteData(values.length * 2);
    for (var i = 0; i < values.length; i++) {
      data.setUint16(i * 2, values[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// Header, JSON chunk (padded with spaces) and BIN chunk (already aligned).
  static Uint8List _glb(List<int> jsonBytes, Uint8List binary) {
    final jsonPad = (4 - jsonBytes.length % 4) % 4;
    final jsonLength = jsonBytes.length + jsonPad;
    final total = 12 + 8 + jsonLength + 8 + binary.length;

    final header = ByteData(20);
    header.setUint32(0, 0x46546C67, Endian.little); // 'glTF'
    header.setUint32(4, 2, Endian.little);
    header.setUint32(8, total, Endian.little);
    header.setUint32(12, jsonLength, Endian.little);
    header.setUint32(16, 0x4E4F534A, Endian.little); // 'JSON'

    final binHeader = ByteData(8);
    binHeader.setUint32(0, binary.length, Endian.little);
    binHeader.setUint32(4, 0x004E4942, Endian.little); // 'BIN\0'

    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(jsonBytes);
    for (var i = 0; i < jsonPad; i++) {
      out.addByte(0x20);
    }
    out
      ..add(binHeader.buffer.asUint8List())
      ..add(binary);
    return out.takeBytes();
  }
}

/// Procedural meshes. Every triangle is counter-clockwise seen from outside.
class _Geometry {
  _Geometry._();

  static _Mesh box(double w, double h, double d) {
    final hx = w / 2;
    final hy = h / 2;
    final hz = d / 2;
    final mesh = _Mesh();

    void face(List<List<double>> corners, double nx, double ny, double nz) {
      final base = mesh.vertexCount;
      for (final p in corners) {
        mesh.vertex(p[0], p[1], p[2], nx, ny, nz);
      }
      mesh.triangle(base, base + 1, base + 2);
      mesh.triangle(base, base + 2, base + 3);
    }

    face(<List<double>>[
      <double>[-hx, -hy, hz],
      <double>[hx, -hy, hz],
      <double>[hx, hy, hz],
      <double>[-hx, hy, hz],
    ], 0, 0, 1);
    face(<List<double>>[
      <double>[hx, -hy, -hz],
      <double>[-hx, -hy, -hz],
      <double>[-hx, hy, -hz],
      <double>[hx, hy, -hz],
    ], 0, 0, -1);
    face(<List<double>>[
      <double>[hx, -hy, hz],
      <double>[hx, -hy, -hz],
      <double>[hx, hy, -hz],
      <double>[hx, hy, hz],
    ], 1, 0, 0);
    face(<List<double>>[
      <double>[-hx, -hy, -hz],
      <double>[-hx, -hy, hz],
      <double>[-hx, hy, hz],
      <double>[-hx, hy, -hz],
    ], -1, 0, 0);
    face(<List<double>>[
      <double>[-hx, hy, hz],
      <double>[hx, hy, hz],
      <double>[hx, hy, -hz],
      <double>[-hx, hy, -hz],
    ], 0, 1, 0);
    face(<List<double>>[
      <double>[-hx, -hy, -hz],
      <double>[hx, -hy, -hz],
      <double>[hx, -hy, hz],
      <double>[-hx, -hy, hz],
    ], 0, -1, 0);
    return mesh;
  }

  /// A flat picture facing +z (UV origin at the top left).
  static _Mesh quad(double w, double h) {
    final hw = w / 2;
    final hh = h / 2;
    final mesh = _Mesh()
      ..vertex(-hw, -hh, 0, 0, 0, 1, u: 0, v: 1)
      ..vertex(hw, -hh, 0, 0, 0, 1, u: 1, v: 1)
      ..vertex(hw, hh, 0, 0, 0, 1, u: 1, v: 0)
      ..vertex(-hw, hh, 0, 0, 0, 1, u: 0, v: 0)
      ..triangle(0, 1, 2)
      ..triangle(0, 2, 3);
    return mesh;
  }

  static _Mesh sphere(double rx, double ry, double rz, int segments) {
    var rings = segments ~/ 2;
    if (rings.isOdd) rings++;
    final mesh = _Mesh();
    for (var r = 0; r <= rings; r++) {
      final theta = math.pi * r / rings;
      final st = math.sin(theta);
      final ct = math.cos(theta);
      for (var s = 0; s <= segments; s++) {
        final phi = 2 * math.pi * s / segments;
        final ux = st * math.cos(phi);
        final uy = ct;
        final uz = st * math.sin(phi);
        final nx = ux / rx;
        final ny = uy / ry;
        final nz = uz / rz;
        final length = math.sqrt(nx * nx + ny * ny + nz * nz);
        mesh.vertex(
          rx * ux,
          ry * uy,
          rz * uz,
          nx / length,
          ny / length,
          nz / length,
        );
      }
    }
    for (var r = 0; r < rings; r++) {
      for (var s = 0; s < segments; s++) {
        final a = r * (segments + 1) + s;
        final b = a + segments + 1;
        mesh.triangle(a, a + 1, b);
        mesh.triangle(a + 1, b + 1, b);
      }
    }
    return mesh;
  }

  /// A cylinder (elliptical section) whose axis is y.
  static _Mesh cylinder(double rx, double height, double rz, int segments) {
    final half = height / 2;
    final mesh = _Mesh();

    // Side: a top and a bottom vertex for every step.
    for (var s = 0; s <= segments; s++) {
      final phi = 2 * math.pi * s / segments;
      final c = math.cos(phi);
      final n = math.sin(phi);
      final nx = c / rx;
      final nz = n / rz;
      final length = math.sqrt(nx * nx + nz * nz);
      mesh.vertex(rx * c, half, rz * n, nx / length, 0, nz / length);
      mesh.vertex(rx * c, -half, rz * n, nx / length, 0, nz / length);
    }
    for (var s = 0; s < segments; s++) {
      final t0 = 2 * s;
      final b0 = 2 * s + 1;
      final t1 = 2 * (s + 1);
      final b1 = 2 * (s + 1) + 1;
      mesh.triangle(t0, t1, b0);
      mesh.triangle(t1, b1, b0);
    }

    void cap(double y, double normalY) {
      final center = mesh.vertexCount;
      mesh.vertex(0, y, 0, 0, normalY, 0);
      for (var s = 0; s <= segments; s++) {
        final phi = 2 * math.pi * s / segments;
        mesh.vertex(
          rx * math.cos(phi),
          y,
          rz * math.sin(phi),
          0,
          normalY,
          0,
        );
      }
      for (var s = 0; s < segments; s++) {
        final a = center + 1 + s;
        final b = center + 2 + s;
        if (normalY > 0) {
          mesh.triangle(center, b, a);
        } else {
          mesh.triangle(center, a, b);
        }
      }
    }

    cap(half, 1);
    cap(-half, -1);
    return mesh;
  }
}
