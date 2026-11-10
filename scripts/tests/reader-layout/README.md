# Reader layout model audit

On macOS with Xcode selected:

```sh
python3 scripts/tests/reader-layout/run.py
```

Compiles the current AppSettings, ReaderLayoutPreferences and ReaderViewModel
twice, selecting their Mac and iPad layout branches in temporary source copies.
The platform condition is replaced only in those copies. UI/archive/network
services use stubs; the actual layout getter, setter and preference storage run.

Coverage includes existing and synced single books, vertical books, persistent
explicit Mac single selection, UUID-scoped overrides, global preferences, unchanged
BookRecord/sync fields on Mac, pager refresh, and unchanged iPad setter behavior.
UserDefaults uses a unique temporary suite, removed on exit. It never reads or
changes VN Reader's real preferences or library. Temporary packages are removed.

This does not validate page geometry, image decoding, toolbar layout or a physical
device; those require the separate build and runtime checks.
