import 'package:flutter/services.dart';

/// Dart bridge to the Android-native Filament engine.
///
/// This first integration phase intentionally exposes only engine lifecycle
/// methods. It does not create a render surface or render GLB files yet.
/// Those capabilities will be added after the native engine is verified on
/// the target Android device and ABI.
class FilamentRenderer {
  FilamentRenderer._();

  static const MethodChannel _channel =
      MethodChannel('com.omer.filament_renderer/methods');

  /// Creates the native Filament Engine once for this Android process.
  ///
  /// Returns true when the native engine exists. Throws a [PlatformException]
  /// if the native library cannot be loaded or the engine cannot be created.
  static Future<bool> initialize() async {
    final initialized = await _channel.invokeMethod<bool>('initialize');
    return initialized ?? false;
  }

  /// Reports whether the native Filament Engine has been initialized.
  static Future<bool> get isInitialized async {
    final value = await _channel.invokeMethod<bool>('isInitialized');
    return value ?? false;
  }

  /// Returns the Filament artifact version linked into the Android plugin.
  static Future<String> getNativeVersion() async {
    final value = await _channel.invokeMethod<String>('getNativeVersion');
    return value ?? 'unknown';
  }

  /// Destroys the native engine if it was initialized.
  static Future<void> dispose() async {
    await _channel.invokeMethod<void>('dispose');
  }
}
