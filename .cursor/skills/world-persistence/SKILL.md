---
name: world-persistence
description: >-
  Atlasbound TileStore and JSON save format: multi-size grids, WorldSaveFile,
  PersistedTileRecord, and UserDefaults tile size. Use when editing persistence,
  clear-progress, tile-size switching, or save/load bugs.
---

# World persistence

## Files / keys

| What | Where |
|------|--------|
| World JSON | `Documents/atlasbound-world.json` |
| Regions JSON | `Documents/atlasbound-regions.json` (place labels only) |
| Tile size pref | UserDefaults `atlasbound.tileSizeMeters` |
| Types | `Persistence/PersistedModels.swift`, `TileStore.swift`, `RegionLookupStore.swift` |

## Save shape (`WorldSaveFile`)

- `tiles: [PersistedTileRecord]` — IDs, `q`/`r`, mastery fields, stamps, dates, `tileSizeMeters`
- `progressBySize: [String: PersistedProgressRecord]` — totals keyed by size

**No geometry** in the save file. Dates: ISO-8601 encode/decode.

## Multi-size rules

- In-memory: `allTilesBySize` + `progressBySize`
- Active `tileSize` loads that grid into published `tiles` / totals
- **Clear** = current size only
- Changing size mid-record is blocked by the controller

## Injectability

`TileStore(fileURL:)` accepts a temp URL — use that for future tests.

## Failure mode

Write failures are currently soft (in-memory kept). If you harden this, surface errors without corrupting the in-memory grid.

## Migration caution

If you change `PersistedTileRecord` fields, keep decode backward-compatible or version the save file explicitly. Prefer additive optional fields.

## See also

- [docs/architecture.md](../../../docs/architecture.md)
- [docs/domain.md](../../../docs/domain.md)
