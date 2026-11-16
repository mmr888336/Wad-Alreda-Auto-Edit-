import 'dart:async';

import 'package:auto_edit/ai_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a step that times out is tried twice, then the next step is used',
      () async {
    AiRouter.resetCooldowns();

    var slowCalls = 0;

    final result = await AiRouter.run<String>(<AiStep<String>>[
      AiStep<String>('slow', () async {
        slowCalls++;
        throw TimeoutException('slow');
      }),
      AiStep<String>('fast', () async => 'ok'),
    ]);

    expect(slowCalls, 2);
    expect(result.value, 'ok');
    expect(result.label, 'fast');
  });
}
