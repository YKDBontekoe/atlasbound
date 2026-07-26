---
name: hex-tiles
description: >-
  Work with Atlasbound hex tile math: TileEngine, axial coordinates, tile IDs,
  polygons, hexLine route coverage, and rings. Use when editing TileEngine,
  DiscoveryMapView overlays, tile ID format, or GPS-to-hex conversion.
---

# Hex tiles

## Invariants

- Flat-top axial (`q`, `r`); `s = -q - r`
- Flat-to-flat width = `tileSizeMeters` (60 / 80 / 100)
- ID: `hex:{sizeMeters}:{q}:{r}` via `TileEngine.makeTileID`
- **Never persist polygons** — derive with `polygon(for:)` / `polygon(forID:)`

## API map (`Engines/TileEngine.swift`)

| Method | Use |
|--------|-----|
| `tileID(for:)` | Single coordinate → ID |
| `axialCoordinate(for:)` | Lat/lon → axial |
| `tileIDs(along:)` | Samples without gap fill |
| `tileIDsCoveringRoute(_:)` | Samples **with** `hexLine` (preferred for recording) |
| `polygon(for:)` | MapKit overlay vertices |
| `ring(around:radius:)` | Nearby fog / counts |
| `parseTileID` / `makeTileID` | ID ↔ axial |

## Route coverage rule

For live recording and session finalize, prefer **`tileIDsCoveringRoute`**. Point-only IDs skip hexes at cycle/drive speed.

## Multi-size

Changing meters changes the ID namespace. Do not strip size from IDs. Progress grids are isolated in `TileStore`.

## When adding map visuals

- Geometry from engine only
- Cap expensive annotations if adding markers (existing ~80 cap pattern)
- Fog wash uses nearby fogged ring tiles from `WorldController.nearbyFogTiles`

## See also

- [docs/domain.md](../../../docs/domain.md)
- [progression-xp](../progression-xp/SKILL.md) for visit awards on those IDs
