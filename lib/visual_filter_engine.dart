import 'package:flutter/material.dart';

class VisualFilterPreset {
  final String id;
  final String title;
  final String description;
  final String ffmpeg;
  final Color overlay;
  final double tintOpacity;

  const VisualFilterPreset({
    required this.id,
    required this.title,
    required this.description,
    required this.ffmpeg,
    required this.overlay,
    this.tintOpacity = 0.24,
  });
}

/// Local FFmpeg colour looks. These do not download files and work offline.
class VisualFilterEngine {
  VisualFilterEngine._();

  static const presets = <VisualFilterPreset>[
    VisualFilterPreset(
      id: 'clean',
      title: 'Clean',
      description: 'ألوان طبيعية وواضحة',
      ffmpeg: 'eq=contrast=1.05:saturation=1.08,unsharp=5:5:0.4:3:3:0.0',
      overlay: Color(0xFFB9DCEB),
      tintOpacity: 0.08,
    ),
    VisualFilterPreset(
      id: 'cinematic',
      title: 'Cinematic',
      description: 'توازن سينمائي مع ظلال باردة',
      ffmpeg: 'colorbalance=rs=-0.04:bs=0.05:rh=0.05:bh=-0.04,eq=contrast=1.10:saturation=1.05:brightness=-0.01,unsharp=5:5:0.35:3:3:0.0,vignette=angle=PI/5',
      overlay: Color(0xFF20384B),
      tintOpacity: 0.28,
    ),
    VisualFilterPreset(
      id: 'vivid',
      title: 'Vivid',
      description: 'ألوان قوية ومشبعة',
      ffmpeg: 'eq=contrast=1.08:saturation=1.30:brightness=0.01,unsharp=5:5:0.45:3:3:0.0',
      overlay: Color(0xFFFF9D35),
      tintOpacity: 0.18,
    ),
    VisualFilterPreset(
      id: 'warm',
      title: 'Warm',
      description: 'دفء ذهبي للبشرة والمشاهد',
      ffmpeg: 'colorbalance=rs=0.08:gs=0.02:bs=-0.06:rh=0.07:gh=0.02:bh=-0.05,eq=contrast=1.06:saturation=1.10',
      overlay: Color(0xFFFF9A45),
      tintOpacity: 0.32,
    ),
    VisualFilterPreset(
      id: 'cool',
      title: 'Cool',
      description: 'برودة زرقاء هادئة',
      ffmpeg: 'colorbalance=rs=-0.05:bs=0.08:rh=-0.06:bh=0.07,eq=contrast=1.08:saturation=0.98',
      overlay: Color(0xFF4A9BCD),
      tintOpacity: 0.30,
    ),
    VisualFilterPreset(
      id: 'moody',
      title: 'Moody',
      description: 'ظلال عميقة وتباين مرتفع',
      ffmpeg: 'eq=contrast=1.18:saturation=0.88:brightness=-0.025,vignette=angle=PI/4',
      overlay: Color(0xFF182437),
      tintOpacity: 0.42,
    ),
    VisualFilterPreset(
      id: 'vintage',
      title: 'Vintage',
      description: 'طابع قديم بألوان دافئة',
      ffmpeg: 'curves=preset=vintage,eq=saturation=0.82:contrast=0.96',
      overlay: Color(0xFFB9824A),
      tintOpacity: 0.34,
    ),
    VisualFilterPreset(
      id: 'mono',
      title: 'Mono',
      description: 'أبيض وأسود بتباين واضح',
      ffmpeg: 'hue=s=0,eq=contrast=1.12:brightness=-0.01',
      overlay: Color(0xFF777777),
      tintOpacity: 1.0,
    ),
    VisualFilterPreset(
      id: 'dreamy',
      title: 'Dreamy',
      description: 'نعومة وإضاءة حالمة',
      ffmpeg: 'eq=contrast=0.94:saturation=1.14:brightness=0.025,colorbalance=rs=0.02:bs=0.03:rh=0.03:bh=0.02',
      overlay: Color(0xFFCEB9F5),
      tintOpacity: 0.26,
    ),
  ];

  static VisualFilterPreset? byId(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// Returns a comma-prefixed FFmpeg chain for the main video layer.
  /// The `auto` choice is resolved by EditingEngine before this call.
  static String filterSuffix(String style) {
    final preset = byId(style);
    if (preset == null) {
      return byId('cinematic')!.ffmpeg.isEmpty
          ? ''
          : ',${byId('cinematic')!.ffmpeg}';
    }
    return ',${preset.ffmpeg}';
  }
}

/// Small local sample scene, colour-treated with the same named look as the
/// export preset. It is a visual guide, not a pixel-identical video preview.
class VisualFilterPreview extends StatelessWidget {
  final String style;
  final double height;

  const VisualFilterPreview({
    super.key,
    required this.style,
    this.height = 64,
  });

  @override
  Widget build(BuildContext context) {
    final preset = VisualFilterEngine.byId(style) ??
        VisualFilterEngine.byId('cinematic')!;
    final baseScene = const CustomPaint(painter: _PreviewScenePainter());
    final Widget filteredScene = preset.id == 'mono'
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: baseScene,
          )
        : ColorFiltered(
            colorFilter: ColorFilter.mode(
              preset.overlay.withOpacity(preset.tintOpacity),
              BlendMode.softLight,
            ),
            child: baseScene,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            filteredScene,
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.58),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text(
                      'WAD ALREDA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VisualFilterChoiceCard extends StatelessWidget {
  final String id;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const VisualFilterChoiceCard({
    super.key,
    required this.id,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? theme.colorScheme.primary.withOpacity(0.07)
              : theme.colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (id == 'auto')
              const _AutoFilterPreview()
            else
              VisualFilterPreview(style: id),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 17, color: theme.colorScheme.primary),
              ],
            ),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoFilterPreview extends StatelessWidget {
  const _AutoFilterPreview();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        height: 64,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: const _PreviewScenePainter()),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x5535A7FF), Color(0x55FFB347), Color(0x5535C98D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            const Center(
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewScenePainter extends CustomPainter {
  const _PreviewScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sky = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF4D8FC7), Color(0xFFEDB67C)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    final sun = Paint()..color = const Color(0xFFFFE8A8);
    canvas.drawCircle(Offset(w * 0.77, h * 0.27), h * 0.13, sun);

    final far = Path()
      ..moveTo(0, h * 0.72)
      ..lineTo(w * 0.20, h * 0.30)
      ..lineTo(w * 0.37, h * 0.70)
      ..lineTo(w * 0.57, h * 0.38)
      ..lineTo(w * 0.82, h * 0.73)
      ..lineTo(w, h * 0.49)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFF536C73));

    final near = Path()
      ..moveTo(0, h * 0.78)
      ..lineTo(w * 0.28, h * 0.54)
      ..lineTo(w * 0.48, h * 0.83)
      ..lineTo(w * 0.71, h * 0.59)
      ..lineTo(w, h * 0.82)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, Paint()..color = const Color(0xFF263F4A));

    final building = Paint()..color = const Color(0xFF172A38);
    canvas.drawRect(Rect.fromLTWH(w * 0.07, h * 0.52, w * 0.10, h * 0.43), building);
    canvas.drawRect(Rect.fromLTWH(w * 0.16, h * 0.61, w * 0.08, h * 0.34), building);
    canvas.drawRect(Rect.fromLTWH(w * 0.83, h * 0.57, w * 0.11, h * 0.38), building);

    final window = Paint()..color = const Color(0xFFFFD887).withOpacity(0.78);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 2; col++) {
        canvas.drawRect(
          Rect.fromLTWH(w * (0.09 + col * 0.045), h * (0.57 + row * 0.10), w * 0.018, h * 0.045),
          window,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewScenePainter oldDelegate) => false;
}
