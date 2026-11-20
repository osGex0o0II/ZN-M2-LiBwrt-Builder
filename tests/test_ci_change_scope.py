#!/usr/bin/env python3
"""Deterministic tests for selective build routing."""
import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ci_change_scope", ROOT / "scripts/ci-change-scope.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ScopeTests(unittest.TestCase):
    def check(self, paths, expected, metadata=frozenset()):
        self.assertEqual(MODULE.classify_paths(paths, metadata), set(expected))

    def test_docs_only(self):
        self.check(["README.md", "docs/installation.md", "NOTICE.md"], [])

    def test_light_change(self):
        self.check(["scripts/release-notes.sh", "tests/test-workflow-contracts.sh",
                    ".github/workflows/publish-profile.yml",
                    ".github/workflows/publish-mature.yml"], [])

    def test_each_profile(self):
        self.check(["configs/zn-m2-libwrt-6.12-nss.config"], ["libwrt", "libwrt_ebpf"])
        self.check(["deps/immortalwrt-6.18.env"], ["ppe", "ppe_ebpf"])
        self.check(["profiles/immortalwrt-viking-main-nss.conf"], ["viking"])
        self.check(["adapters/fanchmwrt-25.12.sh"], ["fanch"])
        self.check(["adapters/libwrt-6.12.sh"], ["libwrt", "libwrt_ebpf"])
        self.check(["adapters/immortalwrt-6.18.sh"], ["ppe", "ppe_ebpf"])

    def test_shared_change(self):
        self.check(["files-shared/etc/uci-defaults/a.sh"], MODULE.ALL)
        self.check(["patches/other.patch"], MODULE.ALL)
        self.check(["scripts/resolve-latest-upstreams.sh"], MODULE.ALL)

    def test_shared_and_profile_specific_files(self):
        self.check(["files/etc/config/a"], ["libwrt", "ppe", "viking", "libwrt_ebpf", "ppe_ebpf", "viking_ebpf"])
        self.check(["files-zn-m2/etc/config/a"], ["libwrt", "ppe", "viking", "libwrt_ebpf", "ppe_ebpf", "viking_ebpf"])
        self.check(["files-upstream-native/etc/config/a"], ["fanch"])
        self.check([".github/workflows/build-profile.yml"], ["viking", "fanch", "viking_ebpf"])
        self.check(["scripts/profile-build.sh"], ["viking", "fanch", "viking_ebpf"])

    def test_honk_isolated(self):
        honk = ["libwrt_ebpf", "ppe_ebpf", "viking_ebpf"]
        for path in ["package/honk/Makefile", "configs/honk-ebpf.config",
                     "scripts/honk-profile.sh"]:
            self.check([path], honk)
        self.check(["profiles/immortalwrt-viking-main-nss-ebpf.conf"], ["viking_ebpf"])
        self.check([".github/workflows/zn-m2-immortalwrt-6.18-ppe-ebpf.yml"], ["ppe_ebpf"])

    def test_unknown_fails_closed(self):
        self.check(["future/unclassified.txt"], MODULE.ALL)
        self.check([".github/workflows/future-build.yml"], MODULE.ALL)

    def test_release_metadata_only(self):
        self.assertTrue(MODULE.metadata_only_diff(
            "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-          prerelease: true\n+          prerelease: false\n"))
        self.check([".github/workflows/zn-m2-256m-main-router.yml"], [],
                   frozenset({".github/workflows/zn-m2-256m-main-router.yml"}))
        self.assertFalse(MODULE.metadata_only_diff(
            "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-          prerelease: true\n+          run: echo hacked\n"))
        self.assertFalse(MODULE.metadata_only_diff(""))
        self.check([".github/workflows/zn-m2-256m-6.18.yml"], ["ppe", "ppe_ebpf"])

    def test_maximum_impact(self):
        self.check(["README.md", "configs/zn-m2-libwrt-6.12-nss.config",
                    "files-shared/etc/config/a"], MODULE.ALL)

    def test_self_modifying_ci_is_high_risk(self):
        self.check(["scripts/ci-change-scope.py"], MODULE.ALL)
        self.check(["scripts/ci-fast-validation.sh"], MODULE.ALL)
        self.check([".github/workflows/pr-validation.yml"], MODULE.ALL)
        self.check([".gitattributes"], MODULE.ALL)

    def test_incomplete_metadata_edits_fail_closed(self):
        self.assertFalse(MODULE.metadata_only_diff("-          prerelease: true\n"))
        self.assertFalse(MODULE.metadata_only_diff("+          prerelease: false\n"))
        self.assertFalse(MODULE.metadata_only_diff(
            "-          prerelease: true\n+          makeLatest: false\n"))
        self.assertFalse(MODULE.metadata_only_diff(
            "-          prerelease: false\n+          prerelease: false\n"))
        self.assertFalse(MODULE.metadata_only_diff(
            "-          prerelease: true\n-          prerelease: false\n+          prerelease: false\n"))


class GitDiffIntegrationTests(unittest.TestCase):
    """Exercise the actual git-diff CLI and GITHUB_OUTPUT contract."""

    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = pathlib.Path(self.work.name)
        self.git("init", "-q")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("config", "user.name", "CI Fixture")
        self.write("README.md", "Original\n")
        self.write(".github/workflows/zn-m2-256m-main-router.yml",
                   "prerelease: true\n")
        self.git("add", ".")
        self.git("commit", "-qm", "initial")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root,
                              text=True, capture_output=True, check=True)

    def write(self, name, content):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "-qm", "fixture change")

    def classify(self, profile="libwrt", base=None):
        output = self.root / "actions-output.txt"
        output.unlink(missing_ok=True)
        process = subprocess.run([
            sys.executable, str(ROOT / "scripts/ci-change-scope.py"),
            "--base", base if base is not None else self.base,
            "--head", "HEAD", "--profile", profile,
            "--output", str(output),
        ], cwd=self.root, text=True, capture_output=True)
        result = {}
        if output.exists():
            for line in output.read_text(encoding="utf-8").splitlines():
                key, value = line.split("=", 1)
                result[key] = value
        return process, result

    def test_cli_document_only(self):
        self.write("README.md", "Updated\n")
        self.commit()
        process, result = self.classify()
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result["changed_count"], "1")
        self.assertEqual(result["code"], "false")
        self.assertTrue(all(result[key] == "false" for key in MODULE.PROFILES))

    def test_cli_profile_selective(self):
        self.write("configs/zn-m2-libwrt-6.12-nss.config", "CONFIG_FLAG=y\n")
        self.commit()
        process, result = self.classify(profile="ppe")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result["code"], "false")
        self.assertEqual(result["libwrt"], "true")
        self.assertEqual(result["ppe"], "false")
        self.assertEqual(result["fanch"], "false")

    def test_cli_variant_matrix(self):
        self.write("package/honk/Makefile", "Honk update\n")
        self.commit()
        process, result = self.classify(profile="ppe")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result["variants"], "[true]")
        self.assertEqual(result["compile_required"], "true")
        self.write("configs/zn-m2-immortalwrt-6.18.config", "PPE change\n")
        self.commit()
        process, result = self.classify(profile="ppe")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result["variants"], "[false,true]")

    def test_cli_metadata_toggle_and_risky_workflow_edit(self):
        path = ".github/workflows/zn-m2-256m-main-router.yml"
        self.write(path, "prerelease: false\n")
        self.commit()
        process, result = self.classify()
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result["code"], "false")
        self.write(path, "prerelease: false\nrun: echo changed\n")
        self.commit()
        process, result = self.classify()
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result["code"], "true")

    def test_cli_unknown_path_fails_closed(self):
        self.write("new-build-script.txt", "unknown impact\n")
        self.commit()
        process, result = self.classify(profile="fanch")
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(result["code"], "true")
        self.assertTrue(all(result[key] == "true" for key in MODULE.PROFILES))

    def test_cli_diff_error_never_silently_skips(self):
        process, result = self.classify(base="invalid-commit-name")
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual(result, {})
        self.assertIn("Unable to classify changes", process.stderr)


if __name__ == "__main__":
    unittest.main()
