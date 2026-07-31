---
name: world-persistence
description: >-
  Atlasbound TileStore and SQLite atlas persistence. Use when editing
  persistence, clear-progress, or save/load behavior.
---

# World persistence

## Files

| What | Where |
|------|--------|
| SQLite database | `Documents/atlasbound.sqlite` (+ `-wal` / `-shm`) |
| Legacy JSON (imported once) | `Documents/atlasbound-*.json` → renamed `*.json.bak` |
| Types | `Persistence/AtlasDatabase.swift`, `SQLiteDatabase.swift`, `PersistedModels.swift`, `TileStore.swift` |

## Database (`AtlasDatabase`)

- Schema version in `meta.schema_version` (currently **1**)
- **`tiles`** table — one row per discovered tile (incremental `UPSERT`)
- **`progress`** — lifetime XP + activity count
- **`frontier`** — weekly expedition state as a JSON payload (IDs only, no geometry)
- Other domains (activities, regions, pinpoint, treasure, inventory, factory) live in the same file

No geometry is persisted. Tile coordinates are axial `q`/`r` only; polygons come from `TileEngine`.

## Rules

- There is one 20 m atlas and no grid switching.
- Clearing wipes the atlas, its XP totals, activity count, and Frontier state.
- Live GPS updates upsert **dirty tiles only** — never rewrite the whole atlas file.
- `TileStore.setDeferPersistence` batches dirty IDs until flush (pause / stop / background / timer).
- `TileStore(fileURL:)` / `AtlasDatabase.makeIsolated` accept a temporary SQLite URL for tests (`.json` suffixes remap to `.sqlite`).
- Write failures remain soft: in-memory state stays authoritative.
- First launch imports legacy Documents JSON once, then archives those files as `.bak`.

## See also

- [docs/architecture.md](../../../docs/architecture.md)
- [docs/domain.md](../../../docs/domain.md)
