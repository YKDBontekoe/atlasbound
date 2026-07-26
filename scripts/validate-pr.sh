#!/usr/bin/env bash
# Static PR validation: privacy alignment, AltStore JSON, Python script tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Privacy / AltStore alignment"
python3 scripts/check-privacy-alignment.py

echo "==> Validate altstore/apps.json"
python3 -m json.tool altstore/apps.json > /dev/null

echo "==> Python script unit tests"
python3 -m unittest discover -s scripts/tests -v

echo "==> PR static validation passed"
