import 'package:auto_edit/timeline_editing.dart';
import 'package:auto_edit/timeline_engine.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineProject _sampleProject({
  double duration = 10,
  List<TransformKeyframe> keyframes = const [],
}) {
  return TimelineProject(
    id: 'timeline-edit-test',
    duration: duration,
    width: 1080,
    height: 1920,
    frameRate: 30,
    tracks: [
      TimelineTrack(
        id: 'video',
        name: 'Video',
        type: TimelineTrackType.video,
        order: 0,
        layers: [
          TimelineLayer(
            id: 'source',
            trackId: 'video',
            type: TimelineLayerType.sourceVideo,
            name: 'Main video',
            start: 0,
            end: duration,
            zIndex: 0,
          ),
        ],
      ),
      TimelineTrack(
        id: 'broll',
        name: 'B-roll',
        type: TimelineTrackType.broll,
        order: 1,
        layers: [
          TimelineLayer(
            id: 'broll_1',
            trackId: 'broll',
            type: TimelineLayerType.broll,
            name: 'B-roll one',
            start: 2,
            end: 6,
            zIndex: 10,
            sourcePath: '/old/clip.mp4',
            keyframes: keyframes,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('Timeline editing operations', () {
    test('moves a clip and shifts its keyframes by the same amount', () {
      final original = _sampleProject(
        keyframes: const [
          TransformKeyframe(
            time: 2,
            transform: LayerTransform(x: 0.2),
          ),
          TransformKeyframe(
            time: 4,
            transform: LayerTransform(x: 0.8),
            easing: KeyframeEasing.easeOut,
          ),
        ],
      );

      final moved = TimelineEditing.moveLayer(
        project: original,
        layerId: 'broll_1',
        newStart: 3,
      );
      final layer = moved.layerById('broll_1')!;

      expect(layer.start, 3);
      expect(layer.end, 7);
      expect(layer.duration, 4);
      expect(layer.keyframes.map((frame) => frame.time), [3, 5]);
      expect(layer.keyframes.last.easing, KeyframeEasing.easeOut);
      expect(original.layerById('broll_1')!.start, 2);
      expect(moved.validate(), isEmpty);
    });

    test('clamps a moved clip so it cannot leave the project duration', () {
      final moved = TimelineEditing.moveLayer(
        project: _sampleProject(),
        layerId: 'broll_1',
        newStart: 99,
      );

      final layer = moved.layerById('broll_1')!;
      expect(layer.start, 6);
      expect(layer.end, 10);
      expect(moved.validate(), isEmpty);
    });

    test('trims a clip and keeps keyframes inside the new range', () {
      final original = _sampleProject(
        keyframes: const [
          TransformKeyframe(
            time: 2,
            transform: LayerTransform(scale: 1),
          ),
          TransformKeyframe(
            time: 3,
            transform: LayerTransform(scale: 1.5),
          ),
          TransformKeyframe(
            time: 5,
            transform: LayerTransform(scale: 2),
          ),
          TransformKeyframe(
            time: 6,
            transform: LayerTransform(scale: 1),
          ),
        ],
      );

      final trimmed = TimelineEditing.trimLayer(
        project: original,
        layerId: 'broll_1',
        newStart: 2.5,
        newEnd: 5.5,
      );
      final layer = trimmed.layerById('broll_1')!;

      expect(layer.start, 2.5);
      expect(layer.end, 5.5);
      expect(layer.keyframes.first.time, 2.5);
      expect(layer.keyframes.last.time, 5.5);
      expect(layer.keyframes.every(
        (frame) => frame.time >= layer.start && frame.time <= layer.end,
      ), isTrue);
      expect(layer.transformAt(2.5).scale, closeTo(1.25, 0.000001));
      expect(trimmed.validate(), isEmpty);
    });

    test('rejects a trim shorter than one output frame', () {
      expect(
        () => TimelineEditing.trimLayer(
          project: _sampleProject(),
          layerId: 'broll_1',
          newStart: 3,
          newEnd: 3.01,
        ),
        throwsArgumentError,
      );
    });

    test('does not allow trimming beyond the current source range', () {
      expect(
        () => TimelineEditing.trimLayer(
          project: _sampleProject(),
          layerId: 'broll_1',
          newStart: 1,
        ),
        throwsArgumentError,
      );
    });

    test('replaces B-roll with an image while preserving clip timing', () {
      final replaced = TimelineEditing.replaceBrollSource(
        project: _sampleProject(),
        layerId: 'broll_1',
        sourcePath: '/gallery/new-shot.jpg',
        displayName: 'New image',
      );
      final layer = replaced.layerById('broll_1')!;

      expect(layer.sourcePath, '/gallery/new-shot.jpg');
      expect(layer.name, 'New image');
      expect(layer.start, 2);
      expect(layer.end, 6);
      expect(TimelineEditing.isImageAssetPath(layer.sourcePath!), isTrue);
      expect(replaced.validate(), isEmpty);
    });

    test('replaces B-roll with another video', () {
      final replaced = TimelineEditing.replaceBrollSource(
        project: _sampleProject(),
        layerId: 'broll_1',
        sourcePath: '/gallery/alternative.MP4',
      );

      expect(replaced.layerById('broll_1')!.sourcePath,
          '/gallery/alternative.MP4');
      expect(
        TimelineEditing.isImageAssetPath('/gallery/alternative.MP4'),
        isFalse,
      );
    });

    test('rejects replacing a non-B-roll layer or unsupported file', () {
      expect(
        () => TimelineEditing.replaceBrollSource(
          project: _sampleProject(),
          layerId: 'source',
          sourcePath: '/gallery/new.mp4',
        ),
        throwsArgumentError,
      );
      expect(
        () => TimelineEditing.replaceBrollSource(
          project: _sampleProject(),
          layerId: 'broll_1',
          sourcePath: '/gallery/document.pdf',
        ),
        throwsArgumentError,
      );
    });

    test('adds keyframes in order and replaces one at the same time', () {
      final original = _sampleProject();
      final first = TimelineEditing.setKeyframe(
        project: original,
        layerId: 'broll_1',
        time: 4,
        transform: const LayerTransform(scale: 1.5),
        easing: KeyframeEasing.easeInOut,
      );
      final second = TimelineEditing.setKeyframe(
        project: first,
        layerId: 'broll_1',
        time: 3,
        transform: const LayerTransform(scale: 1.2),
      );
      final replaced = TimelineEditing.setKeyframe(
        project: second,
        layerId: 'broll_1',
        time: 4,
        transform: const LayerTransform(scale: 2),
      );
      final frames = replaced.layerById('broll_1')!.keyframes;

      expect(frames.map((frame) => frame.time), [3, 4]);
      expect(frames.last.transform.scale, 2);
      expect(frames.last.easing, KeyframeEasing.easeInOut);
      expect(replaced.validate(), isEmpty);
    });

    test('rejects keyframes outside the selected layer', () {
      expect(
        () => TimelineEditing.setKeyframe(
          project: _sampleProject(),
          layerId: 'broll_1',
          time: 8,
          transform: const LayerTransform(),
        ),
        throwsArgumentError,
      );
    });
  });
}
