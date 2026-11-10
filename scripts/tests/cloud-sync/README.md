# Offline coordinator regression harness

On macOS with Xcode's Swift 6 toolchain selected:

```sh
python3 scripts/tests/cloud-sync/run.py
python3 scripts/tests/app-persistence/run.py
```

The first command runs 21 checks against the **current** `LibraryStore`,
`CloudSyncCoordinator`, and `CloudFileStore`, using synthetic `CKRecord` values
and this checkout's `ComicCore` fixtures. Coverage includes the durable record
provider, pending local progress during incoming merges, unrelated field edits,
reader leases, date precision across restart, and incoming persistence failures
preserving both the catalog and sync system fields. Seven retry checks cover
merged record conflicts, bounded attempts, unhandled conflicts, mixed network
failures, quota failure, empty partial errors and nested conflict-only errors. The second command runs the
12 import/persistence checks from the sibling harness against these models.

Every run builds a temporary Swift package from the current app source files.
The coordinator adapter is appended only to that temporary source copy so it
can bind a synthetic account and call the private receive/provider methods.
Production code does not gain test entry points.

The temporary coordinator's `CKContainer` accessor and APNs registration are
fatal-error tripwires: these checks cannot use a CloudKit account or network
backend. The runner refuses to run if the expected container declaration has
changed. User defaults use an in-memory stub; UI services, background tasks,
cover rendering, and settings use minimal stubs. Files are written only to the
fresh temporary library, never the real app library.

This validates local coordinator behavior, not CloudKit transport, CKSyncEngine
event ordering, account-switch callbacks, or background uploads. Those require
separate signed integration tests.

Sources, build output, and synthetic data are removed afterward. Add
`--keep-workspace` to retain them. A failed check or build exits nonzero; no
signing, iCloud entitlement, simulator, or external package download is required.

If an already sandboxed terminal reports `sandbox-exec: sandbox_apply: Operation not permitted`,
append `--disable-swiftpm-sandbox` to skip SwiftPM's nested manifest sandbox.
This only compiles this repository's local package manifests.
