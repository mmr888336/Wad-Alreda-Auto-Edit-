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

    // Track names (VIDEO and CAPTIONS) are painted directly onto the
    // CustomPainter canvas, so they are not standalone Text widgets.
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.text('VIDEO PREVIEW'), findsOneWidget);
    expect(find.text('PROJECT TIMELINE'), findsOneWidget);
    expect(find.byType(CustomPaint), findsOneWidget);
    expect(find.text('Open layer and motion details'), findsOneWidget);
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