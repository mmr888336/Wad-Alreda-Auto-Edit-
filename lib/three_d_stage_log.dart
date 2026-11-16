/// Stages of the automatic 3D scene pipeline, in execution order.
///
/// Each stage has an Arabic label so a failure can be reported in the stage
/// that really failed (and never blamed on the wrong step).
enum ThreeDStage {
  search('البحث'),
  download('التنزيل'),
  inspect('فحص GLB'),
  filamentLoad('تحميل Filament'),
  camera('حركة الكاميرا'),
  ready('جاهزية العرض'),
  capture('الالتقاط'),
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
}

/// Everything the 3D pipeline did during one export.
class ThreeDExportSummary {
  ThreeDExportSummary({this.onEvent});

  /// Called for every recorded event (used for live logging).
  final void Function(ThreeDStageEvent event)? onEvent;

  final List<ThreeDStageEvent> _events = <ThreeDStageEvent>[];

  List<ThreeDStageEvent> get events =>
      List<ThreeDStageEvent>.unmodifiable(_events);

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
