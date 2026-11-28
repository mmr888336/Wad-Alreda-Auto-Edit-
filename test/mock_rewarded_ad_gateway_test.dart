import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auto_edit/ad_page.dart';

void main() {
  group('MockRewardedAdGateway', () {
    // These tests exercise the enabled gate, so force it on regardless of the
    // build-time default (which is false in production).
    setUp(() => AdsConfig.debugSetAdsGate(true));
    tearDown(() => AdsConfig.debugSetAdsGate(null));

    test('completes before the timer fires', () {
      fakeAsync((async) {
        MockRewardResult? result;
        MockRewardedAdGateway.show(AdPlacement.preExport).then((r) {
          result = r;
        });

        async.flushMicrotasks();
        expect(MockRewardedAdGateway.isInFlight(AdPlacement.preExport), isTrue);

        final ok = MockRewardedAdGateway.complete(AdPlacement.preExport);
        expect(ok, isTrue);
        async.flushMicrotasks();

        expect(result, MockRewardResult.completed);
        expect(MockRewardedAdGateway.isInFlight(AdPlacement.preExport), isFalse);

        // The timer must not fire a second resolution.
        async.elapse(AdsConfig.mockDuration * 2);
        expect(result, MockRewardResult.completed);
      });
    });

    test('timer fires before completion', () {
      fakeAsync((async) {
        MockRewardResult? result;
        MockRewardedAdGateway.show(AdPlacement.saveToPhone).then((r) {
          result = r;
        });

        async.elapse(AdsConfig.mockDuration);
        async.flushMicrotasks();

        expect(result, MockRewardResult.completed);
        expect(MockRewardedAdGateway.isInFlight(AdPlacement.saveToPhone), isFalse);

        // A late complete() must not grant a second reward.
        final ok = MockRewardedAdGateway.complete(AdPlacement.saveToPhone);
        expect(ok, isFalse);
      });
    });

    test('cancel resolves with cancelled and clears in-flight', () {
      fakeAsync((async) {
        MockRewardResult? result;
        MockRewardedAdGateway.show(AdPlacement.openTimeline).then((r) {
          result = r;
        });

        async.flushMicrotasks();
        expect(MockRewardedAdGateway.isInFlight(AdPlacement.openTimeline), isTrue);

        MockRewardedAdGateway.cancel(AdPlacement.openTimeline);
        async.flushMicrotasks();

        expect(result, MockRewardResult.cancelled);
        expect(MockRewardedAdGateway.isInFlight(AdPlacement.openTimeline), isFalse);

        // Timer must not override the cancellation.
        async.elapse(AdsConfig.mockDuration * 2);
        expect(result, MockRewardResult.cancelled);
      });
    });

    test('two consecutive show() calls for the same placement', () {
      fakeAsync((async) {
        MockRewardResult? first;
        MockRewardResult? second;

        MockRewardedAdGateway.show(AdPlacement.preExport).then((r) {
          first = r;
        });
        async.flushMicrotasks();

        // Second call while the first is in flight must fail immediately.
        MockRewardedAdGateway.show(AdPlacement.preExport).then((r) {
          second = r;
        });
        async.flushMicrotasks();

        expect(second, MockRewardResult.failed);
        expect(first, isNull);

        MockRewardedAdGateway.complete(AdPlacement.preExport);
        async.flushMicrotasks();
        expect(first, MockRewardResult.completed);

        // After the first resolves, a new show() is allowed again.
        MockRewardResult? third;
        MockRewardedAdGateway.show(AdPlacement.preExport).then((r) {
          third = r;
        });
        async.flushMicrotasks();
        expect(MockRewardedAdGateway.isInFlight(AdPlacement.preExport), isTrue);

        MockRewardedAdGateway.cancel(AdPlacement.preExport);
        async.flushMicrotasks();
        expect(third, MockRewardResult.cancelled);
      });
    });

    test('placements are independent', () {
      fakeAsync((async) {
        MockRewardResult? pre;
        MockRewardResult? save;

        MockRewardedAdGateway.show(AdPlacement.preExport).then((r) {
          pre = r;
        });
        MockRewardedAdGateway.show(AdPlacement.saveToPhone).then((r) {
          save = r;
        });
        async.flushMicrotasks();

        expect(MockRewardedAdGateway.isInFlight(AdPlacement.preExport), isTrue);
        expect(MockRewardedAdGateway.isInFlight(AdPlacement.saveToPhone), isTrue);

        MockRewardedAdGateway.complete(AdPlacement.preExport);
        async.flushMicrotasks();

        expect(pre, MockRewardResult.completed);
        expect(save, isNull);
        expect(MockRewardedAdGateway.isInFlight(AdPlacement.saveToPhone), isTrue);

        MockRewardedAdGateway.cancel(AdPlacement.saveToPhone);
        async.flushMicrotasks();
        expect(save, MockRewardResult.cancelled);
      });
    });
  });
}
