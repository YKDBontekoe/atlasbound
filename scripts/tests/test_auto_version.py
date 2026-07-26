#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


def load_auto_version():
    path = Path(__file__).resolve().parents[1] / "auto-version.py"
    spec = importlib.util.spec_from_file_location("auto_version", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


AV = load_auto_version()


class AutoVersionTests(unittest.TestCase):
    def test_parse_semver(self):
        self.assertEqual(AV.parse_semver("v1.2.3"), (1, 2, 3))
        self.assertEqual(AV.parse_semver("0.1.0"), (0, 1, 0))
        self.assertIsNone(AV.parse_semver("v1.2"))
        self.assertIsNone(AV.parse_semver("release-1"))

    def test_bump_kinds(self):
        self.assertEqual(AV.bump((1, 2, 3), "patch"), (1, 2, 4))
        self.assertEqual(AV.bump((1, 2, 3), "minor"), (1, 3, 0))
        self.assertEqual(AV.bump((1, 2, 3), "major"), (2, 0, 0))
        self.assertEqual(AV.bump((1, 2, 3), "none"), (1, 2, 3))

    def test_feat_is_minor(self):
        self.assertEqual(
            AV.bump_kind_from_subjects(["docs: tweak", "feat: add hex line"]),
            "minor",
        )
        self.assertEqual(
            AV.bump_kind_from_subjects(["feat(map): fog wash"]),
            "minor",
        )

    def test_breaking_is_major(self):
        self.assertEqual(
            AV.bump_kind_from_subjects(["feat!: redesign ids", "feat: ignored"]),
            "major",
        )
        self.assertEqual(
            AV.bump_kind_from_subjects(["BREAKING CHANGE: wipe saves"]),
            "major",
        )

    def test_default_is_patch(self):
        self.assertEqual(
            AV.bump_kind_from_subjects(["fix: gps filter", "chore: ci"]),
            "patch",
        )

    def test_latest_semver(self):
        self.assertEqual(AV.latest_semver(["v0.1.0", "v0.2.1", "v0.2.0"]), (0, 2, 1))
        self.assertEqual(AV.latest_semver([]), (0, 1, 0))


if __name__ == "__main__":
    unittest.main()
