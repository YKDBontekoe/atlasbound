# Atlasbound

Location-based exploration RPG prototype for iPhone. Walk, run, cycle, or drive — new hexagonal map tiles are **discovered**; revisiting awards **familiarity** XP instead of unlimited discovery.

**Docs:** [docs/](docs/) · **Agents:** [AGENTS.md](AGENTS.md)

## Phase 1 (this prototype)

- SwiftUI app shell with MapKit + user location
- Foreground activity recording via Core Location (Info.plist structured for background later)
- Hex tile engine (~60 / **80** / 100 m flat-to-flat, configurable)
- Fog vs discovered tile overlay on the map
- Local persistence of discovered tiles + XP totals (JSON in Documents via FileManager; tile size preference in UserDefaults)
- Discovery vs familiarity progression and an end-of-activity summary

**Not in Phase 1:** Game Center, CloudKit, skill tree, social, StoreKit, Watch, challenges, widgets, Live Activities.

## Open & run

1. Open `Atlasbound.xcodeproj` in Xcode 16+ (project targets iOS 17).
2. Select an iPhone simulator or your device.
3. Set your **Team** under Signing & Capabilities (required for device; simulator usually works with automatic signing).
4. Run (⌘R).
5. Allow location access when prompted.
6. Tap the activity on the bottom sheet to choose Walk / Run / Cycle / Hike / Drive / Transit, then **Start …**, move (or simulate location), and **Finish** for a summary.

### Simulator location

Features → Location → **City Run**, **City Bicycle Ride**, or a custom GPX. Freeway Drive is useful for testing hex coverage at speed.

### Device

Best validation for GPS noise vs activity reveal widths (walk/run vs cycle vs drive).

## Reveal width (by activity)

Tile size is **not** a user setting. It follows the selected activity:

| Activity | Reveal width | Flat-to-flat |
|----------|--------------|--------------|
| Walk, Run | Narrow | 60 m |
| Cycle, Hike, Transit | Medium | 80 m |
| Drive | Wide | 100 m |

Tile IDs include size (`hex:{meters}:{q}:{r}`), so activity grids stay separate. Progress is stored per reveal grid.

## Architecture

| Component | Role |
|-----------|------|
| `ActivityRecorder` | CLLocationManager wrapper; accuracy/distance filtering |
| `TileEngine` | Lat/lon → Web Mercator → flat-top axial hex IDs + polygons |
| `ProgressionEngine` | First visit = discovery XP; revisit = diminishing familiarity XP |
| `TileStore` | JSON FileManager persistence (`Documents/atlasbound-world.json`) |
| `WorldController` | Session orchestration; syncs tile size from activity |
| `DiscoveryMapView` | MapKit overlay of discovered hexes + live route |

Progress stores tile IDs and mastery fields only — hex geometry is derived at render time.

Deeper write-ups: [docs/architecture.md](docs/architecture.md), [docs/domain.md](docs/domain.md).

## Privacy

Location is used on-device for tile discovery. Usage strings live in `Atlasbound/Info.plist`. Background mode is declared for a future passive-driving path; Phase 1 records primarily in the foreground (`When In Use`).

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
