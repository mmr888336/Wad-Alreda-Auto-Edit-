import 'package:auto_edit/timeline_engine.dart';
import 'package:auto_edit/timeline_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineProject _sampleProject() {
  return TimelineProject(
    id: 'phase-3d-preview-test',
    duration: 8,
    width: 1080,
    height: 1920,
    frameRate: 30,
    tracks: [
      TimelineTrack(
        id: 'video',
        name: 'VIDEO',
        type: TimelineTrackType.video,
        order: 0,
        layers: [
          TimelineLayer(
            id: 'source',
            trackId: 'video',
            type: TimelineLayerType.sourceVideo,
            name: 'Source video',
            start: 0,
            end: 8,
            zIndex: 0,
          ),
        ],
      ),
      TimelineTrack(
        id: 'captions',
        name: 'CAPTIONS',
        type: TimelineTrackType.captions,
        order: 1,
        layers: [
          TimelineLayer(
            id: 'caption-one',
            trackId: 'captions',
            type: TimelineLayerType.caption,
            name: 'Caption one',
            text: 'A real caption',
            start: 1,
            end: 4,
            zIndex: 20,
          ),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows preview placeholder and actual project timeline',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePreviewPage(project: _sampleProject()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.text('VIDEO PREVIEW'), findsOneWidget);
    expect(find.text('PROJECT TIMELINE'), findsOneWidget);
    expect(find.text('Open layer and motion details'), findsOneWidget);

    // The timeline canvas has a known size for this 8-second sample project:
    // width = 104 label + (8 seconds * 68 px) + 24 padding = 672 px
    // height = 30 px ruler + (2 tracks * 42 px) = 114 px.
    // Match this exact CustomPaint instead of counting every CustomPaint in
    // the widget tree (icons and framework controls create additional ones).
    final timelineCanvas = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.size == const Size(672, 114),
    );
    expect(timelineCanvas, findsOneWidget);
  });

  testWidgets('shows play controls disabled when no video path is supplied',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelinePreviewPage(project: _sampleProject()),
      ),
    );
    await tester.pumpAndSettle();

    final playButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Play',
      ),
    );
    expect(playButton.onPressed, isNull);
  });
}
