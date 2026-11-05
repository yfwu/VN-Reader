# VN Reader — offline CBZ / CBR reader for iPad

A native iPadOS comic reader focused on three things: **import your own comics, start
reading fast, continue where you left off.** No account, no network, no ads, no tracking.
UI languages: Traditional Chinese (source), English, Simplified Chinese and Japanese, from `App/Resources/Localizable.xcstrings`; other system languages fall back to English.

| | |
|---|---|
| Platforms | iPadOS 18+ (iPad mini 6 is the primary design target; all iPads, portrait/landscape, Split View / Stage Manager) |
| Language / UI | Swift 5 mode, SwiftUI (library, settings) + UIKit (reader paging & zoom) |
| Formats | **CBZ** (ZIP: Stored / Deflate, ZIP64, legacy CJK names) and **CBR** (real **RAR4 and RAR5**, solid and non-solid); JPEG, PNG, **WebP**, GIF, HEIC, AVIF |
| Dependencies | RARLAB unRAR 7.23 source (vendored, unRAR license) + system zlib. Nothing else. |
| Status | See **Status** below and `docs/TEST_REPORT.md` |

## Features (first version, P0)

* **Import** from the Files picker (one or many books; local storage and File Providers such as iCloud Drive). Files are **copied** into app storage so they read offline; progress + cancel per file; failures and cancellations clean up their temporary data; cloud files are downloaded via file coordination first.
* **Format detection by content**, not extension. Encrypted, multi-volume, 7z, PDF, truncated, unsupported-method and image-less archives get a specific explanation and next step.
* **Duplicates**: identical content (size + CRC-32) is not imported twice ("已在書庫中"); different files with the same name become separate books ("名稱 (2)"). Nothing is ever overwritten.
* **Library**: cover grid that adapts to width, title, page count, progress bar, status badges (未讀 / 閱讀中 / 已讀), big **繼續閱讀** card, search (name, series, title, writer, artist, publisher), sort (recently read / imported / title / series & number), filter (status, favourites), rename, reset progress, mark finished, favourite, delete (only the app's copy and caches). Clear empty state with an import button. Import jobs/failures are shown as separate status rows, never as openable books.
* **Book info**: per-book editor (⋯ → 編輯資訊) for display name, series, number, volume, title, writer, artist, publisher, year and summary, pre-filled from ComicInfo.xml. The display name can be generated as US comics "Series (start year) #issue" (Batman (2016) #45), manga "Series 第 N 卷", or the title. **Batch editing**: 選取 → select books → 編輯資訊 sets shared fields, numbers the books in file-name order and regenerates their names; only fields you change are applied. Edits live in the library only; archives are never modified.
* **Reader**: swipe or tap left/right zones to turn pages, centre tap toggles the toolbar; toolbar has back, title, bookmark, reading settings, thumbnails, page slider and page-number jump. Pinch zoom, double-tap zoom/reset, panning while zoomed (page turning is disabled until you zoom back out). **Fit page** / **fit width** (tall strips scroll vertically). Hardware keyboard arrows/space.
* **LTR / RTL per book** (saved). The page list is never reversed: RTL changes which side is "next" for taps, swipes, slider and thumbnail order. Changing direction keeps the same page.
* **Progress** (page, direction, fit mode, layout, last read time) is saved on every page change (coalesced ~0.4 s) and flushed immediately when the app goes to background or the reader closes.
* **Performance**: pages are decoded on demand with ImageIO straight to display size; bounded memory cache (purged on memory warnings), prefetch of 2 pages ahead / 1 behind, stale work cancelled. Solid RAR is decompressed once, sequentially, into a purgeable disk cache, with a progress card ("正在準備頁面") and a way back.
* **Robustness**: disk-space checks before copying and before solid extraction; limits on archive size, entry count, entry size and image pixels; archive entry names are never used as file paths; interrupted imports and orphaned folders are cleaned at launch; a corrupt library file is preserved and the last good backup is restored.

P1 already included: landscape **two-page spreads** (cover alone, pair shift, RTL order, wide pages alone), **vertical continuous scrolling**, **bookmarks**, **favourites**, **ComicInfo.xml** (title/series/RTL hint), **Open in… / AirDrop** and **drag-and-drop** import. iPhone layout is not done (the app targets iPad only).

## Repository map

```
VNReader.xcodeproj   Xcode project (open this)          docs/                  documentation, reports, screenshots
App/                 iOS app sources & resources         scripts/               build / test / archive / fixtures
UITests/             XCUITest end-to-end tests           Config/                xcconfigs, Info.plist, signing & export templates
Packages/ComicCore/  core library (Swift + C++ unrar), testable on macOS, iOS and Linux
deliverables/        build products published by CI (UNSIGNED IPA + info)
```

Architecture: `docs/ARCHITECTURE.md` · page order rules: `docs/PAGE_ORDERING.md` ·
formats: `docs/COMPATIBILITY.md` · tests: `docs/TEST_REPORT.md` ·
build & install: `docs/BUILD_AND_INSTALL.md` · known issues: `docs/KNOWN_ISSUES.md` ·
licenses: `THIRD_PARTY_NOTICES.md`.

## Quick start

```bash
open VNReader.xcodeproj          # scheme VNReader, pick an iPad simulator, ⌘R
```

```bash
cd Packages/ComicCore && swift test   # core tests (macOS or Linux)
```

For your own iPad see `docs/BUILD_AND_INSTALL.md` (Personal Team steps, and the paid-account
Archive / IPA export: `scripts/archive-and-export.sh`).
