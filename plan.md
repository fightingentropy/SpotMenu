# SpotMenu Optimization Plan

## Goals
Improve perceived library speed, reduce repeated processing, and make queue behavior explicit and maintainable.

## Workstream 1: Lazy Metadata Loading
- [x] Prioritize metadata/artwork loading for visible rows first.
- [x] Defer bulk metadata indexing until brief idle time.
- [x] Update UI incrementally in small batches so covers appear progressively.

## Workstream 2: Debounced Search + Indexed Keys
- [x] Add debounced search input handling in playback library view.
- [x] Precompute normalized search keys for tracks in model/controller.
- [x] Use indexed keys for filtering instead of repeated per-keystroke lowercasing.

## Workstream 3: Smarter Library Refresh
- [x] Add file-system folder observation for the selected music folder.
- [x] Trigger forced refresh on folder changes.
- [x] Keep timer fallback as safety path.

## Workstream 4: Persistent Metadata Cache
- [x] Persist extracted track metadata (title/artist/album/duration) keyed by file signature.
- [x] Persist artwork alongside metadata and load from disk cache on startup.
- [x] Skip AV metadata extraction when cached metadata is valid.

## Workstream 5: Queue-Aware Playback Cleanup
- [x] Introduce explicit queue state in playback model for full-library vs filtered queue.
- [x] Keep Play All behavior queue-aware and predictable.
- [x] Ensure next/previous/auto-advance respects active queue.

## Validation
- [x] Build succeeds (`Debug`).
- [x] Build succeeds (`Release`).
- [x] Verify app install updates `/Applications/SpotMenu.app`.
- [ ] Manual sanity checks: no-filter Play All = all tracks, filtered Play All = filtered tracks.
