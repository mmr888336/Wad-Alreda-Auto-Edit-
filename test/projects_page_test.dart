import 'dart:io';

import 'package:auto_edit/project_store.dart';
import 'package:auto_edit/projects_page.dart';
import 'package:auto_edit/timeline_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits for asynchronous filesystem work without calling pumpAndSettle while
/// the page is showing its intentionally indeterminate loading indicator.
/// pumpAndSettle cannot finish while an indeterminate progress animation runs.
Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 120,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }

  expect(
    finder,
    findsOneWidget,
    reason: 'The expected ProjectsPage content did not appear in time.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryRoot;
  late Directory workingDirectory;
  late ProjectStore store;
  late File sourceVideo;
  late File exportedVideo;

  setUp(() async {
    temporaryRoot =
        await Directory.systemTemp.createTemp('wad-projects-page-');
    workingDirectory = Directory('${temporaryRoot.path}/working');
    await workingDirectory.create(recursive: true);
    store = ProjectStore(rootDirectory: temporaryRoot);

    sourceVideo = File('${workingDirectory.path}/source.mp4');
    exportedVideo = File('${workingDirectory.path}/export.mp4');
    await sourceVideo.writeAsBytes([1, 2, 3, 4]);
    await exportedVideo.writeAsBytes([5, 6, 7, 8]);
  });

  tearDown(() async {
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  TimelineProject sampleProject() {
    return TimelineProject(
      id: 'page_test_project',
      duration: 4,
      width: 1080,
      height: 1920,
      frameRate: 30,
      tracks: [
        TimelineTrack(
          id: 'video',
          name: 'الفيديو',
          type: TimelineTrackType.video,
          order: 0,
          layers: [
            TimelineLayer(
              id: 'source_video',
              trackId: 'video',
              type: TimelineLayerType.sourceVideo,
              name: 'الفيديو الأصلي',
              start: 0,
              end: 4,
              zIndex: 0,
              sourcePath: sourceVideo.path,
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('shows a saved project and opens its timeline', (tester) async {
    await store.saveExport(
      project: sampleProject(),
      videoPath: exportedVideo.path,
      name: 'مشروعي المحفوظ',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProjectsPage(store: store)),
    );

    // The page initially displays an indeterminate loader. Wait for the
    // actual list item with finite pumps instead of pumpAndSettle.
    await _pumpUntilVisible(tester, find.text('مشروعي المحفوظ'));
    expect(find.text('المشاريع المحفوظة'), findsOneWidget);

    await tester.tap(find.text('مشروعي المحفوظ'));
    await _pumpUntilVisible(tester, find.text('ACTUAL EDIT MAP'));
    await tester.pumpAndSettle();

    expect(find.text('ACTUAL EDIT MAP'), findsOneWidget);

    final canvas = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.size.width == 586.0,
    ).first;
    final rect = tester.getRect(canvas);
    await tester.tapAt(
      Offset(rect.left + 126 + 72, rect.top + 46 + 34),
    );
    await tester.pumpAndSettle();

    expect(find.text('الفيديو الأصلي'), findsOneWidget);
  });

  testWidgets('shows the empty state when no projects exist', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProjectsPage(store: store)),
    );

    // Do not wait for an indeterminate loading animation to settle. Wait for
    // the final empty-state label, then allow any finite transition to settle.
    await _pumpUntilVisible(
      tester,
      find.text('لا توجد مشاريع محفوظة حتى الآن'),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا توجد مشاريع محفوظة حتى الآن'), findsOneWidget);
    expect(
      find.text('بعد تفعيل الحفظ التلقائي ستظهر مشاريعك هنا.'),
      findsOneWidget,
    );
  });
}