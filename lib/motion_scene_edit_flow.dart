/// Glue between the Studio timeline and the motion scene editor: finds the
/// clips that have an editable description next to them and opens the editor
/// for one of them.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import 'motion_scene_editor_page.dart';
import 'motion_scene_json.dart';
import 'timeline_engine.dart';

class MotionSceneEditFlow {
  MotionSceneEditFlow._();

  /// B-roll layers whose clip is a motion cutaway with an editable
  /// description (`<clip>.motion.json`). [clipPaths] maps a layer id to a
  /// clip that replaced the layer's original one after an edit.
  static List<TimelineLayer> editableClips(
    TimelineProject project, {
    Map<String, String> clipPaths = const <String, String>{},
  }) {
    final result = <TimelineLayer>[];
    for (final layer in project.layers) {
      if (layer.type != TimelineLayerType.broll) continue;
      final path = clipPaths[layer.id] ?? layer.sourcePath;
      if (path == null || path.trim().isEmpty) continue;
      try {
        if (File(MotionSceneJson.sidecarPathFor(path)).existsSync()) {
          result.add(layer);
        }
      } catch (_) {
        // An unreadable path simply means the clip is not editable.
      }
    }
    return result;
  }

  /// Opens the editor. Returns the re-rendered clip, or null when the user
  /// left without applying.
  static Future<MotionSceneEditResult?> openEditor(
    BuildContext context, {
    required MotionSceneDocument document,
    required String clipPath,
  }) {
    return Navigator.of(context).push<MotionSceneEditResult>(
      MaterialPageRoute<MotionSceneEditResult>(
        builder: (_) => MotionSceneEditorPage(
          document: document,
          clipPath: clipPath,
        ),
      ),
    );
  }
}
