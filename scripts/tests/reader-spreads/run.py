#!/usr/bin/env python3
"""Run actual Catalyst reader controllers and image loader in a hidden UIKit harness."""
import argparse
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", type=Path, required=True, help="matching Debug Mac Catalyst build of this checkout")
    parser.add_argument("--keep-workspace", action="store_true")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[2]
    derived = args.derived_data.resolve()
    products = derived / "Build/Products/Debug-maccatalyst"
    for name in ("ComicCore.o", "CUnrar.o", "ComicCore.swiftmodule"):
        if not (products / name).exists():
            parser.error(f"Build this checkout for Debug Mac Catalyst first; missing {products / name}")
    workspace = Path(tempfile.mkdtemp(prefix="vnreader-spread-ui-"))
    try:
        sources = workspace / "Sources"
        sources.mkdir()
        for relative in ("Reader/ReaderViewController.swift", "Reader/VerticalReaderController.swift", "Reader/SpreadPageController.swift",
                         "Reader/SpreadZoomView.swift", "Imaging/PageImageLoader.swift", "Imaging/ImageDecoder.swift"):
            source = root / "App/Sources" / relative
            text = source.read_text()
            adapter = {"ReaderViewController.swift": "ControllerAdapter.swift", "VerticalReaderController.swift": "VerticalAdapter.swift", "PageImageLoader.swift": "LoaderAdapter.swift"}.get(source.name)
            if adapter:
                text += "\n" + (here / adapter).read_text()
            (sources / source.name).write_text(text)
        for name in ("UIStubs.swift", "Audit.swift", "IntentAudit.swift", "VerticalGeometryAudit.swift"):
            shutil.copyfile(here / name, sources / name)
        bundle = workspace / "SpreadAudit.app"
        executable = bundle / "Contents/MacOS/SpreadAudit"
        executable.parent.mkdir(parents=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.vnreader.synthetic.SpreadAudit", "CFBundleExecutable": "SpreadAudit",
            "CFBundleName": "Spread Audit", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
            "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {}},
            "CFBundleSupportedPlatforms": ["MacOSX"], "LSMinimumSystemVersion": "15.0", "UIDeviceFamily": [6],
        }))
        sdk = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip())
        support = sdk / "System/iOSSupport"
        command = ["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-target",
                   f"{platform.machine()}-apple-ios18.0-macabi", "-sdk", str(sdk), "-module-cache-path", str(workspace / "modules"),
                   "-I", str(products), "-Fsystem", str(support / "System/Library/Frameworks"),
                   "-L", str(support / "usr/lib"), "-Xcc", "-isystem", "-Xcc", str(support / "usr/include"),
                   "-Xcc", "-fmodule-map-file=" + str(root / "Packages/ComicCore/Sources/CZlib/module.modulemap"),
                   "-Xcc", "-fmodule-map-file=" + str(derived / "Build/Intermediates.noindex/GeneratedModuleMaps-maccatalyst/CUnrar.modulemap"),
                   "-profile-generate", "-lc++", "-lz", "-o", str(executable)]
        command += [str(path) for path in sorted(sources.glob("*.swift"))]
        command += [str(products / "ComicCore.o"), str(products / "CUnrar.o")]
        subprocess.run(command, check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True)
        env = os.environ.copy()
        env["LLVM_PROFILE_FILE"] = str(workspace / "audit.profraw")
        return subprocess.run([str(executable), str(workspace / "data"),
                               str(root / "Packages/ComicCore/Tests/ComicCoreTests/Fixtures")], env=env, timeout=60).returncode
    finally:
        if args.keep_workspace:
            print(f"Retained UIKit harness: {workspace}")
        else:
            shutil.rmtree(workspace)


if __name__ == "__main__":
    raise SystemExit(main())
