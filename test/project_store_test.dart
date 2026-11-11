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
  late File brollAsset;
  late File titleAsset;
  late File soundEffectAsset;
  late File exportedVideo;
  late File coverImage;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp('wad-project-store-');
    workingFiles = Directory('${temporaryRoot.path}/working');
    await workingFiles.create(recursive: true);
    store = ProjectStore(rootDirectory: temporaryRoot);

    sourceVideo = File('${workingFiles.path}/source.mp4');
    captionAsset = File('${workingFiles.path}/caption.png');
    brollAsset = File('${workingFiles.path}/broll.mp4');
    titleAsset = File('${workingFiles.path}/title.png');
    soundEffectAsset = File('${workingFiles.path}/effect.wav');
    exportedVideo = File('${workingFiles.path}/final.mp4');
    coverImage = File('${workingFiles.path}/cover.jpg');

    await sourceVideo.writeAsBytes([1, 2, 3, 4]);
    await captionAsset.writeAsBytes([5, 6, 7]);
    await brollAsset.writeAsBytes([8, 9, 10]);
    await titleAsset.writeAsBytes([11, 12, 13]);
    await soundEffectAsset.writeAsBytes([14, 15, 16]);
    await exportedVideo.writeAsBytes([17, 18, 19, 20]);
    await coverImage.writeAsBytes([21, 22, 23]);
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
          id: 'broll',
          name: 'B-roll',
          type: TimelineTrackType.broll,
          order: 1,
          layers: [
            TimelineLayer(
              id: 'broll_0',
              trackId: 'broll',
              type: TimelineLayerType.broll,
              name: 'B-roll 1',
              start: 2,
              end: 4,
              zIndex: 10,
              sourcePath: brollAsset.path,
            ),
          ],
        ),
        TimelineTrack(
          id: 'captions',
          name: 'Captions',
          type: TimelineTrackType.captions,
          order: 2,
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
          id: 'graphics',
          name: 'Graphics',
          type: TimelineTrackType.graphics,
          order: 3,
          layers: [
            TimelineLayer(
              id: 'title_0',
              trackId: 'graphics',
              type: TimelineLayerType.title,
              name: 'Opening title',
              start: 0,
              end: 1,
              zIndex: 30,
              sourcePath: titleAsset.path,
              text: 'عنوان البداية',
            ),
          ],
        ),
        TimelineTrack(
          id: 'audio',
          name: 'Audio',
          type: TimelineTrackType.audio,
          order: 4,
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
        TimelineTrack(
          id: 'effects',
          name: 'Effects',
          type: TimelineTrackType.effects,
          order: 5,
          layers: [
            TimelineLayer(
              id: 'sound_effect_0',
              trackId: 'effects',
              type: TimelineLayerType.soundEffect,
              name: 'Whoosh',
              start: 1,
              end: 1.4,
              zIndex: 40,
              sourcePath: soundEffectAsset.path,
            ),
          ],
        ),
      ],
    );
  }

  test('copies export, cover, captions, B-roll, graphics and sound effects',
      () async {
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
    final brollLayer = saved.timelineProject.layerById('broll_0')!;
    final titleLayer = saved.timelineProject.layerById('title_0')!;
    final effectLayer = saved.timelineProject.layerById('sound_effect_0')!;

    expect(sourceLayer.sourcePath, isNot(sourceVideo.path));
    expect(sourceLayer.sourcePath, audioLayer.sourcePath);
    expect(await File(sourceLayer.sourcePath!).exists(), isTrue);
    expect(await File(captionLayer.sourcePath!).exists(), isTrue);
    expect(await File(brollLayer.sourcePath!).exists(), isTrue);
    expect(await File(titleLayer.sourcePath!).exists(), isTrue);
    expect(await File(effectLayer.sourcePath!).exists(), isTrue);
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
    expect(restored.timelineProject.layers, hasLength(6));
    expect(all, hasLength(1));
    expect(all.single.id, saved.id);
    for (final layer in restored.timelineProject.layers) {
      final path = layer.sourcePath;
      if (path != null) expect(await File(path).exists(), isTrue);
    }
  });

  test('renames a project and updates its timestamp', () async {
    final saved = await store.saveExport(
      project: sampleProject(),
      videoPath: exportedVideo.path,
    );

    final renamed = await store.rename(saved.id, 'عنوان جديد');

    expect(renamed.name, 'عنوان جديد');
    expect(
      renamed.updatedAt.isAfter(saved.updatedAt) ||
          renamed.updatedAt.isAtSameMomentAs(saved.updatedAt),
      isTrue,
    );
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

  test('rejects projects whose saved media has been removed', () async {
    final saved = await store.saveExport(
      project: sampleProject(),
      videoPath: exportedVideo.path,
    );
    final captionPath =
        saved.timelineProject.layerById('caption_0')!.sourcePath!;
    await File(captionPath).delete();

    expect(await store.validateAssets(saved), isNotEmpty);
    expect(() => store.load(saved.id), throwsFormatException);
    expect(await store.loadAll(), isEmpty);
  });

  test('removes an incomplete project folder when an asset is missing', () async {
    final project = sampleProject();
    await brollAsset.delete();

    await expectLater(
      store.saveExport(project: project, videoPath: exportedVideo.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await store.loadAll(), isEmpty);
  });
}