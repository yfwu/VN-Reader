# Reader progress regression checks

Run `python3 scripts/tests/reader-progress/run.py --disable-swiftpm-sandbox` from the repository. The optional flag is only needed when SwiftPM runs inside an existing terminal sandbox.

This compiles the current `ReaderViewModel`, `LibraryStore`, import coordinator, CloudKit coordinator/file store, and ComicCore against synthetic CBZ fixtures. UIKit image rendering is stubbed. A temporary same-file adapter exposes reader attachment and incoming record handling. `CKContainer` creation is a fatal test failure; foreground `synchronize()` requests are counted before the transport entry point and never reach a network engine. Preferences are in-memory and all files live in a temporary directory.

Coverage includes both initial fetch/attachment orders; passive, stale, and same-page renderer callbacks; explicit navigation/jump intent; active-reader and background/foreground behavior; close; device-local opening recency/filter/sort and reset; no recency leakage into metadata saves/cloud payloads; offline persistence; final-spread logical focus and completion.

These checks verify model and merge behavior. They do not prove UIKit gesture plumbing, Apple notification delivery, or physical-device/Production CloudKit synchronization. The adjacent reader-UIKit tests and real cross-device release gate remain necessary.
