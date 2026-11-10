#!/usr/bin/env python3
"""Compile current app models and run synthetic persistence failure checks on macOS."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-workspace", action="store_true", help="retain generated sources and synthetic data")
    parser.add_argument("--disable-swiftpm-sandbox", action="store_true", help="allow SwiftPM manifests inside an already sandboxed terminal")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[2]
    # The sync branch uses the same checks with its additional models and offline stubs.
    if (root / "App/Sources/Sync/CloudSyncCoordinator.swift").exists():
        runner = here.parent / "cloud-sync/run.py"
        command = [sys.executable, str(runner), "--persistence-only"]
        if args.keep_workspace:
            command.append("--keep-workspace")
        if args.disable_swiftpm_sandbox:
            command.append("--disable-swiftpm-sandbox")
        return subprocess.run(command).returncode
    workspace = Path(tempfile.mkdtemp(prefix="vnreader-persistence-"))
    try:
        sources = workspace / "Sources/Audit"
        sources.mkdir(parents=True)
        for name in ("LibraryStore.swift", "ImportCoordinator.swift"):
            shutil.copyfile(root / "App/Sources/Model" / name, sources / name)
        for name in ("Audit.swift", "UIStubs.swift"):
            shutil.copyfile(here / name, sources / name)
        dependency = json.dumps(str(root / "Packages/ComicCore"), ensure_ascii=False)
        (workspace / "Package.swift").write_text(
            '// swift-tools-version: 6.0\nimport PackageDescription\n'
            'let package = Package(name: "Audit", platforms: [.macOS(.v14)], '
            f'dependencies: [.package(path: {dependency})], '
            'targets: [.executableTarget(name: "Audit", dependencies: '
            '[.product(name: "ComicCore", package: "ComicCore")])], swiftLanguageModes: [.v5])\n'
        )
        env = os.environ.copy()
        env["CLANG_MODULE_CACHE_PATH"] = str(workspace / "module-cache")
        env["SWIFTPM_MODULECACHE_OVERRIDE"] = str(workspace / "module-cache")
        command = ["swift", "run", "--jobs", "2", "--package-path", str(workspace),
                   "--cache-path", str(workspace / "cache"), "--config-path", str(workspace / "config"),
                   "--security-path", str(workspace / "security"), "--disable-netrc", "--disable-keychain",
                   "Audit", str(workspace / "data"),
                   str(root / "Packages/ComicCore/Tests/ComicCoreTests/Fixtures")]
        print("Running actual LibraryStore and ImportCoordinator with synthetic files only.", flush=True)
        if args.disable_swiftpm_sandbox:
            command.insert(2, "--disable-sandbox")
        return subprocess.run(command, env=env).returncode
    finally:
        if args.keep_workspace:
            print(f"Retained harness workspace: {workspace}")
        else:
            shutil.rmtree(workspace)


if __name__ == "__main__":
    raise SystemExit(main())
