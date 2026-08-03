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
- Flat-to-flat width = 20 m
- ID: `hex:20:{q}:{r}` via `TileEngine.makeTileID`
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

## Canonical atlas

Production tile IDs use `hex:20:{q}:{r}`. There is no runtime grid switching.

## When adding map visuals

- Geometry from engine only
- Style via `TileMapMaterial` + `MapTileLOD` (near dual-rim silhouette, mid single stroke, far perimeter outline)
- Cap mastery markers with LOD (`maxVisibleMarkers` = 40 near; mastered+ only at mid; none at far)
- Fog wash uses nearby fogged ring tiles from `WorldController.nearbyFogTiles` (LOD tightens fog cap)

## See also

- [docs/domain.md](../../../docs/domain.md)
- [progression-xp](../progression-xp/SKILL.md) for visit awards on those IDs
