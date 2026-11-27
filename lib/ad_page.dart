import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';

/// Where a rewarded action is being requested from. Each placement is an
/// independent reward: completing one never unlocks another.
enum AdPlacement {
  /// The pre-export gate that already existed in the app.
  preExport,

  /// Gate before writing the final video and cover to the phone gallery.
  saveToPhone,

  /// Gate before opening the timeline editor for an exported project.
  openTimeline,
}

extension AdPlacementId on AdPlacement {
  /// Stable id used in diagnostics and in the mock gateway.
  String get id {
    switch (this) {
      case AdPlacement.preExport:
        return 'pre_export';
      case AdPlacement.saveToPhone:
        return 'save_to_phone';
      case AdPlacement.openTimeline:
        return 'open_timeline';
    }
  }

  /// Short Arabic label shown on the reward card.
  String get label {
    switch (this) {
      case AdPlacement.preExport:
        return 'بدء التصدير';
      case AdPlacement.saveToPhone:
        return 'حفظ الفيديو والغلاف إلى الهاتف';
      case AdPlacement.openTimeline:
        return 'فتح التايم لاين';
    }
  }
}

/// Result of a rewarded action.
enum MockRewardResult { completed, cancelled, failed }

/// Configuration of the ad layer.
///
/// During the experiment period every ad placement in the app is a LOCAL
/// simulation: no ad SDK is initialised, no network request is made, and no
/// impression/click/revenue event is sent anywhere. The mock is only allowed
/// in debug builds; a release build refuses to run it.
class AdsConfig {
  AdsConfig._();

  /// True only in a debug build. A release build can never enable the mock,
  /// so a production artifact cannot silently ship the fake reward screen.
  static bool get mockMode => kDebugMode && !kReleaseMode;

  /// Diagnostic tag written when a mock reward completes. Never `ad_viewed`
  /// or `ad_impression`.
  static const String mockCompletedTag = 'mock_reward_completed_for_test';

  /// How long the local simulation takes before it can be completed.
  static const Duration mockDuration = Duration(seconds: 3);
}

/// Local, on-device simulation of a rewarded action.
///
/// It never touches an ad SDK, never opens a URL and never sends a network
/// request. Each placement has its own in-flight guard, so a double tap cannot
/// grant two rewards, and a completed `save_to_phone` cannot unlock
/// `open_timeline`.
class MockRewardedAdGateway {
  MockRewardedAdGateway._();

  static final Set<AdPlacement> _inFlight = <AdPlacement>{};

  /// True while a reward for [placement] is being shown.
  static bool isInFlight(AdPlacement placement) =>
      _inFlight.contains(placement);

  /// Runs the local simulation for [placement].
  ///
  /// Returns [MockRewardResult.completed] only when the user explicitly
  /// completes the test card. Cancelling or failing grants nothing.
  static Future<MockRewardResult> show(AdPlacement placement) async {
    if (!AdsConfig.mockMode) {
      return MockRewardResult.failed;
    }
    if (!_inFlight.add(placement)) {
      // A reward for this placement is already running: do not grant a second.
      return MockRewardResult.failed;
    }
    try {
      // The UI drives the actual completion; this delay only keeps the
      // contract honest for callers that do not show a card.
      await Future<void>.delayed(AdsConfig.mockDuration);
      return MockRewardResult.completed;
    } finally {
      _inFlight.remove(placement);
    }
  }

  /// Marks [placement] as completed from the UI. Returns false when the
  /// placement was not in flight (double tap, or a different placement).
  static bool complete(AdPlacement placement) {
    if (!_inFlight.contains(placement)) return false;
    _inFlight.remove(placement);
    return true;
  }

  /// Marks [placement] as cancelled from the UI.
  static void cancel(AdPlacement placement) {
    _inFlight.remove(placement);
  }
}

/// The reward card. It is a local simulation, clearly labelled as such.
///
/// The caller passes the [placement] it is gating. The page pops with `true`
/// only when the user explicitly completes the test card; cancel and failure
/// pop with `false`.
class AdPage extends StatefulWidget {
  final AdPlacement placement;

  const AdPage({super.key, this.placement = AdPlacement.preExport});

  @override
  State<AdPage> createState() => _AdPageState();
}

class _AdPageState extends State<AdPage> {
  bool _loading = true;
  bool _canComplete = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!AdsConfig.mockMode) {
      setState(() {
        _loading = false;
        _error =
            'هذه النسخة لا تسمح بمحاكاة الإعلان. الإعلانات الحقيقية غير مفعّلة '
            'في هذه النسخة التجريبية.';
      });
      return;
    }

    if (MockRewardedAdGateway.isInFlight(widget.placement)) {
      setState(() {
        _loading = false;
        _error = 'طلب مكافأة آخر قيد التنفيذ. انتظر لحظة ثم حاول مرة أخرى.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
      _canComplete = false;
    });

    // Reserve the placement so a double tap cannot start a second session.
    // The gateway's own delay is bypassed here: the UI drives completion.
    MockRewardedAdGateway.show(widget.placement);

    await Future<void>.delayed(AdsConfig.mockDuration);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _canComplete = true;
    });
  }

  void _complete() {
    if (!_canComplete) return;
    final ok = MockRewardedAdGateway.complete(widget.placement);
    if (!mounted) return;
    Navigator.of(context).pop(ok);
  }

  void _cancel() {
    MockRewardedAdGateway.cancel(widget.placement);
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('إعلان تجريبي')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.ondemand_video_rounded, size: 76),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C1820),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF8A3B4F)),
                ),
                child: const Text(
                  'إعلان تجريبي — محاكاة محلية، لا يوجد إعلان حقيقي ولا اتصال '
                  'بشبكة إعلانات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'المكافأة المطلوبة: ${widget.placement.label}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              if (_loading) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                const Text(
                  'جاري تجهيز المحاكاة المحلية...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.6),
                ),
              ] else if (_error.isNotEmpty) ...[
                SelectableText(
                  _error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _start, child: const Text('حاول تاني')),
                TextButton(onPressed: _cancel, child: const Text('رجوع')),
              ] else ...[
                FilledButton.icon(
                  onPressed: _canComplete ? _complete : null,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('إكمال التجربة'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _cancel,
                  child: const Text('إلغاء بدون مكافأة'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
