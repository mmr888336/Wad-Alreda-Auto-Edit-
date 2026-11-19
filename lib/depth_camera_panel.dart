/// Editor controls of the depth camera: a move picker and intensity slider
/// for a scene, and a depth slider for a layer.
///
/// Sliders keep their value locally while they are dragged and report the
/// change once the finger is lifted, so one drag is one undo step.
library;

import 'package:flutter/material.dart';

import 'depth_camera_model.dart';

class DepthCameraPanel extends StatefulWidget {
  /// Camera of the scene (null = no camera).
  final SceneCamera? camera;
  final bool rtl;

  /// Called with the new camera; null removes the camera.
  final ValueChanged<SceneCamera?> onChanged;

  const DepthCameraPanel({
    super.key,
    required this.camera,
    required this.rtl,
    required this.onChanged,
  });

  /// Short name of a camera move.
  static String moveLabel(DepthCameraMove move, bool rtl) {
    switch (move) {
      case DepthCameraMove.none:
        return rtl ? 'بدون' : 'None';
      case DepthCameraMove.pushIn:
        return rtl ? 'تقريب' : 'Push in';
      case DepthCameraMove.pullOut:
        return rtl ? 'إبعاد' : 'Pull out';
      case DepthCameraMove.orbitLeft:
        return rtl ? 'مدار يسار' : 'Orbit left';
      case DepthCameraMove.orbitRight:
        return rtl ? 'مدار يمين' : 'Orbit right';
      case DepthCameraMove.parallaxLeft:
        return rtl ? 'بارالاكس يسار' : 'Parallax left';
      case DepthCameraMove.parallaxRight:
        return rtl ? 'بارالاكس يمين' : 'Parallax right';
      case DepthCameraMove.riseUp:
        return rtl ? 'صعود' : 'Rise';
      case DepthCameraMove.sinkDown:
        return rtl ? 'هبوط' : 'Sink';
      case DepthCameraMove.dollyZoom:
        return rtl ? 'تغيّر المنظور' : 'Dolly zoom';
      case DepthCameraMove.spiralIn:
        return rtl ? 'حلزوني' : 'Spiral in';
      case DepthCameraMove.craneUp:
        return rtl ? 'كرين للأعلى' : 'Crane up';
      case DepthCameraMove.craneDown:
        return rtl ? 'كرين للأسفل' : 'Crane down';
      case DepthCameraMove.windowIn:
        return rtl ? 'دخول النافذة' : 'Enter window';
      case DepthCameraMove.windowOut:
        return rtl ? 'الخروج من النافذة' : 'Exit window';
    }
  }

  @override
  State<DepthCameraPanel> createState() => _DepthCameraPanelState();
}

class _DepthCameraPanelState extends State<DepthCameraPanel> {
  double? _dragIntensity;

  String _s(String ar, String en) => widget.rtl ? ar : en;

  DepthCameraMove get _move => widget.camera?.move ?? DepthCameraMove.none;

  double get _intensity =>
      _dragIntensity ?? widget.camera?.intensity ?? 0.8;

  void _pickMove(DepthCameraMove move) {
    if (move == DepthCameraMove.none) {
      widget.onChanged(null);
      return;
    }
    final base = widget.camera ?? const SceneCamera();
    widget.onChanged(base.copyWith(move: move));
  }

  @override
  Widget build(BuildContext context) {
    final active = _move != DepthCameraMove.none;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171721),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF292A39)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.videocam_outlined,
                size: 18,
                color: Color(0xFFC2B5FF),
              ),
              const SizedBox(width: 7),
              Text(
                _s('كاميرا المشهد', 'Scene camera'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final move in DepthCameraMove.values)
                ChoiceChip(
                  label: Text(DepthCameraPanel.moveLabel(move, widget.rtl)),
                  selected: move == _move,
                  onSelected: (_) => _pickMove(move),
                ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _s('القوة', 'Intensity'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: _intensity
                        .clamp(0.1, SceneCamera.maxIntensity)
                        .toDouble(),
                    min: 0.1,
                    max: SceneCamera.maxIntensity,
                    onChanged: (value) => setState(() => _dragIntensity = value),
                    onChangeEnd: (value) {
                      setState(() => _dragIntensity = null);
                      final base = widget.camera ?? const SceneCamera();
                      widget.onChanged(base.copyWith(intensity: value));
                    },
                  ),
                ),
                Text(
                  _intensity.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Color(0xFFFFD477),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Depth of one layer: automatic, or a fixed distance from the camera
/// (0 far background .. 1 nearest foreground).
class LayerDepthControl extends StatefulWidget {
  /// Explicit depth of the layer (null = automatic).
  final double? depth;

  /// The depth the engine picks when the layer is automatic.
  final double autoDepth;
  final bool rtl;

  /// Called with the new depth; null returns the layer to automatic.
  final ValueChanged<double?> onChanged;

  const LayerDepthControl({
    super.key,
    required this.depth,
    required this.autoDepth,
    required this.rtl,
    required this.onChanged,
  });

  @override
  State<LayerDepthControl> createState() => _LayerDepthControlState();
}

class _LayerDepthControlState extends State<LayerDepthControl> {
  double? _drag;

  String _s(String ar, String en) => widget.rtl ? ar : en;

  @override
  Widget build(BuildContext context) {
    final isAuto = widget.depth == null;
    final value =
        (_drag ?? widget.depth ?? widget.autoDepth).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _s('العمق (بعد عن الكاميرا)', 'Depth (distance from camera)'),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const Spacer(),
            FilterChip(
              label: Text(_s('تلقائي', 'Auto')),
              selected: isAuto,
              onSelected: (on) =>
                  widget.onChanged(on ? null : widget.autoDepth),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              _s('بعيد', 'Far'),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            Expanded(
              child: Slider(
                value: value,
                min: 0,
                max: 1,
                onChanged: (next) => setState(() => _drag = next),
                onChangeEnd: (next) {
                  setState(() => _drag = null);
                  widget.onChanged(next);
                },
              ),
            ),
            Text(
              _s('قريب', 'Near'),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}
