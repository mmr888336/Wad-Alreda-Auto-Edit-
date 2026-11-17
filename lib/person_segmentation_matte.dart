import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart'
    show InputImage;
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

import 'person_silhouette.dart';

/// Real per-frame person matte built with ML Kit Selfie Segmentation.
///
/// The video window is sampled to small JPEG frames with FFmpeg, every frame
/// goes through the segmenter, and the confidence mask becomes an 8-bit
/// grayscale PNG named `matte_00000.png`, `matte_00001.png`, ... which is the
/// exact sequence format [PersonMatteSequence] and the anchored export command
/// already consume. White means person, black means background.
///
/// Returns null (never throws) when segmentation is not possible, so the
/// caller can fall back to the approximate pose-based matte.
class PersonSegmentationMatte {
  PersonSegmentationMatte._();

  static int _even(int value) => value.isEven ? value : value + 1;

  /// Confidence below [_low] is background, above [_high] is solid person.
  static const double _low = 0.30;
  static const double _high = 0.80;

  /// A frame with less than this share of person pixels counts as empty.
  static const double _minimumCoverage = 0.01;

  static Future<PersonMatteSequence?> render({
    required String videoPath,
    required double start,
    required double end,
    required String directory,
    required int frameWidth,
    required int frameHeight,
    int maskWidth = 384,
    double fps = 12,
  }) async {
    if (frameWidth <= 0 || frameHeight <= 0) return null;
    if (!start.isFinite || !end.isFinite || end - start < 0.4) return null;

    try {
      final result = await _run(
        videoPath: videoPath,
        start: start,
        end: end,
        directory: directory,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        maskWidth: maskWidth,
        fps: fps,
      );
      if (result == null) await _deleteQuietly(directory);
      return result;
    } catch (_) {
      await _deleteQuietly(directory);
      return null;
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final folder = Directory(path);
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {
      // Temporary-file cleanup must never crash the export.
    }
  }

  static Future<PersonMatteSequence?> _run({
    required String videoPath,
    required double start,
    required double end,
    required String directory,
    required int frameWidth,
    required int frameHeight,
    required int maskWidth,
    required double fps,
  }) async {
    final width = _even(maskWidth.clamp(160, 640).toInt());
    final height = _even(
      math.max(2, (width * frameHeight / frameWidth).round()),
    );
    final rate = fps.clamp(6.0, 24.0).toDouble();
    final count = math.min(240, ((end - start) * rate).ceil() + 1);

    await _deleteQuietly(directory);
    final source = Directory('$directory/src');
    await source.create(recursive: true);

    SelfieSegmenter? segmenter;

    try {
      final command = '-y -ss ${start.toStringAsFixed(3)} '
          '-t ${(end - start).toStringAsFixed(3)} '
          '-i "$videoPath" '
          '-vf "fps=${rate.toStringAsFixed(2)},'
          'scale=$width:$height:flags=bilinear" '
          '-frames:v $count -q:v 3 "${source.path}/src_%05d.jpg"';

      final session = await FFmpegKit.execute(command);
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code)) return null;

      final active = SelfieSegmenter(
        mode: SegmenterMode.single,
        enableRawSizeMask: false,
      );
      segmenter = active;

      Uint8List? previous;
      var previousHadPerson = false;
      var maskW = 0;
      var maskH = 0;
      var written = 0;
      var detected = 0;
      var failures = 0;

      for (var i = 0; i < count; i++) {
        final name = (i + 1).toString().padLeft(5, '0');
        final frameFile = File('${source.path}/src_$name.jpg');
        if (!await frameFile.exists()) break;

        Uint8List? current;
        var hasPerson = false;

        try {
          final mask = await active
              .processImage(InputImage.fromFilePath(frameFile.path))
              .timeout(const Duration(seconds: 10));

          if (mask != null && mask.width > 0 && mask.height > 0) {
            final w = mask.width;
            final h = mask.height;
            final confidences = mask.confidences;

            if (maskW == 0) {
              maskW = w;
              maskH = h;
            }

            if (w == maskW &&
                h == maskH &&
                confidences.length >= w * h) {
              final bytes = Uint8List(w * h);
              var personPixels = 0;
              for (var p = 0; p < bytes.length; p++) {
                final c = confidences[p];
                if (c > 0.5) personPixels++;
                bytes[p] = _toByte(c);
              }

              hasPerson = personPixels >= bytes.length * _minimumCoverage;

              if (!hasPerson) {
                bytes.fillRange(0, bytes.length, 0);
              } else if (previous != null && previousHadPerson) {
                // Light temporal smoothing removes edge flicker between frames.
                for (var p = 0; p < bytes.length; p++) {
                  bytes[p] = ((bytes[p] * 7 + previous[p] * 3) / 10).round();
                }
              }

              current = bytes;
            }
          }
        } catch (_) {
          current = null;
        }

        if (current == null) {
          failures++;
          // Without any earlier mask there is nothing to hold: give up so the
          // caller can use the approximate matte instead.
          if (previous == null || failures >= 3) return null;
          current = previous;
          hasPerson = previousHadPerson;
        } else {
          failures = 0;
        }

        if (hasPerson) detected++;

        await File('$directory/matte_$name.png'.replaceFirst(
          'matte_$name',
          'matte_${i.toString().padLeft(5, '0')}',
        )).writeAsBytes(encodeGrayPng(current, maskW, maskH));

        previous = current;
        previousHadPerson = hasPerson;
        written++;

        try {
          await frameFile.delete();
        } catch (_) {}
      }

      if (written == 0 || detected == 0 || previous == null) return null;

      // The extractor can return a frame fewer than planned: hold the last
      // mask so the sequence always covers the whole scene window.
      final last = previous;
      for (var i = written; i < count; i++) {
        await File(
          '$directory/matte_${i.toString().padLeft(5, '0')}.png',
        ).writeAsBytes(encodeGrayPng(last, maskW, maskH));
      }

      return PersonMatteSequence(
        directory: directory,
        fps: rate,
        width: maskW,
        height: maskH,
        frameCount: count,
      );
    } finally {
      try {
        await segmenter?.close();
      } catch (_) {}
      await _deleteQuietly(source.path);
    }
  }

  /// Maps a model confidence (0..1) to a matte byte with a soft S-curve, so
  /// edges are firm but not jagged.
  static int _toByte(double confidence) {
    if (confidence.isNaN) return 0;
    final t = ((confidence - _low) / (_high - _low)).clamp(0.0, 1.0).toDouble();
    final s = t * t * (3 - 2 * t);
    return (s * 255).round().clamp(0, 255).toInt();
  }

  // ---------------------------------------------------------------------------
  // Minimal 8-bit grayscale PNG encoder (no dart:ui needed).
  // ---------------------------------------------------------------------------

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  }, growable: false);

  static int _crc32(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static void _chunk(BytesBuilder out, String type, List<int> data) {
    final typeBytes = type.codeUnits;
    final body = Uint8List(typeBytes.length + data.length);
    body.setRange(0, typeBytes.length, typeBytes);
    body.setRange(typeBytes.length, body.length, data);

    final length = ByteData(4)..setUint32(0, data.length);
    out.add(length.buffer.asUint8List());
    out.add(body);

    final crc = ByteData(4)..setUint32(0, _crc32(body));
    out.add(crc.buffer.asUint8List());
  }

  /// Encodes [gray] (one byte per pixel, row-major) as a grayscale PNG.
  static Uint8List encodeGrayPng(Uint8List gray, int width, int height) {
    if (width <= 0 || height <= 0 || gray.length < width * height) {
      throw ArgumentError('Invalid grayscale image size.');
    }

    final raw = BytesBuilder(copy: false);
    for (var y = 0; y < height; y++) {
      raw.addByte(0); // filter type: none
      raw.add(Uint8List.sublistView(gray, y * width, (y + 1) * width));
    }
    final compressed = zlib.encode(raw.takeBytes());

    final header = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 0) // colour type: grayscale
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);

    final out = BytesBuilder(copy: false);
    out.add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    _chunk(out, 'IHDR', header.buffer.asUint8List());
    _chunk(out, 'IDAT', compressed);
    _chunk(out, 'IEND', const <int>[]);
    return out.takeBytes();
  }
}
