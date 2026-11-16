import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import 'package:filament_renderer/filament_renderer.dart';

/// A real native Filament SurfaceView for the automatic 3D pipeline.
///
/// The view is embedded with Hybrid Composition. The native view contains a
/// SurfaceView, and a plain [AndroidView] falls back to a virtual display for
/// such views, where the SurfaceView never gets a frame that PixelCopy can
/// read (PixelCopy then fails with code 3, ERROR_SOURCE_NO_DATA). With Hybrid
/// Composition the SurfaceView lives in the real window, so the capture works.
class ThreeDRenderSurface extends StatelessWidget {
  const ThreeDRenderSurface({
    super.key,
    required this.onPlatformViewCreated,
    this.height = 280,
  });

  final ValueChanged<int> onPlatformViewCreated;
  final double height;

  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;

    if (!supported) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'The native 3D renderer is available on Android only.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: PlatformViewLink(
          viewType: FilamentRenderer.modelViewType,
          surfaceFactory:
              (BuildContext context, PlatformViewController controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers:
                  const <Factory<OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            );
          },
          onCreatePlatformView: (PlatformViewCreationParams params) {
            final controller = PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: FilamentRenderer.modelViewType,
              layoutDirection: TextDirection.ltr,
              creationParams: null,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () {
                params.onFocusChanged(true);
              },
            );

            controller.addOnPlatformViewCreatedListener(
              params.onPlatformViewCreated,
            );
            controller.addOnPlatformViewCreatedListener(
              onPlatformViewCreated,
            );
            controller.create();

            return controller;
          },
        ),
      ),
    );
  }
}
