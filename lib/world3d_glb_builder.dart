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

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'glb_inspector.dart';
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
  ///
  /// [modelBytes] maps the asset key of a [World3DShape.model] object to the
  /// bytes of its GLB (see [World3DGlbBuilder.readModel]); those meshes are
  /// merged into the scene file. A model that cannot be merged is skipped and
  /// listed in [World3DGlb.skipped].
  static World3DGlb build(
    World3DScene scene, {
    Map<String, Uint8List> billboardImages = const <String, Uint8List>{},
    Map<String, Uint8List> modelBytes = const <String, Uint8List>{},
    int segments = 20,
    double? cameraSeconds,
    double holdStart = 0.5,
    double holdEnd = 0.5,
    int cameraFps = 30,
  }) {
    return buildObjects(
      scene.objects,
      billboardImages: billboardImages,
      modelBytes: modelBytes,
      segments: segments,
      camera: cameraSeconds == null ? null : scene.camera,
      cameraSeconds: cameraSeconds,
      holdStart: holdStart,
      holdEnd: holdEnd,
      cameraFps: cameraFps,
    );
  }

  /// Reads the GLB at [path] for [build]'s [modelBytes]. Returns null when the
  /// file is missing or fails [GlbInspector] (a bad model never reaches the
  /// native engine).
  static Future<Uint8List?> readModel(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final report = GlbInspector.inspect(bytes);
      if (!report.isSafe) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// The GLB of [objects]. Throws [StateError] when none can be drawn.
  ///
  /// The rig animation is written only when [camera] is active and
  /// [cameraSeconds] is given.
  static World3DGlb buildObjects(
    List<World3DObject> objects, {
    Map<String, Uint8List> billboardImages = const <String, Uint8List>{},
    Map<String, Uint8List> modelBytes = const <String, Uint8List>{},
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
      final parts = _partsOf(
        object,
        seg,
        billboardImages,
        modelBytes,
        skipped,
      );
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
    Map<String, Uint8List> models,
    List<String> skipped,
  ) {
    switch (o.shape) {
      case World3DShape.model:
        final key = o.assetKey;
        final bytes = key == null ? null : models[key];
        if (bytes == null) {
          skipped.add('${o.id}: no GLB for ${o.assetKey}');
          return const <_Part>[];
        }
        final parts = _modelParts(o, bytes, skipped);
        if (parts.isEmpty) {
          skipped.add('${o.id}: the GLB has no drawable mesh');
        }
        return parts;
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

  /// The parts of a real GLB model, fitted into the box [o.size] and centred
  /// on [o.position]. The model's own materials and embedded images are kept.
  /// A model that cannot be parsed returns an empty list (the caller skips it).
  static List<_Part> _modelParts(
    World3DObject o,
    Uint8List bytes,
    List<String> skipped,
  ) {
    final parsed = _ParsedGlb.parse(bytes);
    if (parsed == null) {
      skipped.add('${o.id}: the GLB could not be parsed');
      return const <_Part>[];
    }
    if (parsed.unsupported.isNotEmpty) {
      skipped.add(
        '${o.id}: unsupported extension ${parsed.unsupported.join(', ')}',
      );
      return const <_Part>[];
    }

    final parts = <_Part>[];
    for (final primitive in parsed.primitives) {
      final mesh = primitive.mesh;
      if (mesh.vertexCount == 0 || mesh.indices.isEmpty) continue;
      if (mesh.vertexCount > 65535) {
        skipped.add('${o.id}: a primitive has too many vertices');
        continue;
      }
      parts.add(
        _Part(
          mesh,
          primitive.color,
          imageKey: primitive.imageKey,
          png: primitive.png,
        ),
      );
    }
    if (parts.isEmpty) return const <_Part>[];

    // Fit the model into the box of the object: centre it, scale it so its
    // longest side matches the box, then move it to the object position.
    final lo = <double>[double.infinity, double.infinity, double.infinity];
    final hi = <double>[
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    ];
    for (final part in parts) {
      final p = part.mesh.positions;
      for (var i = 0; i < p.length; i += 3) {
        for (var axis = 0; axis < 3; axis++) {
          final value = p[i + axis];
          if (value < lo[axis]) lo[axis] = value;
          if (value > hi[axis]) hi[axis] = value;
        }
      }
    }
    final extent = <double>[
      hi[0] - lo[0],
      hi[1] - lo[1],
      hi[2] - lo[2],
    ];
    final longest = math.max(extent[0], math.max(extent[1], extent[2]));
    final target = math.max(o.size.x, math.max(o.size.y, o.size.z));
    final scale = longest <= 1e-9 ? 1.0 : target / longest;
    final cx = (lo[0] + hi[0]) / 2;
    final cy = (lo[1] + hi[1]) / 2;
    final cz = (lo[2] + hi[2]) / 2;

    for (final part in parts) {
      final p = part.mesh.positions;
      for (var i = 0; i < p.length; i += 3) {
        p[i] = (p[i] - cx) * scale;
        p[i + 1] = (p[i + 1] - cy) * scale;
        p[i + 2] = (p[i + 2] - cz) * scale;
      }
    }
    return parts;
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

/// A GLB read back into meshes, so its geometry can be merged into the scene
/// file. Only what the scene builder needs is kept: positions, normals, UVs,
/// indices, a base colour and an embedded PNG per primitive.
class _ParsedGlb {
  final List<_ParsedPrimitive> primitives;
  final List<String> unsupported;

  const _ParsedGlb(this.primitives, this.unsupported);

  static _ParsedGlb? parse(Uint8List bytes) {
    if (bytes.length < 28 ||
        bytes[0] != 0x67 ||
        bytes[1] != 0x6c ||
        bytes[2] != 0x54 ||
        bytes[3] != 0x46) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(4, Endian.little) != 2) return null;
    if (data.getUint32(8, Endian.little) != bytes.length) return null;

    final jsonLength = data.getUint32(12, Endian.little);
    if (data.getUint32(16, Endian.little) != 0x4E4F534A) return null;
    if (20 + jsonLength > bytes.length) return null;

    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(
        utf8.decode(
          Uint8List.sublistView(bytes, 20, 20 + jsonLength),
          allowMalformed: true,
        ),
      );
      if (decoded is! Map) return null;
      root = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }

    var binStart = -1;
    final next = 20 + jsonLength;
    if (next + 8 <= bytes.length &&
        data.getUint32(next + 4, Endian.little) == 0x004E4942) {
      binStart = next + 8;
    }
    if (binStart < 0) return null;

    final required = root['extensionsRequired'];
    final unsupported = <String>[];
    if (required is List) {
      for (final name in required.whereType<String>()) {
        if (GlbInspector.unsupportedRequired.contains(name)) {
          unsupported.add(name);
        }
      }
    }
    if (unsupported.isNotEmpty) {
      return _ParsedGlb(const <_ParsedPrimitive>[], unsupported);
    }

    final accessors = root['accessors'] is List
        ? root['accessors'] as List
        : const <dynamic>[];
    final views = root['bufferViews'] is List
        ? root['bufferViews'] as List
        : const <dynamic>[];
    final materials = root['materials'] is List
        ? root['materials'] as List
        : const <dynamic>[];
    final images = root['images'] is List
        ? root['images'] as List
        : const <dynamic>[];
    final textures = root['textures'] is List
        ? root['textures'] as List
        : const <dynamic>[];
    final meshes = root['meshes'] is List
        ? root['meshes'] as List
        : const <dynamic>[];

    Uint8List? viewBytes(int index) {
      if (index < 0 || index >= views.length) return null;
      final view = views[index];
      if (view is! Map) return null;
      final offset = (view['byteOffset'] as num?)?.toInt() ?? 0;
      final length = (view['byteLength'] as num?)?.toInt() ?? 0;
      final start = binStart + offset;
      if (length <= 0 || start < 0 || start + length > bytes.length) {
        return null;
      }
      return Uint8List.sublistView(bytes, start, start + length);
    }

    List<double>? readFloats(int accessorIndex, int components) {
      if (accessorIndex < 0 || accessorIndex >= accessors.length) return null;
      final accessor = accessors[accessorIndex];
      if (accessor is! Map) return null;
      final viewIndex = (accessor['bufferView'] as num?)?.toInt() ?? -1;
      final count = (accessor['count'] as num?)?.toInt() ?? 0;
      if (count <= 0) return null;
      final raw = viewBytes(viewIndex);
      if (raw == null) return null;
      final offset = (accessor['byteOffset'] as num?)?.toInt() ?? 0;
      final stride = (accessor['byteStride'] as num?)?.toInt() ?? 0;
      final componentType = (accessor['componentType'] as num?)?.toInt() ?? 0;
      if (componentType != 5126) return null;
      final elementSize = components * 4;
      final step = stride > 0 ? stride : elementSize;
      final needed = offset + step * (count - 1) + elementSize;
      if (needed > raw.length) return null;
      final out = <double>[];
      final view = ByteData.sublistView(raw);
      for (var i = 0; i < count; i++) {
        final base = offset + i * step;
        for (var c = 0; c < components; c++) {
          out.add(view.getFloat32(base + c * 4, Endian.little));
        }
      }
      return out;
    }

    List<int>? readIndices(int accessorIndex) {
      if (accessorIndex < 0 || accessorIndex >= accessors.length) return null;
      final accessor = accessors[accessorIndex];
      if (accessor is! Map) return null;
      final viewIndex = (accessor['bufferView'] as num?)?.toInt() ?? -1;
      final count = (accessor['count'] as num?)?.toInt() ?? 0;
      if (count <= 0) return null;
      final raw = viewBytes(viewIndex);
      if (raw == null) return null;
      final offset = (accessor['byteOffset'] as num?)?.toInt() ?? 0;
      final componentType = (accessor['componentType'] as num?)?.toInt() ?? 0;
      final size = switch (componentType) {
        5121 => 1,
        5123 => 2,
        5125 => 4,
        _ => 0,
      };
      if (size == 0) return null;
      if (offset + count * size > raw.length) return null;
      final view = ByteData.sublistView(raw);
      final out = <int>[];
      for (var i = 0; i < count; i++) {
        final at = offset + i * size;
        out.add(switch (size) {
          1 => view.getUint8(at),
          2 => view.getUint16(at, Endian.little),
          _ => view.getUint32(at, Endian.little),
        });
      }
      return out;
    }

    String? imageKeyFor(int materialIndex) {
      if (materialIndex < 0 || materialIndex >= materials.length) return null;
      final material = materials[materialIndex];
      if (material is! Map) return null;
      final pbr = material['pbrMetallicRoughness'];
      if (pbr is! Map) return null;
      final texture = pbr['baseColorTexture'];
      if (texture is! Map) return null;
      final textureIndex = (texture['index'] as num?)?.toInt() ?? -1;
      if (textureIndex < 0 || textureIndex >= textures.length) return null;
      final tex = textures[textureIndex];
      if (tex is! Map) return null;
      final source = (tex['source'] as num?)?.toInt() ?? -1;
      if (source < 0 || source >= images.length) return null;
      final image = images[source];
      if (image is! Map) return null;
      final viewIndex = (image['bufferView'] as num?)?.toInt() ?? -1;
      final raw = viewBytes(viewIndex);
      if (raw == null) return null;
      return 'model:${source}:${raw.length}';
    }

    Uint8List? imageBytesFor(int materialIndex) {
      if (materialIndex < 0 || materialIndex >= materials.length) return null;
      final material = materials[materialIndex];
      if (material is! Map) return null;
      final pbr = material['pbrMetallicRoughness'];
      if (pbr is! Map) return null;
      final texture = pbr['baseColorTexture'];
      if (texture is! Map) return null;
      final textureIndex = (texture['index'] as num?)?.toInt() ?? -1;
      if (textureIndex < 0 || textureIndex >= textures.length) return null;
      final tex = textures[textureIndex];
      if (tex is! Map) return null;
      final source = (tex['source'] as num?)?.toInt() ?? -1;
      if (source < 0 || source >= images.length) return null;
      final image = images[source];
      if (image is! Map) return null;
      final viewIndex = (image['bufferView'] as num?)?.toInt() ?? -1;
      return viewBytes(viewIndex);
    }

    String colorFor(int materialIndex) {
      if (materialIndex < 0 || materialIndex >= materials.length) {
        return '#B9B9C0';
      }
      final material = materials[materialIndex];
      if (material is! Map) return '#B9B9C0';
      final pbr = material['pbrMetallicRoughness'];
      if (pbr is! Map) return '#B9B9C0';
      final factor = pbr['baseColorFactor'];
      if (factor is! List || factor.length < 3) return '#B9B9C0';
      int channel(int i) {
        final value = factor[i];
        if (value is! num) return 0x80;
        final linear = value.toDouble().clamp(0.0, 1.0);
        final srgb = linear <= 0.0031308
            ? linear * 12.92
            : 1.055 * math.pow(linear, 1 / 2.4) - 0.055;
        return (srgb * 255).round().clamp(0, 255).toInt();
      }

      String hex(int value) => value.toRadixString(16).padLeft(2, '0');
      return '#${hex(channel(0))}${hex(channel(1))}${hex(channel(2))}'
          .toUpperCase();
    }

    final primitives = <_ParsedPrimitive>[];
    for (final mesh in meshes) {
      if (mesh is! Map) continue;
      final rows = mesh['primitives'];
      if (rows is! List) continue;
      for (final row in rows) {
        if (row is! Map) continue;
        final attributes = row['attributes'];
        if (attributes is! Map) continue;
        final positionIndex = (attributes['POSITION'] as num?)?.toInt() ?? -1;
        final positions = readFloats(positionIndex, 3);
        if (positions == null || positions.isEmpty) continue;
        final count = positions.length ~/ 3;

        final normalIndex = (attributes['NORMAL'] as num?)?.toInt() ?? -1;
        var normals = readFloats(normalIndex, 3);
        if (normals == null || normals.length != positions.length) {
          normals = _flatNormals(positions);
        }

        final uvIndex = (attributes['TEXCOORD_0'] as num?)?.toInt() ?? -1;
        final uvs = readFloats(uvIndex, 2);

        final indexAccessor = (row['indices'] as num?)?.toInt() ?? -1;
        var indices = readIndices(indexAccessor);
        if (indices == null || indices.isEmpty) {
          indices = <int>[for (var i = 0; i < count; i++) i];
        }
        if (indices.any((index) => index < 0 || index >= count)) continue;

        final materialIndex = (row['material'] as num?)?.toInt() ?? -1;
        final meshData = _Mesh();
        for (var i = 0; i < count; i++) {
          meshData.vertex(
            positions[i * 3],
            positions[i * 3 + 1],
            positions[i * 3 + 2],
            normals[i * 3],
            normals[i * 3 + 1],
            normals[i * 3 + 2],
            u: uvs != null && uvs.length >= count * 2 ? uvs[i * 2] : null,
            v: uvs != null && uvs.length >= count * 2 ? uvs[i * 2 + 1] : null,
          );
        }
        for (var i = 0; i + 2 < indices.length; i += 3) {
          meshData.triangle(indices[i], indices[i + 1], indices[i + 2]);
        }

        primitives.add(
          _ParsedPrimitive(
            mesh: meshData,
            color: colorFor(materialIndex),
            imageKey: imageKeyFor(materialIndex),
            png: imageBytesFor(materialIndex),
          ),
        );
      }
    }

    return _ParsedGlb(primitives, const <String>[]);
  }

  /// Normals for a mesh that has none: one normal per triangle, so the model
  /// still shades correctly.
  static List<double> _flatNormals(List<double> positions) {
    final count = positions.length ~/ 3;
    final normals = List<double>.filled(positions.length, 0);
    for (var i = 0; i + 2 < count; i += 3) {
      final ax = positions[i * 3];
      final ay = positions[i * 3 + 1];
      final az = positions[i * 3 + 2];
      final bx = positions[(i + 1) * 3];
      final by = positions[(i + 1) * 3 + 1];
      final bz = positions[(i + 1) * 3 + 2];
      final cx = positions[(i + 2) * 3];
      final cy = positions[(i + 2) * 3 + 1];
      final cz = positions[(i + 2) * 3 + 2];
      final ux = bx - ax;
      final uy = by - ay;
      final uz = bz - az;
      final vx = cx - ax;
      final vy = cy - ay;
      final vz = cz - az;
      var nx = uy * vz - uz * vy;
      var ny = uz * vx - ux * vz;
      var nz = ux * vy - uy * vx;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length > 1e-9) {
        nx /= length;
        ny /= length;
        nz /= length;
      }
      for (var k = 0; k < 3; k++) {
        normals[(i + k) * 3] = nx;
        normals[(i + k) * 3 + 1] = ny;
        normals[(i + k) * 3 + 2] = nz;
      }
    }
    return normals;
  }
}

class _ParsedPrimitive {
  final _Mesh mesh;
  final String color;
  final String? imageKey;
  final Uint8List? png;

  const _ParsedPrimitive({
    required this.mesh,
    required this.color,
    this.imageKey,
    this.png,
  });
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
