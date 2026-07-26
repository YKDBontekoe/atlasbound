# Atlasbound

Location-based exploration RPG prototype for iPhone. Walk, run, cycle, or drive — new hexagonal map tiles are **discovered**; revisiting awards **familiarity** XP instead of unlimited discovery.

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
6. Tap **Start Activity**, move (or simulate location), then **End Activity** for a summary.

### Simulator location

Features → Location → **City Run**, **City Bicycle Ride**, or a custom GPX. Freeway Drive is useful for testing hex coverage at speed.

### Device

Best validation for GPS noise vs tile size. Try 60 m vs 80 m vs 100 m from the slider menu.

## Tile size

| Option | Flat-to-flat width | Notes |
|--------|--------------------|--------|
| 60 m   | Finer grid         | More sensitive to GPS jitter |
| **80 m** | Default          | Spec midpoint |
| 100 m  | Coarser grid       | More forgiving accuracy |

Tile IDs include size (`hex:{meters}:{q}:{r}`), so grids do not collide when you switch sizes. Progress is stored per tile-size grid.

## Architecture

| Component | Role |
|-----------|------|
| `ActivityRecorder` | CLLocationManager wrapper; accuracy/distance filtering |
| `TileEngine` | Lat/lon → Web Mercator → flat-top axial hex IDs + polygons |
| `ProgressionEngine` | First visit = discovery XP; revisit = diminishing familiarity XP |
| `TileStore` | JSON FileManager persistence (`Documents/atlasbound-world.json`) + UserDefaults tile size |
| `WorldController` | Session orchestration |
| `DiscoveryMapView` | MapKit overlay of discovered hexes + live route |

Progress stores tile IDs and mastery fields only — hex geometry is derived at render time.

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

### Cut a release

```bash
# Option A — tag and push (recommended)
git tag v0.1.0
git push origin v0.1.0

# Option B — Actions → "Build IPA & AltStore Source" → Run workflow
```

The release workflow:

1. Archives the iOS app without code signing
2. Packages `Atlasbound-<version>.ipa`
3. Uploads it to a GitHub Release
4. Prepends a new entry to `apps.json` (keeps prior versions for updates)
5. Deploys `apps.json` + `icon.png` to GitHub Pages

AltStore detects updates by comparing the **first** entry in `versions` with the installed app — each release must bump `version` and/or `buildVersion`.

### Local IPA build

```bash
./scripts/build-ipa.sh
# → dist/Atlasbound-<version>.ipa
# → dist/ipa-metadata.env
```
