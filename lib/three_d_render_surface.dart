
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show PlatformViewHitTestBehavior;

import 'package:filament_renderer/filament_renderer.dart';

/// A real native Filament SurfaceView for the automatic 3D pipeline.
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
        child: AndroidView(
          viewType: FilamentRenderer.modelViewType,
          onPlatformViewCreated: onPlatformViewCreated,
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
      ),
    );
  }
}
