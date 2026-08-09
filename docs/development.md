# Development

## Requirements

- Xcode 16+
- iOS 17+ deployment target
- Location permission (simulator or device)

## Supabase

The app uses the `atlasbound` Supabase project (`ezxelewutisuyxniozfh`). Database schema changes are committed as ordered SQL files in `supabase/migrations/`.

For local migration work, install the Supabase CLI and Docker, then run:

```bash
supabase start
supabase db reset
find supabase/migrations -maxdepth 1 -type f -name '*.sql' -print | sort
```

The iOS app receives the project publishable key through the `SUPABASE_PUBLISHABLE_KEY` Xcode build setting. The Debug and Release configurations resolve their values from local, ignored xcconfig files (or equivalent build-environment values):

```xcconfig
// Atlasbound/Config/Debug.local.xcconfig
SUPABASE_DEBUG_PUBLISHABLE_KEY = <debug publishable key>

// Atlasbound/Config/Release.local.xcconfig
SUPABASE_RELEASE_PUBLISHABLE_KEY = <release publishable key>
```

Mapbox uses the same pattern for its restricted public runtime token:

```xcconfig
MAPBOX_PUBLIC_ACCESS_TOKEN = pk...
# Only set true for a Mapbox account/token explicitly eligible for permanent geocoding.
MAPBOX_GEOCODING_PERMANENT = false
```

The Supabase `spawn-shared-treasure` Edge Function uses the same `MAPBOX_PUBLIC_ACCESS_TOKEN` through its Supabase secret environment. The token is public by design; do not use a Mapbox Downloads credential here.

Publishable keys are safe to ship with the app; service-role/database credentials must never be included in the app.

GitHub Actions requires these encrypted secrets for the production migration job:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_ID` (`ezxelewutisuyxniozfh`)
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_RELEASE_PUBLISHABLE_KEY`
- `MAPBOX_PUBLIC_ACCESS_TOKEN`
- `MAPBOX_DOWNLOADS_TOKEN` (Mapbox Downloads:READ token for binary SDK packages)

Pull requests replay all migrations against a local Supabase instance. Pushes to `main` preview and apply pending migrations to the linked production project before the IPA/AltStore publish job runs.

In the Supabase Dashboard, enable email OTP/magic-link auth and add `atlasbound://auth/callback` to the Auth URL configuration. The release workflow also deploys `supabase/functions/delete-account`, which uses the service role only inside Supabase to permanently remove an authenticated user; never put that key in Xcode or GitHub repository variables.

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
| `Map/` | Mapbox map views |
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
