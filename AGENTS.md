# AGENTS.md — Atlasbound

Guidance for AI agents and contributors working in this repo.

## What this is

**Atlasbound** is a Phase 1 iPhone location RPG: movement discovers hexagonal MapKit tiles; revisits award familiarity XP. Single SwiftUI target, local JSON persistence, unsigned IPA via AltStore/SideStore.

| | |
|--|--|
| Platform | iOS 17+, Xcode 16+ |
| Bundle ID | `com.atlasbound.app` |
| Scheme | `Atlasbound` |
| Persistence | `Documents/atlasbound-world.json` + UserDefaults tile size |
| Distribution | Unsigned IPA → GitHub Releases + Pages AltStore source |

## Read first

1. [README.md](README.md) — run, Phase 1 scope, AltStore overview
2. [docs/architecture.md](docs/architecture.md) — ownership & layering
3. [docs/domain.md](docs/domain.md) — hex IDs, XP, mastery
4. [docs/development.md](docs/development.md) — edit / build conventions
5. [docs/release.md](docs/release.md) — versioning & AltStore pipeline
6. [docs/testing.md](docs/testing.md) — manual test matrix

## Phase 1 boundaries (do not build)

Game Center, CloudKit, skill tree, social, StoreKit, Watch, challenges, widgets, Live Activities, Region Engine (real geo regions). Keep stubs (`regionName`, completion %) clearly placeholder.

## Hard invariants

1. **Geometry is never persisted** — store tile IDs + mastery fields; polygons from `TileEngine.polygon(for:)`.
2. **Tile ID format** — `hex:{sizeMeters}:{q}:{r}` (size in ID prevents grid collisions).
3. **Progress is per tile-size grid** — switching 60/80/100 m loads a different grid; clear only clears the current size.
4. **Use `hexLine` between GPS samples** — high speed must not skip tiles (`tileIDsCoveringRoute`).
5. **`@MainActor` + `ObservableObject`** for `TileStore`, `WorldController`, `ActivityRecorder`; pure math stays `Sendable` structs.
6. **Folder-synced Xcode project** — files under `Atlasbound/` are picked up automatically; avoid manual pbxproj file lists.
7. **Conventional commits** — `feat:` bumps minor on `main`; every push to `main` can publish a release.

## Source map

```
Atlasbound/
  AtlasboundApp.swift          # @main → TileStore + WorldController
  Engines/
    WorldController.swift      # Session orchestration
    ActivityRecorder.swift     # CLLocation filtering
    TileEngine.swift           # Lat/lon → axial hex
    ProgressionEngine.swift    # Discovery / familiarity XP
  Persistence/                 # JSON save + Codable records
  Models/                      # WorldTile, activity types
  Map/                         # DiscoveryMapView (MapKit)
  Views/                       # MainMapScreen, summary, tabs
  Theme/                       # AtlasTheme
scripts/                       # IPA, versioning, AltStore JSON
altstore/                      # apps.json source template
.github/workflows/             # PR build + main release
```

## Commands

```bash
# Run: open Atlasbound.xcodeproj → scheme Atlasbound → ⌘R

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
| [world-persistence](.cursor/skills/world-persistence/SKILL.md) | TileStore, save format, multi-size grids |
| [altstore-release](.cursor/skills/altstore-release/SKILL.md) | IPA build, semver, CI, AltStore `apps.json` |

## Cursor rules

`.cursor/rules/` — Phase 1 scope (always) and SwiftUI/engine conventions (on matching files).

## Working style

- Prefer extending engines over putting domain logic in views.
- Keep privacy strings in `Atlasbound/Info.plist` aligned with `altstore/apps.json` permissions text.
- Do not add SPM/CocoaPods unless explicitly requested.
- No unit test target yet — prefer pure `Sendable` engines so tests can land later without refactor.
