# Domain Story Packs — Accuracy & Visual Grammar Spec

## Revision 4 reuse-first rule
Extend the existing `StoryUnderstanding`, `CinematicWorld`, `StoryWorldBridge`, `ThreeDQueryPlanner` and current AI routing. Domain packs are data/configuration owned by the existing story planner, not a second story engine that the production pipeline does not call. Create a separate domain module only if Phase 0 proves there is no suitable existing registry to extend.

## Contract
A `DomainStoryPack` describes a domain using: domain id, subdomains, normalized vocabulary (Arabic/English variants), entities/places/objects/actions, visual grammar, environment families, asset query expansions, shot patterns, transition preferences, palette/material cues, factual constraints, source requirements, and fallback visuals. The planner can blend multiple domains in one story and must preserve timecodes from captions/ASR.

## Minimum supported domains
1. History & archaeology
2. Religion & spirituality (including Islamic content)
3. Science & nature
4. Sports
5. Medicine & health
6. Education & study
7. Technology & AI
8. Business & economics
9. Geography & travel
10. Biography
11. Culture & heritage
12. Space & astronomy
13. Engineering & inventions
14. Law & civics
15. Environment & climate
16. Food & cooking
17. Psychology & society
18. News & current affairs
19. Conflict & military history
20. Arts, media & entertainment
21. Architecture & real estate
22. Everyday explainers

## Domain-specific visual grammar examples
- Historical: map/context reveal, period-accurate location reconstruction, artifact macro, archive/page transition, timeline/time shift, costume/architecture constraints.
- Religious: respectful architecture, landscape, manuscript, symbolic geometry and everyday context; no depiction of God or prophets; do not fabricate unseen beings or present disputed narration as certain; exact sacred text is verified from a trusted local/source input before rendering.
- Science: lab/experiment, scale comparison, 3D mechanism, molecule/anatomy model, equation/diagram in world space; all units, labels and scale claims validated.
- Sports: field/court geometry, equipment, player positions, action trajectories, replay/orbit, tactical top-down diagram; preserve actual sport rules and physically possible movement.
- Medical: anatomical models with clear educational label, not diagnosis; source and confidence recorded.
- Geography: map fly-through to real environment; location names and borders not invented.
- Biography: age/time transitions and verified locations; avoid fabricated quotations or likenesses unless explicitly licensed/supplied.
- News: current date and source provenance required for real-event depiction. If no verified source is provided/connected, use abstract explanatory graphics and label it as illustrative.

## Accuracy model
Every factual beat stores `claim`, `sourceRef`/source note where applicable, `confidence`, `visualizationType` (`documentary`, `reconstruction`, `illustrative`, `abstract`) and `riskFlags`. If a factual claim cannot be validated, the app must not generate a confident documentary-looking depiction; it should use neutral illustrative visuals or mark the beat for review.

## Tests
- Arabic and English phrases per domain, including dialect variants.
- Multi-domain mixed narration.
- Metaphor and ambiguous phrase cases.
- Historical era/place mismatch detection.
- Religious sensitive-entity handling and exact-text protection.
- Scientific units/scale labels and no invented values.
- Sports rule/field layout validation.
- Offline/no-key fallback.
- Source missing/low-confidence behavior.


## Runtime budget
- Domain classification/planning is batched per caption/beat group, cached by normalized text + language + planner version, and must not invoke an AI request per word or frame.
- If AI is slow/unavailable, use cached/local planning and continue the edit; do not block first preview or final export indefinitely.
- Keep domain QA lightweight during interaction; run full semantic review after the shot plan is built and final render QA after export.
