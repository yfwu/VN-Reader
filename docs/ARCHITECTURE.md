# Architecture

```
VN-Reader/
├─ VNReader.xcodeproj          hand-maintained Xcode 16 project (folder-synchronised groups)
├─ Config/                     xcconfigs, Info.plist, signing template, ExportOptions templates
├─ App/Sources/                iPad and Mac Catalyst app (SwiftUI + UIKit)
│  ├─ VNReaderApp.swift        entry point, open-in handling
│  ├─ Model/                   LibraryStore, ImportCoordinator, AppSettings, UI-test hooks
│  ├─ Library/                 library grid, cells, import status, drag & drop
│  ├─ Reader/                  ReaderScreen (SwiftUI chrome) + ReaderViewController (UIKit pager), page sharing
│  ├─ Imaging/                 ImageIO decoding, page cache, thumbnails, covers
│  ├─ Settings/                settings & licenses
│  ├─ Sync/                    opt-in CloudKit coordinator, file transport, smoke isolation
│  └─ Shared/                  L10n (all strings; translations in Resources/Localizable.xcstrings), ErrorMessages
├─ App/Resources/              asset catalog, sample books used by UI tests
├─ UITests/                    XCUITest end-to-end tests (+ screenshots)
├─ Packages/ComicCore/         platform-independent core (Swift package, builds on Linux too)
│  ├─ Sources/CUnrar/          RARLAB unrar 7.23 (C++) + C shim `vnrar`
│  ├─ Sources/CZlib/           system zlib module map
│  ├─ Sources/ComicCore/
│  │  ├─ Archive/              format detection, ZIP reader, RAR reader, inflate
│  │  ├─ Pages/                page filter, natural sort, manifest, spreads
│  │  ├─ Library/              BookRecord, LibraryDatabase (JSON), LibraryPaths
│  │  ├─ Import/               BookImporter, disk-space policy, storage maintenance
│  │  ├─ Reading/              BookPageSource (+ solid-RAR cache), navigation rules, shared file names
│  │  ├─ Sync/                 Codable field registers, deterministic merge, cloud envelope
│  │  └─ Metadata/             ComicInfo.xml
│  └─ Tests/ComicCoreTests/    unit tests + real CBZ/CBR fixtures
├─ scripts/                    build / test / archive / fixture generation
└─ docs/                       this documentation, reports, screenshots
```

## Layers

| Concern | Where | Notes |
|---|---|---|
| Archive reading | `ComicCore/Archive` | `ComicArchive` protocol; `ZipArchive` (own implementation, true random access through the central directory, `pread`), `RarArchive` (unrar, list-mode scan + forward cursor). Format chosen by magic bytes only. |
| Page list | `ComicCore/Pages` | `PageFilter` + `NaturalSort` → `PageManifest`, frozen at import. |
| Persistence | `ComicCore/Library` | `library.json` (atomic write, latest committed backup, schema validation and write protection). Imports and destructive edits publish only after a successful save; unsupported or unrecoverable libraries stay read-only. |
| Import | `ComicCore/Import` + `App/Model/ImportCoordinator` | Security-scoped access and `NSFileCoordinator` (downloads cloud files) in the app; staging copy, validation, cover, commit in the core. |
| Reading pipeline | `ComicCore/Reading/BookPageSource` | Random access for ZIP/non-solid RAR; sequential background extraction to `Caches/Extracted/<id>/` for solid RAR with waiters. |
| Image decode | `App/Imaging` | ImageIO thumbnail API decodes straight to display size on a background task. `NSCache` with a cost limit (≈10 % RAM, ≤400 MB), purge on memory warning, prefetch window = current ± (2 ahead, 1 behind), stale tasks cancelled. |
| Reader UI | `App/Reader` | `UIPageViewController` (scroll style) hosting `SpreadPageController` (1 page or a spread) with a zoomable `SpreadZoomView`. Paging is disabled while zoomed in so drags pan. SwiftUI overlay for toolbars/sheets. |
| Library UI | `App/Library` | SwiftUI adaptive grid, search, sort/filter menu, continue-reading card, import status rows, selection mode, book info and batch info editors (`BookInfoView`). Naming styles, batch field changes, sequential numbering and series order live in `ComicCore/Library/MetadataEditing`. |

## Threading

Build 7 adds a MainActor `CloudSyncCoordinator` using CKSyncEngine for the private
`Library` zone. Records contain field-level stamps, metadata/progress payloads,
cover assets and page manifests. A separate `BookFiles` zone holds immutable
SHA-256-identified archives and is excluded from all engine fetches. Archives are
uploaded through persisted long-lived operations and downloaded only when opened.
The reader still consumes a verified local archive. CloudKit is confined to the
App target; pure merge/migration tests remain in ComicCore.

The library's durable snapshot is the upload source. Incoming records first
capture pending local edits, merge, and persist the complete local snapshot;
only then may engine state advance. Account changes and failed persistence halt
sync without deleting files. The schema 1 → 2 migration retains the original
snapshot and blocks unsafe downgrade. See [build 7 validation](ICLOUD_BUILD7_TEST_PLAN.md)
for transport limits, smoke isolation and Production release gates.

* Main thread: UI, `LibraryStore` mutations (records are small; writes are atomic and coalesced 0.4 s, flushed immediately on background/close).
* Import queue (serial): one import at a time. The staging step tries an APFS clone first (instant, no extra disk use) and otherwise copies through one reused 1 MB buffer with POSIX reads. Either way the CRC-32 fingerprint is computed with that buffer, with cancellation checks. Memory use does not depend on the file's size. `FileHandle.read` must not be used here: each chunk is an autoreleased `NSData`, and a loop that never drains keeps the whole file in memory (this ended the app on 3 GB books). A background task keeps a running import alive for the ~30 s iPadOS allows after leaving the app.
* Reader overlays: `ReaderPaging.pagesOnScreen()` reports the images on screen and their window frames, for either reading mode. The magnifier redraws those on a display link, so it follows page turns and scrolling without any cooperation from the pager. A long press on either pager opens it and, while held, moves it through `ReaderViewModel.loupeHold`; pages are never turned by that press, since a long-press recognizer excludes the pans and taps. Full-resolution bitmaps come from `PageImageLoader.requestDetail` (at most 2 kept, ≤24 MP each, dropped on memory warnings and when the lens closes).
* Page reads: concurrent queue; unrar calls are serialised by a global lock (unrar has process-wide state).
* Solid RAR extraction: one background thread per book, shared by re-opens, cancellable, writes atomically.
* Decoding: detached tasks per page, cancelled when they leave the prefetch window.

## Storage

| Kind | Location | Backed up | Purgeable |
|---|---|---|---|
| Library records | Application Support/VNReader/library.json | yes | no |
| Book copies, manifests, covers | Application Support/VNReader/Books/<id>/ | yes | no |
| Solid-RAR extracted pages, thumbnails | Caches/VNReader/ | no | yes (system or Settings ▸ Clear cache) |
| Import staging | tmp/VNReader/Import/ | no | removed after each job and at launch |

Launch housekeeping removes staging leftovers and caches of deleted books. `Books/<id>` folders without a record are preserved and reported: a crash or backup recovery can leave complete books outside the catalog. They are never automatically deleted. Extracted caches are trimmed LRU to 3 GB.

The offline build 6 enables Mac Catalyst with the same bundle identifier, a macOS sandbox and user-selected read/write file access (required by the Catalyst document picker; imported originals are only read). The Mac app uses a single scene until shared extraction and share-file lifetimes support independent reader windows.
