# Smart Cinematic Transition Director — Engineering Spec

## Revision 4 reuse-first rule
Inspect and extend the current `motion_transitions.dart`, scene/timeline model, camera path, graphics and compositor pipeline. Do not create a parallel transition registry or a transition class that is never used by final export. A new implementation file is allowed only if Phase 0 proves no current owner can be extended.

## Objective
Choose and render a transition that feels motivated by story, spatial layout, camera movement, subject action, audio rhythm, and art direction. Do not use generic fades as the default. A transition is a timed visual event, not just an enum value.

## Runtime contract
Input: `previousShot`, `nextShot`, `previousZone`, `nextZone`, camera paths/poses/velocities, semantic relation, action continuity, style profile, caption/text safe areas, beat/audio markers, clip durations, device tier and thermal budget.
Output: `TransitionPlan` containing `id`, `kind`, `start`, `duration`, `direction`, `easing`, camera/subject transform bridge, compositing layers/masks, audio timing policy (audio remains unchanged unless explicitly edited), semantic reason, selected assets, estimated CPU/GPU/memory cost, fallback and QA expectations.

## Candidate library
Use the 30 transition families in the main roadmap. Candidates should be scored, not selected by round-robin. Prefer in-world continuous camera movement when two Zones have a valid PortalLink. Prefer a motivated cut when the two locations are unrelated. Avoid fake spatial continuity where there is no physical connection.

## Scoring model
Compute a normalized 0..1 score with explicit component weights that are configurable and unit-tested:
- semantic/story relationship
- spatial graph continuity and valid portal geometry
- motion vector/velocity continuity
- subject pose/action continuity
- composition and face/text safe areas
- visual style and lighting consistency
- audio/beat timing fit without cutting spoken phonemes
- duration and readability
- performance cost / thermal budget

Reject any candidate that violates hard constraints: cuts through a spoken word, obscures the speaker's face, creates a flash/black frame, invalid camera path, unsupported mask, or exceeds the active device budget. If no candidate passes threshold, use `motivated_clean_cut` or continue camera motion; never force a fade.

## Smoothness requirements
- Use continuous, bounded easing curves (cubic Bezier or equivalent) with no sudden acceleration spikes unless a deliberate impact is chosen.
- When the camera continues between shots, match position, orientation, velocity and scale over the transition window. Avoid camera teleport.
- Use motion blur as a directional consequence of camera/object velocity. Disable or reduce it under thermal pressure; do not replace it with random blur.
- Preserve caption/audio timing. Captions remain readable and do not flicker at transition boundaries.
- Default duration is adaptive, not fixed. Typical starting range 0.18–0.85 seconds; shot semantics and dialogue timing override this. A 0.1–0.3 second insert is an impact insert, not a universal transition duration.
- Crossfade/fade-to-black are allowed only when the shot's semantic intent calls for memory, time passing, a soft emotional transition or deliberate ending.

## Preview & UI
- Timeline displays transition handles and a compact visual thumbnail/preview.
- Tapping a transition opens controls: Auto, Replace, Duration, Direction, Intensity, Motion curve, and device cost indicator.
- Auto remains selected by default. Manual override is saved into the project and survives reopening.
- Live Assembly Board reports a transition only when the renderer actually starts/finishes it.

## Tests
1. Portal traversal with valid linked door geometry.
2. Invalid portal graph: reject continuous camera path and choose clean cut.
3. Match-on-action with matched subject transforms.
4. Whip pan: consistent blur direction, no single-frame white/black flash.
5. Caption and spoken-word boundary preserved.
6. Face safe area protected.
7. Thermal downgrade disables expensive DOF/optical flow before degrading core movement.
8. First/middle/last frame checks; no duplicated hold or loop discontinuity.
9. Project save/restore preserves auto or manual transition plan.
10. Final render contact sheet at every transition boundary, with reviewer verdict.


## Viewer pacing and mobile budget
- A visually meaningful change should generally occur every 1.5–3 seconds in short explainers when narration permits; never cut spoken words to meet this heuristic.
- Do not insert a transition between every clip. Prefer the correct clean cut when it is clearer and faster.
- Use cached/proxy previews during timeline interaction; never invoke a full-quality transition render while dragging or scrubbing.
- Transition cost is part of candidate scoring. Disable expensive DOF/optical flow/volumetrics first under thermal pressure while preserving timing and output resolution/FPS.
