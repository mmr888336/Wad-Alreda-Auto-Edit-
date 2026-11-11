import 'package:auto_edit/project_store.dart';
import 'package:auto_edit/projects_page.dart';
import 'package:auto_edit/timeline_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// UI tests use an in-memory store. Real filesystem persistence is covered by
/// project_store_test.dart, so these tests stay focused on ProjectsPage.
class _MemoryProjectStore extends ProjectStore {
  _MemoryProjectStore(this.projects) : super();

  final List<SavedProject> projects;

  @override
  Future<List<SavedProject>> loadAll() async {
    return List<SavedProject>.unmodifiable(projects);
  }

  @override
  Future<SavedProject> load(String id) async {
    return projects.firstWhere((project) => project.id == id);
  }
}

TimelineProject _sampleTimeline() {
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
          ),
        ],
      ),
    ],
  );
}

SavedProject _sampleSavedProject() {
  final now = DateTime.utc(2026, 11, 11, 12);
  return SavedProject(
    id: 'saved_project_1',
    name: 'مشروعي المحفوظ',
    createdAt: now,
    updatedAt: now,
    videoPath: '/memory/final.mp4',
    coverPath: null,
    directoryPath: '/memory/projects/saved_project_1',
    timelineProject: _sampleTimeline(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows a saved project and opens it through the callback',
      (tester) async {
    final project = _sampleSavedProject();
    final store = _MemoryProjectStore([project]);
    SavedProject? openedProject;

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectsPage(
          store: store,
          onProjectOpened: (value) => openedProject = value,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('المشاريع المحفوظة'), findsOneWidget);
    expect(find.text('مشروعي المحفوظ'), findsOneWidget);

    await tester.tap(find.text('مشروعي المحفوظ'));
    await tester.pump();
    await tester.pump();

    expect(openedProject, isNotNull);
    expect(openedProject!.id, project.id);
    expect(openedProject!.timelineProject.layerById('source_video'),
        isNotNull);
  });

  testWidgets('shows the empty state when no projects exist', (tester) async {
    final store = _MemoryProjectStore(const []);

    await tester.pumpWidget(
      MaterialApp(home: ProjectsPage(store: store)),
    );
    await tester.pump();

    expect(find.text('المشاريع المحفوظة'), findsOneWidget);
    expect(find.text('لا توجد مشاريع محفوظة حتى الآن'), findsOneWidget);
    expect(
      find.text('بعد تفعيل الحفظ التلقائي ستظهر مشاريعك هنا.'),
      findsOneWidget,
    );
  });
}