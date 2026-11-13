import 'package:filament_renderer/filament_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.omer.filament_renderer/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('initialize asks the Android plugin to create Filament', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'initialize');
      return true;
    });
    expect(await FilamentRenderer.initialize(), isTrue);
  });

  test('isInitialized returns native engine state', () async {
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

  test('model view type matches Android plugin registration', () {
    expect(
      FilamentRenderer.modelViewType,
      'com.omer.filament_renderer/model_view',
    );
  });

  test('renderer diagnostics are requested for the selected native view', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getViewDiagnostics');
      expect(call.arguments, <String, Object>{'viewId': 7});
      return <String, Object>{
        'surfaceReady': true,
        'modelLoaded': true,
        'framesRendered': 12,
      };
    });
    final state = await FilamentRenderer.getViewDiagnostics(7);
    expect(state['surfaceReady'], isTrue);
    expect(state['modelLoaded'], isTrue);
    expect(state['framesRendered'], 12);
  });

  test('captureFrames returns the native frame directory', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'captureFrames');
      expect(call.arguments, <String, Object>{
        'viewId': 7,
        'durationSeconds': 3.0,
        'frameRate': 24,
      });
      return '/tmp/filament_frames_test';
    });
    final path = await FilamentRenderer.captureFrames(viewId: 7);
    expect(path, '/tmp/filament_frames_test');
  });
}
