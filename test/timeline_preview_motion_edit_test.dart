import 'dart:io';

import 'package:auto_edit/timeline_engine.dart';
import 'package:auto_edit/timeline_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineProject _project(String? brollPath) {
  return TimelineProject(
    id: 'preview-motion-edit-test',
    duration: 12,
    width: 1080,
    height: 1920,
    frameRate: 30,
    tracks: [
      TimelineTrack(
        id: 'track_video',
        name: 'VIDEO',
        type: TimelineTrackType.video,
        order: 0,
        layers: [
          TimelineLayer(
            id: 'source_video',
            trackId: 'track_video',
            type: TimelineLayerType.sourceVideo,
            name: 'Source video',
            start: 0,
            end: 12,
            zIndex: 0,
          ),
        ],
      ),
      TimelineTrack(
        id: 'track_broll',
        name: 'B-ROLL',
        type: TimelineTrackType.broll,
        order: 1,
        layers: [
          TimelineLayer(
            id: 'broll_0',
            trackId: 'track_broll',
            type: TimelineLayerType.broll,
            name: 'Motion scene 1',
            start: 3,
            end: 7,
            zIndex: 10,
            sourcePath: brollPath,
          ),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hides the motion section when no clip is editable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TimelinePreviewPage(project: _project(null))),
    );
    await tester.pumpAndSettle();

    expect(find.text('EDITABLE MOTION SCENES'), findsNothing);
    expect(find.text('Edit scene'), findsNothing);
  });

  testWidgets('offers to edit a motion scene that has an editable description',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('motion_preview_test');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final clip = File('${dir.path}/motion_scene_1_0.mp4')
      ..writeAsBytesSync(<int>[0]);
    File('${dir.path}/motion_scene_1_0.motion.json').writeAsStringSync('{}');

    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: TimelinePreviewPage(project: _project(clip.path))),
    );
    await tester.pumpAndSettle();

    expect(find.text('EDITABLE MOTION SCENES'), findsOneWidget);
    expect(find.text('Edit scene'), findsOneWidget);
    expect(find.text('Motion scene 1'), findsOneWidget);
  });

  testWidgets('a clip without an editable description is not offered',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('motion_preview_test');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final clip = File('${dir.path}/broll_plain.mp4')
      ..writeAsBytesSync(<int>[0]);

    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: TimelinePreviewPage(project: _project(clip.path))),
    );
    await tester.pumpAndSettle();

    expect(find.text('EDITABLE MOTION SCENES'), findsNothing);
  });
}
