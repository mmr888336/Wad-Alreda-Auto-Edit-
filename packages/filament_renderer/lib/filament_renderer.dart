import 'package:flutter/services.dart';

/// Dart bridge to the Android-native Filament renderer.
///
/// The method channel provides lifecycle diagnostics, while [modelViewType]
/// identifies the Android PlatformView that displays the bundled GLB model.
class FilamentRenderer {
  FilamentRenderer._();

  static const MethodChannel _channel =
      MethodChannel('com.omer.filament_renderer/methods');

  /// Must match the view type registered by FilamentRendererPlugin on Android.
  static const String modelViewType =
      'com.omer.filament_renderer/model_view';

  /// Creates the diagnostic native Filament Engine once for this process.
  ///
  /// Returns true when the native engine exists. Throws a [PlatformException]
  /// if the native library cannot be loaded or the engine cannot be created.
  static Future<bool> initialize() async {
    final initialized = await _channel.invokeMethod<bool>('initialize');
    return initialized ?? false;
  }

  /// Reports whether the diagnostic native engine has been initialized.
  static Future<bool> get isInitialized async {
    final value = await _channel.invokeMethod<bool>('isInitialized');
    return value ?? false;
  }

  /// Returns the Filament artifact version linked into the Android plugin.
  static Future<String> getNativeVersion() async {
    final value = await _channel.invokeMethod<String>('getNativeVersion');
    return value ?? 'unknown';
  }

  /// Destroys the diagnostic native engine if it was initialized.
  static Future<void> dispose() async {
    await _channel.invokeMethod<void>('dispose');
  }
}
