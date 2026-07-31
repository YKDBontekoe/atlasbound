# Atlasbound

Location-based exploration RPG for iPhone. Reveal a shared atlas, follow daily landmark treasure trails, collect relics, and unlock a weekly vault. Fitness activity tracking is optional.

**Website:** [ykdbontekoe.github.io/atlasbound](https://ykdbontekoe.github.io/atlasbound/) · **Docs:** [docs/](docs/) · **Agents:** [AGENTS.md](AGENTS.md)

## Current capabilities

- SwiftUI app with five tabs: **Map**, **Pinpoint**, **Journal**, **Progress (Atlas Stats)**, and **Factory**
- Automatic foreground exploration plus opt-in screen-locked exploration
- Optional walk/run/cycle/hike/drive/transit tracking and activity history
- One canonical **20 m** hex atlas
- Fog vs discovered tile overlay on the map; mastery ladder and familiarity XP
- Configurable live atlas with 3D terrain, Explorer, Satellite, and Hybrid styles plus mastery, visit-heat, places, fog, and Frontier layers
- **Explorer progression** — 50 account levels, rank titles, Atlas Tokens, map unlocks, and achievement milestones
- **Scout Circuit** — three fresh daily goals for discovery, revisits, and route coverage, tracked on the map and Progress tab
- **Frontier Expeditions** — weekly missions, combo scoring, Game Center leaderboards
- **Treasure trails** — three daily landmark clues, route choices, collectible relics, and weekly vaults
- **Field finds** — deterministic tile pickups into a stackable inventory (materials, boosts, charges); assemble, salvage, use, and activate
- **Real-world factory** — reveal deterministic deposits, craft construction kits, place roads and buildings on nearby discovered hexes, automate production, route goods, generate power, and research upgrades
- **Pinpoint** — 5-round Look Around location guessing (dynamic Worldwide streets + Home Turf)
- **Atlas Stats** — territory km², personal records, layered explorer map, Pinpoint stats
- **Activity session history** — last 100 finished sessions with detail sheets
- Local persistence (JSON in Documents)
- First-run onboarding overlay on the map

## Open & run

1. Open `Atlasbound.xcodeproj` in Xcode 16+ (project targets iOS 17).
2. Select an iPhone simulator or your device.
3. Set your **Team** under Signing & Capabilities (required for device; simulator usually works with automatic signing).
4. Run (⌘R).
5. Allow location access when prompted.
6. Move (or simulate location) to explore automatically. Use **Track an activity** only when you want route and fitness history.

### Simulator location

Features → Location → **City Run**, **City Bicycle Ride**, or a custom GPX. Freeway Drive is useful for testing hex coverage at speed.

### Device

Best validation for GPS noise, landmark routing, automatic exploration, and screen-locked discovery.

## Exploration modes

- **Automatic Explore:** discovery while the app is open; screen-locked discovery is a separate Always-location opt-in.
- **Track Activity:** adds distance, route, duration, and an activity stamp while discovering the same 20 m atlas.

## Architecture

| Component | Role |
|-----------|------|
| `ActivityRecorder` | Shared CLLocationManager wrapper; explicit and passive sample filtering |
| `TileEngine` | Lat/lon → Web Mercator → flat-top axial hex IDs + polygons |
| `ProgressionEngine` | First visit = discovery XP; revisit = diminishing familiarity XP |
| `TileStore` | SQLite persistence (`Documents/atlasbound.sqlite`) |
| `WorldController` | Exploration-mode, progression, Frontier, and treasure orchestration |
| `TreasureEventEngine` / `TreasureStore` | Daily trails, choices, relics, vaults, and persistence |
| `FactoryController` / `FactoryStore` | Construction, road networks, production simulation, research, and isolated factory persistence |
| `DiscoveryMapView` | MapKit overlay of discovered hexes + live route |

Progress stores tile IDs and mastery fields only — hex geometry is derived at render time.

Deeper write-ups: [docs/architecture.md](docs/architecture.md), [docs/domain.md](docs/domain.md).

## Privacy

Location is used for tile discovery, treasure arrivals, and optional activity tracking. Foreground and screen-locked automatic exploration are separate opt-ins; screen-locked use requires Always access.

## Requirements

- Xcode 16+ / iOS 17+
- Location permission

## AltStore / SideStore distribution

This repo builds an **unsigned IPA** on GitHub Actions and publishes an [AltStore-compatible source](https://faq.altstore.io/developers/make-a-source) on GitHub Pages. AltStore / SideStore re-sign the IPA with your Apple ID on install.

### Source URL

After the first release deploys Pages:

```text
https://ykdbontekoe.github.io/atlasbound/apps.json
```

In AltStore / SideStore: **Sources → + → paste the URL above**.

### Automatic versioning

Every push to `main` publishes a release. Versions are computed automatically:

| Field | Source |
|--------|--------|
| Marketing version (`CFBundleShortVersionString`) | Next semver from the latest `v*` tag |
| Build (`CFBundleVersion`) | GitHub Actions run number (always unique) |

Bump rules (conventional commits since the previous tag):

- `feat:` → **minor**
- `BREAKING CHANGE` / `feat!:` → **major**
- anything else → **patch**
- first release (no tags) → **0.1.0**

Override via **Actions → Build IPA & AltStore Source → Run workflow** (`auto` / `patch` / `minor` / `major` / `none`).

```bash
git push origin main   # auto-bumps, builds IPA, updates AltStore source
```

Preview the next version locally:

```bash
python3 scripts/auto-version.py --bump auto
```

The release workflow:

1. Computes the next version from git tags
2. Archives the iOS app without code signing
3. Packages `Atlasbound-<version>+<build>.ipa`
4. Creates a GitHub Release + `v*` tag
5. Prepends a new entry to `apps.json` (keeps prior versions for updates)
6. Deploys `apps.json` + `icon.png` to GitHub Pages

AltStore detects updates from the first `versions` entry — unique `buildVersion` values ensure each main push is offered as an update.

### Local IPA build

```bash
./scripts/build-ipa.sh
# → dist/Atlasbound-<version>.ipa
# → dist/ipa-metadata.env
```

Full release notes: [docs/release.md](docs/release.md). Manual test matrix: [docs/testing.md](docs/testing.md).
