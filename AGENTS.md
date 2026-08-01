# AGENTS.md — Atlasbound

Guidance for AI agents and contributors working in this repo.

## What this is

**Atlasbound** is an iPhone location RPG: movement discovers hexagonal MapKit tiles; revisits award familiarity XP. Single SwiftUI target, local SQLite persistence, unsigned IPA via AltStore/SideStore.

| | |
|--|--|
| Platform | iOS 17+, Xcode 16+ |
| Bundle ID | `com.atlasbound.app` |
| Scheme | `Atlasbound` |
| Persistence | `Documents/atlasbound.sqlite` (legacy JSON imported once) + UserDefaults prefs |
| Distribution | Unsigned IPA → GitHub Releases + Pages AltStore source |

## Read first

1. [README.md](README.md) — run, capabilities, AltStore overview
2. [docs/architecture.md](docs/architecture.md) — ownership & layering
3. [docs/domain.md](docs/domain.md) — hex IDs, XP, mastery
4. [docs/development.md](docs/development.md) — edit / build conventions
5. [docs/release.md](docs/release.md) — versioning & AltStore pipeline
6. [docs/testing.md](docs/testing.md) — manual test matrix

## Hard invariants

1. **Geometry is never persisted** — store tile IDs + mastery fields; polygons from `TileEngine.polygon(for:)`.
2. **Tile ID format** — `hex:{sizeMeters}:{q}:{r}` (size in ID prevents grid collisions).
3. **One atlas only** — all discovery, progress, Frontier, Pinpoint awards, and clearing use the 20 m grid.
4. **Use `hexLine` between GPS samples** — high speed must not skip tiles (`tileIDsCoveringRoute`).
5. **`@MainActor` + `ObservableObject`** for `TileStore`, `WorldController`, `ActivityRecorder`; pure math stays `Sendable` structs.
6. **Folder-synced Xcode project** — files under `Atlasbound/` are picked up automatically; avoid manual pbxproj file lists.
7. **Conventional commits** — `feat:` bumps minor on `main`; every push to `main` can publish a release.
8. **SOLID principles** — every type has a single responsibility. Models are plain data, engines are pure logic (`Sendable`), controllers orchestrate state (`@MainActor`), stores own persistence, and views only render + forward actions. Do not mix concerns into a single file; split when a type serves more than one role.

## Source map

```
Atlasbound/
  AtlasboundApp.swift          # @main → TileStore + WorldController
  Engines/
    WorldController.swift      # Session orchestration
    ActivityRecorder.swift     # CLLocation filtering
    TileEngine.swift           # Lat/lon → axial hex
    ProgressionEngine.swift    # Discovery / familiarity XP
    StatsEngine.swift          # Territory area, footprints, explorer metrics
    RegionLookupEngine.swift   # Coarse-cell place labels + places-visited aggregate
    GeocodeLimiter.swift       # Shared throttled CLGeocoder
    FrontierEngine.swift       # Weekly expeditions + frontier scoring
    TerritoryEngine.swift      # Home Base + sector claim eligibility / buffs
    IdleScoutEngine.swift      # Hireable scouts, Home drip, capped AFK discoveries
    TreasureEventEngine.swift  # Daily trails, weekly vaults, and relic rewards
    FieldFindEngine.swift      # Field-find rolls, loot tables, craft/salvage
    PinpointController.swift   # Pinpoint game orchestration
    PinpointScoring.swift      # Distance + score math (Sendable)
    LookAroundLocationPool.swift # Coverage-region + Home Turf targets (Sendable)
    LookAroundSnapshotEngine.swift # Spoiler-free Look Around gallery snapshots
    GameCenterManager.swift    # GameKit auth + leaderboards
  Persistence/                 # SQLite AtlasDatabase + store facades
    SQLiteDatabase.swift       # Low-level SQLite3 wrapper
    AtlasDatabase.swift        # Schema, tile upserts, legacy JSON import
    TileStore.swift            # Canonical atlas + Frontier + territory claims
    RegionLookupStore.swift    # Reverse-geocode place cache
    PinpointStore.swift        # Pinpoint game history
    ActivityHistoryStore.swift # Activity session history + per-type records
    TreasureStore.swift        # Trail, vault, relic persistence
    InventoryStore.swift       # Field finds + stackable inventory
    FactoryStore.swift         # Factory structures + research
    IdleStore.swift            # Scout roster + Home drip / circuit-claim counters
  Models/                      # WorldTile, activity types, FrontierModels, TerritoryModels, TreasureModels, ItemModels, IdlePackModels, PinpointModels
  Map/                         # DiscoveryMapView, AtlasStatsMapView, GuessMapView (MapKit)
  Views/                       # MainMapScreen, summary, Workshop (Journal+Factory), Pinpoint + inventory + idle scout views
  Theme/                       # AtlasTheme
AtlasboundTests/               # Unit + chrome snapshot tests
AtlasboundUITests/             # UI smoke tests
scripts/                       # IPA, versioning, AltStore JSON, validate-pr.sh
altstore/                      # apps.json source template
.github/workflows/             # PR validate/test/IPA + main release
```

## Commands

```bash
# Run: open Atlasbound.xcodeproj → scheme Atlasbound → ⌘R

./scripts/validate-pr.sh
xcodebuild test -project Atlasbound.xcodeproj -scheme Atlasbound \
  -destination 'platform=iOS Simulator,name=iPhone 16'
./scripts/build-ipa.sh
python3 scripts/auto-version.py --bump auto
```

## Project skills

Load these when the task matches (under `.cursor/skills/`):

| Skill | Use when |
|-------|----------|
| [hex-tiles](.cursor/skills/hex-tiles/SKILL.md) | TileEngine, hex math, IDs, polygons, route coverage |
| [progression-xp](.cursor/skills/progression-xp/SKILL.md) | Discovery/familiarity XP, mastery states, visit logic |
| [activity-recording](.cursor/skills/activity-recording/SKILL.md) | GPS sessions, ActivityRecorder, WorldController live path |
| [world-persistence](.cursor/skills/world-persistence/SKILL.md) | TileStore and canonical atlas save format |
| [altstore-release](.cursor/skills/altstore-release/SKILL.md) | IPA build, semver, CI, AltStore `apps.json` |

## Cursor rules

`.cursor/rules/` — engineering invariants (always) and SwiftUI/engine conventions (on matching files).

## Working style

- Prefer extending engines over putting domain logic in views.
- Keep privacy strings in `Atlasbound/Info.plist` aligned with `altstore/apps.json` permissions text.
- Do not add SPM/CocoaPods unless explicitly requested.
- Prefer pure `Sendable` engines; unit tests live in `AtlasboundTests/`, UI smoke in `AtlasboundUITests/`.
