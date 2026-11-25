import 'package:auto_edit/person_silhouette.dart';
import 'package:auto_edit/timeline_engine.dart';
import 'package:auto_edit/world_scene_compositor.dart';
import 'package:flutter_test/flutter_test.dart';

const _matte = PersonMatteSequence(
  directory: '/m',
  fps: 12,
  width: 480,
  height: 854,
  frameCount: 36,
);

const _clip = WorldBackgroundClip(path: '/w/a.mp4', start: 1.0, end: 4.0);

TimelineLayer _layer({
  required String id,
  required TimelineLayerType type,
  String? path = '/c/cap.png',
  double start = 1.0,
  double end = 3.0,
  bool visible = true,
  List<TransformKeyframe> keyframes = const <TransformKeyframe>[],
}) {
  return TimelineLayer(
    id: id,
    trackId: 't',
    type: type,
    name: id,
    start: start,
    end: end,
    zIndex: 1,
    sourcePath: path,
    visible: visible,
    keyframes: keyframes,
  );
}

TimelineProject _project(List<TimelineLayer> layers) {
  return TimelineProject(
    id: 'p',
    duration: 10,
    width: 540,
    height: 960,
    tracks: <TimelineTrack>[
      TimelineTrack(
        id: 't',
        name: 't',
        type: TimelineTrackType.captions,
        order: 0,
        layers: layers,
      ),
    ],
  );
}

void main() {
  group('person on top of the world', () {
    test('a clip with a matte adds a cut-out of the video window', () {
      final plan = WorldBackgroundCommand.build(
        videoPath: '/v/main.mp4',
        width: 540,
        height: 960,
        clips: <WorldBackgroundClip>[_clip.withMatte(_matte)],
      );

      expect(plan.inputs, hasLength(4));
      expect(plan.inputs[2], '-ss 1.000 -t 3.100 -i "/v/main.mp4"');
      expect(plan.inputs[3], '-framerate 12.000 -i "/m/matte_%05d.png"');
      expect(plan.filterComplex, contains('alphamerge'));
      expect(
        plan.filterComplex,
        contains('overlay=x=0:y=0:eof_action=pass:repeatlast=0'),
      );
      expect(plan.filterComplex.endsWith('[world_bg_out]'), isTrue);
    });

    test('a clip without a matte adds no person input', () {
      final plan = WorldBackgroundCommand.build(
        videoPath: '/v/main.mp4',
        width: 540,
        height: 960,
        clips: const <WorldBackgroundClip>[_clip],
      );

      expect(plan.inputs, hasLength(2));
      expect(plan.filterComplex.contains('alphamerge'), isFalse);
    });
  });

  group('captions on top of the world', () {
    test('a caption inside the window is drawn again, centred at its y', () {
      final plan = WorldBackgroundCommand.build(
        videoPath: '/v/main.mp4',
        width: 540,
        height: 960,
        clips: const <WorldBackgroundClip>[_clip],
        textOverlays: const <WorldTextOverlay>[
          WorldTextOverlay(path: '/c/cap.png', start: 1.5, end: 3.0, y: 0.8),
        ],
      );

      expect(plan.inputs, hasLength(3));
      expect(plan.inputs.last, contains('-loop 1'));
      expect(plan.inputs.last, contains('"/c/cap.png"'));
      expect(plan.filterComplex, contains('between(t,1.500,3.000)'));
      expect(plan.filterComplex, contains('main_h*0.800-overlay_h/2'));
      expect(plan.filterComplex.endsWith('[world_bg_out]'), isTrue);
    });

    test('a caption outside every world window is not added', () {
      final plan = WorldBackgroundCommand.build(
        videoPath: '/v/main.mp4',
        width: 540,
        height: 960,
        clips: const <WorldBackgroundClip>[_clip],
        textOverlays: const <WorldTextOverlay>[
          WorldTextOverlay(path: '/c/late.png', start: 6.0, end: 7.0, y: 0.8),
        ],
      );

      expect(plan.inputs, hasLength(2));
    });

    test('a caption that crosses the window is cut to the window', () {
      final plan = WorldBackgroundCommand.build(
        videoPath: '/v/main.mp4',
        width: 540,
        height: 960,
        clips: const <WorldBackgroundClip>[_clip],
        textOverlays: const <WorldTextOverlay>[
          WorldTextOverlay(path: '/c/long.png', start: 3.0, end: 6.0, y: 0.8),
        ],
      );

      expect(plan.filterComplex, contains('between(t,3.000,4.000)'));
    });
  });

  group('text overlays from the timeline', () {
    test('captions and titles with a picture are read, others are not', () {
      final overlays = WorldTextOverlay.fromTimeline(
        _project(<TimelineLayer>[
          _layer(
            id: 'cap',
            type: TimelineLayerType.caption,
            keyframes: const <TransformKeyframe>[
              TransformKeyframe(
                time: 1.0,
                transform: LayerTransform(y: 0.9),
              ),
              TransformKeyframe(
                time: 1.3,
                transform: LayerTransform(y: 0.78),
              ),
            ],
          ),
          // Later start, so the order of the two results does not depend on a
          // tie between equal start times.
          _layer(
            id: 'title',
            type: TimelineLayerType.title,
            start: 2.0,
            end: 3.0,
          ),
          _layer(id: 'hidden', type: TimelineLayerType.caption, visible: false),
          _layer(id: 'nopath', type: TimelineLayerType.caption, path: null),
          _layer(id: 'shape', type: TimelineLayerType.shape),
        ]),
      );

      expect(overlays, hasLength(2));
      expect(overlays.first.y, closeTo(0.78, 1e-9));
      expect(overlays.first.path, '/c/cap.png');
      // A title without keyframes falls back to the top of the frame.
      expect(overlays.last.y, closeTo(0.10, 1e-9));
    });
  });
}
