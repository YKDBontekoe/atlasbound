# Domain

## Hex tiles

- Flat-top axial hexes (`q`, `r`; `s = -q - r`).
- Flat-to-flat width: **60 / 80 (default) / 100** m (`TileSizeOption`).
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

Thresholds live in `ProgressionEngine.advanceStateIfNeeded` — Phase 1 lightweight; full skill tree later.

## XP

| Kind | Rule |
|------|------|
| Discovery | First visit: **+100** XP; state → discovered |
| Familiarity | Revisits: **25, 20, 16, 12, 10**, then floor **5** |

`familiarityXP(forVisitCount:)` uses visit count *before* the revisit (at least 1 after discovery).

Session totals: `SessionProgress` (discovered / revisited / XP splits). Lifetime totals: `TileStore` per tile-size grid.

## Activity types

`walk` | `run` | `cycle` | `drive` | `unknown` — stamped on tiles (`activityStamps`).

## Session extras (UI / soft)

- **Discovery streak:** counts new tiles; expires **20 minutes** after last discovery; multiplier shown in UI but **not** applied to XP yet.
- **Nearby fog / undiscovered counts:** rings around user via `TileEngine.ring`.

## Multi-size progress

`TileStore` keeps `allTilesBySize` and `progressBySize`. Changing size mid-record is blocked. Switching size loads another grid. Clearing progress clears only the **current** size.
