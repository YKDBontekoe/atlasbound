# Snapshot reference PNGs

Golden images for visual regression tests in `AtlasboundTests/Visual/`.

Expected files (record on macOS):

- `ActivitySummaryView.png`
- `ActivityTypeRow-selected.png`
- `ActivityTypeRow-unselected.png`

```bash
RECORD_SNAPSHOTS=1 ./scripts/ci-run-tests.sh \
  -only-testing:AtlasboundTests/ActivitySummarySnapshotTests \
  -only-testing:AtlasboundTests/ActivityTypeRowSnapshotTests
```

CI bootstraps missing references once per run and uploads them as workflow artifacts. Commit PNGs here after intentional UI chrome changes.
