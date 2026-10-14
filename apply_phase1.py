#!/usr/bin/env python3
"""Apply the Phase 1 AutoEdit editing/layout and sound fallback patch.

Run from the repository root:
    python apply_phase1.py

The script refuses to write anything unless all expected source anchors are
found exactly once. It preserves the rest of the app's existing code.
"""
from pathlib import Path
import sys

ROOT = Path.cwd()


def require_replace(text: str, old: str, new: str, filename: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{filename}: expected one occurrence of an edit anchor, found {count}. "
            "No source files have been written. Check that main is the expected version."
        )
    return text.replace(old, new, 1)


def main() -> int:
    settings_path = ROOT / "lib/settings.dart"
    enhancer_path = ROOT / "lib/enhancer.dart"
    text_render_path = ROOT / "lib/text_render.dart"
    router_path = ROOT / "lib/ai_router.dart"

    if not all(
        p.exists()
        for p in [
            settings_path,
            enhancer_path,
            text_render_path,
            router_path,
        ]
    ):
        print(
            "ERROR: run this script from the Flutter repository root "
            "(lib/*.dart was not found)."
        )
        return 2

    # Read and transform all source files in memory first. No partial writes.
    s = settings_path.read_text(encoding="utf-8")
    e = enhancer_path.read_text(encoding="utf-8")
    tr = text_render_path.read_text(encoding="utf-8")
    ar = router_path.read_text(encoding="utf-8")

    # settings.dart: persisted preferences
    s = require_replace(
        s,
        "  String pixabayKey;\n",
        """  String pixabayKey;
  String captionPosition; // middle | bottom
  String brollLayout; // topPanel | fullScreen
  String captionStyle;
  String captionAnimation; // none | slideUp | slideDown
  String soundEffectStyle; // a generated non-musical sound effect id
""",
        "lib/settings.dart",
    )

    s = require_replace(
        s,
        "    this.pixabayKey = '',\n",
        """    this.pixabayKey = '',
    this.captionPosition = 'middle',
    this.brollLayout = 'topPanel',
    this.captionStyle = 'classic',
    this.captionAnimation = 'slideUp',
    this.soundEffectStyle = 'whoosh_soft',
""",
        "lib/settings.dart",
    )

    s = require_replace(
        s,
        "      pixabayKey: prefs.getString('pixabayKey') ?? '',\n",
        """      pixabayKey: prefs.getString('pixabayKey') ?? '',
      captionPosition: prefs.getString('captionPosition') ?? 'middle',
      brollLayout: prefs.getString('brollLayout') ?? 'topPanel',
      captionStyle: prefs.getString('captionStyle') ?? 'classic',
      captionAnimation: prefs.getString('captionAnimation') ?? 'slideUp',
      soundEffectStyle: prefs.getString('soundEffectStyle') ?? 'whoosh_soft',
""",
        "lib/settings.dart",
    )

    s = require_replace(
        s,
        "    await prefs.setString('pixabayKey', pixabayKey.trim());\n",
        """    await prefs.setString('pixabayKey', pixabayKey.trim());
    await prefs.setString('captionPosition', captionPosition);
    await prefs.setString('brollLayout', brollLayout);
    await prefs.setString('captionStyle', captionStyle);
    await prefs.setString('captionAnimation', captionAnimation);
    await prefs.setString('soundEffectStyle', soundEffectStyle);
""",
        "lib/settings.dart",
    )

    # settings.dart: user-facing choices. Layout options appear only after B-roll is enabled.
    s = require_replace(
        s,
        "          SwitchListTile(title: const Text('B-roll (مقاطع توضيحية)'), subtitle: const Text('يحتاج مفتاح Pexels أو Pixabay واتصالًا بالإنترنت'), value: current.broll, onChanged: (value) => setState(() => current.broll = value)),\n",
        """          SwitchListTile(title: const Text('B-roll (مقاطع توضيحية)'), subtitle: const Text('يحتاج مفتاح Pexels أو Pixabay واتصالًا بالإنترنت'), value: current.broll, onChanged: (value) => setState(() => current.broll = value)),
          if (current.broll) ...[
            const SizedBox(height: 6),
            const Text('طريقة عرض B-roll', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(
              value: current.brollLayout,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'topPanel', child: Text('B-roll في الأعلى والشخص في الأسفل')),
                DropdownMenuItem(value: 'fullScreen', child: Text('B-roll يغطي الشاشة كاملة')),
              ],
              onChanged: (value) => setState(() => current.brollLayout = value ?? 'topPanel'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text('وضع الأعلى يترك الجزء السفلي من الفيديو الأصلي ظاهرًا.', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          ],
""",
        "lib/settings.dart",
    )

    s = require_replace(
        s,
        "          SwitchListTile(title: const Text('إضافة كابشن'), subtitle: const Text('عطّله إذا كان الفيديو يحتوي على كابشن جاهز'), value: current.captions, onChanged: (value) => setState(() => current.captions = value)),\n",
        """          SwitchListTile(title: const Text('إضافة كابشن'), subtitle: const Text('عطّله إذا كان الفيديو يحتوي على كابشن جاهز'), value: current.captions, onChanged: (value) => setState(() => current.captions = value)),
          if (current.captions) ...[
            const SizedBox(height: 6),
            const Text('موضع الكابشن'),
            DropdownButtonFormField<String>(
              value: current.captionPosition,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'middle', child: Text('منتصف الشاشة')),
                DropdownMenuItem(value: 'bottom', child: Text('أسفل الشاشة')),
              ],
              onChanged: (value) => setState(() => current.captionPosition = value ?? 'bottom'),
            ),
            const SizedBox(height: 8),
            const Text('شكل الكابشن'),
            DropdownButtonFormField<String>(
              value: current.captionStyle,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                for (final entry in EditingCatalog.captionStyles.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => setState(() => current.captionStyle = value ?? 'classic'),
            ),
            const SizedBox(height: 8),
            const Text('حركة دخول الكابشن'),
            DropdownButtonFormField<String>(
              value: current.captionAnimation,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('بدون حركة')),
                DropdownMenuItem(value: 'slideUp', child: Text('دخول من الأسفل')),
                DropdownMenuItem(value: 'slideDown', child: Text('دخول من الأعلى')),
              ],
              onChanged: (value) => setState(() => current.captionAnimation = value ?? 'slideUp'),
            ),
          ],
""",
        "lib/settings.dart",
    )

    s = require_replace(
        s,
        "          SwitchListTile(title: const Text('مؤثرات صوتية انتقالية'), value: current.sfx, onChanged: (value) => setState(() => current.sfx = value)),\n",
        """          SwitchListTile(title: const Text('مؤثرات صوتية انتقالية'), value: current.sfx, onChanged: (value) => setState(() => current.sfx = value)),
          if (current.sfx) ...[
            const SizedBox(height: 6),
            const Text('نوع المؤثر الصوتي (بدون موسيقى)'),
            DropdownButtonFormField<String>(
              value: current.soundEffectStyle,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                for (final entry in EditingCatalog.soundEffects.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => setState(() => current.soundEffectStyle = value ?? 'whoosh_soft'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text('المؤثرات تتولد محليًا من ضوضاء معالجة، ولا تُضاف أي موسيقى.', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          ],
""",
        "lib/settings.dart",
    )

    # The settings file needs the preset names.
    s = require_replace(
        s,
        "import 'languages.dart';\n",
        "import 'languages.dart';\nimport 'editing_catalog.dart';\n",
        "lib/settings.dart",
    )

    # text_render.dart: 30 visual looks, with distinct palette/box/scale combinations.
    tr = require_replace(
        tr,
        """    bool box = false,
  }) async {
    final maxW = width * 0.9;
    final pad = fontSize * 0.35;
    final strokeW = fontSize * 0.2;
""",
        """    bool box = false,
    String preset = 'classic',
  }) async {
    var effectiveFill = fill;
    var effectiveStroke = stroke;
    var effectiveBox = box;
    var effectiveBoxColor = const Color(0xB3000000);
    var fontScale = 1.0;
    const fills = <String, Color>{
      'neon': Color(0xFF7BFFDE), 'gradient': Color(0xFFFFD400),
      'word_pop': Color(0xFFFFE45E), 'karaoke': Color(0xFF80FFEA),
      'highlight_word': Color(0xFFFFD166), 'comic_pop': Color(0xFFFF8A65),
      'soft_glow': Color(0xFFC9B6FF), 'cinematic': Color(0xFFFFDCA8),
      'typewriter': Color(0xFFE0E0E0), 'underline': Color(0xFF80D8FF),
      'glass': Color(0xFFF4F7FF), 'pill': Color(0xFFFFFFFF),
      'double_line': Color(0xFFFFE082), 'large_hook': Color(0xFFFFD400),
      'split_phrase': Color(0xFFA7FFEB), 'bounce': Color(0xFFFFAB91),
      'lower_third': Color(0xFFFFFFFF), 'slide_side': Color(0xFFB3E5FC),
      'middle_safe': Color(0xFFFFFFFF), 'high_contrast': Color(0xFFFFFF00),
      'classic': Color(0xFFFFFFFF), 'bold_center': Color(0xFFFFE082),
      'boxed': Color(0xFFFFFFFF), 'outline': Color(0xFFFFFFFF),
      'shadow': Color(0xFFF5F5F5), 'minimal': Color(0xFFECEFF1),
      'typewriter': Color(0xFFD7CCC8), 'fade': Color(0xFFCFD8DC),
      'slide_up': Color(0xFFFFF176), 'underline': Color(0xFF80D8FF),
      'double_line': Color(0xFFFFE082), 'compact': Color(0xFFFFFFFF),
      'split_phrase': Color(0xFFA7FFEB), 'clean_white': Color(0xFFFFFFFF),
      'pill': Color(0xFFFFFFFF), 'glass': Color(0xFFF4F7FF),
      'large_hook': Color(0xFFFFD400), 'comic_pop': Color(0xFFFF8A65),
    };
    const strokeColors = <String, Color>{
      'neon': Color(0xFF202050), 'comic_pop': Color(0xFF4A1010),
      'high_contrast': Color(0xFF000000), 'soft_glow': Color(0xFF442A7A),
      'cinematic': Color(0xFF22170A), 'outline': Color(0xFF000000),
    };
    const boxed = <String>{'boxed', 'pill', 'glass', 'gradient', 'lower_third', 'highlight_word', 'comic_pop'};
    effectiveFill = fills[preset] ?? effectiveFill;
    effectiveStroke = strokeColors[preset] ?? effectiveStroke;
    effectiveBox = effectiveBox || boxed.contains(preset);
    if (preset == 'glass') effectiveBoxColor = const Color(0xB8242B3D);
    if (preset == 'gradient') effectiveBoxColor = const Color(0xCC5A3A00);
    if (preset == 'lower_third') effectiveBoxColor = const Color(0xCC101018);
    if (preset == 'pill') effectiveBoxColor = const Color(0xC9000000);
    if (preset == 'outline') effectiveFill = Colors.transparent;
    if (preset == 'minimal' || preset == 'compact') fontScale = 0.84;
    if (preset == 'large_hook' || preset == 'bold_center') fontScale = 1.12;
    final effectiveFontSize = fontSize * fontScale;
    final maxW = width * 0.9;
    final pad = effectiveFontSize * 0.35;
    final strokeW = effectiveFontSize * 0.2;
""",
        "lib/text_render.dart",
    )

    tr = require_replace(
        tr,
        "    final back = build(TextStyle(\n      fontSize: fontSize,\n",
        "    final back = build(TextStyle(\n      fontSize: effectiveFontSize,\n",
        "lib/text_render.dart",
    )

    tr = require_replace(
        tr,
        "    final front = build(TextStyle(\n      fontSize: fontSize,\n",
        "    final front = build(TextStyle(\n      fontSize: effectiveFontSize,\n",
        "lib/text_render.dart",
    )

    tr = require_replace(
        tr,
        "..color = stroke,",
        "..color = effectiveStroke,",
        "lib/text_render.dart",
    )

    tr = require_replace(
        tr,
        "      color: fill,\n",
        "      color: effectiveFill,\n",
        "lib/text_render.dart",
    )

    tr = require_replace(
        tr,
        "    if (box) {\n",
        "    if (effectiveBox) {\n",
        "lib/text_render.dart",
    )

    tr = require_replace(
        tr,
        "        Paint()..color = const Color(0xB3000000),\n",
        "        Paint()..color = effectiveBoxColor,\n",
        "lib/text_render.dart",
    )

    tr = require_replace(
        tr,
        "Radius.circular(fontSize * 0.4)",
        "Radius.circular(effectiveFontSize * 0.4)",
        "lib/text_render.dart",
    )

    # enhancer.dart: imports
    e = require_replace(
        e,
        "import 'settings.dart';\n",
        "import 'settings.dart';\nimport 'editing_catalog.dart';\nimport 'sound_effect_generator.dart';\n",
        "lib/enhancer.dart",
    )

    # Selectable caption look is passed into the PNG renderer.
    e = require_replace(
        e,
        "              fontSize: outW * 0.062,\n              fill: Colors.white,\n",
        "              fontSize: outW * 0.062,\n              fill: Colors.white,\n              preset: s.captionStyle,\n",
        "lib/enhancer.dart",
    )

    # Replace the current single pink-noise whoosh with a chosen non-musical effect.
    start = e.find("    // 4) مؤثر صوتي (وش) يتولد بـ FFmpeg\n")
    end = e.find("    // 5) التركيب والتصدير\n", start)

    if start < 0 or end < 0:
        raise RuntimeError(
            "lib/enhancer.dart: sound effect block anchors not found. "
            "No source files have been written."
        )

    old_block = e[start:end]
    expected = "String? whoosh;"

    if old_block.count(expected) != 1:
        raise RuntimeError(
            "lib/enhancer.dart: unexpected sound effect block. "
            "No source files have been written."
        )

    new_block = """    // 4) Generate one user-selected, non-musical sound effect from filtered noise.
    String? whoosh;
    if (s.sfx && s.soundEffectStyle != 'none') {
      final path = '$dir/sfx_${stamp}.wav';
      final ok = await SoundEffectGenerator.render(
        style: s.soundEffectStyle,
        outputPath: path,
        execute: _run,
      );
      if (ok && File(path).existsSync()) {
        whoosh = path;
        temps.add(path);
      } else {
        notes.add('تعذر توليد المؤثر الصوتي المختار؛ سيستمر التصدير بدونه.');
      }
    }

"""
    e = e[:start] + new_block + e[end:]

    # Make B-roll optional: top panel keeps the original video/person visible below.
    e = require_replace(
        e,
        """        chains.add(
            '[$idx:v]scale=$outW:$outH:force_original_aspect_ratio=increase,crop=$outW:$outH,setsar=1,setpts=PTS-STARTPTS+${_f(b.start)}/TB[bv$idx]');
""",
        """        if (s.brollLayout == 'topPanel') {
          final panelH = math.max(2, ((outH * 0.38).round() ~/ 2) * 2);
          chains.add(
              '[$idx:v]scale=$outW:$panelH:force_original_aspect_ratio=increase,crop=$outW:$panelH,setsar=1,setpts=PTS-STARTPTS+${_f(b.start)}/TB[bv$idx]');
        } else {
          chains.add(
              '[$idx:v]scale=$outW:$outH:force_original_aspect_ratio=increase,crop=$outW:$outH,setsar=1,setpts=PTS-STARTPTS+${_f(b.start)}/TB[bv$idx]');
        }
""",
        "lib/enhancer.dart",
    )

    # Caption placement and simple enter motion. FFmpeg uses the main-video timeline.
    e = require_replace(
        e,
        """        chains.add(
            "[$cur][$idx:v]overlay=x=0:y=main_h*0.70-overlay_h/2:enable='between(t,${_f(c.start)},${_f(c.end)})'[$o]");
""",
        """        final baseY = s.captionPosition == 'middle'
            ? 'main_h*0.52-overlay_h/2'
            : 'main_h*0.70-overlay_h/2';
        var captionY = baseY;
        if (s.captionAnimation == 'slideUp') {
          captionY = "if(lt(t,${_f(c.start + 0.14)}),($baseY)+(${_f(c.start + 0.14)}-t)*main_h*0.28,($baseY))";
        } else if (s.captionAnimation == 'slideDown') {
          captionY = "if(lt(t,${_f(c.start + 0.14)}),($baseY)-(${_f(c.start + 0.14)}-t)*main_h*0.28,($baseY))";
        }
        chains.add(
            "[$cur][$idx:v]overlay=x=0:y='$captionY':enable='between(t,${_f(c.start)},${_f(c.end)})'[$o]");
""",
        "lib/enhancer.dart",
    )

    # If AI analysis fails, still create a localized generic hook; never invent captions.
    anchor = "    // 3) B-roll مرتبط بمعنى الكلام، بدون نساء (فلتر وصف + فحص بصري بـ Gemini)\n"

    fallback = """    // Local fallback title only. This is not represented as a transcription.
    if (s.hook && hookFile == null) {
      try {
        final fallbackPath = await TextRender.png(
          text: EditingCatalog.fallbackHook(s.country),
          outPath: '$dir/hook_fallback_$stamp.png',
          width: outW,
          fontSize: outW * 0.085,
          fill: const Color(0xFFFFD400),
          box: true,
          preset: 'large_hook',
        );
        temps.add(fallbackPath);
        hookFile = fallbackPath;
        notes.add('استُخدم عنوان احتياطي محلي لأن تحليل العنوان بالذكاء الاصطناعي لم ينجح.');
      } catch (_) {
        notes.add('تعذر إنشاء العنوان الاحتياطي؛ سيستمر التصدير.');
      }
    }

"""
    e = require_replace(e, anchor, fallback + anchor, "lib/enhancer.dart")

    # ai_router.dart: no repeated retries on a 429; cool down and immediately try the next provider.
    ar = require_replace(
        ar,
        """        } on AiFailure catch (e) {
          failures.add('${step.label} ← ${cut(e.toString())}');
          transient = e.transient;
""",
        """        } on AiFailure catch (e) {
          failures.add('${step.label} ← ${cut(e.toString())}');
          if (e.status == 429) {
            _cool[step.label] = DateTime.now().add(const Duration(minutes: 5));
            break; // Rate/quota limit: skip this provider/model immediately.
          }
          transient = e.transient;
""",
        "lib/ai_router.dart",
    )

    # Write only after every transformation above passed its exact-anchor checks.
    settings_path.write_text(s, encoding="utf-8")
    enhancer_path.write_text(e, encoding="utf-8")
    text_render_path.write_text(tr, encoding="utf-8")
    router_path.write_text(ar, encoding="utf-8")

    # Install the two additional library files shipped alongside this script.
    package_root = Path(__file__).resolve().parent

    for rel in [
        "lib/editing_catalog.dart",
        "lib/sound_effect_generator.dart",
    ]:
        source = package_root / rel
        target = ROOT / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")

    print("Phase 1 patch applied.")
    print(
        "Changed: lib/settings.dart, lib/enhancer.dart, "
        "lib/text_render.dart, lib/ai_router.dart"
    )
    print(
        "Added:   lib/editing_catalog.dart, "
        "lib/sound_effect_generator.dart"
    )
    print(
        "Next: run `dart format lib` and `flutter analyze`, "
        "then build and test a sample video."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)