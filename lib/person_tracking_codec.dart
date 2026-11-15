import 'dart:convert';

import 'person_tracking_models.dart';

/// Saves tracking results as compact JSON and loads them back, so later
/// phases (3D integration, camera tracking) can reuse a video's tracks
/// without running detection again.
///
/// Numbers are rounded to 4 decimals. Unknown landmark names are skipped on
/// load, and malformed data raises a [FormatException].
class PersonTrackingCodec {
  PersonTrackingCodec._();

  static const int version = 1;

  static double _round(double value) =>
      (value * 10000).roundToDouble() / 10000;

  static Map<String, Object?> encode(PersonTrackingResult result) {
    return <String, Object?>{
      'v': version,
      'fps': result.sampleFps,
      'w': result.frameWidth,
      'h': result.frameHeight,
      'frames': result.framesAnalyzed,
      'failed': result.failedFrames,
      'primary': result.primaryTrackId,
      'notes': result.notes,
      'tracks': result.tracks.map(_encodeTrack).toList(),
    };
  }

  static String encodeToString(PersonTrackingResult result) =>
      jsonEncode(encode(result));

  static Map<String, Object?> _encodeTrack(PersonTrack track) {
    return <String, Object?>{
      'id': track.id,
      'obs': track.observations.map(_encodeObservation).toList(),
    };
  }

  static Map<String, Object?> _encodeObservation(PersonObservation item) {
    final landmarks = <String, Object?>{};
    item.landmarks.forEach((type, point) {
      landmarks[type.name] = <double>[
        _round(point.x),
        _round(point.y),
        _round(point.z),
        _round(point.confidence),
      ];
    });
    return <String, Object?>{
      't': _round(item.time),
      'b': <double>[
        _round(item.box.left),
        _round(item.box.top),
        _round(item.box.right),
        _round(item.box.bottom),
      ],
      'c': _round(item.confidence),
      'lm': landmarks,
    };
  }

  static PersonTrackingResult decodeFromString(String text) {
    final Object? parsed = jsonDecode(text);
    return decode(_map(parsed));
  }

  static PersonTrackingResult decode(Map<String, Object?> json) {
    final found = json['v'];
    if (found != version) {
      throw FormatException('Unsupported tracking data version: $found');
    }

    final tracks = <PersonTrack>[];
    for (final rawTrack in _list(json['tracks'])) {
      final map = _map(rawTrack);
      final observations = <PersonObservation>[
        for (final rawObservation in _list(map['obs']))
          _decodeObservation(_map(rawObservation)),
      ];
      tracks.add(PersonTrack(id: _int(map['id']), observations: observations));
    }

    final primary = json['primary'];
    final notes = json['notes'];

    return PersonTrackingResult(
      sampleFps: _num(json['fps']),
      frameWidth: _int(json['w']),
      frameHeight: _int(json['h']),
      framesAnalyzed: _int(json['frames']),
      failedFrames: json['failed'] == null ? 0 : _int(json['failed']),
      tracks: tracks,
      primaryTrackId: primary == null ? null : _int(primary),
      notes: notes == null
          ? const <String>[]
          : <String>[for (final note in _list(notes)) note.toString()],
    );
  }

  static PersonObservation _decodeObservation(Map<String, Object?> json) {
    final box = _list(json['b']);
    if (box.length != 4) throw const FormatException('Invalid box.');

    final landmarks = <BodyLandmark, LandmarkPoint>{};
    final rawLandmarks = json['lm'];
    if (rawLandmarks != null) {
      _map(rawLandmarks).forEach((name, value) {
        final type = BodyLandmark.fromName(name);
        if (type == null) return;
        final point = _list(value);
        if (point.length != 4) throw const FormatException('Invalid landmark.');
        landmarks[type] = LandmarkPoint(
          x: _num(point[0]),
          y: _num(point[1]),
          z: _num(point[2]),
          confidence: _num(point[3]),
        );
      });
    }

    return PersonObservation(
      time: _num(json['t']),
      box: NormalizedRect(
        left: _num(box[0]),
        top: _num(box[1]),
        right: _num(box[2]),
        bottom: _num(box[3]),
      ),
      confidence: _num(json['c']),
      landmarks: landmarks,
    );
  }

  static double _num(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Expected a finite number, got: $value');
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw FormatException('Expected an integer, got: $value');
  }

  static List<Object?> _list(Object? value) {
    if (value is List) return List<Object?>.from(value);
    throw FormatException('Expected a list, got: $value');
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) {
      return value.map<String, Object?>(
        (key, item) => MapEntry<String, Object?>(key.toString(), item),
      );
    }
    throw FormatException('Expected an object, got: $value');
  }
}
