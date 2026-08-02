# Architecture

Lightweight MV + engines. Not Clean Architecture — keep it small.

## Ownership

```
AtlasboundApp
  ├─ TileStore (@MainActor ObservableObject)
  │    persistence + canonical 20 m atlas
  ├─ TreasureStore (@MainActor ObservableObject)
  │    daily trail + weekly vault + relic persistence
  ├─ InventoryStore (@MainActor ObservableObject)
  │    field finds + stackable inventory + active effects
  ├─ FactoryStore (@MainActor ObservableObject)
  │    placed structures + factory production + research persistence
  ├─ FactoryController (@MainActor ObservableObject)
  │    nearby construction + simulation + inventory transactions
  ├─ IdleStore (@MainActor ObservableObject)
  │    scout roster + Home drip / circuit-claim counters
  └─ WorldController (@MainActor ObservableObject)
       ├─ ActivityRecorder     — shared explicit/passive GPS samples
       ├─ TileEngine           — via store.tileEngine
       ├─ LandmarkResolver     — MapKit public-landmark targets
       ├─ TreasureEventEngine — pure trail/choice/reward rules
       ├─ FieldFindEngine     — pure find rolls + craft/salvage
       ├─ IdleScoutEngine     — hire chain, Home drip, capped AFK discoveries
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
| `DailyChallengeEngine` | Today’s tile timestamps → Scout Circuit goals | `Sendable` value type |
| `IdleScoutEngine` | Scout hire/unlock, Home drip, capped AFK tile picks | `Sendable` value type |
| `IdleStore` | Persist idle roster + daily caps (`idle_state` blob) | `@MainActor` |
| `WorldTile` / models | Domain records | `Sendable` where pure |
| `FactoryController` | Construction, lifecycle simulation, research, transfers, remote collect | `@MainActor` |
| `FactoryStore` | Load/save factory state in its independent schema | `@MainActor` |
| `ConstructionEngine` | Deposit derivation and placement/demolition rules | `Sendable` |
| `FactoryNetworkEngine` | Derived road components and deterministic routes | `Sendable` |
| `FactorySimulationEngine` | Minute-step power, logistics, extraction, and recipes | `Sendable` |

## Session flow

1. Automatic exploration starts when the map opens; the user can optionally start activity tracking.
2. Each accepted sample → tile IDs via engine (including `hexLine` fill) → `ProgressionEngine` on session-local tiles.
3. Live discoveries upsert into the map mid-session.
4. Stop → merge into `TileStore`; only tracked activities create `ActivitySummary` history.

## Persistence boundary

- **Persisted:** 20 m tile IDs, axial `q`/`r`, mastery fields, activity stamps, dates, and totals.
- **Derived at render:** hex polygons, map overlays, fog rings.
- Primary store: `Documents/atlasbound.sqlite` (WAL). Tiles are upserted incrementally; nested Frontier / territory / treasure / inventory / factory / Pinpoint payloads live in the same database.
- Legacy Documents JSON files are imported once on first SQLite open, then renamed to `*.json.bak`.

Factory state remains independently versioned inside SQLite so a factory wipe cannot erase the atlas.

## UI notes

- Primary chrome: `MainMapScreen` + settings sheet.
- Map: `DiscoveryMapView` (MapKit polygons / polyline / user annotation).
- Live-map presentation preferences use `AppStorage`: mastery/visit-heat data lens, 3D terrain, places, fog, and Frontier visibility. The basemap is always the muted Explorer standard style.
- Discovered markers are capped (~80 highest-ranked) for performance.
- Map header uses procedural hex **sectors** (`HexSectorEngine`), not political geography.
- Atlas Stats **Places visited** uses reverse-geocoded country / province / city labels from a coarse-cell cache (`RegionLookupStore`).

## Pinpoint mode

A location-guessing game alongside the tile discovery mode.

| Type | Role | Threading |
|------|------|-----------|
| `PinpointScoring` | Pure scoring, area metrics, distance calc | `Sendable` value type |
| `LookAroundLocationPool` | Worldwide coverage-region sampling + Home Turf targets | `Sendable` value type |
| `PinpointStore` | Game history + per-mode high scores (SQLite) | `@MainActor` |
| `PinpointController` | Game orchestration + tile XP awards | `@MainActor` |
| `GameCenterManager` | GameKit auth + leaderboard submission | `@MainActor` |
| `PinpointView` | Lobby, preparing, active game, round result, game over | SwiftUI |
| `PinpointPreparingView` | Full-screen prep UI with live find progress | SwiftUI |
| `LookAroundSnapshotEngine` | Nearby-probe Look Around snapshots (spoiler-free) | `Sendable` value type |
| `LookAroundGuessView` | Static snapshot gallery + timed guess map | SwiftUI |

Flow: lobby (Worldwide or Home Turf) → preparing (dynamic Look Around scouting with progress) → 5 rounds (static Look Around gallery around spawn + timer → tap map to guess → score) → game over → submit to Game Center leaderboard. No live `MKLookAroundViewController` during play (avoids place-name spoilers). Worldwide samples random streets inside Look Around coverage regions (not a fixed landmark list).

Persistence: Pinpoint tables inside `Documents/atlasbound.sqlite`. Leaderboard ID: `com.atlasbound.geoguessr.highscore`.

## Treasure trails

Serverless daily exploration loop using nearby MapKit landmarks.

| Type | Role | Threading |
|------|------|-----------|
| `TreasureEventEngine` | Daily/weekly keys, choices, deterministic relic rolls | `Sendable` |
| `LandmarkResolver` | Named-landmark search and pedestrian validation | async value type |
| `TreasureStore` | Trail, vault, encounter, and relic persistence | `@MainActor` |
| `DiscoveryMapView` | Tappable treasure destination marker | SwiftUI |
| `WorkshopTabView` | Combined Journal + Factory tab (adventure log, inventory, production) | SwiftUI |
| `JournalHubView` | Trail, relics, discoveries, optional activity history | SwiftUI |

Each local day produces a three-stage trail. Three daily keys unlock the ISO-week vault.

## Field finds & inventory

Deterministic pickups while exploring tiles; stackable pack separate from Treasure relics.

| Type | Role | Threading |
|------|------|-----------|
| `FieldFindEngine` | Spawn rolls, loot tables, assemble/salvage, XP effect math | `Sendable` |
| `InventoryStore` | Stacks, claimed find IDs, active effects, cartographer pins | `@MainActor` |
| `DiscoveryMapView` | Nearby unclaimed find preview markers | SwiftUI |
| `JournalHubView` | Inventory use / activate / salvage; links to shared Recipe book | SwiftUI |
| `FactoryHubView` | Factory overview, research, structures, recipe book (sole craft UI) | SwiftUI |

Find IDs are `find:{dayKey}:{tileID}` — claim once per local day. Atlas Tokens remain non-consumable; field items grant temporary modifiers and charges only.

## Home Base / territory claims

| Type | Role | Threading |
|------|------|-----------|
| `TerritoryEngine` | Claim eligibility, Home Base cooldown, XP/find buffs | `Sendable` |
| `TerritoryState` | Claimed sector IDs + Home Base ID (no geometry) | `Sendable` |
| `TileStore.territoryState` | Load/save with atlas clear | `@MainActor` |
| `DiscoveryMapView` | Claimed-sector wash + Home Base marker | SwiftUI |

Claim unit is `sector:{size}:{q}:{r}`. Unlock at ≥25% sector discovery while the player is inside or adjacent. First claim auto-sets Home Base; moving Home Base has a 24 h cooldown.

## Idle pack (scouts + Home Camp + circuit chest)

| Type | Role | Threading |
|------|------|-----------|
| `IdleScoutEngine` | Hire/unlock chain, Home drip math, fogged tile picks | `Sendable` |
| `IdleStore` | Roster + accumulators + claimed circuit day key | `@MainActor` |
| `WorldController.advanceIdle` | Deposit drip + apply scout visits via Automatic Explore path | `@MainActor` |
| `FactoryController.remoteCollectAllDepots` | Drain depot outputs to backpack remotely | `@MainActor` |
| `IdleScoutsCard` / `IdleScoutsSheet` | Adventures stack hire UI | SwiftUI |

AFK discoveries are permanent atlas visits but hard-capped (18/day, 8 h offline catch-up). Geometry is never stored — candidates are derived from claimed sector IDs + `TileEngine.ring`.

## Extension points

- Region Engine (map-header sector names → richer geo coverage UI; stats already use reverse-geocode places)
- CloudKit integration / live-ops event schedules
