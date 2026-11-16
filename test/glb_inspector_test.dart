import 'dart:convert';
import 'dart:typed_data';

import 'package:auto_edit/glb_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _pad(List<int> data, int padding) {
  final extra = (4 - data.length % 4) % 4;
  return Uint8List.fromList(<int>[...data, ...List<int>.filled(extra, padding)]);
}

Uint8List _glb(Map<String, dynamic> json, {Uint8List? bin}) {
  final jsonBytes = _pad(utf8.encode(jsonEncode(json)), 0x20);
  final binBytes = bin == null ? null : _pad(bin, 0);
  final total = 12 + 8 + jsonBytes.length + (binBytes == null ? 0 : 8 + binBytes.length);

  final out = BytesBuilder();
  final header = ByteData(20);
  header.setUint32(0, 0x46546C67, Endian.little);
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, total, Endian.little);
  header.setUint32(12, jsonBytes.length, Endian.little);
  header.setUint32(16, 0x4E4F534A, Endian.little);
  out.add(header.buffer.asUint8List());
  out.add(jsonBytes);

  if (binBytes != null) {
    final binHeader = ByteData(8);
    binHeader.setUint32(0, binBytes.length, Endian.little);
    binHeader.setUint32(4, 0x004E4942, Endian.little);
    out.add(binHeader.buffer.asUint8List());
    out.add(binBytes);
  }
  return out.toBytes();
}

Uint8List _pngHeader(int width, int height) {
  final data = ByteData(33);
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    data.setUint8(i, signature[i]);
  }
  data.setUint32(8, 13, Endian.big);
  data.setUint8(12, 0x49);
  data.setUint8(13, 0x48);
  data.setUint8(14, 0x44);
  data.setUint8(15, 0x52);
  data.setUint32(16, width, Endian.big);
  data.setUint32(20, height, Endian.big);
  return data.buffer.asUint8List();
}

void main() {
  group('GlbInspector', () {
    test('accepts a small valid model and counts vertices', () {
      final report = GlbInspector.inspect(
        _glb(<String, dynamic>{
          'asset': <String, dynamic>{'version': '2.0'},
          'accessors': <dynamic>[
            <String, dynamic>{'count': 3000},
          ],
          'meshes': <dynamic>[
            <String, dynamic>{
              'primitives': <dynamic>[
                <String, dynamic>{
                  'attributes': <String, dynamic>{'POSITION': 0},
                },
              ],
            },
          ],
          'animations': <dynamic>[<String, dynamic>{}],
        }),
      );

      expect(report.isSafe, isTrue);
      expect(report.vertexCount, 3000);
      expect(report.animationCount, 1);
    });

    test('rejects a truncated download', () {
      final bytes = _glb(<String, dynamic>{
        'asset': <String, dynamic>{'version': '2.0'},
      });
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 8);

      final report = GlbInspector.inspect(truncated);
      expect(report.isSafe, isFalse);
    });

    test('rejects a file that is not GLB', () {
      final report = GlbInspector.inspect(Uint8List.fromList(List<int>.filled(64, 1)));
      expect(report.isSafe, isFalse);
    });

    test('rejects compression the engine cannot decode', () {
      final report = GlbInspector.inspect(
        _glb(<String, dynamic>{
          'asset': <String, dynamic>{'version': '2.0'},
          'extensionsRequired': <String>['KHR_draco_mesh_compression'],
        }),
      );

      expect(report.isSafe, isFalse);
      expect(report.rejection, contains('KHR_draco_mesh_compression'));
    });

    test('an optional unsupported extension is allowed', () {
      final report = GlbInspector.inspect(
        _glb(<String, dynamic>{
          'asset': <String, dynamic>{'version': '2.0'},
          'extensionsUsed': <String>['KHR_draco_mesh_compression'],
        }),
      );

      expect(report.isSafe, isTrue);
    });

    test('rejects a model with too many vertices', () {
      final report = GlbInspector.inspect(
        _glb(<String, dynamic>{
          'asset': <String, dynamic>{'version': '2.0'},
          'accessors': <dynamic>[
            <String, dynamic>{'count': 2000000},
          ],
          'meshes': <dynamic>[
            <String, dynamic>{
              'primitives': <dynamic>[
                <String, dynamic>{
                  'attributes': <String, dynamic>{'POSITION': 0},
                },
              ],
            },
          ],
        }),
      );

      expect(report.isSafe, isFalse);
    });

    test('estimates texture memory from the embedded image size', () {
      Map<String, dynamic> model(int images) => <String, dynamic>{
            'asset': <String, dynamic>{'version': '2.0'},
            'bufferViews': <dynamic>[
              <String, dynamic>{'buffer': 0, 'byteOffset': 0, 'byteLength': 33},
            ],
            'images': <dynamic>[
              for (var i = 0; i < images; i++)
                <String, dynamic>{'bufferView': 0, 'mimeType': 'image/png'},
            ],
          };

      final two = GlbInspector.inspect(_glb(model(2), bin: _pngHeader(4096, 4096)));
      expect(two.isSafe, isTrue);
      expect(two.imageCount, 2);
      expect(two.estimatedTextureBytes, greaterThan(150 * 1024 * 1024));

      final three = GlbInspector.inspect(_glb(model(3), bin: _pngHeader(4096, 4096)));
      expect(three.isSafe, isFalse);
    });
  });
}
