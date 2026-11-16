import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Result of checking a GLB file before it reaches the native 3D engine.
class GlbReport {
  final int byteLength;
  final List<String> extensionsRequired;
  final List<String> extensionsUsed;
  final int vertexCount;
  final int imageCount;
  final int estimatedTextureBytes;
  final int animationCount;

  /// Arabic reason why the file must not be loaded, or null when it is safe.
  final String? rejection;

  const GlbReport({
    required this.byteLength,
    this.extensionsRequired = const <String>[],
    this.extensionsUsed = const <String>[],
    this.vertexCount = 0,
    this.imageCount = 0,
    this.estimatedTextureBytes = 0,
    this.animationCount = 0,
    this.rejection,
  });

  bool get isSafe => rejection == null;
}

/// Reads the JSON header of a GLB and rejects files that are corrupt, use
/// compression the native engine cannot decode, or are too heavy for a phone.
/// A native crash cannot be caught from Dart, so these checks run first.
class GlbInspector {
  GlbInspector._();

  static const int maxFileBytes = 30 * 1024 * 1024;
  static const int maxVertices = 1200000;
  static const int maxTextureBytes = 192 * 1024 * 1024;

  static const Set<String> unsupportedRequired = <String>{
    'KHR_draco_mesh_compression',
    'EXT_meshopt_compression',
    'KHR_texture_basisu',
    'EXT_texture_webp',
  };

  static Future<GlbReport> inspectFile(String path) async {
    final file = File(path);
    final length = await file.length();
    if (length > maxFileBytes) {
      return GlbReport(
        byteLength: length,
        rejection:
            'حجم المجسم ${(length / (1024 * 1024)).toStringAsFixed(1)} MB أكبر من الحد الآمن للهاتف (30 MB).',
      );
    }
    return inspect(await file.readAsBytes());
  }

  static GlbReport inspect(Uint8List bytes) {
    GlbReport reject(String reason) =>
        GlbReport(byteLength: bytes.length, rejection: reason);

    if (bytes.length > maxFileBytes) {
      return reject(
        'حجم المجسم ${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB أكبر من الحد الآمن للهاتف (30 MB).',
      );
    }
    if (bytes.length < 28 ||
        bytes[0] != 0x67 ||
        bytes[1] != 0x6c ||
        bytes[2] != 0x54 ||
        bytes[3] != 0x46) {
      return reject('الملف ليس GLB صالحاً.');
    }

    final data = ByteData.sublistView(bytes);
    if (data.getUint32(4, Endian.little) != 2) {
      return reject('إصدار GLB غير مدعوم.');
    }
    if (data.getUint32(8, Endian.little) != bytes.length) {
      return reject('ملف GLB ناقص أو تالف (الحجم لا يطابق المعلن).');
    }

    final jsonLength = data.getUint32(12, Endian.little);
    final jsonType = data.getUint32(16, Endian.little);
    if (jsonType != 0x4E4F534A || 20 + jsonLength > bytes.length) {
      return reject('بنية ملف GLB غير صالحة.');
    }

    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(
        utf8.decode(
          Uint8List.sublistView(bytes, 20, 20 + jsonLength),
          allowMalformed: true,
        ),
      );
      if (decoded is! Map) {
        return reject('تعذر قراءة وصف المجسم داخل GLB.');
      }
      root = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return reject('تعذر قراءة وصف المجسم داخل GLB.');
    }

    var binStart = -1;
    final next = 20 + jsonLength;
    if (next + 8 <= bytes.length &&
        data.getUint32(next + 4, Endian.little) == 0x004E4942) {
      binStart = next + 8;
    }

    final required = _strings(root['extensionsRequired']);
    final used = _strings(root['extensionsUsed']);

    final accessors =
        root['accessors'] is List ? root['accessors'] as List : const <dynamic>[];

    var vertices = 0;
    final meshes = root['meshes'];
    if (meshes is List) {
      for (final mesh in meshes) {
        if (mesh is! Map) continue;
        final primitives = mesh['primitives'];
        if (primitives is! List) continue;
        for (final primitive in primitives) {
          if (primitive is! Map) continue;
          final attributes = primitive['attributes'];
          if (attributes is! Map) continue;
          final position = attributes['POSITION'];
          if (position is int && position >= 0 && position < accessors.length) {
            final accessor = accessors[position];
            if (accessor is Map && accessor['count'] is num) {
              vertices += (accessor['count'] as num).toInt();
            }
          }
        }
      }
    }

    var imageCount = 0;
    var textureBytes = 0;
    final images = root['images'];
    final views = root['bufferViews'];
    if (images is List) {
      for (final image in images) {
        imageCount++;
        int? width;
        int? height;

        if (image is Map) {
          final viewIndex = image['bufferView'];
          if (viewIndex is int &&
              views is List &&
              viewIndex >= 0 &&
              viewIndex < views.length &&
              binStart >= 0) {
            final view = views[viewIndex];
            if (view is Map) {
              final offset = (view['byteOffset'] as num?)?.toInt() ?? 0;
              final length = (view['byteLength'] as num?)?.toInt() ?? 0;
              final start = binStart + offset;
              if (start >= 0 && length > 0 && start + length <= bytes.length) {
                final size = _imageSize(bytes, start, length);
                if (size != null) {
                  width = size[0];
                  height = size[1];
                }
              }
            }
          }
        }

        // Unknown size: assume a common 2K texture.
        final w = width ?? 2048;
        final h = height ?? 2048;
        // RGBA8 plus mipmaps.
        textureBytes += (w * h * 4 * 4 / 3).round();
      }
    }

    final animations = root['animations'] is List
        ? (root['animations'] as List).length
        : 0;

    String? rejection;
    for (final name in required) {
      if (unsupportedRequired.contains(name)) {
        rejection =
            'المجسم يستخدم ضغطاً غير مدعوم في محرك 3D ($name).';
        break;
      }
    }
    if (rejection == null && vertices > maxVertices) {
      rejection =
          'المجسم ثقيل جداً للهاتف ($vertices نقطة هندسية).';
    }
    if (rejection == null && textureBytes > maxTextureBytes) {
      rejection =
          'خامات المجسم كبيرة جداً على ذاكرة الهاتف (~${textureBytes ~/ (1024 * 1024)} MB).';
    }

    return GlbReport(
      byteLength: bytes.length,
      extensionsRequired: required,
      extensionsUsed: used,
      vertexCount: vertices,
      imageCount: imageCount,
      estimatedTextureBytes: textureBytes,
      animationCount: animations,
      rejection: rejection,
    );
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList();
  }

  /// Reads the pixel size of an embedded PNG or JPEG, or null.
  static List<int>? _imageSize(Uint8List bytes, int start, int length) {
    final end = start + (length < 262144 ? length : 262144);

    // PNG
    if (length >= 24 &&
        bytes[start] == 0x89 &&
        bytes[start + 1] == 0x50 &&
        bytes[start + 2] == 0x4E &&
        bytes[start + 3] == 0x47) {
      final data = ByteData.sublistView(bytes);
      return <int>[
        data.getUint32(start + 16, Endian.big),
        data.getUint32(start + 20, Endian.big),
      ];
    }

    // JPEG
    if (length >= 4 && bytes[start] == 0xFF && bytes[start + 1] == 0xD8) {
      final data = ByteData.sublistView(bytes);
      var i = start + 2;
      while (i + 9 < end) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = bytes[i + 1];
        if (marker == 0xFF) {
          i++;
          continue;
        }
        final isFrame = marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC;
        if (isFrame) {
          return <int>[
            data.getUint16(i + 7, Endian.big),
            data.getUint16(i + 5, Endian.big),
          ];
        }
        if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2;
          continue;
        }
        final segment = data.getUint16(i + 2, Endian.big);
        if (segment < 2) return null;
        i += 2 + segment;
      }
    }

    return null;
  }
}
