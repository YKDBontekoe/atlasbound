# Release (AltStore / SideStore)

Unsigned IPA distribution. AltStore/SideStore re-signs with the user’s Apple ID.

## Source URL

```text
https://ykdbontekoe.github.io/atlasbound/apps.json
```

## What ships on `main`

Workflow: `.github/workflows/release.yml`

1. `scripts/auto-version.py` → next marketing version from latest `v*` tag
2. Build number = Actions `run_number` (always unique)
3. Unsigned archive via `scripts/build-ipa.sh`
4. GitHub Release + `v*` tag + `Atlasbound-<version>+<build>.ipa`
5. `scripts/generate-altstore-source.py` prepends version to `altstore/apps.json`
6. Deploy `apps.json` + `icon.png` to GitHub Pages

PR workflow (`.github/workflows/build.yml`) builds IPA artifact only — no publish.

## Semver bump rules

| Commits since last `v*` tag | Marketing bump |
|-----------------------------|----------------|
| `feat:` | minor |
| `BREAKING CHANGE` / `feat!:` | major |
| everything else | patch |
| no tags yet | `0.1.0` |

Override: Actions → **Build IPA & AltStore Source** → `auto` / `patch` / `minor` / `major` / `none`.

Preview locally:

```bash
python3 scripts/auto-version.py --bump auto
```

## Local IPA

```bash
./scripts/build-ipa.sh
```

## Gotchas

- Pushing to `main` always attempts a release — choose commit prefixes intentionally.
- Duplicate tag guard skips publish if the tag already exists.
- `bump=none` rebuilds the same marketing version; build number still unique.
- Keep `altstore/apps.json` permission text in sync with `Info.plist` usage strings.
- CI IPAs are **unsigned** by design; device debug builds need a local Team in Xcode.
