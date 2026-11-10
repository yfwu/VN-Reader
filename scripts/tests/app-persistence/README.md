# App persistence regression harness

On macOS with Xcode's Swift 6 toolchain selected, run from any working directory:

```sh
python3 scripts/tests/app-persistence/run.py
```

The runner copies the **current** `LibraryStore.swift` and `ImportCoordinator.swift`
into a temporary Swift package and links this checkout's `ComicCore`. No stale
production model copy is checked in. Only UI services, cover rendering, settings,
and display strings are stubbed; library writes and archive imports are real.

The 12 checks cover durable import publication, source retention on validation,
cancellation, or save failure, failed metadata writes, and failed deletion keeping
both the row and archive. They use bundled fixtures copied into a fresh temporary
library. They do not open the app's actual library, launch a simulator, or test UI.

Generated sources, build output, and test data are removed afterward. Add
`--keep-workspace` to retain them for inspection. A failed check or build exits
nonzero. No signing or external dependency download is required.

In the iCloud branch, this entry point delegates to the sibling `cloud-sync`
runner so the added coordinator is compiled with its offline stubs as well.

If an already sandboxed terminal reports `sandbox-exec: sandbox_apply: Operation not permitted`,
append `--disable-swiftpm-sandbox` to skip SwiftPM's nested manifest sandbox.
This only compiles this repository's local package manifests.

Imports exercise the real macOS `NSFileCoordinator` service. A restricted agent
sandbox can reject that service with `NSCocoaErrorDomain 256` even when compilation
succeeds; run this harness in a normal local macOS terminal in that case.
