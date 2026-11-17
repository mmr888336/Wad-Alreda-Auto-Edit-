import 'package:auto_edit/motion_timeline_integration.dart';
import 'package:auto_edit/timeline_engine.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineProject _project() {
  return TimelineProject(
    id: 'motion-integration-test',
    duration: 20,
    width: 1080,
    height: 1920,
    frameRate: 30,
    tracks: [
      TimelineTrack(
        id: 'track_broll',
        name: 'B-roll',
        type: TimelineTrackType.broll,
        order: 1,
        layers: [
          TimelineLayer(
            id: 'broll_0',
            trackId: 'track_broll',
            type: TimelineLayerType.broll,
            name: 'Motion scene 1',
            start: 4,
            end: 9,
            zIndex: 10,
            sourcePath: '/tmp/motion_scene_1_0.mp4',
          ),
        ],
      ),
      TimelineTrack(
        id: 'track_captions',
        name: 'Captions',
        type: TimelineTrackType.captions,
        order: 2,
        layers: [
          TimelineLayer(
            id: 'caption_0',
            trackId: 'track_captions',
            type: TimelineLayerType.caption,
            name: 'Caption 1',
            text: 'hello',
            start: 1,
            end: 3,
            zIndex: 20,
          ),
        ],
      ),
    ],
  );
}

void main() {
  final layer = _project().layerById('broll_0')!;

  group('overlayWindow', () {
    test('is the whole layer when the clip has the same length', () {
      final window = MotionTimelineIntegration.overlayWindow(layer, 5)!;
      expect(window.start, 4);
      expect(window.end, 9);
      expect(window.duration, 5);
    });

    test('never goes past the layer end when the clip is longer', () {
      final window = MotionTimelineIntegration.overlayWindow(layer, 8)!;
      expect(window.start, 4);
      expect(window.end, 9);
    });

    test('ends with the clip when the clip is shorter', () {
      final window = MotionTimelineIntegration.overlayWindow(layer, 3.5)!;
      expect(window.start, 4);
      expect(window.end, closeTo(7.5, 1e-9));
    });

    test('is null for unusable clip lengths', () {
      expect(MotionTimelineIntegration.overlayWindow(layer, 0), isNull);
      expect(MotionTimelineIntegration.overlayWindow(layer, -1), isNull);
      expect(MotionTimelineIntegration.overlayWindow(layer, 0.1), isNull);
      expect(
        MotionTimelineIntegration.overlayWindow(layer, double.nan),
        isNull,
      );
      expect(
        MotionTimelineIntegration.overlayWindow(layer, double.infinity),
        isNull,
      );
    });
  });

  group('applyEditedClip', () {
    test('points the layer at the new clip and keeps its window', () {
      final next = MotionTimelineIntegration.applyEditedClip(
        project: _project(),
        layerId: 'broll_0',
        clipPath: '/tmp/motion_scene_1_1.mp4',
        clipDuration: 5,
      );
      final edited = next.layerById('broll_0')!;
      expect(edited.sourcePath, '/tmp/motion_scene_1_1.mp4');
      expect(edited.start, 4);
      expect(edited.end, 9);
      expect(edited.name, 'Motion scene 1');
      expect(next.validate(), isEmpty);
    });

    test('trims the layer when the new clip is shorter', () {
      final next = MotionTimelineIntegration.applyEditedClip(
        project: _project(),
        layerId: 'broll_0',
        clipPath: '/tmp/motion_scene_1_1.mp4',
        clipDuration: 3,
      );
      final edited = next.layerById('broll_0')!;
      expect(edited.sourcePath, '/tmp/motion_scene_1_1.mp4');
      expect(edited.start, 4);
      expect(edited.end, closeTo(7, 1e-9));
      expect(next.validate(), isEmpty);
    });

    test('does not touch other layers or the original project', () {
      final original = _project();
      final next = MotionTimelineIntegration.applyEditedClip(
        project: original,
        layerId: 'broll_0',
        clipPath: '/tmp/motion_scene_1_1.mp4',
        clipDuration: 3,
      );
      expect(next.layerById('caption_0')!.end, 3);
      expect(original.layerById('broll_0')!.sourcePath,
          '/tmp/motion_scene_1_0.mp4');
      expect(original.layerById('broll_0')!.end, 9);
    });

    test('throws for an unknown layer', () {
      expect(
        () => MotionTimelineIntegration.applyEditedClip(
          project: _project(),
          layerId: 'missing',
          clipPath: '/tmp/a.mp4',
          clipDuration: 3,
        ),
        throwsArgumentError,
      );
    });

    test('throws for a layer that is not B-roll', () {
      expect(
        () => MotionTimelineIntegration.applyEditedClip(
          project: _project(),
          layerId: 'caption_0',
          clipPath: '/tmp/a.mp4',
          clipDuration: 1.5,
        ),
        throwsArgumentError,
      );
    });

    test('throws when the edited clip is too short', () {
      expect(
        () => MotionTimelineIntegration.applyEditedClip(
          project: _project(),
          layerId: 'broll_0',
          clipPath: '/tmp/a.mp4',
          clipDuration: 0.1,
        ),
        throwsArgumentError,
      );
    });
  });
}
