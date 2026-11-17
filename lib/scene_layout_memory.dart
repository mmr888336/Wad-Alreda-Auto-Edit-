/// Remembers the last scene layout used inside one export, so the first scene
/// of the next cutaway never repeats the last scene of the previous one.
///
/// A new export has a new `stamp`, which starts the memory fresh. Pure Dart,
/// no I/O.
library;

import 'continuous_scene_generator.dart' show SceneLayout;

class SceneLayoutMemory {
  SceneLayoutMemory._();

  static int? _stamp;
  static SceneLayout? _last;

  /// The last layout remembered for the export [stamp], or null when this is
  /// the first cutaway of that export.
  static SceneLayout? previousFor(int stamp) {
    if (_stamp != stamp) return null;
    return _last;
  }

  /// Remembers [layout] as the last scene layout of the export [stamp].
  static void remember(int stamp, SceneLayout layout) {
    _stamp = stamp;
    _last = layout;
  }

  /// Forgets everything.
  static void reset() {
    _stamp = null;
    _last = null;
  }
}
