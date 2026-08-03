# Testing

CI discovers the XCTest suite on every run, compiles once via
`build-for-testing` into a portable `.xctestproducts` artifact, then runs
unit/visual on one runner and balances UI smoke methods across three
`test-without-building` runners. The unsigned IPA job stays parallel with the
compile wave. Static validation runs alongside them. Releases gate publishing
on the complete matrix plus validation and packaging.

Shared steps live in [`scripts/ci-run-tests.sh`](../scripts/ci-run-tests.sh),
[`.github/actions/ios-build-tests`](../.github/actions/ios-build-tests) (compile
+ DerivedData cache + product upload), and
[`.github/actions/ios-test`](../.github/actions/ios-test) (download products,
simulator boot, snapshot bootstrap, `test-without-building`).

Locally, `CI_TEST_MODE=all` (default) still builds then tests in one process.
In Actions, `CI_TEST_MODE=build` and `CI_TEST_MODE=test` split that work so
each runner does not recompile.

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

# Unit + visual + UI tests (simulator; local build+test parity)
./scripts/ci-run-tests.sh

# Optional: match CI split locally
CI_TEST_MODE=build ./scripts/ci-run-tests.sh
CI_TEST_MODE=test ./scripts/ci-run-tests.sh

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
| Activity switch | Map idle sheet / Workshop | Walk → Cycle etc.; activity metadata changes, atlas stays 20 m |
| Activity mid-record | Try change while recording | Blocked until finish |
| Activity persistence | Pick Run, relaunch app | Still Run; Start button says Start Run |
| Clear progress | Clear atlas | All atlas tiles, exploration totals, Frontier, and territory claims are wiped |
| Device GPS noise | Explore on a real device | Samples outside the accuracy threshold are discarded |
| Layers places pins | Toggle layers with resolved places | Locality pins appear; no Apple POIs |
| Live map options | Map → layers button | Style picker, mastery/heat lens, fog, places, and Frontier toggles update independently |
| 3D live map | Reach level 4 → Map → cube button | Camera pitches smoothly, preserves center/heading, and returns flat without moving the atlas |
| Level rewards | Progress after earning XP | Level progress, nearby rewards, tokens, and achievement progress reflect lifetime atlas stats |
| Scout Circuit | Discover 5 new tiles, return to 3 older tiles, visit 12 unique tiles in one local day | Map mission, active tracker, and Progress card stay in sync; claim circuit chest once when 3/3 |
| Idle Scouts | Set Home Base, hire Apprentice, advance clock / reopen app | “While you were away” sheet when scouts/camp gather; Adventures → Idle Scouts Last watch itemizes drip; hiring unlocks Pathfinder |
| Home Camp drip | Leave app with Home Base set, reopen after ≥30 min | Reopen sheet lists camp goods by name; materials also in inventory without walking |
| Territory claim | Explore a sector to ≥25% while inside/adjacent | Adventures → Claim sector; claimed wash + Home Base marker appear; Progress shows claims |
| Home Base move | Claim a second sector; wait 24 h or advance clock in tests | Set Home Base moves after cooldown; familiarity/find buffs follow the new home |
| Factory remote collect | Produce into a depot, open Factory away from site | Remote collect ships depot stock to backpack |
| Automatic foreground | Open Map and move with app open | Tiles reveal without an explicit session or fitness record |
| Automatic background | Enable screen-locked exploration and grant Always | Discovery continues with the iOS location indicator |
| Daily treasure trail | Reach multi-km marker with Sim GPS and choose routes | Each target advances once; final target grants distance-banded relic + key |
| Weekly vault | Complete three daily trails | Far vault target appears and awards rare-or-better relic once |
| Landmark fallback | Disable network before generating trail | Distant procedural caches (~1–8 km) remain playable and can be rerolled once |
| Field find pickup | Explore new tiles via Sim GPS; compare near Home vs remote | Occasional pickup sheet; farther from Home tends toward rarer items |
| Inventory use / activate | Workshop → Journal → long-press item | Boosts start effects; charges apply trail reroll / fog lantern / survey pulse |
| Assemble | Workshop → Recipe book | Recipes craft when materials are sufficient |
| Salvage | Workshop → Journal → long-press uncommon+ item | Breaks into 1–2 materials |
| Clear atlas finds | Settings → Clear discovered tiles | Claimed find IDs reset so tiles can yield again; owned stacks kept |

## Agent checklist after behavioral changes

- [ ] Discovery still awards once per tile ID
- [ ] Route coverage still uses line fill between samples
- [ ] Save file still has no geometry
- [ ] All new discovery uses the canonical 20 m tile namespace
- [ ] Privacy / AltStore permission copy still aligned if strings changed
- [ ] Unit / visual / UI tests still pass (`xcodebuild test` or CI)
