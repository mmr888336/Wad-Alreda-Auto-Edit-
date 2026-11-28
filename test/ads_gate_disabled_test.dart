import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auto_edit/ad_page.dart';

/// Verifies that with the reward gate disabled (the production default) the
/// ad page is never opened and the three gated actions continue directly.
void main() {
  setUp(() => AdsConfig.debugSetAdsGate(false));
  tearDown(() => AdsConfig.debugSetAdsGate(null));

  testWidgets('gate is disabled by default in this test', (tester) async {
    expect(AdsConfig.adsGate, isFalse);
  });

  testWidgets('show() resolves completed without a session', (tester) async {
    final result = await MockRewardedAdGateway.show(AdPlacement.preExport);
    expect(result, MockRewardResult.completed);
    expect(MockRewardedAdGateway.isInFlight(AdPlacement.preExport), isFalse);
  });

  testWidgets('preExport continues without opening AdPage', (tester) async {
    var continued = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  if (AdsConfig.adsGate) {
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const AdPage(placement: AdPlacement.preExport),
                      ),
                    );
                    if (ok != true) return;
                  }
                  continued = true;
                },
                child: const Text('export'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('export'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
    expect(find.byType(AdPage), findsNothing);
  });

  testWidgets('saveToPhone continues without opening AdPage', (tester) async {
    var continued = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  if (AdsConfig.adsGate) {
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const AdPage(placement: AdPlacement.saveToPhone),
                      ),
                    );
                    if (ok != true) return;
                  }
                  continued = true;
                },
                child: const Text('save'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
    expect(find.byType(AdPage), findsNothing);
  });

  testWidgets('openTimeline continues without opening AdPage', (tester) async {
    var continued = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  if (AdsConfig.adsGate) {
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const AdPage(placement: AdPlacement.openTimeline),
                      ),
                    );
                    if (ok != true) return;
                  }
                  continued = true;
                },
                child: const Text('timeline'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('timeline'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
    expect(find.byType(AdPage), findsNothing);
  });

  testWidgets('placements stay independent when the gate is off',
      (tester) async {
    final pre = await MockRewardedAdGateway.show(AdPlacement.preExport);
    final save = await MockRewardedAdGateway.show(AdPlacement.saveToPhone);
    final timeline =
        await MockRewardedAdGateway.show(AdPlacement.openTimeline);

    expect(pre, MockRewardResult.completed);
    expect(save, MockRewardResult.completed);
    expect(timeline, MockRewardResult.completed);
    expect(MockRewardedAdGateway.isInFlight(AdPlacement.preExport), isFalse);
    expect(MockRewardedAdGateway.isInFlight(AdPlacement.saveToPhone), isFalse);
    expect(MockRewardedAdGateway.isInFlight(AdPlacement.openTimeline), isFalse);
  });
}
