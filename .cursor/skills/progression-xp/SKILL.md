---
name: progression-xp
description: >-
  Atlasbound discovery and familiarity XP, mastery ladder, and visit processing.
  Use when editing ProgressionEngine, WorldTile state, SessionProgress, XP totals,
  or mastery thresholds.
---

# Progression XP

## Rules

| Event | XP | State effect |
|-------|-----|----------------|
| First visit (`fogged` / no `firstVisitedAt`) | **100** | → `discovered` |
| Revisit | **25, 20, 16, 12, 10**, then **5** | Advance mastery by thresholds |

Familiarity table index uses visit count **before** the revisit (`familiarityXP(forVisitCount:)`).

## Mastery thresholds (`masteryXP`)

| XP | State |
|----|-------|
| ≥ 150 | explored |
| ≥ 200 | surveyed |
| ≥ 300 | mastered |
| ≥ 500 | legendary |

Only advance forward; discovery sets discovered without jumping the ladder.

## API (`Engines/ProgressionEngine.swift`)

- `processVisit(tile:at:activity:modifiers:)` → `VisitResult`
- `processVisits(tileIDs:tiles:tileEngine:…modifiers:)` → `SessionProgress`
- `applyMasteryPulse(tile:amount:modifiers:)` for Survey Beacon / tools
- Stamp `activity` into `activityStamps` every visit
- Optional `SkillModifiers` multiply discovery/familiarity XP and soften mastery thresholds

## Skill tree

- `SkillTreeEngine` + `SkillStore` — Pathfinding / Surveying / Cartography / Artifice
- Skill Points = explorer level − 1; infinite node ranks with diminishing bonuses
- Wire modifiers through `WorldController` / `FactoryController`; engines stay pure

## Integration

- Live session mutates **session-local** tiles in `WorldController`, then merges via `TileStore` on stop.
- Lifetime totals: `discoveryXPTotal` / `familiarityXPTotal` for the single atlas.
- Explorer levels are uncapped; classic L1–50 curve preserved.

## Do not

- Wire streak multiplier into XP until product asks (UI-only today: `streakMultiplier`)
- Make Atlas Tokens spendable (Skill Points are the spendable currency)
- Award discovery twice for the same tile ID

## See also

- [docs/domain.md](../../../docs/domain.md)
- [hex-tiles](../hex-tiles/SKILL.md)
