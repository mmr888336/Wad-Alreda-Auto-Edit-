import 'dart:async';

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
/// impression/click/revenue event is sent anywhere.
///
/// Whether the simulation is allowed is decided by an explicit build-time
/// flag, not by the build mode. The default is the experiment mode (mock
/// allowed and clearly labelled); only a build that passes
/// `--dart-define=PRODUCTION_ADS=true` refuses to run the mock.
class AdsConfig {
  AdsConfig._();

  /// Explicit build-time switch. Defaults to `false`, i.e. the experiment
  /// mode where the local simulation is allowed. Set it to `true` only for a
  /// production build that must not ship the fake reward screen.
  static const bool productionAds =
      bool.fromEnvironment('PRODUCTION_ADS', defaultValue: false);

  /// Explicit build-time switch for the reward gate itself. Defaults to
  /// `false`, i.e. the gate is disabled: every reward request resolves as
  /// completed immediately, with no screen, no delay and no message, so the
  /// original action continues straight away. Set it to `true` to run the
  /// current local simulation path.
  static const bool _adsGateBuild =
      bool.fromEnvironment('ADS_GATE', defaultValue: false);

  /// Runtime override used by tests only. Null means "use the build-time
  /// value". Production code never sets it, so the shipped default stays
  /// `false` unless `--dart-define=ADS_GATE=true` was passed.
  static bool? _adsGateOverride;

  /// True when the reward gate is enabled. Reads the build-time flag unless a
  /// test explicitly overrode it via [debugSetAdsGate].
  static bool get adsGate => _adsGateOverride ?? _adsGateBuild;

  /// Test-only hook to force the gate on or off. Pass null to restore the
  /// build-time value.
  static void debugSetAdsGate(bool? value) {
    _adsGateOverride = value;
  }

  /// True when the local simulation may run. Independent of `kDebugMode` and
  /// `kReleaseMode`, so a CI release build still gets the experiment mode
  /// unless `PRODUCTION_ADS=true` was passed explicitly.
  static bool get mockMode => !productionAds;

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
class _MockSession {
  _MockSession(this.placement);

  final AdPlacement placement;
  final Completer<MockRewardResult> completer =
      Completer<MockRewardResult>();
  Timer? timer;

  /// Guards against a second resolution (timer vs. complete vs. cancel).
  bool resolved = false;

  void resolve(MockRewardResult result) {
    if (resolved) return;
    resolved = true;
    timer?.cancel();
    timer = null;
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }
}

class MockRewardedAdGateway {
  MockRewardedAdGateway._();

  static final Map<AdPlacement, _MockSession> _sessions =
      <AdPlacement, _MockSession>{};

  /// True while a reward for [placement] is being shown.
  static bool isInFlight(AdPlacement placement) =>
      _sessions.containsKey(placement);

  /// Runs the local simulation for [placement].
  ///
  /// Returns a single future per request. It resolves exactly once:
  /// - [MockRewardResult.completed] when the UI calls [complete] before the
  ///   timer fires,
  /// - [MockRewardResult.cancelled] when the UI calls [cancel],
  /// - [MockRewardResult.completed] when the timer fires first (the local
  ///   simulation finished on its own),
  /// - [MockRewardResult.failed] when the mock is disabled or a reward for
  ///   this placement is already in flight.
  static Future<MockRewardResult> show(AdPlacement placement) {
    // Single entry point for every reward request. When the gate is disabled
    // the reward is granted immediately: no screen, no timer, no message.
    if (!AdsConfig.adsGate) {
      return Future<MockRewardResult>.value(MockRewardResult.completed);
    }
    if (!AdsConfig.mockMode) {
      return Future<MockRewardResult>.value(MockRewardResult.failed);
    }
    if (_sessions.containsKey(placement)) {
      // A reward for this placement is already running: do not grant a second.
      return Future<MockRewardResult>.value(MockRewardResult.failed);
    }
    final session = _MockSession(placement);
    _sessions[placement] = session;
    session.timer = Timer(AdsConfig.mockDuration, () {
      _finish(session, MockRewardResult.completed);
    });
    return session.completer.future;
  }

  /// Marks [placement] as completed from the UI. Returns false when the
  /// placement was not in flight (double tap, or a different placement).
  static bool complete(AdPlacement placement) {
    final session = _sessions[placement];
    if (session == null || session.resolved) return false;
    _finish(session, MockRewardResult.completed);
    return true;
  }

  /// Marks [placement] as cancelled from the UI.
  static void cancel(AdPlacement placement) {
    final session = _sessions[placement];
    if (session == null) return;
    _finish(session, MockRewardResult.cancelled);
  }

  static void _finish(_MockSession session, MockRewardResult result) {
    if (session.resolved) return;
    _sessions.remove(session.placement);
    session.resolve(result);
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
            'هذه النسخة مبنية بوضع الإنتاج (PRODUCTION_ADS=true) ولا تسمح '
            'بمحاكاة الإعلان. الإعلانات الحقيقية غير مفعّلة في هذه النسخة.';
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

    // One future per request. The gateway owns the timer and resolves it
    // exactly once (complete / cancel / timer), so there is no race here.
    final result = await MockRewardedAdGateway.show(widget.placement);
    if (!mounted) return;
    if (result == MockRewardResult.failed) {
      setState(() {
        _loading = false;
        _error = 'تعذّر بدء المحاكاة. حاول مرة أخرى.';
      });
      return;
    }
    // The gateway resolved on its own (timer) or was cancelled elsewhere.
    // Only a completed result grants the reward.
    if (result == MockRewardResult.completed) {
      setState(() {
        _loading = false;
        _canComplete = true;
      });
    } else {
      Navigator.of(context).pop(false);
    }
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
