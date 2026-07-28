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

## World events & map highlights

Client-scheduled loop layered like Frontier (no live ops server).

| Type | Role | Threading |
|------|------|-----------|
| `WorldEventEngine` | Catalog windows, daily hotspots, visit scoring | `Sendable` value type |
| `WorldEventModels` | Event kinds, instance, per-grid state, map hotspot/pin DTOs | `Sendable` |
| `TileStore` (`eventsBySize`) | Persist progress per tile-size grid | `@MainActor` |
| `WorldController` | Publish beacons / washes / hotspots; apply XP & frontier multipliers | `@MainActor` |
| `WorldEventViews` | Banner, sheet, in-session tracker | SwiftUI |
| `DiscoveryMapView` | Event wash, beacon, hotspot pins, optional places pins | SwiftUI |

Kinds rotate by UTC day-of-year: Surge, Beacon Rush, Hotspot Circuit, Frontier Charge. Destination events run all day; bonus events run 14:00–20:00 UTC. Daily hotspots always appear near the frontier.

## Extension points

- Region Engine (map-header sector names → richer geo coverage UI; stats already use reverse-geocode places)
- CloudKit integration / live-ops event schedules
