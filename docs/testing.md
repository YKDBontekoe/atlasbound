# Testing

CI discovers the XCTest suite on every run, balances unit/visual test classes
across four macOS runners, and balances UI test methods across five more.
Static validation and the unsigned IPA build run alongside those shards.
Releases gate publishing on the complete matrix plus validation and packaging.

Shared macOS test steps live in [`scripts/ci-run-tests.sh`](../scripts/ci-run-tests.sh) and [`.github/actions/ios-test`](../.github/actions/ios-test) (simulator boot, snapshot bootstrap, `xcodebuild test`).
The shared action restores a versioned Xcode DerivedData cache so later commits
can compile incrementally; unit/visual and UI targets use separate runners but
the same cache lineage.

## Automated suite

| Layer | Where | What |
|-------|--------|------|
| Static | `./scripts/validate-pr.sh` | Privacy/AltStore alignment, `apps.json` JSON, Python script unit tests, CI shell syntax |
| Unit | `AtlasboundTests` | `TileEngine`, `ProgressionEngine`, `TileStore`, persistence (no geometry) |
| Visual | `AtlasboundTests/Visual` | Non-map chrome snapshots (`ActivitySummaryView`, `ActivityTypeRow`, `ActivityHistoryRow`) |
| UI smoke | `AtlasboundUITests` | Launch, activity picker, Progress tab, settings (when map chrome available) |
| Package | `./scripts/build-ipa.sh` | Unsigned IPA archive (PR artifact / release) |

### Local commands

```bash
# Static checks (no Xcode)
./scripts/validate-pr.sh

# Unit + visual + UI tests (simulator; same entry point as CI)
./scripts/ci-run-tests.sh

# Or invoke xcodebuild directly
xcodebuild test \
  -project Atlasbound.xcodeproj \
  -scheme Atlasbound \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Unsigned IPA
./scripts/build-ipa.sh
```

### Chrome snapshots

Reference PNGs live in `AtlasboundTests/Visual/__Snapshots__/`. MapKit / `DiscoveryMapView` is **not** snapshotted (flaky map tiles + GPS).

```bash
# Regenerate golden images after intentional UI chrome changes
RECORD_SNAPSHOTS=1 xcodebuild test \
  -project Atlasbound.xcodeproj \
  -scheme Atlasbound \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AtlasboundTests/ActivitySummarySnapshotTests \
  -only-testing:AtlasboundTests/ActivityTypeRowSnapshotTests
```

Commit updated PNGs with the UI change. CI bootstraps missing references once (`BOOTSTRAP_SNAPSHOTS`) and uploads them as artifacts — commit those PNGs so later runs compare instead of re-record.

## Manual matrix

| Scenario | How | Expect |
|----------|-----|--------|
| Discover tiles | DEBUG Sim GPS pad (or City Run) | Fog → discovered fill; +100 XP first visit |
| Familiarity | Revisit same path via Sim GPS / GPX | Diminishing revisit XP (25→5 floor) |
| High speed | Sim GPS leap step + Auto, or Freeway Drive | Continuous hex fill via `hexLine` (no large gaps) |
| Pause / resume | Pause mid-activity | Samples stop; resume continues route |
| Finish summary | End activity | Sheet with discovery/familiarity splits |
| Places visited | Progress tab after discovering tiles (network) | Countries / provinces / cities appear as MapKit reverse-geocode resolves |
| Session history | Activity tab → Recent activities | Past sessions listed; tap for detail sheet |
| Background recording | Settings → Record while screen is off; grant Always; Drive sim with screen locked | Recording continues; tiles still discovered |
| Activity switch | Map idle sheet / Journal | Walk → Cycle etc.; activity metadata changes, atlas stays 20 m |
| Activity mid-record | Try change while recording | Blocked until finish |
| Activity persistence | Pick Run, relaunch app | Still Run; Start button says Start Run |
| Clear progress | Clear atlas | All atlas tiles and exploration totals are wiped |
| Device GPS noise | Explore on a real device | Samples outside the accuracy threshold are discarded |
| Layers places pins | Toggle layers with resolved places | Locality pins appear; no Apple POIs |
| Live map options | Map → layers button | Style picker, mastery/heat lens, fog, places, and Frontier toggles update independently |
| 3D live map | Reach level 4 → Map → cube button | Camera pitches smoothly, preserves center/heading, and returns flat without moving the atlas |
| Level rewards | Progress after earning XP | Level progress, nearby rewards, tokens, and achievement progress reflect lifetime atlas stats |
| Automatic foreground | Open Map and move with app open | Tiles reveal without an explicit session or fitness record |
| Automatic background | Enable screen-locked exploration and grant Always | Discovery continues with the iOS location indicator |
| Daily treasure trail | Reach marker with Sim GPS and choose routes | Each target advances once; final target grants relic + key |
| Weekly vault | Complete three daily trails | Vault target appears and awards rare-or-better relic once |
| Landmark fallback | Disable network before generating trail | Procedural cache remains playable and can be rerolled once |
| Field find pickup | Explore new tiles via Sim GPS | Occasional pickup sheet; item appears in Journal → Inventory |
| Inventory use / activate | Journal → long-press item | Boosts start effects; charges apply trail reroll / fog lantern / survey pulse |
| Assemble | Journal → Assemble | Recipes craft when materials are sufficient |
| Salvage | Journal → long-press uncommon+ item | Breaks into 1–2 materials |
| Clear atlas finds | Settings → Clear discovered tiles | Claimed find IDs reset so tiles can yield again; owned stacks kept |

## Agent checklist after behavioral changes

- [ ] Discovery still awards once per tile ID
- [ ] Route coverage still uses line fill between samples
- [ ] Save file still has no geometry
- [ ] All new discovery uses the canonical 20 m tile namespace
- [ ] Privacy / AltStore permission copy still aligned if strings changed
- [ ] Unit / visual / UI tests still pass (`xcodebuild test` or CI)
