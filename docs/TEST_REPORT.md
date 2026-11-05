# Test report

Latest CI numbers are regenerated on every publishing run in
`docs/test-results/ci/SUMMARY.md` (plus per-test JSON); this page explains them and maps
them to the acceptance criteria. **Simulator results are not iPad-mini performance results**,
and apart from the owner's hands-on check (see the last row of the status table) nothing in this report was run on a physical iPad.

## Delivery status

| Status | Result | Evidence |
|---|---|---|
| 原始碼完成 (source complete) | ✅ P0 complete; P1 items 1–6 implemented; iPhone layout not started | this repository |
| 編譯成功 (builds) | ✅ Simulator (Debug) and device `iphoneos` arm64 (Release archive) with Xcode 26.3 (17C529), iOS SDK 26.2, macOS 15.8.2 runner | `docs/test-results/ci/SUMMARY.md` |
| 模擬器測試通過 (simulator tests) | ✅ core 53 tests (51 run + 2 opt-in stress skipped) pass on macOS host and iPad mini 6 simulator; **UI 8/8 on iPad mini 6 and 8/8 on iPad Pro 13** (iOS 26.2), all on the first iteration (no retries) — [run 41896232490](https://github.com/yfwu/VN-Reader/actions/runs/41896232490), commit `95220b9`; re-verified after the static-review fixes in [run 41965308253](https://github.com/yfwu/VN-Reader/actions/runs/41965308253), commit `9a99072` (8/8 + 8/8) | `docs/test-results/ci/` |
| 實機 Archive 成功 (device archive) | ✅ **unsigned** archive (`CODE_SIGNING_ALLOWED=NO`); ❌ signed archive not done — no Team / certificate available | `deliverables/UNSIGNED-IPA-INFO.txt` |
| IPA 匯出成功 (IPA export) | ⚠️ Only `VNReader-0.1.0-1-UNSIGNED.ipa` (packaged, **cannot be installed**). Signed export: pending your Team ID | `deliverables/` |
| 指定 iPad 安裝並啟動成功 (installed on iPad) | ✅ **Reported by the owner (2026-11-05):** built from Xcode on a Mac and installed on their iPad; "運作良好" (works well). Not an automated test; iPad model, iPadOS version and signing method (Personal Team vs paid Team) not recorded; no performance numbers taken | owner report |

## Environments

| Id | Environment | Used for |
|---|---|---|
| L | Linux x86_64 container, Swift 6.0.3, 4 vCPU / 15 GB | core unit tests, 1 GB stress tests, fixture generation |
| CI-L | GitHub Actions `ubuntu-24.04`, `swift:6.0-noble` | core unit tests |
| M | GitHub Actions `macos-15` (macOS 15.8.2, Apple silicon), Xcode 26.3 | core unit tests (host), all Xcode builds |
| S-mini | Simulator "VN iPad mini 6" (iPad mini 6th generation, 744×1133 pt), iOS 26.2 | core tests on iOS, UI tests, screenshots |
| S-pro | Simulator "VN iPad Pro 13" (iPad Pro 13-inch M4, 1032×1376 pt), iOS 26.2 | UI tests, screenshots |

## Unit tests (Packages/ComicCore, 59 tests)

| Suite | Covers |
|---|---|
| ArchiveReadingTests (17) | real CBZ / RAR4 / RAR5 solid & non-solid decoding, byte equality across formats, sequential solid extraction + early stop, CJK names, Shift_JIS names, WebP/PNG/GIF, ZIP64, encryption (4 kinds), multi-volume (RAR4/RAR5), truncated ZIP/RAR, corrupt RAR data, PDF/7z/no-images, BZIP2 method, broken image listed, entry/entry-count limits |
| PageOrderingTests (11) | unpadded / padded / mixed padding, prefixes, sub-folders & root-first, CJK + full-width digits, same names in different folders, exact duplicates (stable), case-only differences, system-file filtering, manifest round trip, `../` names |
| LibraryAndImportTests (11) | import of every format then offline read (source deleted), ComicInfo → RTL, duplicate rule, same-name rule ("(2)", "(3)"), every failure leaves no files, cancel cleans up, insufficient disk space, unreadable source, delete keeps user's original byte-identical, launch cleanup of staging/orphans, DB round trip + corrupt-file recovery, old records decode |
| MetadataEditingTests (6) | name styles (US issue, manga volume, title), batch changes keep other fields and clear empty ones, sequential numbering in natural file order, series sort, old metadata decodes, ComicInfo credits/year |
| NavigationTests (8) | tap zones, LTR/RTL taps & swipes, boundaries & rapid "next", direction change keeps logical page (RTL starts at page 1), prefetch window, spreads (cover alone, shift, wide pages, RTL screen order), progress/status |
| PageSourceTests (4) | solid preparation waits then serves from cache, cancelled waiter returns, concurrent random reads, solid extraction needs disk space |
| StressTests (2, opt-in) | 1 GB / 1000-page ZIP, RAR5 non-solid, RAR5 solid, RAR4 solid |

Skipped: `testLegacyShiftJISNames` on Linux only (no converter in corelibs-foundation);
`StressTests` unless `VN_STRESS_DIR` is set.

## UI tests (UITests/ReaderUITests.swift)

Run on S-mini and S-pro. `-retry-tests-on-failure -test-iterations 2` is enabled: a test
that fails once and passes on retry is counted as passed by Xcode but listed as a repeat
in the `*-tests.json` files.

| Test | What it checks |
|---|---|
| test01EmptyLibrary | empty state with import button, portrait + landscape |
| test02ImportAndLibrary | 3 sample books (RAR5 solid, CBZ, RAR4) import and appear with covers |
| test03LTRPagingZoomThumbnailsAndProgress | right/left tap zones, first-page boundary, swipe, double-tap zoom, **panning while zoomed does not turn the page**, pinch in/out, thumbnail jump, 20 rapid taps stop at the last page, rotation keeps the page, double-page layout, progress after reopen |
| test04RTLAndDirectionSwitchKeepsPage | RTL book opens on page 1 (not the last), left tap / right swipe = next, switch to LTR stays on the same page, page-number jump |
| test05ProgressSurvivesBackgroundAndRelaunch | go to background without closing, kill, relaunch → "繼續閱讀 3 / 6" and reader on page 3; fit width on tall strips scrolls |
| test06RenameDeleteAndMenu | rename via menu, delete with confirmation, search |
| test07RepeatedOpenClose | open/close two books 5× with page turns |
| test08VerticalScrollMode | vertical continuous mode advances logical page, jump works |
| test09EditInfoAndBatchEdit | book info editor + generated US-style name, writer search, select all → batch series + auto-numbering + manga-style names, per-book fields survive the batch |

### Results — CI run 41896232490 (commit 95220b9, Xcode 26.3, iOS 26.2 simulators)

| Test | iPad mini 6 | iPad Pro 13 |
|---|---|---|
| test01EmptyLibrary | ✅ 34.9 s | ✅ 74.1 s |
| test02ImportAndLibrary | ✅ 24.5 s | ✅ 20.6 s |
| test03LTRPagingZoomThumbnailsAndProgress | ✅ 141.3 s | ✅ 168.5 s |
| test04RTLAndDirectionSwitchKeepsPage | ✅ 74.8 s | ✅ 65.6 s |
| test05ProgressSurvivesBackgroundAndRelaunch | ✅ 84.1 s | ✅ 57.8 s |
| test06RenameDeleteAndMenu | ✅ 37.0 s | ✅ 51.3 s |
| test07RepeatedOpenClose | ✅ 70.4 s | ✅ 89.5 s |
| test08VerticalScrollMode | ✅ 54.2 s | ✅ 69.2 s |

(Durations are simulator wall-clock including launches and deliberate waits; they are not performance numbers.)

History: earlier runs exposed and fixed (1) two quick side taps being taken as a double-tap zoom — side zones now turn pages immediately; (2) tall-strip covers stretching grid cells; (3) the empty-state layout; (4) the reader-settings sheet hiding controls at medium height on 13-inch iPads; (5) a cold-simulator launch timeout (simulators are now booted before tests).
Latest regenerated summary: `docs/test-results/ci/SUMMARY.md`.

## Acceptance criteria (section 11) — coverage

| # | Criterion | Automated evidence | Not covered / remaining |
|---|---|---|---|
| 1 | Real CBZ, RAR4 CBR, RAR5 CBR import + read | Unit (L, M, S-mini) + UI (sample RAR5 solid, RAR4, CBZ) | device |
| 2 | Ordering: unpadded, padded, sub-folders, CJK | PageOrderingTests, testNestedCJKNames | — |
| 3 | Multiple import, same names, cancel, failure cleanup | LibraryAndImportTests (core); UI seeds 3 books at once | cancelling from the UI button is not UI-tested (no large file in the picker flow) |
| 4 | LTR / RTL, same page after switching | NavigationTests + test04 | — |
| 5 | Pinch, double tap, pan while zoomed, thumbnail jump | test03 | real-finger feel on device |
| 6 | Reopen, rotation, background progress | test03 (reopen, rotate), test05 (background + kill) | — |
| 7 | Offline reading after import | testImportEveryFormatAndReadOffline (source deleted before reading); app has no network code | airplane-mode run on device |
| 8 | Large books, rapid paging, random jumps, repeated open/close | StressTests 1 GB (L), test03 rapid taps, test07 | iPad-mini memory/time measurements |
| 9 | Corrupt, no images, broken image, unsupported method, low disk | ArchiveReadingTests, LibraryAndImportTests, PageSourceTests (injected disk-space provider) | broken-image page appearance not UI-tested; real full disk |
| 10 | Delete keeps the user's original | testDeleteKeepsUserOriginal (byte-identical check) | — |
| 11 | iPad mini vs large iPad, portrait/landscape | UI tests + screenshots on S-mini and S-pro | — |
| 12 | Device build and IPA install | unsigned arm64 archive + IPA | signed export & install need your Team |

## Performance (measured, Linux container — NOT iPad)

From `docs/test-results/stress-linux.txt` (1000 pages × ~1 MB, release build):

| Archive (≈1 GB) | Import (copy + CRC + list) | 200 random page reads | Solid: first page | Solid: page 500 | Solid: full preparation | Peak RSS |
|---|---|---|---|---|---|---|
| ZIP (stored) | 3.1 s | 0.08 s | — | — | — | 30 MB |
| RAR5 non-solid | 0.8 s | 0.42 s | — | — | — | 34 MB |
| RAR5 solid | 2.0 s | 0.04 s (from cache) | 0.014 s | 6.3 s | 8.0 s | 73 MB |
| RAR4 solid | 0.8 s | 0.03 s (from cache) | 0.014 s | 5.8 s | 9.4 s | 73 MB |

Memory stays flat with book size because only single entries are ever held in memory.
Expect the iPad mini 6 (A15) to be slower for solid preparation; measure on the device.

## Not tested

* Systematic checks on a physical iPad: the owner confirmed the app installs and works well, but there is no recorded per-criterion pass/fail, no memory/thermal/performance measurement, and no test of large (≈1 GB) books on the device.
* iCloud Drive / third-party File Provider downloads (code path present, needs a signed-in device).
* VoiceOver end-to-end audit; Dynamic Type at the largest accessibility sizes.
* Split View / Stage Manager window resizing (supported in code; not exercised in UI tests).
* Open-in / drag-and-drop import (implemented; not in UI tests).
