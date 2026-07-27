# Testing

CI on pull requests runs three parallel jobs: **static validation**, **unit + visual + UI tests**, and **unsigned IPA** build. Releases gate on the same validate + test suite before publishing.

## Automated suite

| Layer | Where | What |
|-------|--------|------|
| Static | `./scripts/validate-pr.sh` | Privacy/AltStore alignment, `apps.json` JSON, Python script unit tests |
| Unit | `AtlasboundTests` | `TileEngine`, `ProgressionEngine`, `TileStore`, persistence (no geometry) |
| Visual | `AtlasboundTests/Visual` | Non-map chrome snapshots (`ActivitySummaryView`, `ActivityTypeRow`) + theme color samples |
| UI smoke | `AtlasboundUITests` | Launch, activity picker, settings, Activity tab |
| Package | `./scripts/build-ipa.sh` | Unsigned IPA archive (PR artifact / release) |

### Local commands

```bash
# Static checks (no Xcode)
./scripts/validate-pr.sh

# Unit + visual + UI tests (simulator)
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
| Activity switch | Map idle sheet / Activity tab | Walk → Cycle etc.; reveal width + grid update |
| Activity mid-record | Try change while recording | Blocked until finish |
| Activity persistence | Pick Run, relaunch app | Still Run; Start button says Start Run |
| Clear progress | Clear for current size | Only active size wiped |
| Size mid-record | Try change while recording | Blocked |
| Device GPS noise | Real device, try 60 vs 100 m | Finer grids more jitter-sensitive |

## Agent checklist after behavioral changes

- [ ] Discovery still awards once per tile ID
- [ ] Route coverage still uses line fill between samples
- [ ] Save file still has no geometry
- [ ] Tile size switch still isolates grids
- [ ] Privacy / AltStore permission copy still aligned if strings changed
- [ ] Unit / visual / UI tests still pass (`xcodebuild test` or CI)
