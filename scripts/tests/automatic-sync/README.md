# Automatic synchronization scheduler checks

Run `python3 scripts/tests/automatic-sync/run.py --disable-swiftpm-sandbox` when the terminal is already sandboxed. Omit the optional flag otherwise.

The harness compiles the current app coordinator, LibraryStore, importer and ComicCore. It replaces only the awaitable transport call with controlled continuations and the 500 ms debounce sleep with a cancellable cooperative yield. The actual request, busy/follow-up, generation, disable/halt, save/import and completion logic runs unchanged. CloudKit container access is a fatal test failure; preferences are in-memory and synthetic files use temporary directories. There are no long wall-clock sleeps.

Coverage: rapid activation/book-switch bursts; no parallel same-generation runs; busy manual/automatic requests retained once; immediate manual retry; network errors without self-retry; one already-requested follow-up after failure; disable and halt cancellation; stale completion after generation replacement; missing-archive and repeated-save loop prevention; imports arriving during a run.

The reader-progress suite separately checks automatic calls from actual ReaderViewModel open/close/foreground paths without blocking local archive opening. Neither suite proves notification delivery, background scheduling, or live CloudKit convergence. A queued checkpoint currently waits for the entire in-flight cycle, including any large archive upload.
