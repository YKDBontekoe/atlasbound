---
name: world-persistence
description: >-
  Atlasbound TileStore and canonical 20 m JSON save format. Use when editing
  persistence, clear-progress, or save/load behavior.
---

# World persistence

## Files

| What | Where |
|------|--------|
| World JSON | `Documents/atlasbound-world.json` |
| Regions JSON | `Documents/atlasbound-regions.json` |
| Types | `Persistence/PersistedModels.swift`, `TileStore.swift`, `RegionLookupStore.swift` |

## Save shape (`WorldSaveFile`)

- `version` — required exact schema contract
- `tiles: [PersistedTileRecord]` — canonical 20 m IDs and mastery fields
- `progress: PersistedProgressRecord` — lifetime atlas totals
- `frontier: PersistedFrontierRecord` — weekly expedition state

No geometry is persisted. Dates use ISO-8601 encoding.

## Rules

- There is one 20 m atlas and no grid switching.
- Clearing wipes the atlas, its XP totals, activity count, and Frontier state.
- A schema mismatch starts a fresh atlas; there are no migration or compatibility paths.
- `TileStore(fileURL:)` accepts a temporary URL for tests.
- Write failures remain soft: in-memory state stays authoritative.

## See also

- [docs/architecture.md](../../../docs/architecture.md)
- [docs/domain.md](../../../docs/domain.md)
