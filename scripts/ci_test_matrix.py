#!/usr/bin/env python3
"""Discover XCTest cases and emit a balanced GitHub Actions matrix."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path


CLASS_PATTERN = re.compile(
    r"^\s*(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase\b"
)
TEST_PATTERN = re.compile(
    r"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*"
    r"func\s+(test[A-Za-z0-9_]*)\s*\("
)


@dataclass(frozen=True)
class TestClass:
    name: str
    methods: tuple[str, ...]


def discover_test_classes(source_root: Path) -> list[TestClass]:
    discovered: list[TestClass] = []
    candidate_method_count = 0

    for source in sorted(source_root.rglob("*.swift")):
        current_name: str | None = None
        current_methods: list[str] = []
        class_depth = 0

        for line in source.read_text(encoding="utf-8").splitlines():
            if TEST_PATTERN.match(line):
                candidate_method_count += 1

            if current_name is None:
                match = CLASS_PATTERN.match(line)
                if match:
                    current_name = match.group(1)
                    current_methods = []
                    class_depth = line.count("{") - line.count("}")
                continue

            method_match = TEST_PATTERN.match(line)
            if method_match:
                current_methods.append(method_match.group(1))

            class_depth += line.count("{") - line.count("}")
            if class_depth <= 0:
                if current_methods:
                    discovered.append(
                        TestClass(current_name, tuple(sorted(current_methods)))
                    )
                current_name = None
                current_methods = []

    discovered_method_count = sum(len(test_class.methods) for test_class in discovered)
    if discovered_method_count != candidate_method_count:
        raise ValueError(
            "Found test methods outside a directly declared XCTestCase class; "
            "update the matrix parser before using that declaration style"
        )

    return sorted(discovered, key=lambda test_class: test_class.name)


def test_items(
    target: str,
    classes: list[TestClass],
    granularity: str,
) -> list[tuple[str, int]]:
    if granularity == "class":
        return [
            (f"{target}/{test_class.name}", len(test_class.methods))
            for test_class in classes
        ]

    return [
        (f"{target}/{test_class.name}/{method}", 1)
        for test_class in classes
        for method in test_class.methods
    ]


def balanced_matrix(
    items: list[tuple[str, int]],
    requested_shards: int,
    label: str,
) -> dict[str, list[dict[str, str]]]:
    if not items:
        raise ValueError("No XCTest cases were discovered")
    if requested_shards < 1:
        raise ValueError("Shard count must be at least one")

    shard_count = min(requested_shards, len(items))
    shards: list[list[str]] = [[] for _ in range(shard_count)]
    weights = [0] * shard_count

    for identifier, weight in sorted(items, key=lambda item: (-item[1], item[0])):
        shard_index = min(range(shard_count), key=lambda index: (weights[index], index))
        shards[shard_index].append(identifier)
        weights[shard_index] += weight

    return {
        "include": [
            {
                "name": f"{label}-{index + 1}-of-{shard_count}",
                "only_testing": " ".join(sorted(identifiers)),
            }
            for index, identifiers in enumerate(shards)
        ]
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", type=Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--shards", type=int, required=True)
    parser.add_argument("--granularity", choices=("class", "method"), required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()

    classes = discover_test_classes(args.path)
    items = test_items(args.target, classes, args.granularity)
    print(
        json.dumps(
            balanced_matrix(items, args.shards, args.label),
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
