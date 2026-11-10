#!/usr/bin/env python3
"""Compile actual AppSettings/ReaderViewModel in both layout branches, without UI/network."""
import json
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disable-swiftpm-sandbox", action="store_true", help="run SwiftPM inside an existing terminal sandbox")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[2]
    workspace = Path(tempfile.mkdtemp(prefix="vnreader-layout-audit-"))
    try:
        sources = workspace / "Sources/Audit"
        sources.mkdir(parents=True)
        for relative in ("Model/AppSettings.swift", "Model/ReaderLayoutPreferences.swift",
                         "Reader/ReaderViewModel.swift", "Shared/L10n.swift", "Shared/SyncL10n.swift"):
            source = root / "App/Sources" / relative
            text = source.read_text()
            if source.name == "AppSettings.swift":
                text = text.replace("UserDefaults.standard", "HarnessDefaults.store")
                text += "\nextension AppSettings { static func auditMake() -> AppSettings { AppSettings() } }\n"
            if source.name == "ReaderLayoutPreferences.swift":
                condition = "#if targetEnvironment(macCatalyst)"
                if text.count(condition) != 1:
                    raise RuntimeError("Platform selector changed; update audit before running")
                text = text.replace(condition, "#if VN_LAYOUT_AUDIT_MAC")
            (sources / source.name).write_text(text)
        for filename in ("Audit.swift", "UIStubs.swift"):
            shutil.copyfile(here / filename, sources / filename)
        dependency = json.dumps(str(root / "Packages/ComicCore"))
        (workspace / "Package.swift").write_text(
            '// swift-tools-version: 6.0\nimport PackageDescription\n'
            'let package = Package(name: "Audit", platforms: [.macOS(.v14)], '
            f'dependencies: [.package(path: {dependency})], '
            'targets: [.executableTarget(name: "Audit", dependencies: '
            '[.product(name: "ComicCore", package: "ComicCore")])], swiftLanguageModes: [.v5])\n')
        for mode in ("mac", "ipad"):
            command = ["swift", "run", "--jobs", "2", "--package-path", str(workspace),
                       "--scratch-path", str(workspace / ("build-" + mode)),
                       "--cache-path", str(workspace / "cache"), "--config-path", str(workspace / "config"),
                       "--security-path", str(workspace / "security"),
                       "--disable-netrc", "--disable-keychain"]
            if args.disable_swiftpm_sandbox:
                command.insert(2, "--disable-sandbox")
            if mode == "mac":
                command += ["-Xswiftc", "-DVN_LAYOUT_AUDIT_MAC"]
            command += ["Audit", str(workspace / ("data-" + mode))]
            print("Running actual app layout model: " + mode, flush=True)
            env = os.environ.copy()
            env["CLANG_MODULE_CACHE_PATH"] = str(workspace / "module-cache")
            env["SWIFTPM_MODULECACHE_OVERRIDE"] = str(workspace / "module-cache")
            subprocess.run(command, check=True, env=env)
        return 0
    finally:
        shutil.rmtree(workspace)


if __name__ == "__main__":
    raise SystemExit(main())
