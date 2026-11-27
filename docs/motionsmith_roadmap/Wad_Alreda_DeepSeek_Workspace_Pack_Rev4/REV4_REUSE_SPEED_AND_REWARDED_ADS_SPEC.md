# Revision 4 — Reuse-First, Speed Budgets & Local Mock Rewarded Actions

**Repository:** `mmr888336/Wad-Alreda-Auto-Edit-`  
**Applies to:** Revision 4 of the MotionSmith+ implementation roadmap.

This specification is mandatory. It overrides any older instruction that could lead to duplicate systems, slow editing/rendering, or real ad-network activity during the experiment period.

---

## 1. Reuse-first engineering contract

### 1.1 Required decision before any implementation
For every requested capability, inspect the current repository and record one of:

- `REUSE`: existing production implementation already does the job; connect/use it without creating a parallel implementation.
- `EXTEND`: existing implementation is the right owner; add capability there while preserving current API/behavior.
- `REFACTOR`: existing implementation has a proven structural issue; refactor behind compatibility adapters and regression tests.
- `NEW`: no equivalent exists after semantic code search and call-graph inspection. Document why extension is unsafe/impossible, the public interface, production call site, migration and tests.

`NEW` is exceptional. “Cleaner”, “easier”, “more modular” or “I prefer a new class” are not sufficient reasons.

### 1.2 Audit procedure
Before creating a file, class, manager, widget, model or service:
1. Search repository symbols and content with `rg`, IDE search and import/call-site search. Search synonyms, not only the exact proposed name.
2. Inspect current model and state ownership. Determine who owns persistence, IDs, media paths, timing, undo, rendering and errors.
3. Inspect the complete runtime call path from the current UI action to its final visible/export effect.
4. Search tests for equivalent behavior and identify missing coverage.
5. Write an audit row in `EXECUTION_LOG.md`: proposed capability, existing owner, exact files/classes/methods, decision, gap, changes, test.
6. Only then change code.

### 1.3 Known existing owners to inspect first
These are known from the previously audited baseline; verify they still exist and are still used at current HEAD:

| Capability | Existing owners to inspect first |
|---|---|
| Story semantics | `StoryUnderstanding`, `CinematicWorld`, `StoryWorldBridge`, `_captionSegments`/`_storyBeats` in `ThreeDScenePipeline` |
| Asset query/provider/download | `ThreeDAssetService`, `ThreeDQueryPlanner`, `KhronosModelCatalog`, `GlbInspector` |
| 3D world/GLB/camera | `World3DPlanner`, `World3DGlbBuilder`, `World3DSetPieces`, `World3DSceneRunner`, `World3DRig`, native Filament plugin |
| Person and world composite | `PersonTrackingService`, `PersonSegmentationMatte`, `PersonAnchoredCompositor`, `WorldSceneCompositor`, `ThreeDScenePipeline` |
| Transition/motion systems | `motion_transitions.dart`, `motion_scene_model.dart`, `WorldSceneCamera`, `motion_graphics.dart`, `MotionCutawayRenderer`, `WorldLookGrade` |
| Timeline and persistence | `TimelineProject`/existing timeline models, `timeline_engine.dart`, `ProjectStore`, existing Editor/Timeline widgets |
| Export and gallery save | `main.dart`, `Enhancer.run`, `SilenceCutter`, `ProjectStore`, current Gallery/Photo Picker/SAF integration |
| Ads / reward | `AdPage` and every existing Ad SDK/service/gate/callback/placement in the app |
| Settings and flags | `AppSettings`, secure storage, build flavors/Dart defines, existing experiment/debug flags |

Do not assume that a named existing class is complete. The point is to extend the current owner and preserve the app's data path, not to claim the feature exists if it is unintegrated.

### 1.4 No duplicate architecture
- Do not create `StoryDirector2`, `NewTimelineProject`, `SecondProjectStore`, `NewAdPage`, `AdManager2`, `AssetServiceV2`, or parallel compositors when a current owner can be extended.
- If the current model lacks a field, add a backward-compatible field and migration/default handling rather than creating a separate model that cannot be opened by the app.
- If an old path is unsafe, add an adapter or replace it only after regression tests prove feature parity and a safe rollback exists.
- A new widget is permitted when there is no existing screen/widget for that interaction, but it must read/write the current project model and reuse current services.

---

## 2. Speed, pacing and responsiveness

### 2.1 Viewer-facing pacing
The phrase “montage should not be slow for the viewer” means the exported video must remain visually active without sacrificing comprehension:
- For short explainers, aim for a meaningful visual change (shot, camera move, object reveal, zone move or composition change) roughly every 1.5–3 seconds when the narration supports it.
- Holds of 3–5 seconds or longer are acceptable only with a clear storytelling reason, complex explanation, emotional pause or continuing camera move. Record the reason in the shot plan.
- Keep the picture synchronized to speech. Do not reveal an object before the words make sense, and do not wait several seconds after it is spoken.
- Do not cut through spoken phonemes or captions. 0.2–0.8s inserts are emphasis shots, not a universal cutting rate.
- No unmotivated static environment, repeated scene, blank frame, black interval, loading slate or accidental freeze may reach export.
- A clean cut is often better than a decorative transition. The Transition Director must optimize clarity and momentum, not maximize transition count.

### 2.2 Editor responsiveness
- Timeline drag/scrub/selection/trim must use cached thumbnails, proxy video and cached waveforms. It must never trigger full-resolution 3D render or full export while the finger is moving.
- Show immediate local UI feedback; target initial action acknowledgement 100–200ms when the operation is local and available. Instrument P50/P95 on real devices instead of claiming it from widget tests.
- Preview must return the nearest cached frame/proxy immediately, then refine asynchronously if needed. Do not block preview on an asset API call.
- Import media asynchronously: return UI control quickly, show thumbnail/probe status, and allow cancel. Do not copy/decode large full-resolution files on the UI thread.

### 2.3 Export speed and cost controls
- Benchmark the same 15-second source, same resolution/FPS, settings and device before/after. Record the baseline and P50/P95, not only elapsed time from one run.
- In Balanced mode, aim for P50 total export time no more than 1.35× the measured baseline unless the extra cost produces a proven visual improvement; if exceeded, profile and optimize or offer an explicit Quality mode.
- Build one final FFmpeg filter graph for captions/graphics/transitions/audio/composites wherever possible. Avoid encoding the same complete video repeatedly for each layer.
- Use dirty-shot rendering/caching: an edit to one overlay or one shot should not invalidate unaffected source clips/asset downloads. Cache keys include source hash, graph/settings hash, time range and project version.
- Cache downloaded assets, validated GLBs, converted textures, proxies, thumbnails, waveforms and rendered shots. Do not re-download or re-convert a known compatible asset each export.
- Plan story once per export/project; do not call AI once per word/frame. Batch related queries and use local cache/fallback when network is slow.
- Limit network asset prefetch to 1–2 concurrent downloads by default. Keep Filament capture/render sequential on phones unless proven safe on target hardware.
- Never run export-quality 3D preview concurrently with final export. Dispose/release native resources deterministically.
- Keep final resolution/FPS selected by user. Reduce optional effects, texture quality, LOD, shadow/reflection/particle costs before altering output size/FPS; never silently lower those settings.
- If a thermal pause is needed, pause safely with progress and cancel/resume options. Do not freeze the UI or corrupt the project.

### 2.4 Device profile testing
Test at minimum: low-memory profile, balanced profile, warm/thermal constrained profile and best available profile. Use Android thermal APIs with SDK guards. Where a device/API does not provide real thermal status, record that and do not invent temperature readings.

---

## 3. Rewarded actions — local mock only during experiments

### 3.1 Exact user flows
There are two new independent rewarded placements, in addition to any pre-existing ad placements that must also be routed through the same local mock provider during experiments:

**Placement A — `save_to_phone`**
1. User taps the existing “حفظ للهاتف” action.
2. The app opens the local simulated rewarded flow.
3. The UI clearly says: **“إعلان تجريبي — محاكاة محلية، لا يوجد إعلان حقيقي ولا اتصال بشبكة إعلانات.”**
4. User completes the test card/short local demonstration via an explicit completion action.
5. Only after `completed`, invoke the existing Gallery save method for the final video and cover.
6. If cancelled/failed, do not save and do not grant this action's reward.

**Placement B — `open_timeline`**
1. User taps the existing “فتح التايم لاين” action for an exported project.
2. The app opens a separate local simulated reward flow.
3. It uses a separate placement ID and in-flight state.
4. Only after `completed`, open the existing/newly extended Timeline Editor using the current `ProjectStore` project data.
5. If cancelled/failed, do not open the editor and do not grant this action's reward.

A completed mock for one placement must not unlock the other placement. Prevent double-tap duplicate rewards, duplicate saves and duplicate editor routes. The reward is scoped to the one requested action; do not create hidden permanent entitlements.

### 3.2 What “fake ads” means here
- Every ad placement in the app during experiment mode (including any legacy pre-edit `AdPage`/ad gate and the two new reward placements) is a local mock experience, not an ad from an advertiser. Keep the familiar placement in the user journey, but swap its provider to the mock.
- No ad SDK, ad mediation adapter, external web page or ad endpoint may be initialized or called anywhere in the app in experiment/mock mode, including startup initialization and legacy placements.
- Do not send or fabricate impressions, clicks, completion callbacks, revenue or attribution to any advertising network/analytics provider.
- Do not use live ad unit IDs or ask a network to accept fake events. The entire reward simulation stays on-device.
- Label the flow and diagnostic event as `mock_reward_completed_for_test`, never `ad_viewed` or `ad_impression`.
- Keep the existing ad placement and user journey intact where present, but route it through the local mock provider in experiment mode. The two new reward placements are additional gates on existing save/open actions. No old placement may remain connected to a real ad provider during the experiment.

### 3.3 Build/environment guard
- Define one clear experiment flag/config using the current app configuration system (for example `ADS_TEST_MODE` or an existing environment flag). Do not make a second settings system.
- Current internal testing APK must use global mock-ad mode for every ad placement, so the user can test the existing pre-edit ad location, Save to phone and Open Timeline without ad-network traffic.
- Production distribution must reject mock mode or fail closed. Add an assertion/guard/build validation so a production artifact cannot silently ship the fake reward screen.
- Do not add/change CI workflows or Android product flavors merely for convenience unless the task explicitly requires it; first inspect the existing build configuration and choose the smallest compatible way to mark the internal experiment build.
- If any real ad integration is proposed later, it must be a separate task with approved SDK, test ad units, consent/privacy and store-policy review. It is not part of this revision.

### 3.4 UI behavior
- Use the existing icon/theme/button/modal conventions. A clean contemporary reward card with restrained motion is enough; do not simulate a third-party brand or create deceptive ad creatives.
- Show the requested destination clearly (“سيتم حفظ الفيديو” / “سيتم فتح التايم لاين”).
- Completion/cancel/failure states are accessible, RTL-correct and reduce-motion aware.
- Provide retry after cancel/failure; no reward on cancel.

### 3.5 Tests
- Save: no Gallery write before completion; exactly one write after completion; no write after cancel/failure.
- Timeline: no route push before completion; opens correct project exactly once after completion; no push after cancel/failure.
- Placement isolation: save reward cannot unlock timeline, timeline reward cannot save to gallery.
- Double tap: only one simulated session, one reward and one action.
- Mock mode: assert zero ad SDK initialization anywhere in the app, zero ad HTTP requests, zero external ad URLs, zero impression/click/revenue events across legacy and new placements.
- Production guard: production build cannot enable mock mode.
- Gallery permission revoked / invalid URI / no storage / corrupt video: show failure, never report save success.
- Process death mid-dialog: no reward granted; action can be retried safely.

---

## 4. Phase acceptance additions

Do not pass Phase 0 without the reuse matrix and baseline timings. Do not pass Phase 3 without both independent mock reward tests and a Timeline editor tied to the current project model. Do not pass Phase 4 without viewer-pacing and export-performance benchmarks. The detailed roadmap remains authoritative for all other feature and visual acceptance requirements.
