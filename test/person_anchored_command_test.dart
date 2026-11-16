import 'dart:typed_data';

import 'package:auto_edit/person_anchor_path.dart';
import 'package:auto_edit/person_anchored_command.dart';
import 'package:auto_edit/person_silhouette.dart';
import 'package:auto_edit/person_tracking_models.dart';
import 'package:auto_edit/scene_key_color.dart';
import 'package:flutter_test/flutter_test.dart';

LandmarkPoint _pt(double x, double y) =>
    LandmarkPoint(x: x, y: y, confidence: 0.9);

PersonTrack _track() {
  final observations = <PersonObservation>[];
  for (var i = 0; i <= 50; i++) {
    const cx = 0.4;
    observations.add(
      PersonObservation(
        time: i * 0.2,
        box: const NormalizedRect(
          left: cx - 0.15,
          top: 0.2,
          right: cx + 0.15,
          bottom: 0.9,
        ),
        confidence: 0.9,
        landmarks: <BodyLandmark, LandmarkPoint>{
          BodyLandmark.nose: _pt(cx, 0.3),
          BodyLandmark.leftShoulder: _pt(cx + 0.1, 0.45),
          BodyLandmark.rightShoulder: _pt(cx - 0.1, 0.45),
          BodyLandmark.leftHip: _pt(cx + 0.08, 0.7),
          BodyLandmark.rightHip: _pt(cx - 0.08, 0.7),
        },
      ),
    );
  }
  return PersonTrack(id: 1, observations: observations);
}

Uint8List _image(int width, int height, List<int> Function(int x) colorAt) {
  final data = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = colorAt(x);
      final offset = (y * width + x) * 4;
      data[offset] = color[0];
      data[offset + 1] = color[1];
      data[offset + 2] = color[2];
      data[offset + 3] = 255;
    }
  }
  return data;
}

void main() {
  group('PersonAnchoredCommand', () {
    final path = PersonAnchorPath.plan(
      track: _track(),
      start: 1,
      end: 3,
      placement: PersonPlacement.behindShoulder,
      frameWidth: 1080,
      frameHeight: 1920,
    )!;

    const matte = PersonMatteSequence(
      directory: '/tmp/m',
      fps: 12,
      width: 240,
      height: 426,
      frameCount: 25,
    );

    test('anchors a scene behind the person and keeps a panel fallback', () {
      final command = PersonAnchoredCommand.build(
        videoPath: '/v/in.mp4',
        outputPath: '/v/out.mp4',
        width: 1080,
        height: 1920,
        duration: 10,
        scenes: <AnchoredSceneSpec>[
          AnchoredSceneSpec(
            scenePath: '/v/pip.mp4',
            start: 5,
            end: 7,
          ),
          AnchoredSceneSpec(
            scenePath: '/v/anchored.mp4',
            start: 1,
            end: 3,
            path: path,
            matte: matte,
            keyColors: const <String>['0x101521'],
          ),
        ],
      );

      expect(command, contains('-filter_complex'));
      expect(command, contains('colorkey=0x101521:0.12:0.08'));
      expect(command, contains('alphamerge'));
      expect(command, contains('-framerate 12.000 -i "/tmp/m/matte_%05d.png"'));
      expect(command, contains("overlay=x='if(lt(t,"));
      expect(command, contains("enable='between(t,1.000,3.000)'"));
      expect(command, contains('drawbox'));
      expect(command, contains("enable='between(t,5.000,7.000)'"));
      expect(command, contains('-map "0:a?"'));
      expect(command, endsWith('"/v/out.mp4"'));

      // Inputs: video, anchored scene, person window, matte, pip scene.
      expect(RegExp(r'-i "').allMatches(command).length, 5);
    });

    test('the person layer is its own short input, never a split of the '
        'full video (that buffered every frame and crashed the app)', () {
      final command = PersonAnchoredCommand.build(
        videoPath: '/v/in.mp4',
        outputPath: '/v/out.mp4',
        width: 1080,
        height: 1920,
        duration: 10,
        scenes: <AnchoredSceneSpec>[
          AnchoredSceneSpec(
            scenePath: '/v/anchored.mp4',
            start: 1,
            end: 3,
            path: path,
            matte: matte,
            keyColors: const <String>['0x101521'],
          ),
        ],
      );

      expect(command, isNot(contains('split=')));
      expect(command, isNot(contains('trim=start')));
      expect(command, contains('-ss 1.000 -t 2.100 -i "/v/in.mp4"'));
      expect(RegExp(r'-i "/v/in\.mp4"').allMatches(command).length, 2);
      expect(command, isNot(contains('-preset slow')));
    });

    test('without occlusion no person layer is created', () {
      final command = PersonAnchoredCommand.build(
        videoPath: '/v/in.mp4',
        outputPath: '/v/out.mp4',
        width: 1080,
        height: 1920,
        duration: 10,
        scenes: <AnchoredSceneSpec>[
          AnchoredSceneSpec(
            scenePath: '/v/anchored.mp4',
            start: 1,
            end: 3,
            path: path,
          ),
        ],
        maximumQuality: false,
      );

      expect(command, isNot(contains('split=')));
      expect(command, isNot(contains('alphamerge')));
      expect(command, isNot(contains('-ss ')));
      expect(command, contains('-preset veryfast'));
    });

    test('rejects an empty scene list', () {
      expect(
        () => PersonAnchoredCommand.build(
          videoPath: '/v/in.mp4',
          outputPath: '/v/out.mp4',
          width: 1080,
          height: 1920,
          duration: 10,
          scenes: const <AnchoredSceneSpec>[],
        ),
        throwsArgumentError,
      );
    });
  });

  group('SceneKeyColor.dominantEdgeColors', () {
    test('finds a flat background', () {
      final data = _image(16, 16, (x) => <int>[13, 16, 25]);
      expect(
        SceneKeyColor.dominantEdgeColors(data, 16, 16),
        <String>['0x0D1019'],
      );
    });

    test('returns the two dominant edge colors, strongest first', () {
      final data = _image(
        16,
        16,
        (x) => x < 8 ? <int>[16, 21, 33] : <int>[200, 0, 200],
      );
      final colors = SceneKeyColor.dominantEdgeColors(data, 16, 16);

      expect(colors.length, 2);
      expect(colors.first, '0xC800C8');
      expect(colors.last, '0x101521');
    });

    test('returns nothing for invalid input', () {
      expect(
        SceneKeyColor.dominantEdgeColors(Uint8List(8), 16, 16),
        isEmpty,
      );
    });
  });
}
