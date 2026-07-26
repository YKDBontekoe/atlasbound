---
name: altstore-release
description: >-
  Build unsigned IPAs, semver auto-versioning, and AltStore source updates for
  Atlasbound. Use when working on scripts/, GitHub Actions, altstore/apps.json,
  releases, version bumps, or distribution.
---

# AltStore release

## Local IPA

```bash
./scripts/build-ipa.sh
# → dist/Atlasbound-<version>.ipa
# → dist/ipa-metadata.env
```

Archive is **unsigned** (`CODE_SIGNING_ALLOWED=NO`) — required for AltStore re-sign.

## Version preview

```bash
python3 scripts/auto-version.py --bump auto
# auto | patch | minor | major | none
```

| Since last `v*` tag | Bump |
|---------------------|------|
| `feat:` | minor |
| `BREAKING` / `feat!:` | major |
| else | patch |
| no tags | `0.1.0` |

Build number in CI = Actions `run_number` (unique for AltStore updates).

## AltStore JSON

```bash
python3 scripts/generate-altstore-source.py \
  --ipa dist/Atlasbound-0.1.0.ipa \
  --download-url "…" \
  --version 0.1.0 \
  --build 1 \
  --notes "…" \
  --icon-url "https://ykdbontekoe.github.io/atlasbound/icon.png" \
  --website "https://github.com/YKDBontekoe/atlasbound" \
  --input altstore/apps.json \
  --output altstore/apps.json
```

Prepends newest version first. Public source:

```text
https://ykdbontekoe.github.io/atlasbound/apps.json
```

## Workflows

| Trigger | Workflow | Jobs | Publishes? |
|---------|----------|------|------------|
| PR | `build.yml` | `validate` (static) · `test` (unit/visual/UI) · `build` (IPA) | IPA artifact only |
| Push `main` / dispatch | `release.yml` | `validate` + `test` gate → IPA → Release + Pages | Yes |

```bash
./scripts/validate-pr.sh   # privacy alignment, apps.json, script unit tests
```

## Agent rules

- Prefer conventional commits — `main` auto-releases
- Keep permission blurbs in `altstore/apps.json` aligned with `Info.plist`
- Do not add App Store signing to CI unless product direction changes
- Do not force-push release tags

## See also

- [docs/release.md](../../../docs/release.md)
