#!/usr/bin/env python3
"""Classify PR changes by affected ZN-M2 firmware profile (unknown paths fail closed)."""
from __future__ import annotations
import argparse
import re
import subprocess
import sys

PROFILES = ("libwrt", "ppe", "viking", "fanch")
ALL = frozenset(PROFILES)
LIGHT = frozenset({
    ".github/workflows/pr-validation.yml",
    ".github/workflows/publish-profile.yml",
    ".github/workflows/prune-caches.yml",
    "scripts/release-notes.sh",
    "scripts/ci-change-scope.py",
    "scripts/ci-fast-validation.sh",
})
WORKFLOWS = {
    ".github/workflows/zn-m2-256m-main-router.yml": "libwrt",
    ".github/workflows/zn-m2-256m-6.18.yml": "ppe",
    ".github/workflows/zn-m2-256m-viking-nss.yml": "viking",
    ".github/workflows/zn-m2-256m-fanchmwrt-fwx.yml": "fanch",
}
CONFIGS = {
    "configs/zn-m2-libwrt-6.12-nss.config": "libwrt",
    "configs/zn-m2-immortalwrt-6.18.config": "ppe",
    "configs/zn-m2-immortalwrt-viking-main-nss.config": "viking",
    "configs/zn-m2-fanchmwrt-25.12.config": "fanch",
}
SOURCES = {
    "libwrt-6.12.sh": "libwrt",
    "immortalwrt-6.18.sh": "ppe",
    "deps/libwrt-6.12.env": "libwrt",
    "deps/immortalwrt-6.18.env": "ppe",
    "deps/immortalwrt-viking-main-nss.env": "viking",
    "deps/fanchmwrt-25.12.env": "fanch",
    "profiles/libwrt-25.12-nss.conf": "libwrt",
    "profiles/immortalwrt-viking-owrt-ppe.conf": "ppe",
    "profiles/immortalwrt-viking-main-nss.conf": "viking",
    "profiles/fanchmwrt-25.12.conf": "fanch",
    "adapters/immortalwrt-viking-main-nss.sh": "viking",
    "adapters/fanchmwrt-25.12.sh": "fanch",
}
EXPERIMENTAL_SCRIPTS = frozenset({
    "scripts/experimental-build.sh",
    "scripts/experimental-package.sh",
    "scripts/validate-experimental-output.sh",
})
SHARED_BUILD_SCRIPTS = frozenset({
    "scripts/load-profile.sh",
    "scripts/resolve-latest-upstreams.sh",
    "scripts/zn-m2-luci-port-order.sh",
})
RELEASE_METADATA_LINE = re.compile(r"(?:prerelease|makeLatest):\s*(?:true|false)\s*$")


def metadata_only_diff(patch: str) -> bool:
    changes = []
    for line in patch.splitlines():
        if line.startswith(("+++", "---")):
            continue
        if line.startswith(("+", "-")):
            changes.append(line[1:].strip())
    return bool(changes) and all(RELEASE_METADATA_LINE.fullmatch(s) for s in changes)


def classify_paths(paths: list[str], metadata_only: frozenset[str] = frozenset()) -> set[str]:
    affected: set[str] = set()
    for path in paths:
        if (path.endswith(".md") or path.startswith("docs/")
                or path.startswith("tests/") or path in {".gitattributes", ".gitignore", "LICENSE"}
                or path in LIGHT):
            continue
        if path in WORKFLOWS:
            if path not in metadata_only:
                affected.add(WORKFLOWS[path])
        elif path in CONFIGS:
            affected.add(CONFIGS[path])
        elif path in SOURCES:
            affected.add(SOURCES[path])
        elif path.startswith(("files-shared/", "patches/")):
            affected.update(ALL)
        elif path.startswith("files-upstream-native/"):
            affected.add("fanch")
        elif path.startswith("files-zn-m2/"):
            affected.update(("libwrt", "ppe"))
        elif path.startswith("files/"):
            affected.update(("libwrt", "ppe", "viking"))
        elif path in EXPERIMENTAL_SCRIPTS or path == ".github/workflows/build-profile.yml":
            affected.update(("viking", "fanch"))
        elif path in SHARED_BUILD_SCRIPTS:
            affected.update(ALL)
        else:
            affected.update(ALL)
    return affected


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--profile", choices=PROFILES)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        files = [
            s.decode("utf-8", errors="surrogateescape")
            for s in git("diff", "--name-only", "--no-renames", "-z", args.base, args.head).split(b"\0")
            if s
        ]
        metadata = set()
        for path in files:
            if path in (".github/workflows/zn-m2-256m-main-router.yml",
                        ".github/workflows/zn-m2-256m-6.18.yml"):
                patch = git("diff", "--unified=0", args.base, args.head, "--", path).decode("utf-8")
                if metadata_only_diff(patch):
                    metadata.add(path)
        affected = classify_paths(files, frozenset(metadata))
    except (subprocess.CalledProcessError, UnicodeError) as exc:
        print(f"Unable to classify changes: {exc}", file=sys.stderr)
        return 1
    result = {profile: str(profile in affected).lower() for profile in PROFILES}
    result["code"] = result[args.profile] if args.profile else str(bool(affected)).lower()
    result["changed_count"] = str(len(files))
    for key, value in result.items():
        print(f"{key}={value}")
    if args.output:
        with open(args.output, "a", encoding="utf-8") as out:
            for key, value in result.items():
                out.write(f"{key}={value}\n")
    print(f"Changed paths: {', '.join(files) or '(none)'}", file=sys.stderr)
    print(f"Required profiles: {', '.join(sorted(affected)) or '(none)'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
