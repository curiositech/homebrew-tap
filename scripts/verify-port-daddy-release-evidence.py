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
MIN_ATTESTED_VERSION = (3, 30, 3)


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


def load_json_document(path: Path, label: str) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError) as error:
        _reject(f"cannot read {label}: {error}")
    if not isinstance(document, dict):
        _reject(f"{label} must be a JSON object")
    return document


def parse_release_feed(document: dict[str, Any]) -> dict[str, str]:
    version = document.get("tag")
    if not isinstance(version, str) or not RELEASE_TAG.fullmatch(version):
        _reject("latest release feed must contain an exact stable tag")

    artifacts = document.get("artifacts")
    if not isinstance(artifacts, list):
        _reject("latest release feed artifacts must be an array")

    result = {"tag": version}
    for output_name, archive_name, _ in ASSETS:
        matches = [
            artifact
            for artifact in artifacts
            if isinstance(artifact, dict) and artifact.get("filename") == archive_name
        ]
        if len(matches) != 1:
            _reject(f"latest release feed must contain exactly one {archive_name}")
        digest = matches[0].get("sha256")
        if not isinstance(digest, str) or not SHA256.fullmatch(digest):
            _reject(f"latest release feed {archive_name} digest is invalid")
        result[output_name] = digest
    return result


def parse_git_ref(document: dict[str, Any]) -> dict[str, str]:
    git_object = document.get("object")
    if not isinstance(git_object, dict):
        _reject("release tag ref is missing its Git object")
    object_type = git_object.get("type")
    object_sha = git_object.get("sha")
    if object_type not in {"commit", "tag"}:
        _reject(f"release tag resolved to unsupported Git object type {object_type}")
    if not isinstance(object_sha, str) or not FULL_SHA.fullmatch(object_sha):
        _reject("release tag ref contains an invalid Git object SHA")
    return {"type": object_type, "sha": object_sha}


def parse_annotated_tag(document: dict[str, Any]) -> str:
    git_object = document.get("object")
    if not isinstance(git_object, dict) or git_object.get("type") != "commit":
        _reject("annotated release tag must peel directly to a commit")
    object_sha = git_object.get("sha")
    if not isinstance(object_sha, str) or not FULL_SHA.fullmatch(object_sha):
        _reject("annotated release tag contains an invalid commit SHA")
    return object_sha


def requires_provenance(version: str) -> bool:
    if not RELEASE_TAG.fullmatch(version):
        _reject("provenance boundary requires an exact stable release tag")
    parsed = tuple(int(part) for part in version.removeprefix("v").split("."))
    return parsed >= MIN_ATTESTED_VERSION


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
        imprint = load_json_document(imprint_path, imprint_name)

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
    inspection = parser.add_mutually_exclusive_group()
    inspection.add_argument("--inspect-release-feed", type=Path)
    inspection.add_argument("--inspect-git-ref", type=Path)
    inspection.add_argument("--inspect-annotated-tag", type=Path)
    inspection.add_argument("--requires-provenance")
    parser.add_argument("--version")
    parser.add_argument("--candidate-sha")
    parser.add_argument("--darwin-expected-sha256")
    parser.add_argument("--linux-expected-sha256")
    parser.add_argument("--assets-dir", type=Path)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()

    if args.inspect_release_feed:
        print(json.dumps(parse_release_feed(
            load_json_document(args.inspect_release_feed, "latest release feed")
        ), sort_keys=True))
        return 0
    if args.inspect_git_ref:
        print(json.dumps(parse_git_ref(
            load_json_document(args.inspect_git_ref, "release tag ref")
        ), sort_keys=True))
        return 0
    if args.inspect_annotated_tag:
        print(parse_annotated_tag(
            load_json_document(args.inspect_annotated_tag, "annotated release tag")
        ))
        return 0
    if args.requires_provenance:
        return 0 if requires_provenance(args.requires_provenance) else 1

    required = {
        "--version": args.version,
        "--candidate-sha": args.candidate_sha,
        "--darwin-expected-sha256": args.darwin_expected_sha256,
        "--linux-expected-sha256": args.linux_expected_sha256,
        "--assets-dir": args.assets_dir,
    }
    missing = [flag for flag, value in required.items() if value is None]
    if missing:
        parser.error(f"the following arguments are required: {', '.join(missing)}")

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
