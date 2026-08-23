import tempfile
from pathlib import Path
import unittest

from scripts.update_port_daddy_formula import (
    FormulaUpdateError,
    update_formula_file,
    update_formula_text,
)


ARM64 = "a" * 64
LINUX = "b" * 64
NEXT_ARM64 = "c" * 64
NEXT_LINUX = "d" * 64
FORMULA = f'''class PortDaddy < Formula
  version "3.30.2"
  revision 2
  sha256 "{ARM64}"
  sha256 "{LINUX}"
end
'''


class UpdatePortDaddyFormulaTest(unittest.TestCase):
    def update(self, source=FORMULA, version="3.30.2"):
        return update_formula_text(
            source,
            version=version,
            arm64_sha256=NEXT_ARM64,
            linux_sha256=NEXT_LINUX,
        )

    def test_same_version_preserves_formula_revision(self):
        updated = self.update()
        self.assertIn('version "3.30.2"', updated)
        self.assertIn("revision 2", updated)
        self.assertIn(f'sha256 "{NEXT_ARM64}"', updated)
        self.assertIn(f'sha256 "{NEXT_LINUX}"', updated)

    def test_new_upstream_version_clears_old_revision(self):
        updated = self.update(version="3.30.3")
        self.assertIn('version "3.30.3"', updated)
        self.assertNotIn("revision", updated)

    def test_new_version_without_existing_revision_is_valid(self):
        updated = self.update(FORMULA.replace("  revision 2\n", ""), version="3.30.3")
        self.assertIn('version "3.30.3"', updated)

    def test_rejects_ambiguous_formula_shape(self):
        with self.assertRaisesRegex(FormulaUpdateError, "one formula version"):
            self.update(FORMULA.replace('  version "3.30.2"\n', ""))
        with self.assertRaisesRegex(FormulaUpdateError, "two formula sha256"):
            self.update(FORMULA.replace(f'  sha256 "{LINUX}"\n', ""))
        with self.assertRaisesRegex(FormulaUpdateError, "at most one formula revision"):
            self.update(FORMULA.replace("  revision 2\n", "  revision 2\n  revision 3\n"))

    def test_rejects_malformed_release_inputs(self):
        for version in ("v3.30.2", "3.30", "3.30.2-rc.1"):
            with self.subTest(version=version):
                with self.assertRaisesRegex(FormulaUpdateError, "version"):
                    self.update(version=version)
        with self.assertRaisesRegex(FormulaUpdateError, "arm64 sha256"):
            update_formula_text(
                FORMULA,
                version="3.30.2",
                arm64_sha256="short",
                linux_sha256=NEXT_LINUX,
            )

    def test_file_update_is_atomic_and_writes_only_after_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            formula = Path(directory)/"port-daddy.rb"
            formula.write_text(FORMULA, encoding="utf-8")
            update_formula_file(
                formula,
                version="3.30.2",
                arm64_sha256=NEXT_ARM64,
                linux_sha256=NEXT_LINUX,
            )
            self.assertIn("revision 2", formula.read_text(encoding="utf-8"))
            self.assertFalse((formula.parent/f".{formula.name}.tmp").exists())

            malformed = FORMULA.replace(f'  sha256 "{LINUX}"\n', "")
            formula.write_text(malformed, encoding="utf-8")
            with self.assertRaises(FormulaUpdateError):
                update_formula_file(
                    formula,
                    version="3.30.2",
                    arm64_sha256=NEXT_ARM64,
                    linux_sha256=NEXT_LINUX,
                )
            self.assertEqual(malformed, formula.read_text(encoding="utf-8"))

    def test_workflow_uses_tested_updater(self):
        workflow = Path(".github/workflows/update-formula.yml").read_text(encoding="utf-8")
        self.assertIn("python3 scripts/update_port_daddy_formula.py", workflow)
        self.assertNotIn("sed -i '/^[[:space:]]*revision", workflow)


if __name__ == "__main__":
    unittest.main()
