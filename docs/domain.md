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
- Each level grants Atlas Tokens; milestone levels unlock live-map presentation features, including visit heat, satellite imagery, 3D terrain, and hybrid imagery.
- Achievements measure discovery, deep mastery, repeat visits, activity variety, active days, and Frontier expeditions.
- Atlas Tokens and unlocks are deterministic lifetime rewards, not consumable currency.

This system does not change per-tile mastery XP or discovery/revisit awards.

## Exploration and activity types

`walk` | `run` | `cycle` | `hike` | `drive` | `publicTransport` | `unknown` — stamped on tiles (`activityStamps`).

Automatic Explore discovers without fitness history while the app is open. Screen-locked exploration is independently opt-in. Activity types are optional stamps and history metadata; every mode uses the same 20 m atlas.

## Session extras

- **Frontier combo:** during an active expedition, consecutive qualifying frontier tiles within **20 minutes** build a combo multiplier on frontier scoring (see `FrontierEngine`).
- **Treasure trails:** three local-day landmark targets with direct/detour choices. Completion grants a relic and weekly key.
- **Weekly vault:** three keys reveal a once-per-ISO-week destination with rare-or-better loot.
- **Field finds:** deterministic tile pickups (`FieldFindEngine`) into `InventoryStore` — materials, boosts, charges; assemble / salvage / use / activate. Soft daily claim cap; claimed find IDs only (no geometry).
- **Nearby fog / undiscovered counts:** rings around user via `TileEngine.ring`.

## Activity history & territory stats

Finished sessions are persisted in `Documents/atlasbound-activities.json` (`ActivityHistoryStore`): distance, duration, activity type, XP totals, frontier bonuses, and rolling per-activity bests/totals (longest session distance, lifetime km, session counts). The Activity tab shows recent sessions; tap any row for a read-only detail sheet.

**Unlocked area** is derived at runtime — never stored. Per hex tile (flat-to-flat width `W` meters):

```
areaPerTile = (√3 / 2) × W²   // square meters
```

`StatsEngine.totalUnlockedArea` derives area from the single 20 m atlas. The Progress tab ("Atlas Stats") shows km² totals, personal records per activity, activity footprint from tile stamps, a layered exploration map, and **places visited** (countries / provinces / cities) when reverse-geocoded labels are available.

### Places visited

Discovered tile centers are quantized into ~2 km cache cells and reverse-geocoded via `CLGeocoder` (`GeocodeLimiter`). Results live in `Documents/atlasbound-regions.json` (`RegionLookupStore`) — placemark label strings only, never polygons. Aggregation is pure (`RegionLookupEngine` / `StatsEngine.placesVisited`). Empty placemark fields are omitted; unresolved cells do not block other stats.
