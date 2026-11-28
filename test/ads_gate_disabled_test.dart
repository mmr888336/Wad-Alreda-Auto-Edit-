import 'package:flutter_test/flutter_test.dart';
import 'package:auto_edit/ad_page.dart';

void main() {
  test('reward resolves as completed immediately when the gate is disabled',
      () async {
    // The default build has ADS_GATE=false, so the gate is off.
    expect(AdsConfig.adsGate, isFalse);

    for (final placement in AdPlacement.values) {
      final result = await MockRewardedAdGateway.show(placement);
      expect(result, MockRewardResult.completed);
      // Nothing is left in flight: the request resolved synchronously.
      expect(MockRewardedAdGateway.isInFlight(placement), isFalse);
    }
  });
}
