import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:filament_renderer/filament_renderer.dart';

/// Temporary diagnostics screen used to verify Filament + gltfio on-device.
class FilamentTestPage extends StatefulWidget {
  const FilamentTestPage({super.key});

  @override
  State<FilamentTestPage> createState() => _FilamentTestPageState();
}

class _FilamentTestPageState extends State<FilamentTestPage> {
  late Future<String> _versionFuture;
  int _viewGeneration = 0;
  bool _viewCreated = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _versionFuture = FilamentRenderer.getNativeVersion();
  }

  void _retryView() {
    setState(() {
      _viewCreated = false;
      _viewGeneration++;
      _versionFuture = FilamentRenderer.getNativeVersion();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filament 3D Test'),
        actions: [
          IconButton(
            tooltip: 'Reload 3D view',
            onPressed: _retryView,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Native Filament renderer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<String>(
                    future: _versionFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('Plugin channel error: ${snapshot.error}');
                      }
                      if (!snapshot.hasData) {
                        return const LinearProgressIndicator();
                      }
                      return Text('Filament artifact: ${snapshot.data}');
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isAndroid
                        ? (_viewCreated
                            ? 'Android native view created. Check the model below.'
                            : 'Starting the Android native 3D view…')
                        : 'The Filament sample renderer is available on Android only.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 390,
              width: double.infinity,
              color: const Color(0xFF101521),
              child: _isAndroid
                  ? AndroidView(
                      key: ValueKey(_viewGeneration),
                      viewType: FilamentRenderer.modelViewType,
                      creationParams: const <String, Object>{},
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: (_) {
                        if (mounted) setState(() => _viewCreated = true);
                      },
                    )
                  : const Center(
                      child: Text('Open this screen on an Android device.'),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What to verify',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('1. A blue 3D cube should appear in the preview.'),
                  Text('2. Drag on the cube to rotate the camera.'),
                  Text('3. No red error panel should appear.'),
                  SizedBox(height: 8),
                  Text(
                    'If the cube is visible and responds to touch, Filament, gltfio, the bundled GLB and the Android PlatformView are working together.',
                    style: TextStyle(color: Colors.white70, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
