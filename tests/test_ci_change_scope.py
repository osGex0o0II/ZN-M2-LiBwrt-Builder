#!/usr/bin/env python3
"""Deterministic tests for selective build routing."""
import importlib.util
import pathlib
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
                    ".github/workflows/publish-profile.yml"], [])

    def test_each_profile(self):
        self.check(["configs/zn-m2-libwrt-6.12-nss.config"], ["libwrt"])
        self.check(["deps/immortalwrt-6.18.env"], ["ppe"])
        self.check(["profiles/immortalwrt-viking-main-nss.conf"], ["viking"])
        self.check(["adapters/fanchmwrt-25.12.sh"], ["fanch"])

    def test_shared_change(self):
        self.check(["files-shared/etc/uci-defaults/a.sh"], MODULE.ALL)
        self.check(["patches/other.patch"], MODULE.ALL)
        self.check(["scripts/resolve-latest-upstreams.sh"], MODULE.ALL)

    def test_shared_and_profile_specific_files(self):
        self.check(["files/etc/config/a"], ["libwrt", "ppe", "viking"])
        self.check(["files-zn-m2/etc/config/a"], ["libwrt", "ppe"])
        self.check(["files-upstream-native/etc/config/a"], ["fanch"])
        self.check([".github/workflows/build-profile.yml"], ["viking", "fanch"])

    def test_unknown_fails_closed(self):
        self.check(["future/unclassified.txt"], MODULE.ALL)
        self.check([".github/workflows/auto-merge-deps.yml"], MODULE.ALL)

    def test_release_metadata_only(self):
        self.assertTrue(MODULE.metadata_only_diff(
            "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-          prerelease: true\n+          prerelease: false\n"))
        self.check([".github/workflows/zn-m2-256m-main-router.yml"], [],
                   frozenset({".github/workflows/zn-m2-256m-main-router.yml"}))
        self.assertFalse(MODULE.metadata_only_diff(
            "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-          prerelease: true\n+          run: echo hacked\n"))
        self.assertFalse(MODULE.metadata_only_diff(""))
        self.check([".github/workflows/zn-m2-256m-6.18.yml"], ["ppe"])

    def test_maximum_impact(self):
        self.check(["README.md", "configs/zn-m2-libwrt-6.12-nss.config",
                    "files-shared/etc/config/a"], MODULE.ALL)


if __name__ == "__main__":
    unittest.main()
