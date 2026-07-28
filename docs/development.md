# Development

## Requirements

- Xcode 16+
- iOS 17+ deployment target
- Location permission (simulator or device)

## Run

1. Open `Atlasbound.xcodeproj`
2. Scheme: **Atlasbound**
3. Set Signing **Team** for physical devices (`DEVELOPMENT_TEAM` is empty in the project)
4. ⌘R → allow location → move to discover tiles automatically; pick an activity on the map sheet only when you want to track it.

Simulator / DEBUG Sim GPS: set `ATLASBOUND_ENABLE_SIM_GPS=true` in `.env`, run `python3 scripts/sync-env.py`, rebuild, then enable **Show Sim GPS controls** in Settings. The on-map pad stays hidden otherwise.

## Project layout conventions

| Path | Put here |
|------|----------|
| `Engines/` | Domain orchestration & pure math |
| `Models/` | Codable/Sendable domain types |
| `Persistence/` | File IO + persisted DTOs |
| `Map/` | MapKit views |
| `Views/` | Screens / sheets |
| `Theme/` | Colors, type helpers, appearance preference, glass button styles, motion tokens (`AtlasMotion`), haptics (`AtlasHaptics`) |

Xcode uses **PBXFileSystemSynchronizedRootGroup** — new files under `Atlasbound/` appear in the target automatically. Prefer not editing `project.pbxproj` membership by hand (`Info.plist` is a known exception).

## Coding conventions

- Session/store/recorder: `@MainActor` + `ObservableObject`
- Pure engines/models: `struct` + `Sendable`
- Domain logic in engines; views observe and call controller methods
- Persist IDs and mastery fields only — derive geometry
- Match existing naming: `tileID`, `masteryXP`, `sessionVisitedTileIDs`
- No third-party deps unless requested
- Appearance: `AppearancePreference` (`Auto` / `Light` / `Dark`) via `@AppStorage("appearance.preference")`; apply with `.preferredColorScheme` on the app root. Glass chrome/button styles live in `Theme/GlassChrome.swift`. Shared springs/easings live in `Theme/AtlasMotion.swift`; discrete haptics in `Theme/AtlasHaptics.swift`. Prefer those tokens over ad-hoc `Animation` literals, and honor `accessibilityReduceMotion` via `AtlasMotion.optional` / `withOptionalAnimation`.

## Tests

```bash
# Static: privacy alignment, apps.json, Python script tests
./scripts/validate-pr.sh

# Unit + chrome snapshots + UI smoke (simulator)
xcodebuild test \
  -project Atlasbound.xcodeproj \
  -scheme Atlasbound \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Test sources live outside the app sync group: `AtlasboundTests/`, `AtlasboundUITests/`. See [testing.md](testing.md).

## Local IPA

```bash
./scripts/build-ipa.sh
# → dist/Atlasbound-<version>.ipa
# → dist/ipa-metadata.env
```

Optional env: `SCHEME`, `CONFIGURATION`, `MARKETING_VERSION`, `BUILD_NUMBER`, `OUTPUT_DIR`.

## Privacy strings

Location usage copy lives in `Atlasbound/Info.plist`. Keep AltStore permission blurbs in `altstore/apps.json` aligned when you change wording (`scripts/check-privacy-alignment.py` / `./scripts/validate-pr.sh`).

## Git / versioning

Prefer conventional commits (`feat:`, `fix:`, …). Pushes to `main` trigger release versioning — see [release.md](release.md).
