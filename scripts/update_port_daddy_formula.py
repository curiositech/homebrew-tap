#!/usr/bin/env python3
"""Update Port Daddy release fields without erasing same-version revisions."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re


STABLE_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
SHA256 = re.compile(r"[0-9a-f]{64}")
VERSION_LINE = re.compile(
    r'(?m)^(?P<prefix>[ \t]*version[ \t]+")(?P<value>[^"]+)(?P<suffix>"[^\n]*)$'
)
REVISION_LINE = re.compile(r"(?m)^[ \t]*revision[ \t]+[0-9]+[ \t]*\n?")
SHA_LINE = re.compile(
    r'(?m)^(?P<prefix>[ \t]*sha256[ \t]+")(?P<value>[0-9a-fA-F]+|PLACEHOLDER_[A-Z0-9_]+)(?P<suffix>"[^\n]*)$'
)


class FormulaUpdateError(ValueError):
    """The formula shape or requested release fields are unsafe to update."""


def _require_fullmatch(pattern: re.Pattern[str], value: str, label: str) -> None:
    if pattern.fullmatch(value) is None:
        raise FormulaUpdateError(f"{label} has invalid format: {value!r}")


def update_formula_text(
    source: str,
    *,
    version: str,
    arm64_sha256: str,
    linux_sha256: str,
) -> str:
    """Return a fail-closed formula update for one stable release."""

    _require_fullmatch(STABLE_VERSION, version, "version")
    _require_fullmatch(SHA256, arm64_sha256, "arm64 sha256")
    _require_fullmatch(SHA256, linux_sha256, "linux sha256")

    version_matches = list(VERSION_LINE.finditer(source))
    if len(version_matches) != 1:
        raise FormulaUpdateError(
            f"expected exactly one formula version line, found {len(version_matches)}"
        )
    revision_matches = list(REVISION_LINE.finditer(source))
    if len(revision_matches) > 1:
        raise FormulaUpdateError(
            f"expected at most one formula revision line, found {len(revision_matches)}"
        )

    current_version = version_matches[0].group("value")
    updated = VERSION_LINE.sub(
        lambda match: f'{match.group("prefix")}{version}{match.group("suffix")}',
        source,
        count=1,
    )
    # Homebrew revisions belong to one upstream version. Preserve a hotfix when
    # self-discovery sees that same release again; clear it only for a new one.
    if current_version != version:
        updated = REVISION_LINE.sub("", updated, count=1)

    sha_matches = list(SHA_LINE.finditer(updated))
    if len(sha_matches) != 2:
        raise FormulaUpdateError(
            f"expected exactly two formula sha256 lines, found {len(sha_matches)}"
        )
    replacements = iter((arm64_sha256, linux_sha256))
    updated = SHA_LINE.sub(
        lambda match: f'{match.group("prefix")}{next(replacements)}{match.group("suffix")}',
        updated,
    )
    return updated


def update_formula_file(
    path: Path,
    *,
    version: str,
    arm64_sha256: str,
    linux_sha256: str,
) -> None:
    """Atomically update a formula after all structural checks pass."""

    source = path.read_text(encoding="utf-8")
    updated = update_formula_text(
        source,
        version=version,
        arm64_sha256=arm64_sha256,
        linux_sha256=linux_sha256,
    )
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(updated, encoding="utf-8")
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--formula", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--arm64-sha256", required=True)
    parser.add_argument("--linux-sha256", required=True)
    args = parser.parse_args()
    update_formula_file(
        args.formula,
        version=args.version,
        arm64_sha256=args.arm64_sha256,
        linux_sha256=args.linux_sha256,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
