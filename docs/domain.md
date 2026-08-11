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

Thresholds live in `ProgressionEngine.advanceStateIfNeeded`. Surveying skills can soften effective thresholds without rewriting stored `masteryXP`.

## XP

| Kind | Rule |
|------|------|
| Discovery | First visit: **+100** XP (× Pathfinding skills); state → discovered |
| Familiarity | Revisits: **25, 20, 16, 12, 10**, then floor **5** (× Surveying / claim buffs) |

`familiarityXP(forVisitCount:)` uses visit count *before* the revisit (at least 1 after discovery).

Session totals: `SessionProgress` (discovered / revisited / XP splits). Lifetime totals live in `TileStore`.

## Explorer levels and rewards

Lifetime discovery + familiarity XP also feeds `ExplorerProgressionEngine`. This account-wide layer is derived from canonical progress, so existing saves gain the correct level and rewards without a migration.

- Levels are **uncapped**. L1–50 keep the classic curve `250 × (level - 1)² + 750 × (level - 1)`; beyond 50 the continuation is `xp(50) + 2000×(L−50) + 40×(L−50)²`.
- Rank titles advance from Wanderer through Atlas Legend; past level 50 titles become procedural epithets (`Atlas Legend · Ember Circlet I`, …).
- Each level grants Atlas Tokens; milestone levels unlock live-map presentation features, including visit heat and 3D terrain.
- Achievements are **tiered and infinite** (escalating targets per family); the Progress UI shows recent unlocked tiers plus the next locked tier.
- Atlas Tokens and unlocks are deterministic lifetime rewards, not consumable currency.

This system does not change the base per-tile mastery XP rules; skills multiply awards at visit time.

## Skill tree

`SkillTreeEngine` + `SkillStore` (`skill_state` blob) implement four infinite disciplines: **Pathfinding**, **Surveying**, **Cartography**, and **Artifice**.

- Skill Points earned = `explorerLevel − 1` (retroactive). Spent ranks persist; available = earned − spent.
- Each discipline has a fixed node graph; every node has infinite ranks with cost `1, 2, 3…` and diminishing-return bonuses.
- Derived `SkillModifiers` feed Progression, Idle Scouts, Field Finds, Territory claim buffs, Frontier combo window, and Factory speed / Insight thrift.
- Atlas Tokens remain non-consumable; Skill Points are the spendable progression currency.

## Exploration and activity types

`walk` | `run` | `cycle` | `hike` | `drive` | `publicTransport` | `unknown` — stamped on tiles (`activityStamps`).

Automatic Explore discovers without fitness history while the app is open. Screen-locked exploration is independently opt-in. Activity types are optional stamps and history metadata; every mode uses the same 20 m atlas.

## Session extras

- **Scout Circuit:** a local-day, derived challenge for discovering 5 new tiles, revisiting 3 known tiles, and visiting 12 unique tiles. It reads canonical visit timestamps and resets with the local day. Completing all three goals unlocks a once-per-day claimable material chest (no XP change from the goals themselves).
- **Idle Scouts / Home Camp:** with a Home Base set, a capped offline tick (max 8 h) drips camp materials and lets hired scouts permanently discover a tiny number of fogged tiles inside claimed sectors (Home first). Hiring each scout unlocks the next roster tier (Apprentice → … → Waykeeper). Daily AFK discoveries soft-cap at 18 (Pathfinding can raise toward an absolute 36). Persist roster + counters only — never geometry.
- **Frontier combo:** during an active expedition, consecutive qualifying frontier tiles within **20 minutes** (extendable via Pathfinding) build a combo multiplier on frontier scoring (see `FrontierEngine`).
- **Treasure trails:** three local-day landmark targets spanning hundreds of meters to multiple kilometers, with direct/detour choices. Farther destinations yield better relic rarity and completion XP. Completion grants a relic and weekly key.
- **Weekly vault:** three keys reveal a once-per-ISO-week destination several kilometers out with rare-or-better loot (further boosted by distance band).
- **Field finds:** deterministic tile pickups (`FieldFindEngine`) into `InventoryStore` — materials, boosts, charges; assemble / salvage / use / activate. Soft daily claim cap; claimed find IDs only (no geometry). Drop **rate** is boosted near Home/claims; drop **quality** improves with distance from Home Base (local → expedition bands).
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
- Factory research consumes Atlas Insight and is also gated by the existing Explorer level. Late tiers include Logistics III, Automation II, Power III, and Extraction III; Artifice skills provide infinite soft factory power beyond the fixed research catalog.
- Research bootstraps with a slower field-material Insight recipe; Mechanics unlocks the faster mechanism-based recipe.
- Nearby players can manually load or unload machine buffers, while connected depots automate transfers.
- Depot stock can be **remote-collected** into the backpack from Workshop → Factory without standing nearby.
- The factory has its own schema version inside SQLite so a factory reset or incompatibility cannot erase the canonical atlas.

## Living Atlas / Atlas Pulse

Atlas Pulse is a local-first living-world layer over the canonical 20 m atlas. Pulses are temporary, deterministic phenomena anchored to tile IDs: signal drift, fog fronts, and resource blooms currently refresh in six-hour local slots around the latest accepted player location. Each Pulse advances through detected, developing, peak, and resolved phases and can be resolved once at close range with an observe, stabilize, or harvest action. Rewards use existing inventory items; claim conditions and scout reports are additive and never remove atlas progress.

Pulse state persists as IDs, phases, dates, interactions, claim conditions, scout stance, and reports in the SQLite `pulse_state` blob. Geometry remains derived from `TileEngine`. The current client schedules optional local peak alerts only for Pulses already known to the device; server-authored refreshes, remote notifications, widgets, and Horizon aggregation remain extension points for the authenticated live-ops layer.

## Crewfront cards and crews

- A **blueprint** is permanent; a **card instance** is a crafted copy with three integrity states. Protected starter copies cannot be staked.
- Field Decks contain exactly 12 instances and at most two copies of one blueprint. They are validated by `CrewfrontBattleEngine` before an encounter begins.
- Guardian training uses a deterministic seven-hex board, six rounds, three energy per player, and a seeded tiebreaker. This same pure rules contract is the conformance target for future server-authoritative crew rooms.
- Crew territory is a separate seasonal overlay on the canonical personal atlas. It persists sector IDs only, never player geometry or exact locations.
