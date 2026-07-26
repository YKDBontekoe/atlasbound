# Development

## Requirements

- Xcode 16+
- iOS 17+ deployment target
- Location permission (simulator or device)

## Run

1. Open `Atlasbound.xcodeproj`
2. Scheme: **Atlasbound**
3. Set Signing **Team** for physical devices (`DEVELOPMENT_TEAM` is empty in the project)
4. ⌘R → allow location → pick an activity on the map sheet → **Start …**

Simulator / DEBUG Sim GPS: set `ATLASBOUND_ENABLE_SIM_GPS=true` in `.env`, run `python3 scripts/sync-env.py`, rebuild, then enable **Show Sim GPS controls** in Settings. The on-map pad stays hidden otherwise.

## Project layout conventions

| Path | Put here |
|------|----------|
| `Engines/` | Domain orchestration & pure math |
| `Models/` | Codable/Sendable domain types |
| `Persistence/` | File IO + persisted DTOs |
| `Map/` | MapKit views |
| `Views/` | Screens / sheets |
| `Theme/` | Colors, type helpers |

Xcode uses **PBXFileSystemSynchronizedRootGroup** — new files under `Atlasbound/` appear in the target automatically. Prefer not editing `project.pbxproj` membership by hand (`Info.plist` is a known exception).

## Coding conventions

- Session/store/recorder: `@MainActor` + `ObservableObject`
- Pure engines/models: `struct` + `Sendable`
- Domain logic in engines; views observe and call controller methods
- Persist IDs and mastery fields only — derive geometry
- Match existing naming: `tileID`, `masteryXP`, `sessionVisitedTileIDs`
- No third-party deps unless requested

## Local IPA

```bash
./scripts/build-ipa.sh
# → dist/Atlasbound-<version>.ipa
# → dist/ipa-metadata.env
```

Optional env: `SCHEME`, `CONFIGURATION`, `MARKETING_VERSION`, `BUILD_NUMBER`, `OUTPUT_DIR`.

## Privacy strings

Location usage copy lives in `Atlasbound/Info.plist`. Keep AltStore permission blurbs in `altstore/apps.json` aligned when you change wording.

## Git / versioning

Prefer conventional commits (`feat:`, `fix:`, …). Pushes to `main` trigger release versioning — see [release.md](release.md).
