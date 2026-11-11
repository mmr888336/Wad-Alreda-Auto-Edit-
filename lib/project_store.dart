import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'timeline_engine.dart';

/// A durable project entry stored inside the application's documents folder.
/// Every media path referenced by [timelineProject] points to a copied asset
/// inside this project's own directory.
class SavedProject {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String videoPath;
  final String? coverPath;
  final String directoryPath;
  final TimelineProject timelineProject;

  const SavedProject({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.videoPath,
    required this.coverPath,
    required this.directoryPath,
    required this.timelineProject,
  });

  SavedProject copyWith({String? name, DateTime? updatedAt}) {
    return SavedProject(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      videoPath: videoPath,
      coverPath: coverPath,
      directoryPath: directoryPath,
      timelineProject: timelineProject,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'videoPath': videoPath,
        'coverPath': coverPath,
        'timelineProject': timelineProject.toJson(),
      };

  factory SavedProject.fromJson(
    Map<String, dynamic> json, {
    required String directoryPath,
  }) {
    final projectJson = Map<String, dynamic>.from(
      (json['timelineProject'] as Map?) ?? const <String, dynamic>{},
    );

    return SavedProject(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'مشروع بدون اسم',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      videoPath: json['videoPath'] as String? ?? '',
      coverPath: json['coverPath'] as String?,
      directoryPath: directoryPath,
      timelineProject: TimelineProject.fromJson(projectJson),
    );
  }
}

/// Local project storage. It deliberately uses the already-installed
/// path_provider package and does not add a new dependency.
///
/// Pass [rootDirectory] in tests. In the app, the default location is:
/// Documents/WadAlredaStudio/Projects/<project-id>/
class ProjectStore {
  final Directory? rootDirectory;

  const ProjectStore({this.rootDirectory});

  static const String manifestFileName = 'project.json';

  Future<Directory> _projectsRoot() async {
    final Directory base;
    if (rootDirectory != null) {
      base = rootDirectory!;
    } else {
      base = await getApplicationDocumentsDirectory();
    }

    final directory = Directory(_join([
      base.path,
      if (rootDirectory == null) 'WadAlredaStudio',
      'Projects',
    ]));
    await directory.create(recursive: true);
    return directory;
  }

  String _join(List<String> parts) =>
      parts.where((part) => part.isNotEmpty).join(Platform.pathSeparator);

  String _safeId(String id) {
    final value = id.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(value)) {
      throw ArgumentError.value(id, 'id', 'Invalid project id.');
    }
    return value;
  }

  String _safeFileName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.isEmpty ? 'asset' : cleaned;
  }

  String _extensionOf(String path, {String fallback = '.bin'}) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return fallback;
    return name.substring(dot).toLowerCase();
  }

  Future<String> _copyFile({
    required String sourcePath,
    required String destinationPath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Project asset does not exist', sourcePath);
    }

    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);

    final sourceAbsolute = source.absolute.path;
    final destinationAbsolute = destination.absolute.path;
    if (sourceAbsolute == destinationAbsolute) return destination.path;

    await source.copy(destination.path);
    return destination.path;
  }

  TimelineProject _withStoredAssetPaths(
    TimelineProject project,
    Map<String, String> copiedPaths,
  ) {
    return TimelineProject(
      id: project.id,
      duration: project.duration,
      width: project.width,
      height: project.height,
      frameRate: project.frameRate,
      tracks: project.tracks.map((track) {
        return TimelineTrack(
          id: track.id,
          name: track.name,
          type: track.type,
          order: track.order,
          layers: track.layers.map((layer) {
            final oldPath = layer.sourcePath;
            return TimelineLayer(
              id: layer.id,
              trackId: layer.trackId,
              type: layer.type,
              name: layer.name,
              start: layer.start,
              end: layer.end,
              zIndex: layer.zIndex,
              sourcePath: oldPath == null ? null : copiedPaths[oldPath],
              text: layer.text,
              visible: layer.visible,
              keyframes: layer.keyframes,
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Future<void> _writeManifest(SavedProject project) async {
    final directory = Directory(project.directoryPath);
    await directory.create(recursive: true);

    final manifest = File(_join([
      project.directoryPath,
      manifestFileName,
    ]));
    final temporary = File('${manifest.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
      flush: true,
    );

    File? backup;
    if (await manifest.exists()) {
      backup = File('${manifest.path}.bak');
      if (await backup.exists()) await backup.delete();
      await manifest.rename(backup.path);
    }

    try {
      await temporary.rename(manifest.path);
      if (backup != null && await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (backup != null &&
          await backup.exists() &&
          !(await manifest.exists())) {
        await backup.rename(manifest.path);
      }
      rethrow;
    }
  }

  /// Returns every missing or unsafe media path referenced by a saved entry.
  /// Paths must remain inside the project's own folder; a damaged manifest
  /// must never make the library read arbitrary files elsewhere on the phone.
  Future<List<String>> validateAssets(SavedProject project) async {
    final root = await Directory(project.directoryPath).resolveSymbolicLinks();
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    final paths = <String>{
      project.videoPath,
      if (project.coverPath != null) project.coverPath!,
      ...project.timelineProject.layers
          .map((layer) => layer.sourcePath)
          .whereType<String>(),
    };
    final problems = <String>[];

    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) {
        problems.add('Saved asset is missing: $path');
        continue;
      }

      try {
        final resolved = await file.resolveSymbolicLinks();
        if (resolved != root && !resolved.startsWith(prefix)) {
          problems.add('Asset path is outside the project folder: $path');
        }
      } catch (_) {
        problems.add('Saved asset cannot be resolved: $path');
      }
    }
    return problems;
  }

  /// Saves an export and copies every source asset referenced by its timeline
  /// before the enhancer deletes its temporary working files.
  ///
  /// This method MUST be called from Enhancer.run before its temporary-file
  /// cleanup block. Calling it after Enhancer.run returns is too late for
  /// caption PNGs, B-roll clips, and generated sound-effect files.
  Future<SavedProject> saveExport({
    required TimelineProject project,
    required String videoPath,
    String? coverPath,
    String? name,
  }) async {
    final errors = project.validate();
    if (errors.isNotEmpty) {
      throw StateError('Cannot save invalid timeline: ${errors.first}');
    }

    final id = _safeId(project.id);
    final root = await _projectsRoot();
    final projectDirectory = Directory(_join([root.path, id]));
    if (await projectDirectory.exists()) {
      throw StateError('A project with id $id already exists.');
    }

    try {
      final assetsDirectory = Directory(
        _join([projectDirectory.path, 'assets']),
      );
      final exportsDirectory = Directory(
        _join([projectDirectory.path, 'exports']),
      );
      await assetsDirectory.create(recursive: true);
      await exportsDirectory.create(recursive: true);

      final copiedPaths = <String, String>{};
      var assetIndex = 0;
      for (final layer in project.layers) {
        final sourcePath = layer.sourcePath;
        if (sourcePath == null || sourcePath.trim().isEmpty) continue;
        if (copiedPaths.containsKey(sourcePath)) continue;

        final extension = _extensionOf(sourcePath);
        final fileName =
            '${assetIndex.toString().padLeft(3, '0')}_'
            '${_safeFileName(layer.id)}$extension';
        final destination = _join([assetsDirectory.path, fileName]);
        copiedPaths[sourcePath] = await _copyFile(
          sourcePath: sourcePath,
          destinationPath: destination,
        );
        assetIndex++;
      }

      final videoExtension = _extensionOf(videoPath, fallback: '.mp4');
      final storedVideoPath = await _copyFile(
        sourcePath: videoPath,
        destinationPath: _join([exportsDirectory.path, 'final$videoExtension']),
      );

      String? storedCoverPath;
      if (coverPath != null && coverPath.trim().isNotEmpty) {
        if (await File(coverPath).exists()) {
          final coverExtension = _extensionOf(coverPath, fallback: '.jpg');
          storedCoverPath = await _copyFile(
            sourcePath: coverPath,
            destinationPath:
                _join([exportsDirectory.path, 'cover$coverExtension']),
          );
        }
      }

      final now = DateTime.now();
      final storedTimeline = _withStoredAssetPaths(project, copiedPaths);
      final displayName = name?.trim().isNotEmpty == true
          ? name!.trim()
          : 'مشروع ${now.year}-${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')} '
              '${now.hour.toString().padLeft(2, '0')}:'
              '${now.minute.toString().padLeft(2, '0')}';

      final saved = SavedProject(
        id: id,
        name: displayName,
        createdAt: now,
        updatedAt: now,
        videoPath: storedVideoPath,
        coverPath: storedCoverPath,
        directoryPath: projectDirectory.path,
        timelineProject: storedTimeline,
      );

      await _writeManifest(saved);
      return saved;
    } catch (_) {
      if (await projectDirectory.exists()) {
        await projectDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<List<SavedProject>> loadAll() async {
    final root = await _projectsRoot();
    final projects = <SavedProject>[];
    if (!await root.exists()) return projects;

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final manifest = File(_join([entity.path, manifestFileName]));
      if (!await manifest.exists()) continue;

      try {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded is! Map) continue;
        final project = SavedProject.fromJson(
          Map<String, dynamic>.from(decoded),
          directoryPath: entity.path,
        );
        if (project.timelineProject.validate().isEmpty &&
            (await validateAssets(project)).isEmpty) {
          projects.add(project);
        }
      } catch (_) {
        // One damaged project must not prevent the rest of the library opening.
      }
    }

    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<SavedProject> load(String id) async {
    final safeId = _safeId(id);
    final root = await _projectsRoot();
    final directory = Directory(_join([root.path, safeId]));
    final manifest = File(_join([directory.path, manifestFileName]));
    if (!await manifest.exists()) {
      throw FileSystemException('Saved project was not found', manifest.path);
    }

    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map) throw const FormatException('Invalid project file.');
    final project = SavedProject.fromJson(
      Map<String, dynamic>.from(decoded),
      directoryPath: directory.path,
    );
    final errors = project.timelineProject.validate();
    if (errors.isNotEmpty) {
      throw FormatException('Invalid saved timeline: ${errors.first}');
    }
    final assetProblems = await validateAssets(project);
    if (assetProblems.isNotEmpty) {
      throw FormatException(
        'Saved project assets are incomplete: ${assetProblems.first}',
      );
    }
    return project;
  }

  Future<SavedProject> rename(String id, String newName) async {
    final value = newName.trim();
    if (value.isEmpty) throw ArgumentError.value(newName, 'newName');
    if (value.length > 80) {
      throw ArgumentError.value(newName, 'newName', 'Name is too long.');
    }

    final project = await load(id);
    final renamed = project.copyWith(name: value, updatedAt: DateTime.now());
    await _writeManifest(renamed);
    return renamed;
  }

  Future<void> delete(String id) async {
    final safeId = _safeId(id);
    final root = await _projectsRoot();
    final directory = Directory(_join([root.path, safeId]));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}