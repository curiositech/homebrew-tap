#!/usr/bin/env python3
"""Fail-closed verifier for Port Daddy release-to-tap evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
RELEASE_TAG = re.compile(
    r"^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$"
)
ASSETS = (
    ("arm64", "pd-darwin-arm64.tar.gz", "pd-darwin-arm64-imprint.json"),
    ("linux", "pd-linux-x64.tar.gz", "pd-linux-x64-imprint.json"),
)


class EvidenceError(ValueError):
    """Release evidence is incomplete or contradictory."""


def sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def _reject(message: str) -> None:
    raise EvidenceError(f"Port Daddy release evidence rejected: {message}")


def verify_release_evidence(
    *,
    version: str,
    candidate_sha: str,
    expected_sha256: dict[str, str],
    assets_dir: Path,
) -> dict[str, str]:
    candidate_sha = candidate_sha.lower()
    if not RELEASE_TAG.fullmatch(version):
        _reject("version must be an exact stable v-prefixed release tag")
    if not FULL_SHA.fullmatch(candidate_sha):
        _reject("candidate SHA must be a full lowercase commit")

    result: dict[str, str] = {"version": version.removeprefix("v")}
    for output_name, archive_name, imprint_name in ASSETS:
        expected = expected_sha256.get(output_name, "").lower()
        if not SHA256.fullmatch(expected):
            _reject(f"payload {output_name} digest is invalid")

        archive_path = assets_dir / archive_name
        imprint_path = assets_dir / imprint_name
        if not archive_path.is_file() or not imprint_path.is_file():
            _reject(f"missing {archive_name} or {imprint_name}")
        try:
            imprint: dict[str, Any] = json.loads(imprint_path.read_text())
        except (json.JSONDecodeError, OSError) as error:
            _reject(f"cannot read {imprint_name}: {error}")

        if str(imprint.get("sourceCommit", "")).lower() != candidate_sha:
            _reject(f"{imprint_name} sourceCommit does not match candidate")
        if imprint.get("releaseVersion") != version:
            _reject(f"{imprint_name} releaseVersion does not match tag")
        if imprint.get("missingRequired") != []:
            _reject(f"{imprint_name} is incomplete")
        matches = [
            entry
            for entry in imprint.get("archives", [])
            if isinstance(entry, dict) and entry.get("name") == archive_name
        ]
        if len(matches) != 1:
            _reject(f"{imprint_name} must seal exactly one {archive_name}")

        actual_digest, actual_bytes = sha256_file(archive_path)
        sealed = matches[0]
        if sealed.get("sha256", "").lower() != actual_digest:
            _reject(f"{archive_name} bytes do not match its imprint digest")
        if sealed.get("bytes") != actual_bytes or actual_bytes <= 0:
            _reject(f"{archive_name} byte count does not match its imprint")
        if actual_digest != expected:
            _reject(f"{archive_name} digest does not match source dispatch")
        result[output_name] = actual_digest

    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--darwin-expected-sha256", required=True)
    parser.add_argument("--linux-expected-sha256", required=True)
    parser.add_argument("--assets-dir", type=Path, required=True)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()

    result = verify_release_evidence(
        version=args.version,
        candidate_sha=args.candidate_sha,
        expected_sha256={
            "arm64": args.darwin_expected_sha256,
            "linux": args.linux_expected_sha256,
        },
        assets_dir=args.assets_dir,
    )
    rendered = "".join(f"{key}={value}\n" for key, value in result.items())
    if args.github_output:
        with args.github_output.open("a") as output:
            output.write(rendered)
    else:
        print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as error:
        raise SystemExit(str(error)) from error
