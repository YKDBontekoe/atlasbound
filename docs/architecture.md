# Architecture

Lightweight MV + engines. Not Clean Architecture — keep it small.

## Ownership

```
AtlasboundApp
  ├─ TileStore (@MainActor ObservableObject)
  │    persistence + canonical 20 m atlas
  ├─ TreasureStore (@MainActor ObservableObject)
  │    daily trail + weekly vault + relic persistence
  └─ WorldController (@MainActor ObservableObject)
       ├─ ActivityRecorder     — shared explicit/passive GPS samples
       ├─ TileEngine           — via store.tileEngine
       ├─ LandmarkResolver     — MapKit public-landmark targets
       ├─ TreasureEventEngine — pure trail/choice/reward rules
       └─ ProgressionEngine    — discovery / familiarity
            └─ Views (RootTabView → MainMapScreen → DiscoveryMapView)
```

| Type | Role | Threading |
|------|------|-----------|
| `TileStore` | Load/save the 20 m atlas and totals | `@MainActor` |
| `WorldController` | Session: start/pause/stop, live tiles, streak UI | `@MainActor` |
| `ActivityRecorder` | `CLLocationManager` wrapper | `@MainActor` |
| `TileEngine` | Projection + axial hex + polygons | `Sendable` value type |
| `ProgressionEngine` | Visit → XP + state | `Sendable` value type |
| `ExplorerProgressionEngine` | Lifetime XP → level, title, reward track, achievements | `Sendable` value type |
| `WorldTile` / models | Domain records | `Sendable` where pure |

## Session flow

1. Automatic exploration starts when the map opens; the user can optionally start activity tracking.
2. Each accepted sample → tile IDs via engine (including `hexLine` fill) → `ProgressionEngine` on session-local tiles.
3. Live discoveries upsert into the map mid-session.
4. Stop → merge into `TileStore`; only tracked activities create `ActivitySummary` history.

## Persistence boundary

- **Persisted:** 20 m tile IDs, axial `q`/`r`, mastery fields, activity stamps, dates, and totals.
- **Derived at render:** hex polygons, map overlays, fog rings.
- Save files: `Documents/atlasbound-world.json` and `atlasbound-treasures.json`.

## UI notes

- Primary chrome: `MainMapScreen` + settings sheet.
- Map: `DiscoveryMapView` (MapKit polygons / polyline / user annotation).
- Live-map presentation preferences use `AppStorage`: basemap style, mastery/visit-heat data lens, places, fog, and Frontier visibility.
- Discovered markers are capped (~80 highest-ranked) for performance.
- Map header uses procedural hex **sectors** (`HexSectorEngine`), not political geography.
- Atlas Stats **Places visited** uses reverse-geocoded country / province / city labels from a coarse-cell cache (`RegionLookupStore`).

## Pinpoint mode

A location-guessing game alongside the tile discovery mode.

| Type | Role | Threading |
|------|------|-----------|
| `PinpointScoring` | Pure scoring, area metrics, distance calc | `Sendable` value type |
| `LookAroundLocationPool` | Worldwide coverage-region sampling + Home Turf targets | `Sendable` value type |
| `PinpointStore` | Game history + per-mode high scores (JSON) | `@MainActor` |
| `PinpointController` | Game orchestration + tile XP awards | `@MainActor` |
| `GameCenterManager` | GameKit auth + leaderboard submission | `@MainActor` |
| `PinpointView` | Lobby, preparing, active game, round result, game over | SwiftUI |
| `PinpointPreparingView` | Full-screen prep UI with live find progress | SwiftUI |
| `LookAroundSnapshotEngine` | Nearby-probe Look Around snapshots (spoiler-free) | `Sendable` value type |
| `LookAroundGuessView` | Static snapshot gallery + timed guess map | SwiftUI |

Flow: lobby (Worldwide or Home Turf) → preparing (dynamic Look Around scouting with progress) → 5 rounds (static Look Around gallery around spawn + timer → tap map to guess → score) → game over → submit to Game Center leaderboard. No live `MKLookAroundViewController` during play (avoids place-name spoilers). Worldwide samples random streets inside Look Around coverage regions (not a fixed landmark list).

Persistence: `Documents/atlasbound-pinpoint.json`. Leaderboard ID: `com.atlasbound.geoguessr.highscore`.

## Treasure trails

Serverless daily exploration loop using nearby MapKit landmarks.

| Type | Role | Threading |
|------|------|-----------|
| `TreasureEventEngine` | Daily/weekly keys, choices, deterministic relic rolls | `Sendable` |
| `LandmarkResolver` | Named-landmark search and pedestrian validation | async value type |
| `TreasureStore` | Trail, vault, encounter, and relic persistence | `@MainActor` |
| `DiscoveryMapView` | Tappable treasure destination marker | SwiftUI |
| `JournalTabView` | Trail, relics, discoveries, optional activity history | SwiftUI |

Each local day produces a three-stage trail. Three daily keys unlock the ISO-week vault.

## Extension points

- Region Engine (map-header sector names → richer geo coverage UI; stats already use reverse-geocode places)
- CloudKit integration / live-ops event schedules
