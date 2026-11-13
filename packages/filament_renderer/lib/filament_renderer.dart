import 'package:flutter/services.dart';

/// Flutter bridge for the native Filament preview and frame capture.
class FilamentRenderer {
  FilamentRenderer._();

  static const MethodChannel _channel =
      MethodChannel('com.omer.filament_renderer/methods');

  /// Must match the Android PlatformView factory registration.
  static const String modelViewType =
      'com.omer.filament_renderer/model_view';

  /// Kept for compatibility with the phase-one native bridge.
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

  /// Gets the actual Android surface/model/render-loop state for this view.
  static Future<Map<String, dynamic>> getViewDiagnostics(int viewId) async {
    final value = await _channel.invokeMapMethod<String, dynamic>(
      'getViewDiagnostics',
      <String, Object>{'viewId': viewId},
    );
    return value ?? <String, dynamic>{};
  }

  /// Captures the visible Filament SurfaceView as numbered PNG frames.
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
