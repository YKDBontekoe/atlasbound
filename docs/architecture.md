# Architecture

Lightweight MV + engines. Not Clean Architecture — keep it small.

## Ownership

```
AtlasboundApp
  ├─ TileStore (@MainActor ObservableObject)
  │    persistence + tile size preference + active grid
  └─ WorldController (@MainActor ObservableObject)
       ├─ ActivityRecorder     — GPS samples (filter → callback)
       ├─ TileEngine           — via store.tileEngine
       └─ ProgressionEngine    — discovery / familiarity
            └─ Views (RootTabView → MainMapScreen → DiscoveryMapView)
```

| Type | Role | Threading |
|------|------|-----------|
| `TileStore` | Load/save world; multi-size maps; totals | `@MainActor` |
| `WorldController` | Session: start/pause/stop, live tiles, streak UI | `@MainActor` |
| `ActivityRecorder` | `CLLocationManager` wrapper | `@MainActor` |
| `TileEngine` | Projection + axial hex + polygons | `Sendable` value type |
| `ProgressionEngine` | Visit → XP + state | `Sendable` value type |
| `WorldTile` / models | Domain records | `Sendable` where pure |

## Session flow

1. User starts activity → `WorldController` → `ActivityRecorder.start`.
2. Each accepted sample → tile IDs via engine (including `hexLine` fill) → `ProgressionEngine` on session-local tiles.
3. Live discoveries upsert into the map mid-session.
4. Stop → merge session into `TileStore.applySessionProgress` → persist JSON → show `ActivitySummary`.

## Persistence boundary

- **Persisted:** tile IDs, axial `q`/`r`, mastery fields, activity stamps, dates, totals per size.
- **Derived at render:** hex polygons, map overlays, fog rings.
- Save file: `Documents/atlasbound-world.json` (`WorldSaveFile`).
- Tile size preference: UserDefaults key `atlasbound.tileSizeMeters`.

## UI notes

- Primary chrome: `MainMapScreen` + settings sheet.
- Map: `DiscoveryMapView` (MapKit polygons / polyline / user annotation).
- Discovered markers are capped (~80 highest-ranked) for performance.
- Stubs: `regionName = "Dordrecht"` + discovered tile count in the header — not real geo regions / % coverage.

## Pinpoint mode

A location-guessing game alongside the tile discovery mode.

| Type | Role | Threading |
|------|------|-----------|
| `PinpointScoring` | Pure scoring, area metrics, distance calc | `Sendable` value type |
| `LookAroundLocationPool` | Worldwide + Home Turf target generation | `Sendable` value type |
| `PinpointStore` | Game history + per-mode high scores (JSON) | `@MainActor` |
| `PinpointController` | Game orchestration + tile XP awards | `@MainActor` |
| `GameCenterManager` | GameKit auth + leaderboard submission | `@MainActor` |
| `PinpointView` | Lobby, active game, round result, game over | SwiftUI |
| `LookAroundSnapshotEngine` | Nearby-probe Look Around snapshots (spoiler-free) | `Sendable` value type |
| `LookAroundGuessView` | Static snapshot gallery + timed guess map | SwiftUI |

Flow: lobby (Worldwide or Home Turf) → 5 rounds (static Look Around gallery around spawn + timer → tap map to guess → score) → game over → submit to Game Center leaderboard. No live `MKLookAroundViewController` during play (avoids place-name spoilers).

Persistence: `Documents/atlasbound-pinpoint.json`. Leaderboard ID: `com.atlasbound.geoguessr.highscore`.

## Extension points

- Region Engine (replace stub `regionName` / tile-count header with real geo regions)
- Background Always + passive drive path (`enableBackgroundRecordingIfAuthorized` wired via Settings toggle)
- CloudKit integration
