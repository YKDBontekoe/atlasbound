---
name: activity-recording
description: >-
  Atlasbound GPS activity sessions: ActivityRecorder filtering, WorldController
  live route/discovery, pause/resume/finish, and background location caveats.
  Use when editing recording, CLLocation, session UI, streaks, or activity summary.
---

# Activity recording

## Flow

1. `WorldController.start…` → `ActivityRecorder` starts `CLLocationManager`
2. Filtered samples → `onSample` → handle: update route, cover hexes, progression
3. Pause/resume toggles sampling
4. Stop → merge session tiles/progress into `TileStore` → `ActivitySummary` sheet

## Filtering defaults (`ActivitySettings.default`)

- Max horizontal accuracy ≈ **50 m**
- Min distance between samples ≈ **8 m**

Prefer adjusting settings objects over hardcoding magic numbers in the recorder.

## Live session state (`WorldController`)

- `liveRoute`, `sessionVisitedTileIDs`, `sessionDiscoveredCount`
- Session-local `sessionTiles` until stop merge
- Discovery streak + `streakExpiresAt` (**20 min**); multiplier is **UI-only**
- Block tile-size changes while recording

## Location auth

- **When In Use** is the current primary path
- Background mode declared in Info.plist; `allowsBackgroundLocationUpdates` only when Always authorized
- Do not silently require Always for features that work with When In Use

## UI touchpoints

- `MainMapScreen` — start / pause / finish chrome; idle sheet opens `ActivityPickerSheet`
- Activity tab — same `setActivityType` path (blocked while recording)
- `ActivitySummaryView` — end-of-activity sheet
- `DiscoveryMapView` — route polyline + hex overlays

Selection persists in UserDefaults (`atlasbound.selectedActivityType`) and drives `TileStore.tileSize` via `WorldController.syncTileSizeToActivity`.

## Checklist when changing recording

- [ ] Still use route-covering tile IDs (hex line fill)
- [ ] Pause stops awards; resume continues cleanly
- [ ] Finish persists via store and shows summary
- [ ] Info.plist usage strings still accurate

## See also

- [docs/architecture.md](../../../docs/architecture.md)
- [hex-tiles](../hex-tiles/SKILL.md)
- [world-persistence](../world-persistence/SKILL.md)
