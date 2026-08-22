import hashlib
import json
import tempfile
import unittest
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "verify-port-daddy-release-evidence.py"
WORKFLOW = (Path(__file__).parents[1] / ".github/workflows/update-formula.yml").read_text()
SPEC = spec_from_file_location("release_evidence", SCRIPT)
release_evidence = module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(release_evidence)


class ReleaseEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.assets = Path(self.temp.name)
        self.version = "v3.28.0"
        self.candidate_sha = "a" * 40
        self.expected = {}
        for index, (output_name, archive_name, imprint_name) in enumerate(
            release_evidence.ASSETS, start=1
        ):
            data = f"archive-{index}".encode()
            digest = hashlib.sha256(data).hexdigest()
            (self.assets / archive_name).write_bytes(data)
            (self.assets / imprint_name).write_text(json.dumps({
                "sourceCommit": self.candidate_sha,
                "releaseVersion": self.version,
                "missingRequired": [],
                "archives": [{
                    "name": archive_name,
                    "bytes": len(data),
                    "sha256": digest,
                }],
            }))
            self.expected[output_name] = digest

    def tearDown(self):
        self.temp.cleanup()

    def verify(self):
        return release_evidence.verify_release_evidence(
            version=self.version,
            candidate_sha=self.candidate_sha,
            expected_sha256=self.expected,
            assets_dir=self.assets,
        )

    def test_accepts_bytes_bound_to_candidate_tag_and_payload(self):
        self.assertEqual(self.verify(), {
            "version": "3.28.0",
            "arm64": self.expected["arm64"],
            "linux": self.expected["linux"],
        })

    def test_rejects_candidate_mismatch(self):
        path = self.assets / "pd-darwin-arm64-imprint.json"
        imprint = json.loads(path.read_text())
        imprint["sourceCommit"] = "b" * 40
        path.write_text(json.dumps(imprint))
        with self.assertRaisesRegex(release_evidence.EvidenceError, "sourceCommit"):
            self.verify()

    def test_rejects_archive_tampering(self):
        (self.assets / "pd-linux-x64.tar.gz").write_bytes(b"tampered")
        with self.assertRaisesRegex(release_evidence.EvidenceError, "imprint digest"):
            self.verify()

    def test_rejects_dispatch_digest_mismatch(self):
        self.expected["arm64"] = "f" * 64
        with self.assertRaisesRegex(release_evidence.EvidenceError, "source dispatch"):
            self.verify()

    def test_rejects_incomplete_imprint(self):
        path = self.assets / "pd-linux-x64-imprint.json"
        imprint = json.loads(path.read_text())
        imprint["missingRequired"] = ["daemon"]
        path.write_text(json.dumps(imprint))
        with self.assertRaisesRegex(release_evidence.EvidenceError, "incomplete"):
            self.verify()

    def test_rejects_prerelease_tags(self):
        self.version = "v3.28.0-rc.1"
        with self.assertRaisesRegex(release_evidence.EvidenceError, "exact stable"):
            self.verify()

    def test_workflow_requires_and_verifies_every_dispatch_field(self):
        self.assertIn("github.event.client_payload.candidate_sha", WORKFLOW)
        self.assertIn("github.event.client_payload.darwin_archive_sha256", WORKFLOW)
        self.assertIn("github.event.client_payload.linux_archive_sha256", WORKFLOW)
        self.assertIn("python3 scripts/verify-port-daddy-release-evidence.py", WORKFLOW)
        self.assertIn("--github-output \"$GITHUB_OUTPUT\"", WORKFLOW)

    def test_workflow_self_discovers_stable_release_without_cross_repo_credentials(self):
        self.assertIn("schedule:", WORKFLOW)
        self.assertIn("workflow_dispatch:", WORKFLOW)
        self.assertIn("releases/latest/download/latest.json", WORKFLOW)
        self.assertIn("pd-darwin-arm64-imprint.json", WORKFLOW)
        self.assertIn("PAYLOAD_CANDIDATE_SHA=", WORKFLOW)
        self.assertIn("git/ref/tags/${PAYLOAD_VERSION}", WORKFLOW)
        self.assertIn("git/tags/${TAG_OBJECT_SHA}", WORKFLOW)
        self.assertIn("TAG_OBJECT_TYPE", WORKFLOW)
        self.assertIn("jq -er", WORKFLOW)
        self.assertIn("--retry-all-errors", WORKFLOW)
        self.assertIn("--max-time 30", WORKFLOW)
        self.assertIn("group: port-daddy-formula-update", WORKFLOW)
        self.assertNotIn("secrets.", WORKFLOW)

    def test_workflow_requires_signed_provenance_for_new_releases(self):
        self.assertIn('MIN_ATTESTED_VERSION="3.30.3"', WORKFLOW)
        self.assertIn("gh attestation verify", WORKFLOW)
        self.assertIn("--signer-workflow curiositech/port-daddy/.github/workflows/release.yml", WORKFLOW)
        self.assertIn('--source-ref "refs/tags/${TAG}"', WORKFLOW)
        self.assertIn('--source-digest "$CANDIDATE_SHA"', WORKFLOW)
        self.assertIn("--deny-self-hosted-runners", WORKFLOW)
        self.assertIn("predates the v3.30.3 provenance boundary", WORKFLOW)

    def test_workflow_noops_when_formula_already_matches(self):
        self.assertIn("git diff --cached --quiet", WORKFLOW)
        self.assertIn("nothing to publish", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
