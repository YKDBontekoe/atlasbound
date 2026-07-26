#!/usr/bin/env python3
"""Compute the next semver from existing git tags (automatic versioning)."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys


SEMVER_RE = re.compile(
    r"^v?(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)$"
)


def git_tags() -> list[str]:
    result = subprocess.run(
        ["git", "tag", "--list", "v*"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def parse_semver(tag: str) -> tuple[int, int, int] | None:
    match = SEMVER_RE.match(tag)
    if not match:
        return None
    return int(match["major"]), int(match["minor"]), int(match["patch"])


def latest_semver(tags: list[str]) -> tuple[int, int, int]:
    parsed = [v for v in (parse_semver(t) for t in tags) if v is not None]
    if not parsed:
        return (0, 1, 0)
    return max(parsed)


def bump(version: tuple[int, int, int], kind: str) -> tuple[int, int, int]:
    major, minor, patch = version
    if kind == "major":
        return major + 1, 0, 0
    if kind == "minor":
        return major, minor + 1, 0
    if kind == "patch":
        return major, minor, patch + 1
    if kind == "none":
        return major, minor, patch
    raise SystemExit(f"unknown bump kind: {kind}")


def detect_bump_from_commits(base_ref: str) -> str:
    """Infer bump from conventional commit prefixes since base_ref (or all commits)."""
    args = ["git", "log", "--pretty=%s"]
    if base_ref:
        args.append(f"{base_ref}..HEAD")
    result = subprocess.run(args, check=False, capture_output=True, text=True)
    subjects = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    bump_kind = "patch"
    for subject in subjects:
        lower = subject.lower()
        if lower.startswith("breaking change") or "!" in subject.split(":")[0]:
            return "major"
        if lower.startswith("feat:") or lower.startswith("feat("):
            bump_kind = "minor"
    return bump_kind


def format_version(version: tuple[int, int, int]) -> str:
    return f"{version[0]}.{version[1]}.{version[2]}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bump",
        choices=("auto", "major", "minor", "patch", "none"),
        default="auto",
        help="How to bump from the latest tag (auto uses conventional commits)",
    )
    parser.add_argument(
        "--initial",
        default="0.1.0",
        help="Version to use when no tags exist and bump=none/first release",
    )
    parser.add_argument(
        "--github-output",
        action="store_true",
        help="Also write version/tag/previous to $GITHUB_OUTPUT",
    )
    args = parser.parse_args()

    tags = git_tags()
    previous = latest_semver(tags)
    has_tags = any(parse_semver(t) is not None for t in tags)

    if not has_tags:
        initial = parse_semver(args.initial)
        if initial is None:
            print(f"error: invalid --initial {args.initial}", file=sys.stderr)
            return 1
        next_version = initial
        bump_kind = "initial"
        previous_tag = ""
    else:
        previous_tag = f"v{format_version(previous)}"
        if args.bump == "auto":
            bump_kind = detect_bump_from_commits(previous_tag)
        else:
            bump_kind = args.bump
        # First release after initial tag should bump; "none" keeps previous (rebuild).
        if bump_kind == "none":
            next_version = previous
        else:
            next_version = bump(previous, bump_kind)

    version = format_version(next_version)
    tag = f"v{version}"

    print(f"previous={format_version(previous) if has_tags else ''}")
    print(f"bump={bump_kind}")
    print(f"version={version}")
    print(f"tag={tag}")

    if args.github_output:
        import os
        from pathlib import Path

        out = os.environ.get("GITHUB_OUTPUT")
        if not out:
            print("error: GITHUB_OUTPUT not set", file=sys.stderr)
            return 1
        with Path(out).open("a", encoding="utf-8") as fh:
            fh.write(f"previous={format_version(previous) if has_tags else ''}\n")
            fh.write(f"bump={bump_kind}\n")
            fh.write(f"version={version}\n")
            fh.write(f"tag={tag}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
