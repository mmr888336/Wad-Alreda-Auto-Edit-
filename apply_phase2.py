
#!/usr/bin/env python3

from pathlib import Path
import sys


def replace_exact(source, old, new, label):
    if new in source:
        print(f"Already applied: {label}")
        return source

    count = source.count(old)

    if count != 1:
        raise SystemExit(
            f"ERROR: {label}: expected 1 matching block, found {count}."
        )

    print(f"Applied: {label}")
    return source.replace(old, new, 1)


def main():
    target = Path(
        sys.argv[1] if len(sys.argv) > 1
        else "app/lib/enhancer.dart"
    )

    if not target.is_file():
        raise SystemExit(f"Enhancer file not found: {target}")

    source = target.read_text(encoding="utf-8")

    # 1. Import motion graphics engine.
    source = replace_exact(
        source,
        "import 'editing_engine.dart';\n",
        "import 'editing_engine.dart';\n"
        "import 'motion_graphics.dart';\n",
        "motion graphics import",
    )

    # 2. Create topic-aware motion plan.
    source = replace_exact(
        source,
        """    final editingProfile = EditingEngine.select(
      content: profileText,
      requestedStyle: s.visualStyle,
    );
""",
        """    final editingProfile = EditingEngine.select(
      content: profileText,
      requestedStyle: s.visualStyle,
    );
    final motionPlan = MotionGraphicsPlan.forProfile(editingProfile);
""",
        "topic-aware motion plan",
    )

    # 3. Animate B-roll clips.
    source = replace_exact(
        source,
        """        chains.add(
          '[$idx:v]scale=$outW:$outH:force_original_aspect_ratio=increase,crop=$outW:$outH,setsar=1,setpts=PTS-STARTPTS+${_f(b.start)}/TB[bv$idx]',
        );
""",
        """        chains.add(
          '[$idx:v]${motionPlan.brollInputFilter(width: outW, height: outH, start: b.start, end: b.end)}[bv$idx]',
        );
""",
        "B-roll animation",
    )

    # 4. Animate captions.
    old_caption = """        inputs.add(
          '-loop 1 -framerate 30 -t ${_f(duration)} -i "${capFiles[i]}"',
        );

        final baseY = s.captionPosition == 'middle'
            ? '(main_h-overlay_h)/2'
            : 'main_h*0.80-overlay_h/2';
        var captionY = baseY;
        if (s.captionAnimation == 'slideUp') {
          captionY =
              "if(lt(t,${_f(c.start + 0.20)}),"
              "($baseY)+overlay_h*(1-(t-${_f(c.start)})/0.20),"
              "$baseY)";
        } else if (s.captionAnimation == 'slideDown') {
          captionY =
              "if(lt(t,${_f(c.start + 0.20)}),"
              "($baseY)-overlay_h*(1-(t-${_f(c.start)})/0.20),"
              "$baseY)";
        }

        final o = next();
        chains.add(
          "[$cur][$idx:v]overlay=x=0:y='$captionY':enable='between(t,${_f(c.start)},${_f(c.end)})'[$o]",
        );
"""

    new_caption = """        inputs.add(
          '-loop 1 -framerate 30 -t ${_f(duration)} -i "${capFiles[i]}"',
        );

        final captionLabel = 'capmotion$i';

        chains.add(
          '[$idx:v]${motionPlan.overlayInputFilter(duration: duration, timelineStart: c.start)}[$captionLabel]',
        );

        final baseY = s.captionPosition == 'middle'
            ? '(main_h-overlay_h)/2'
            : 'main_h*0.80-overlay_h/2';

        final direction = s.captionAnimation == 'slideDown'
            ? 'down'
            : (s.captionAnimation == 'slideUp' ? 'up' : 'none');

        final captionY = motionPlan.captionYExpression(
          baseY: baseY,
          start: c.start,
          direction: direction,
        );

        const baseX = '(main_w-overlay_w)/2';

        final captionX = motionPlan.captionXExpression(
          baseX: baseX,
          start: c.start,
        );

        final o = next();

        chains.add(
          "[$cur][$captionLabel]overlay=x='$captionX':y='$captionY':enable='between(t,${_f(c.start)},${_f(c.end)})'[$o]",
        );
"""

    source = replace_exact(
        source,
        old_caption,
        new_caption,
        "animated captions",
    )

    # 5. Animate opening hook/title.
    source = replace_exact(
        source,
        """        inputs.add('-i "$hook"');
        final o = next();
        chains.add(
          "[$cur][$idx:v]overlay=x=0:y=main_h*0.10:enable='between(t,0.1,3.1)'[$o]",
        );
        cur = o;
        sfxTimes.insert(0, 0.1);
""",
        """        final hookStart = 0.1;
        final hookDuration = motionPlan.hookDurationSeconds;
        final hookEnd = hookStart + hookDuration;

        inputs.add(
          '-loop 1 -framerate 30 -t ${_f(hookDuration)} -i "$hook"',
        );

        const hookLabel = 'hookmotion';

        chains.add(
          '[$idx:v]${motionPlan.overlayInputFilter(duration: hookDuration, timelineStart: hookStart, fadeInSeconds: motionPlan.hookEnterSeconds, fadeOutSeconds: 0.24)}[$hookLabel]',
        );

        const baseX = '(main_w-overlay_w)/2';
        const baseY = 'main_h*0.10';

        final hookX = motionPlan.hookXExpression(
          baseX: baseX,
          start: hookStart,
        );

        final hookY = motionPlan.hookYExpression(
          baseY: baseY,
          start: hookStart,
        );

        final o = next();

        chains.add(
          "[$cur][$hookLabel]overlay=x='$hookX':y='$hookY':enable='between(t,${_f(hookStart)},${_f(hookEnd)})'[$o]",
        );

        cur = o;
        sfxTimes.insert(0, hookStart);
""",
        "animated opening hook",
    )

    # Final validation.
    required = [
        "import 'motion_graphics.dart';",
        "final motionPlan = MotionGraphicsPlan.forProfile(editingProfile);",
        "motionPlan.brollInputFilter(",
        "motionPlan.overlayInputFilter(",
        "motionPlan.hookXExpression(",
    ]

    missing = [item for item in required if item not in source]

    if missing:
        raise SystemExit(
            "ERROR: Motion Graphics integration incomplete: "
            + ", ".join(missing)
        )

    target.write_text(source, encoding="utf-8")

    print("Motion Graphics phase 2 integration completed.")
    print(f"Updated file: {target}")


if __name__ == "__main__":
    main()
