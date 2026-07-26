#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


def load_module():
    path = Path(__file__).resolve().parents[1] / "generate-altstore-source.py"
    spec = importlib.util.spec_from_file_location("generate_altstore_source", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GAS = load_module()


class GenerateAltStoreSourceTests(unittest.TestCase):
    def test_upsert_prepends_newest_first(self):
        source = {
            "apps": [
                {
                    "versions": [
                        {"version": "0.1.0", "buildVersion": "1"},
                    ]
                }
            ]
        }
        GAS.upsert_version(
            source,
            {"version": "0.2.0", "buildVersion": "2", "downloadURL": "https://example/a.ipa"},
        )
        versions = source["apps"][0]["versions"]
        self.assertEqual(len(versions), 2)
        self.assertEqual(versions[0]["version"], "0.2.0")
        self.assertEqual(versions[0]["buildVersion"], "2")
        self.assertEqual(versions[1]["version"], "0.1.0")

    def test_upsert_replaces_same_version_build(self):
        source = {
            "apps": [
                {
                    "versions": [
                        {"version": "0.1.0", "buildVersion": "3", "notes": "old"},
                    ]
                }
            ]
        }
        GAS.upsert_version(
            source,
            {"version": "0.1.0", "buildVersion": "3", "notes": "new"},
        )
        versions = source["apps"][0]["versions"]
        self.assertEqual(len(versions), 1)
        self.assertEqual(versions[0]["notes"], "new")

    def test_cli_writes_valid_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ipa = root / "Atlasbound-0.1.0.ipa"
            ipa.write_bytes(b"fake-ipa-bytes")
            out = root / "apps.json"
            template = {
                "name": "Atlasbound",
                "apps": [
                    {
                        "name": "Atlasbound",
                        "bundleIdentifier": "com.atlasbound.app",
                        "versions": [],
                        "appPermissions": {"entitlements": [], "privacy": []},
                    }
                ],
            }
            input_path = root / "input.json"
            input_path.write_text(json.dumps(template), encoding="utf-8")

            import sys

            argv = sys.argv
            try:
                sys.argv = [
                    "generate-altstore-source.py",
                    "--ipa",
                    str(ipa),
                    "--download-url",
                    "https://example.com/app.ipa",
                    "--version",
                    "0.1.0",
                    "--build",
                    "9",
                    "--notes",
                    "test",
                    "--input",
                    str(input_path),
                    "--output",
                    str(out),
                ]
                self.assertEqual(GAS.main(), 0)
            finally:
                sys.argv = argv

            data = json.loads(out.read_text(encoding="utf-8"))
            versions = data["apps"][0]["versions"]
            self.assertEqual(versions[0]["version"], "0.1.0")
            self.assertEqual(versions[0]["buildVersion"], "9")
            self.assertEqual(versions[0]["size"], len(b"fake-ipa-bytes"))
            self.assertTrue(versions[0]["sha256"])


if __name__ == "__main__":
    unittest.main()
