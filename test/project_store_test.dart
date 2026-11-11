import 'dart:io';

import 'package:auto_edit/project_store.dart';
import 'package:auto_edit/timeline_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryRoot;
  late Directory workingFiles;
  late ProjectStore store;
  late File sourceVideo;
  late File captionAsset;
  late File exportedVideo;
  late File coverImage;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp('wad-project-store-');
    workingFiles = Directory('${temporaryRoot.path}/working');
    await workingFiles.create(recursive: true);
    store = ProjectStore(rootDirectory: temporaryRoot);

    sourceVideo = File('${workingFiles.path}/source.mp4');
    captionAsset = File('${workingFiles.path}/caption.png');
    exportedVideo = File('${workingFiles.path}/final.mp4');
    coverImage = File('${workingFiles.path}/cover.jpg');

    await sourceVideo.writeAsBytes([1, 2, 3, 4]);
    await captionAsset.writeAsBytes([5, 6, 7]);
    await exportedVideo.writeAsBytes([8, 9, 10, 11]);
    await coverImage.writeAsBytes([12, 13, 14]);
  });

  tearDown(() async {
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  TimelineProject sampleProject() {
    return TimelineProject(
      id: 'job_123456789',
      duration: 5,
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
              id: 'source_video',
              trackId: 'video',
              type: TimelineLayerType.sourceVideo,
              name: 'Source video',
              start: 0,
              end: 5,
              zIndex: 0,
              sourcePath: sourceVideo.path,
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
              id: 'caption_0',
              trackId: 'captions',
              type: TimelineLayerType.caption,
              name: 'Caption 1',
              start: 1,
              end: 3,
              zIndex: 20,
              sourcePath: captionAsset.path,
              text: 'مرحبا',
              keyframes: const [
                TransformKeyframe(
                  time: 1,
                  transform: LayerTransform(opacity: 0),
                  easing: KeyframeEasing.easeOut,
                ),
                TransformKeyframe(
                  time: 1.3,
                  transform: LayerTransform(opacity: 1),
                ),
              ],
            ),
          ],
        ),
        TimelineTrack(
          id: 'audio',
          name: 'Audio',
          type: TimelineTrackType.audio,
          order: 2,
          layers: [
            TimelineLayer(
              id: 'source_audio',
              trackId: 'audio',
              type: TimelineLayerType.sourceAudio,
              name: 'Source audio',
              start: 0,
              end: 5,
              zIndex: 0,
              // Same file as the video layer: it should be copied only once.
              sourcePath: sourceVideo.path,
            ),
          ],
        ),
      ],
    );
  }

  test('saves output and copies every referenced source asset', () async {
    final saved = await store.saveExport(
      project: sampleProject(),
      videoPath: exportedVideo.path,
      coverPath: coverImage.path,
      name: 'اختبار الحفظ',
    );

    expect(saved.name, 'اختبار الحفظ');
    expect(await File(saved.videoPath).exists(), isTrue);
    expect(saved.coverPath, isNotNull);
    expect(await File(saved.coverPath!).exists(), isTrue);

    final sourceLayer = saved.timelineProject.layerById('source_video')!;
    final audioLayer = saved.timelineProject.layerById('source_audio')!;
    final captionLayer = saved.timelineProject.layerById('caption_0')!;

    expect(sourceLayer.sourcePath, isNot(sourceVideo.path));
    expect(sourceLayer.sourcePath, audioLayer.sourcePath);
    expect(await File(sourceLayer.sourcePath!).exists(), isTrue);
    expect(await File(captionLayer.sourcePath!).exists(), isTrue);
    expect(captionLayer.text, 'مرحبا');
    expect(saved.timelineProject.validate(), isEmpty);
  });

  test('restores projects after constructing a new store instance', () async {
    final saved = await store.saveExport(
      project: sampleProject(),
      videoPath: exportedVideo.path,
      coverPath: coverImage.path,
    );

    final reopenedStore = ProjectStore(rootDirectory: temporaryRoot);
    final restored = await reopenedStore.load(saved.id);
    final all = await reopenedStore.loadAll();

    expect(restored.id, saved.id);
    expect(restored.timelineProject.layers.length, 3);
    expect(all, hasLength(1));
    expect(all.single.id, saved.id);
  });

  test('renames a project and updates its timestamp', () async {
    final saved = await store.saveExport(
      project: sampleProject(),
      videoPath: exportedVideo.path,
    );

    final renamed = await store.rename(saved.id, 'عنوان جديد');

    expect(renamed.name, 'عنوان جديد');
    expect(renamed.updatedAt.isAfter(saved.updatedAt) ||
        renamed.updatedAt.isAtSameMomentAs(saved.updatedAt), isTrue);
    expect((await store.load(saved.id)).name, 'عنوان جديد');
  });

  test('deletes project folder and its copied media', () async {
    final saved = await store.saveExport(
      project: sampleProject(),
      videoPath: exportedVideo.path,
    );
    final savedDirectory = Directory(saved.directoryPath);

    await store.delete(saved.id);

    expect(await savedDirectory.exists(), isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('rejects duplicate project ids rather than overwriting', () async {
    final project = sampleProject();
    await store.saveExport(project: project, videoPath: exportedVideo.path);

    expect(
      () => store.saveExport(project: project, videoPath: exportedVideo.path),
      throwsStateError,
    );
  });
}
