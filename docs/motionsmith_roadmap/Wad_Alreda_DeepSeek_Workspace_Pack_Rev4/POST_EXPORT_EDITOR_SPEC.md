# Post-Export Non-Destructive Editor — Product & Engineering Spec

## Revision 4 reuse-first rule
Before adding an Editor screen, Timeline model, media picker, save action, or project store, inspect existing app files and call sites. Extend the existing `TimelineProject`/timeline model, `ProjectStore`, existing editor widgets and Android Photo Picker/SAF integration wherever available. Do not add a second project model or parallel export pipeline. A new widget is allowed only when no current UI can be extended; it must use the existing project and services.

## User promise
The exported video remains editable as a saved project. Reopening it must restore the real Timeline, media references, effects, transitions, captions, camera plans and output versions. Do not treat a flattened MP4 as the only saved project state.

## Media import
- Use Android Photo Picker or Storage Access Framework as appropriate; request minimal permissions.
- Support local photos, videos and audio. Preserve reliable persisted URI access or copy approved media into project-managed storage.
- Probe codecs, dimensions, duration, rotation metadata, frame rate, audio channels and file size. Generate thumbnails/proxies for smooth preview.
- Handle revoked URI, corrupt file, unsupported codec, low disk space, cancelled import and duplicate assets without corrupting the project.

## Timeline tracks
- Main footage, B-roll/overlay, still images, picture-in-picture, titles, captions, graphics/stickers, SFX and audio tracks.
- Add, delete, replace, duplicate, reorder, trim in/out, split, ripple delete, insert/overwrite, freeze frame, crop, fit/fill, rotate/flip, scale, position, opacity, playback speed and volume/mute/fades.
- Edit text/captions, font/size/color/RTL alignment, timing, animation, safe-area position and highlight style.
- Edit camera keyframes, shot duration, 3D asset, environment zone and transition. Support multi-select and snap/magnet.
- Undo/redo, autosave, crash recovery, markers, zoom, scrub, frame stepping and playhead preview.

## Non-destructive project model
- Each action creates a reversible transaction. Source files are immutable unless the user explicitly chooses replace/delete from project assets.
- Save `project.json` plus media/asset references, stable IDs, duration/timebase, track order, transforms, effects, transition plans, proxies and output versions.
- Export v2/v3 creates a new version by default. Never silently overwrite the original or a gallery file.
- Render cache is keyed by source hash + filter graph + timing + project version; invalidate when dependencies change.
- Autosave and restore after process death; maintain a safe backup before destructive project edits.

## Runtime validation after each user action
Check affected clip/asset exists and decodes, duration/timebase is valid, track bounds are valid, no illegal overlap, transforms finite, URI permissions valid, project serialization round-trips, preview updates and Undo/Redo restores previous state. Use cheap checks/proxies while dragging; reserve full encode QA for export or completed edit batches.

## UI/UX
- Timeline first on mobile: pinch zoom, horizontal scroll, vertical track scroll, large touch handles, accessible context actions, clear selection state.
- Modern restrained icon family, consistent stroke/filled states, subtle surface elevation, readable typography and clear primary accent. Avoid excessive neon/glow and do not use emoji as editor controls.
- Short smooth micro-animations for inserting/replacing/splitting clips; respect Android Reduce Motion and avoid GPU-heavy continuous animation.
- Preview quality adaptive to device; final export retains selected output resolution/FPS unless user changes it.

## Acceptance tests
Import local image/video/audio → edit → save → close app → reopen → same timeline restored; test trim/split/delete/replace/reorder/crop/speed/caption/keyframes/transition; undo/redo; export new version; verify original export unchanged; revoke permission and ensure clear recovery path; low-storage and big-file tests.


## Revision 4 access gate during experiment mode
All legacy ad placements must also be routed through the same local mock provider during experiment mode; do not leave an existing pre-edit AdPage connected to a real SDK/network. Preserve its user-flow location but replace the provider.
- “حفظ للهاتف” is gated by a local mock rewarded placement `save_to_phone`; after a mock completion, call the existing Gallery save method.
- “فتح التايم لاين” is gated by a different local mock placement `open_timeline`; after completion, open the editor using the existing saved project.
- In experiment mode both are clearly labelled local simulations, with no ad SDK, no network, and no fabricated ad metrics. Cancel/failure grants nothing. The two rewards are independent.
- Do not create a second AdPage or reward service if a current ad gate can be extended. Production mode must reject local mock rewards.
