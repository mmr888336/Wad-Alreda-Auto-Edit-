import 'package:auto_edit/timeline_engine.dart';
import 'package:auto_edit/timeline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineProject _sampleProject() {
  return TimelineProject(
    id: 'phase-3b-test',
    duration: 6,
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
            name: 'Source video',
            start: 0,
            end: 6,
            zIndex: 0,
          ),
        ],
      ),
      TimelineTrack(
        id: 'captions',
        name: 'Captions',
        type: TimelineTrackType.captions,
        order: 1,
        layers: [
          TimelineLayer(
            id: 'caption-one',
            trackId: 'captions',
            type: TimelineLayerType.caption,
            name: 'Caption one',
            text: 'A real caption layer',
            start: 1,
            end: 3,
            zIndex: 20,
            keyframes: const [
              TransformKeyframe(
                time: 1,
                transform: LayerTransform(x: 0.5, y: 0.85, opacity: 0),
                easing: KeyframeEasing.easeOut,
              ),
              TransformKeyframe(
                time: 1.25,
                transform: LayerTransform(x: 0.5, y: 0.8, opacity: 1),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows actual project summary and timeline tracks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TimelinePage(project: _sampleProject())),
    );
    await tester.pumpAndSettle();

    expect(find.text('ACTUAL EDIT MAP'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('72 px/s'), findsOneWidget);
  });

  testWidgets('selecting a caption displays its keyframes and transform',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TimelinePage(project: _sampleProject())),
    );
    await tester.pumpAndSettle();

    final canvas = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.size.width == 586.0,
    ).first;
    final rect = tester.getRect(canvas);
    // The first row is video. The second row is the caption track.
    // Label column = 126 px; the caption runs from 1s to 3s.
    await tester.tapAt(Offset(rect.left + 126 + 1.5 * 72,
        rect.top + 46 + 72 + 34));
    await tester.pumpAndSettle();

    expect(find.text('A real caption layer'), findsOneWidget);
    expect(find.text('KEYFRAME POINTS'), findsOneWidget);
    expect(find.textContaining('easeOut'), findsOneWidget);
    expect(find.textContaining('Scale'), findsOneWidget);
  });

  testWidgets('zoom controls change timeline scale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TimelinePage(project: _sampleProject())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();

    expect(find.text('90 px/s'), findsOneWidget);
  });
}
