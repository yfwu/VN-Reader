#!/usr/bin/env python3
"""Run the actual automatic-sync scheduler with an injected, awaitable transport and no network."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-workspace", action="store_true", help="retain generated sources and synthetic data")
    parser.add_argument("--disable-swiftpm-sandbox", action="store_true", help="allow SwiftPM manifests inside an already sandboxed terminal")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[2]
    workspace = Path(tempfile.mkdtemp(prefix="vnreader-automatic-sync-"))
    try:
        sources = workspace / "Sources/Audit"
        sources.mkdir(parents=True)
        app_sources = (
            "Model/LibraryStore.swift", "Model/ImportCoordinator.swift",
            "Sync/CloudSyncCoordinator.swift", "Sync/CloudFileStore.swift",
            "Shared/L10n.swift", "Shared/SyncL10n.swift",
        )
        for relative in app_sources:
            source = root / "App/Sources" / relative
            text = source.read_text().replace("import UIKit\n", "")
            text = text.replace("UserDefaults.standard", "HarnessDefaults.store")
            if source.name == "CloudSyncCoordinator.swift":
                initializer = 'private lazy var container = CKContainer(identifier: "iCloud.org.yfwu.VNReader")'
                if text.count(initializer) != 1:
                    raise RuntimeError("CloudKit container declaration changed; update the offline tripwire before running")
                text = text.replace(initializer, 'private var container: CKContainer { fatalError("Network use forbidden in offline audit") }')
                if "CKContainer(" in text:
                    raise RuntimeError("Unexpected CloudKit container creation in offline source copy")
                call = "try await performSynchronization(ticket: ticket)"
                if text.count(call) != 1:
                    raise RuntimeError("Synchronization operation seam changed")
                text = text.replace(call, "try await auditCycleHandler()")
                text = text.replace("    private var runTask: Task<Void, Never>?", "    var auditCycleHandler: @MainActor () async throws -> Void = { fatalError(\"Missing offline cycle handler\") }\n    private var runTask: Task<Void, Never>?")
                delay = "try await Task.sleep(for: .milliseconds(500))"
                if text.count(delay) != 1:
                    raise RuntimeError("Debounce seam changed")
                text = text.replace(delay, "try await auditDebounce()")
                text += "\n" + (here.parent / "cloud-sync/CoordinatorAdapter.swift").read_text()
                text += "\n" + (here / "SchedulerAdapter.swift").read_text()
            (sources / source.name).write_text(text)
        audit = here / "Audit.swift"
        shutil.copyfile(audit, sources / "Audit.swift")
        shutil.copyfile(here.parent / "cloud-sync/UIStubs.swift", sources / "UIStubs.swift")
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
        print("Running actual app models offline; CKContainer access is a fatal test failure.", flush=True)
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
