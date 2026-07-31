# Domain

## Hex tiles

- Flat-top axial hexes (`q`, `r`; `s = -q - r`).
- Flat-to-flat width: **20 m**.
- Projection: lat/lon → Web Mercator meters → axial.
- **ID:** `hex:{sizeMeters}:{q}:{r}` — size is part of identity so grids never collide.

Geometry is always derived from ID + size via `TileEngine`. Never store polygons.

### Route coverage

Between consecutive GPS samples, walk intermediate hexes with `hexLine` (`tileIDsCoveringRoute`). Point-sampling alone skips tiles at cycle/drive speeds.

## Tile states (mastery ladder)

| State | Typical gate |
|-------|----------------|
| `fogged` | Undiscovered |
| `discovered` | First visit (+100 XP) |
| `explored` | masteryXP ≥ 150 |
| `surveyed` | ≥ 200 |
| `mastered` | ≥ 300 |
| `legendary` | ≥ 500 |

Thresholds live in `ProgressionEngine.advanceStateIfNeeded`. These are intentionally simple; a skill tree can layer on top.

## XP

| Kind | Rule |
|------|------|
| Discovery | First visit: **+100** XP; state → discovered |
| Familiarity | Revisits: **25, 20, 16, 12, 10**, then floor **5** |

`familiarityXP(forVisitCount:)` uses visit count *before* the revisit (at least 1 after discovery).

Session totals: `SessionProgress` (discovered / revisited / XP splits). Lifetime totals live in `TileStore`.

## Explorer levels and rewards

Lifetime discovery + familiarity XP also feeds `ExplorerProgressionEngine`. This account-wide layer is derived from canonical progress, so existing saves gain the correct level and rewards without a migration.

- 50 levels use the cumulative curve `250 × (level - 1)² + 750 × (level - 1)`.
- Rank titles advance from Wanderer through Atlas Legend.
- Each level grants Atlas Tokens; milestone levels unlock live-map presentation features, including visit heat and 3D terrain.
- Achievements measure discovery, deep mastery, repeat visits, activity variety, active days, and Frontier expeditions.
- Atlas Tokens and unlocks are deterministic lifetime rewards, not consumable currency.

This system does not change per-tile mastery XP or discovery/revisit awards.

## Exploration and activity types

`walk` | `run` | `cycle` | `hike` | `drive` | `publicTransport` | `unknown` — stamped on tiles (`activityStamps`).

Automatic Explore discovers without fitness history while the app is open. Screen-locked exploration is independently opt-in. Activity types are optional stamps and history metadata; every mode uses the same 20 m atlas.

## Session extras

- **Scout Circuit:** a local-day, derived challenge for discovering 5 new tiles, revisiting 3 known tiles, and visiting 12 unique tiles. It reads canonical visit timestamps, resets automatically with the local day, and does not modify XP.
- **Frontier combo:** during an active expedition, consecutive qualifying frontier tiles within **20 minutes** build a combo multiplier on frontier scoring (see `FrontierEngine`).
- **Treasure trails:** three local-day landmark targets with direct/detour choices. Completion grants a relic and weekly key.
- **Weekly vault:** three keys reveal a once-per-ISO-week destination with rare-or-better loot.
- **Field finds:** deterministic tile pickups (`FieldFindEngine`) into `InventoryStore` — materials, boosts, charges; assemble / salvage / use / activate. Soft daily claim cap; claimed find IDs only (no geometry).
- **Home Base / territory claims:** claim neighborhood sectors (`HexSectorEngine` IDs) once discovery completion reaches 25% and you are inside or adjacent. First claim becomes Home Base; additional claims expand territory. Soft familiarity XP and field-find rate buffs apply inside claimed sectors (stronger at Home Base). Persist sector IDs only.
- **Nearby fog / undiscovered counts:** rings around user via `TileEngine.ring`.

## Activity history & territory stats

Finished sessions are persisted in SQLite (`ActivityHistoryStore`): distance, duration, activity type, XP totals, frontier bonuses, and rolling per-activity bests/totals (longest session distance, lifetime km, session counts). The Activity tab shows recent sessions; tap any row for a read-only detail sheet.

**Unlocked area** is derived at runtime — never stored. Per hex tile (flat-to-flat width `W` meters):

```
areaPerTile = (√3 / 2) × W²   // square meters
```

`StatsEngine.totalUnlockedArea` derives area from the single 20 m atlas. The Progress tab ("Atlas Stats") shows km² totals, personal records per activity, activity footprint from tile stamps, a layered exploration map, and **places visited** (countries / provinces / cities) when reverse-geocoded labels are available.

### Places visited

Discovered tile centers are quantized into ~2 km cache cells and reverse-geocoded via `CLGeocoder` (`GeocodeLimiter`). Results live in SQLite (`RegionLookupStore`) — placemark label strings only, never polygons. Aggregation is pure (`RegionLookupEngine` / `StatsEngine.placesVisited`). Empty placemark fields are omitted; unresolved cells do not block other stats.

## Real-world factory

- Structures and roads occupy one canonical 20 m hex and persist only their tile ID and mutable state.
- Construction requires a recent accepted location on the target or an adjacent discovered tile.
- Deposits are deterministically derived from `StableHash(tileID)` and become visible at `explored`.
- Road components, shortest paths, throughput, power balance, and deposit geometry are derived rather than persisted.
- Production advances in deterministic one-minute steps with at most eight hours of offline progress.
- Factory research consumes Atlas Insight and is also gated by the existing Explorer level.
- Research bootstraps with a slower field-material Insight recipe; Mechanics unlocks the faster mechanism-based recipe.
- Nearby players can manually load or unload machine buffers, while connected depots automate transfers.
- The factory has its own schema version inside SQLite so a factory reset or incompatibility cannot erase the canonical atlas.
