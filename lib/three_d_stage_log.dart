/// Stages of the automatic 3D scene pipeline, in execution order.
///
/// Each stage has an Arabic label so a failure can be reported in the stage
/// that really failed (and never blamed on the wrong step).
enum ThreeDStage {
  /// World scene: the story world is planned as a 3D scene (pure Dart).
  worldPlan('تخطيط مشهد العالم'),

  /// World scene: the 3D scene is written as a GLB file (pure Dart).
  worldGlb('بناء GLB للعالم'),
  search('البحث'),
  download('التنزيل'),
  inspect('فحص GLB'),
  filamentLoad('تحميل Filament'),
  camera('حركة الكاميرا'),

  /// World scene: the native camera is set to manual, so the camera rig
  /// inside the GLB moves the world.
  manualCamera('كاميرا manual'),
  ready('جاهزية العرض'),
  capture('الالتقاط'),

  /// Releasing the native Filament view after the last scene is captured.
  /// It is its own stage, so a crash here is never blamed on the last model.
  rendererRelease('تحرير المحرك'),
  composite('التركيب');

  const ThreeDStage(this.label);

  final String label;
}

/// One finished stage of one scene (or of the whole export).
class ThreeDStageEvent {
  const ThreeDStageEvent({
    required this.scene,
    required this.stage,
    required this.ok,
    required this.elapsed,
    this.detail,
  });

  /// 1-based scene number. 0 means the whole export (e.g. compositing).
  final int scene;
  final ThreeDStage stage;
  final bool ok;
  final Duration elapsed;
  final String? detail;

  String toLine() {
    final where = scene == 0 ? 'التصدير' : 'مشهد $scene';
    final status = ok ? 'نجح' : 'فشل';
    final text = detail?.trim() ?? '';
    final extra = text.isEmpty ? '' : ' — $text';
    return '[$where] ${stage.label}: $status '
        '(${elapsed.inMilliseconds}ms)$extra';
  }

  /// The log line written when a stage STARTS. Together with [toLine] (written
  /// when it ends) the log shows exactly which stage was running at a crash.
  static String startLine(
    int scene,
    ThreeDStage stage, {
    String? detail,
  }) {
    final where = scene == 0 ? 'التصدير' : 'مشهد $scene';
    final text = detail?.trim() ?? '';
    final extra = text.isEmpty ? '' : ' — $text';
    return '[$where] ${stage.label}: بدأ$extra';
  }
}

/// Reads the on-disk export log. The log is written line by line, so it can
/// confirm that a stage finished even when the crash note is out of date.
class ThreeDLogReader {
  ThreeDLogReader._();

  /// True when [log] holds a SUCCESS line for [stage] of [scene] (and, when
  /// [assetTitle] is given, for that model). A start line does not count.
  static bool succeeded(
    String log, {
    required int scene,
    required ThreeDStage stage,
    String assetTitle = '',
  }) {
    final where = scene == 0 ? 'التصدير' : 'مشهد $scene';
    final prefix = '[$where] ${stage.label}: نجح';
    final title = assetTitle.trim();

    for (final raw in log.split('\n')) {
      final line = raw.trim();

      if (!line.startsWith(prefix)) continue;
      if (title.isEmpty || line.contains(title)) return true;
    }

    return false;
  }
}

/// Everything the 3D pipeline did during one export.
class ThreeDExportSummary {
  ThreeDExportSummary({this.onEvent, this.onStart});

  /// Called for every recorded (finished) event (used for live logging).
  final void Function(ThreeDStageEvent event)? onEvent;

  /// Called when a stage starts (used for live logging).
  final void Function(int scene, ThreeDStage stage, String? detail)? onStart;

  final List<ThreeDStageEvent> _events = <ThreeDStageEvent>[];

  List<ThreeDStageEvent> get events =>
      List<ThreeDStageEvent>.unmodifiable(_events);

  /// Notes that a stage started. It is only logged: start notes are not
  /// events, so they never change the failure counts or the headline.
  void begin(int scene, ThreeDStage stage, {String? detail}) {
    onStart?.call(scene, stage, detail);
  }

  void record(
    int scene,
    ThreeDStage stage, {
    required bool ok,
    Duration elapsed = Duration.zero,
    String? detail,
  }) {
    final event = ThreeDStageEvent(
      scene: scene,
      stage: stage,
      ok: ok,
      elapsed: elapsed,
      detail: detail,
    );

    _events.add(event);
    onEvent?.call(event);
  }

  List<ThreeDStageEvent> get failures =>
      _events.where((event) => !event.ok).toList();

  /// How many failures happened in each stage.
  Map<ThreeDStage, int> get failuresByStage {
    final counts = <ThreeDStage, int>{};

    for (final event in _events) {
      if (event.ok) continue;
      counts[event.stage] = (counts[event.stage] ?? 0) + 1;
    }

    return counts;
  }

  /// The stage with the most failures. On a tie the earlier stage wins,
  /// because an early failure is the root cause of later ones.
  ThreeDStage? get mostFailedStage {
    final counts = failuresByStage;
    if (counts.isEmpty) return null;

    ThreeDStage? best;
    var bestCount = 0;

    for (final stage in ThreeDStage.values) {
      final count = counts[stage] ?? 0;

      if (count > bestCount) {
        best = stage;
        bestCount = count;
      }
    }

    return best;
  }

  /// One line that says how the export went.
  String get headline {
    if (_events.isEmpty) {
      return 'لا توجد مراحل 3D مسجلة.';
    }

    final failed = failures;

    if (failed.isEmpty) {
      return 'مراحل 3D: نجحت كل الخطوات (${_events.length}).';
    }

    final worst = mostFailedStage;
    final worstCount = worst == null ? 0 : (failuresByStage[worst] ?? 0);

    return 'مراحل 3D: فشلت ${failed.length} من ${_events.length} خطوة؛ '
        'أكثر مرحلة فشلاً: ${worst?.label ?? 'غير معروفة'} ($worstCount).';
  }

  /// The full log, one line per event, after the headline.
  String toText() {
    final buffer = StringBuffer(headline);

    for (final event in _events) {
      buffer.write('\n');
      buffer.write(event.toLine());
    }

    return buffer.toString();
  }
}
