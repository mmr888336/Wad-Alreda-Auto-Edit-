import 'dart:convert';

import 'package:auto_edit/timeline_engine.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineLayer _layer({
  String id = 'caption_1',
  String trackId = 'captions',
  double start = 0,
  double end = 3,
  List<TransformKeyframe> keyframes = const [],
}) {
  return TimelineLayer(
    id: id,
    trackId: trackId,
    type: TimelineLayerType.caption,
    name: 'Test caption',
    start: start,
    end: end,
    zIndex: 20,
    text: 'مرحبا',
    keyframes: keyframes,
  );
}

TimelineProject _project(List<TimelineLayer> layers) {
  return TimelineProject(
    id: 'test-project',
    duration: 5,
    width: 1080,
    height: 1920,
    tracks: [
      TimelineTrack(
        id: 'captions',
        name: 'Captions',
        type: TimelineTrackType.captions,
        order: 2,
        layers: layers,
      ),
    ],
  );
}

void main() {
  group('Timeline keyframe engine', () {
    test('interpolates every transform channel linearly', () {
      final layer = _layer(
        keyframes: const [
          TransformKeyframe(
            time: 0,
            transform: LayerTransform(
              x: 0.2,
              y: 0.8,
              scale: 1,
              rotation: 0,
              opacity: 0,
            ),
          ),
          TransformKeyframe(
            time: 2,
            transform: LayerTransform(
              x: 0.8,
              y: 0.4,
              scale: 1.4,
              rotation: 45,
              opacity: 1,
            ),
          ),
        ],
      );

      final middle = layer.transformAt(1);
      expect(middle.x, closeTo(0.5, 0.000001));
      expect(middle.y, closeTo(0.6, 0.000001));
      expect(middle.scale, closeTo(1.2, 0.000001));
      expect(middle.rotation, closeTo(22.5, 0.000001));
      expect(middle.opacity, closeTo(0.5, 0.000001));
    });

    test('ease-out reaches the expected interpolated value', () {
      final layer = _layer(
        keyframes: const [
          TransformKeyframe(
            time: 0,
            transform: LayerTransform(x: 0),
            easing: KeyframeEasing.easeOut,
          ),
          TransformKeyframe(
            time: 2,
            transform: LayerTransform(x: 1),
          ),
        ],
      );

      expect(layer.transformAt(1).x, closeTo(0.875, 0.000001));
    });

    test('holds the first and last transform outside keyframe range', () {
      final layer = _layer(
        keyframes: const [
          TransformKeyframe(time: 1, transform: LayerTransform(x: 0.25)),
          TransformKeyframe(time: 2, transform: LayerTransform(x: 0.75)),
        ],
      );

      expect(layer.transformAt(0).x, 0.25);
      expect(layer.transformAt(4).x, 0.75);
    });

    test('creates an FFmpeg expression for animated coordinates', () {
      final layer = _layer(
        keyframes: const [
          TransformKeyframe(
            time: 0.2,
            transform: LayerTransform(y: 0.9),
            easing: KeyframeEasing.easeOut,
          ),
          TransformKeyframe(
            time: 0.5,
            transform: LayerTransform(y: 0.8),
          ),
        ],
      );

      final expression =
          layer.ffmpegExpression(TransformProperty.y, fallback: '0.5');

      expect(expression, contains('if(lt(t,0.200000)'));
      expect(expression, contains('pow('));
      expect(expression, contains('0.900000'));
      expect(expression, contains('0.800000'));
    });

    test('serializes and restores a complete timeline project', () {
      final original = _project([
        _layer(
          keyframes: const [
            TransformKeyframe(
              time: 0,
              transform: LayerTransform(x: 0.5, y: 0.9, opacity: 0),
              easing: KeyframeEasing.easeOut,
            ),
            TransformKeyframe(
              time: 0.3,
              transform: LayerTransform(x: 0.5, y: 0.8, opacity: 1),
            ),
          ],
        ),
      ]);

      final json = jsonDecode(jsonEncode(original.toJson()))
          as Map<String, dynamic>;
      final restored = TimelineProject.fromJson(json);

      expect(restored.validate(), isEmpty);
      expect(restored.id, original.id);
      expect(restored.width, 1080);
      expect(restored.layers.single.text, 'مرحبا');
      expect(
        restored.layers.single.transformAt(0.15).opacity,
        closeTo(0.875, 0.000001),
      );
    });

    test('sorts layer queries by timeline start', () {
      final project = _project([
        _layer(id: 'later', start: 2, end: 4),
        _layer(id: 'earlier', start: 0.5, end: 1.5),
      ]);

      expect(
        project.layersOfType(TimelineLayerType.caption)
            .map((layer) => layer.id)
            .toList(),
        ['earlier', 'later'],
      );
      expect(project.layerById('later')?.start, 2);
    });

    test('reports broken track references and keyframe order', () {
      final project = _project([
        _layer(
          trackId: 'wrong_track',
          keyframes: const [
            TransformKeyframe(time: 1, transform: LayerTransform()),
            TransformKeyframe(time: 0.5, transform: LayerTransform()),
          ],
        ),
      ]);

      final errors = project.validate();
      expect(errors, isNotEmpty);
      expect(errors.any((error) => error.contains('different track')), isTrue);
      expect(errors.any((error) => error.contains('keyframe')), isTrue);
    });

    test('rejects invalid opacity and project dimensions', () {
      final project = TimelineProject(
        id: 'bad-project',
        duration: 3,
        width: 0,
        height: 1920,
        tracks: [
          TimelineTrack(
            id: 'captions',
            name: 'Captions',
            type: TimelineTrackType.captions,
            order: 0,
            layers: [
              _layer(
                keyframes: const [
                  TransformKeyframe(
                    time: 0,
                    transform: LayerTransform(opacity: 1.5),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final errors = project.validate();
      expect(errors.any((error) => error.contains('dimensions')), isTrue);
      expect(errors.any((error) => error.contains('transform')), isTrue);
    });
  });
}
