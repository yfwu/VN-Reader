# Known issues and next steps

## P0 — gaps against the first-version requirements

| Item | Status | What is missing |
|---|---|---|
| Real-device verification (install, launch, import, read on iPad mini 6) | **Owner reported "works well" on their iPad (2026-11-05)** | Record model / iPadOS version; walk through the acceptance list on the device; signed IPA export still needs a paid Team. |
| Performance on iPad mini hardware | **Not measured** | Only Linux-container and simulator numbers exist; they are not iPad numbers. Measure with Instruments (Allocations, Time Profiler) on the device. |
| Low-disk behaviour on a device | Unit-tested with an injected disk-space provider | Not exercised with a truly full device. |
| Cloud (iCloud Drive / third-party File Provider) not-yet-downloaded files | Implemented (`NSFileCoordinator` + "正在從雲端下載…" state, cancellable) | Not exercised in CI (simulator has no signed-in iCloud). |
| VoiceOver walkthrough | Labels/identifiers set on all controls | Not audited end-to-end with VoiceOver on a device. |

## Format limitations (by design for v1, each shows a specific message)

* Encrypted archives (ZIP ZipCrypto/AES, RAR4/RAR5 `-p` / `-hp`).
* Multi-volume archives (`.part1.rar`, `.r00`, spanned ZIP).
* ZIP methods other than Stored / Deflate (BZIP2, LZMA, Deflate64, Zstandard, XZ, PPMd).
* 7z / CB7, TAR / CBT, PDF.
* Self-extracting archives (RAR/ZIP behind an `.exe` stub).
* RAR archives with a dictionary larger than 4 GB (RAR 7 `-md` > 4g): refused to avoid running out of memory.
* GIF / animated WebP show the first frame only.
* Extremely tall single images (webtoon strips longer than 16 384 px after scaling) are shown downscaled to that height, so they look soft at fit-width; splitting such strips into tiles is a possible improvement.
* Truncated RAR archives: unrar stops listing at the break, so the book may import with fewer pages; the missing pages are simply not there. (Truncated ZIPs are rejected because the central directory is missing.)

## P1 status

| # | Feature | Status |
|---|---|---|
| 1 | Two-page spreads in landscape (cover alone, pair shift, RTL order, wide pages alone) | Implemented (`SpreadLayout`, `ReaderViewController`); wide pages are detected when first decoded, so pairing can re-flow once as you approach a wide page. |
| 2 | Continuous vertical scrolling | Implemented (`VerticalReaderController`), shares page numbers. No pinch-zoom inside vertical mode yet. |
| 3 | Bookmarks | Implemented (toolbar button, "書籤" tab in the thumbnail sheet). |
| 4 | Favourites | Implemented (menu + filter). No custom collections yet. |
| 5 | ComicInfo.xml | Title/series/number/writer/summary/manga read; `Manga=YesAndRightToLeft` sets RTL. Metadata not yet shown in a detail view. |
| 6 | Open-in / drag-and-drop import | Implemented (document types, `onOpenURL`, `.onDrop`). Not covered by UI tests. |
| 7 | iPhone layout | Not started; `TARGETED_DEVICE_FAMILY = 2` (iPad only) so nobody gets an untested iPhone layout. |

## Other known issues / ideas

* Sample books (≈1.6 MB) are bundled for UI tests and screenshots (`App/Resources/Samples`). They are only imported with the `-seed-samples` launch argument; remove the folder before an App Store release if size matters.
* Page turn animation can be disabled in Settings; rapid taps during an animation jump without animation (to avoid UIPageViewController glitches).
* The library JSON is rewritten as a whole (fine for thousands of books; consider SQLite if libraries grow far beyond that).
* The English, Simplified Chinese and Japanese translations in `App/Resources/Localizable.xcstrings` have not been reviewed by native speakers yet. Licence texts in Settings stay in English on purpose.

## What you need to provide for real-device delivery

1. Apple Developer Program membership → your **Team ID**.
2. On a Mac with Xcode 16+: sign in to that account in Xcode ▸ Settings ▸ Accounts.
3. Connect the iPad mini once (Developer Mode on) so automatic signing can register its UDID — or send the UDID to whoever builds.
4. Run `DEVELOPMENT_TEAM=<TEAMID> scripts/archive-and-export.sh development` (or `ad-hoc`), then install the IPA via Finder / Apple Configurator. Details: `docs/BUILD_AND_INSTALL.md`.
