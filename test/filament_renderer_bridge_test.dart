import 'package:filament_renderer/filament_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.omer.filament_renderer/methods');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('initialize asks the Android plugin to create Filament', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'initialize');
      called = true;
      return true;
    });

    expect(await FilamentRenderer.initialize(), isTrue);
    expect(called, isTrue);
  });

  test('isInitialized returns the native engine state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isInitialized');
      return true;
    });

    expect(await FilamentRenderer.isInitialized, isTrue);
  });

  test('native version is passed through from the plugin', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getNativeVersion');
      return '1.56.0';
    });

    expect(await FilamentRenderer.getNativeVersion(), '1.56.0');
  });

  test('dispose calls the native plugin', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'dispose');
      called = true;
      return null;
    });

    await FilamentRenderer.dispose();
    expect(called, isTrue);
  });
}
