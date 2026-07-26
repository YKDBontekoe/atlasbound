# Testing

No XCTest / Swift Testing target yet. CI validates **compile + unsigned IPA**, not behavior.

## Manual matrix

| Scenario | How | Expect |
|----------|-----|--------|
| Discover tiles | Simulator City Run / walk with GPS | Fog → discovered fill; +100 XP first visit |
| Familiarity | Revisit same path | Diminishing revisit XP (25→5 floor) |
| High speed | Freeway Drive / fast GPX | Continuous hex fill via `hexLine` (no large gaps) |
| Pause / resume | Pause mid-activity | Samples stop; resume continues route |
| Finish summary | End activity | Sheet with discovery/familiarity splits |
| Tile size switch | Settings 60 / 80 / 100 | Different grid; prior size progress retained |
| Clear progress | Clear for current size | Only active size wiped |
| Size mid-record | Try change while recording | Blocked |
| Device GPS noise | Real device, try 60 vs 100 m | Finer grids more jitter-sensitive |

## Future automated tests (preferred seams)

Engines are already testable value types / injectable deps:

1. **`TileEngine`** — project / round-trip / `hexLine` / ID parse / `makeTileID`
2. **`ProgressionEngine`** — discovery once, familiarity table, mastery thresholds
3. **`TileStore`** — temp `fileURL`, multi-size isolation, clear current size only

`WorldController(store:recorder:)` accepts injection for session tests later.

## Agent checklist after behavioral changes

- [ ] Discovery still awards once per tile ID
- [ ] Route coverage still uses line fill between samples
- [ ] Save file still has no geometry
- [ ] Tile size switch still isolates grids
- [ ] Privacy / AltStore permission copy still aligned if strings changed
