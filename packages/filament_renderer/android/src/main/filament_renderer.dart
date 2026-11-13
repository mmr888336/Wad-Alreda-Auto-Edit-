import 'package:flutter/services.dart';

/// Flutter bridge for the native Filament 3D viewer, asset loading and camera.
class FilamentRenderer {
  FilamentRenderer._();

  static const MethodChannel _channel =
      MethodChannel('com.omer.filament_renderer/methods');

  static const String modelViewType =
      'com.omer.filament_renderer/model_view';

  static Future<bool> initialize() async {
    final value = await _channel.invokeMethod<bool>('initialize');
    return value ?? false;
  }

  static Future<bool> get isInitialized async {
    final value = await _channel.invokeMethod<bool>('isInitialized');
    return value ?? false;
  }

  static Future<String> getNativeVersion() async {
    final value = await _channel.invokeMethod<String>('getNativeVersion');
    return value ?? 'unknown';
  }

  static Future<void> dispose() async {
    await _channel.invokeMethod<void>('dispose');
  }

  static Future<Map<String, dynamic>> getViewDiagnostics(int viewId) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'getViewDiagnostics',
      <String, Object>{'viewId': viewId},
    );
    return value ?? <String, dynamic>{};
  }

  /// Loads a downloaded, self-contained GLB v2 file into the live Filament view.
  static Future<void> loadModelFromFile({
    required int viewId,
    required String filePath,
  }) async {
    await _channel.invokeMethod<void>(
      'loadModelFromFile',
      <String, Object>{'viewId': viewId, 'filePath': filePath},
    );
  }

  /// Starts an automated native 3D camera path. The user can still take over
  /// the camera by touching the model; a fresh mode call restarts automation.
  static Future<void> setCameraMotion({
    required int viewId,
    required String mode,
  }) async {
    await _channel.invokeMethod<void>(
      'setCameraMotion',
      <String, Object>{'viewId': viewId, 'mode': mode},
    );
  }

  static Future<String> captureFrames({
    required int viewId,
    double durationSeconds = 3,
    int frameRate = 24,
  }) async {
    final path = await _channel.invokeMethod<String>(
      'captureFrames',
      <String, Object>{
        'viewId': viewId,
        'durationSeconds': durationSeconds,
        'frameRate': frameRate,
      },
    );
    if (path == null || path.trim().isEmpty) {
      throw StateError('Filament did not return a frame directory.');
    }
    return path;
  }
}
