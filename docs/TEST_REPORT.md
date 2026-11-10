# Test report

Latest CI numbers are regenerated on every publishing run in
`docs/test-results/ci/SUMMARY.md` (plus per-test JSON); this page explains them and maps
them to the acceptance criteria. **Simulator results are not iPad-mini performance results**,
and automated simulator results do not establish physical-device behavior. Hands-on physical observations are recorded separately with their build and environment.

## Build 8 automatic sync and reader corrections — source/local QA complete

Build 8 remains isolated on `codex/mac-reader-layout` in
`/Users/yfwu/Developer/VN-Reader/.worktrees/build-8`; **it has not been uploaded**.
The requested small-guide physical Production round trip passed on TestFlight 7,
while Build 8's later automatic synchronization and native reader corrections are
recorded separately with their environment and source stage.

- [Actual reader/library/merge model](test-results/build-8/reader-progress-after-auto.txt):
  **37/37**. [Automatic scheduler](test-results/build-8/automatic-sync.txt): **17/17**.
  These verify passive/explicit progress intent, local recency isolation, lifecycle
  requests, debounce/busy follow-up, cancellation and no scheduler self-loop without a backend.
- [Actual UIKit/controller/geometry](test-results/build-8/reader-spreads.txt): **56/56**,
  including cached tall-page sizing, late height adjustment and navigation intent.
  Coordinator **21/21**, layout **12 Mac + 8 iPad**, prior unchanged persistence
  **12/12**, and the earlier Core run **91 passed + 2 stress skips** are retained.
- The latest affected [iPad 05/08 rerun](test-results/build-8/ipad-native-final.txt)
  passed **2/2 in 79.957 seconds**, retaining two SwiftUI publishing-during-view-update
  warnings. The earlier automatic integration run remains **3/4**, with test08
  swipe-synthesis timeout and unusually slow test05 timing. The 2/2 rerun is not a
  new complete-suite run or proof of a single cause for all earlier timing symptoms.
- The latest reader source uses the native Mac top toolbar and reserved bottom row.
  Native QA found title contrast and toolbar-hosted sharing issues, then the
  [final signed Debug build](test-results/build-8/mac-native-final-v2-build.txt) and
  [native rerun](test-results/build-8/MAC_NATIVE_TOOLBAR.md) verified the corrections:
  readable title, two-image share popover, jump/cancel and hidden-chrome Escape
  returning to library page 8. Select/settings/thumbnails checks preceded the
  final bar/share-only change. Back remains in the right-hand group; narrow/white/older-OS
  and complete zoom/RTL/slider behavior are not inferred passed.
- [Physical TestFlight 7 / Production](test-results/build-8/PHYSICAL_PRODUCTION_SYNC.md):
  **Mac page 4 → iPad page 4 → Mac page 8**, plus Mac termination/relaunch and cover-only
  removal/redownload retaining page 8. Reverse receipt was delayed across completed
  rounds. This was manual synchronization and the iPad receipt was user-reported.
- [Build 8 automatic / Development](test-results/build-8/AUTO_DEVELOPMENT_SMOKE.md):
  **A page 4 → fresh cover-only B page 4 → returning A page 8** without Sync Now driving
  the round trip, including `appOpened` and awaited conflict retry. This used two
  isolated catalogues sequentially on **one Mac**, not two physical devices or Production.

Retained Build 8 v1/v2 archives and exports are stale. Historical validation hashes/provenance retain their original scope; the single
Build 8 release checklist below is the current delivery reference. Historical
source/artifact manifests remain untouched. No new archive/export/upload was performed. See the [current evidence and remaining gates](test-results/build-8/README.md),
[progress policy](test-results/build-8/READING_PROGRESS.md) and [automatic-sync limits](test-results/build-8/AUTOMATIC_SYNC.md).
Automatic physical Build 8 Production behavior, cold-open timing on physical release
devices, account switching, interruption recovery and 20–30 GB performance remain
outside the completed small-guide evidence.

## Build 7 prototype verification — 2026-11-10

Both **0.1.0 (7)** uploads completed successfully: the final iPad and Mac `v2`
upload logs each contain `Upload succeeded.` and `EXPORT SUCCEEDED`. App Store
Connect subsequently showed **Ready to Submit** for both platforms and the
**Internal** group with **2 testers**; [the observed build IDs and links](test-results/build-7/app-store-connect.json) are retained. Local exported
IPA/PKG signatures were verified with CloudKit **Production**, push **production**,
the expected container, and debugging disabled. This validates export configuration,
not live Production synchronization. The Book/BookFile schema was separately
deployed to Production on 2026-11-10; its exported definition is preserved in
[CloudKit.schema.ckdb](../Config/CloudKit.schema.ckdb). See the
[build 7 source and artifact index](test-results/build-7/README.md).

- Core: **92 tests, 90 passed, 2 opt-in stress tests skipped**, no failures. New coverage includes deterministic register merges, concurrent edits, pending page turns, bookmark removal, counter overflow, schema migration and fractional date save/reload.
- The app persistence harness passed **12 checks** against actual app sources, covering import publication, persistence failure, cancellation, and original-file retention.
- The separate offline coordinator audit passes **21 checks** against actual App model/coordinator sources. It does not validate live CloudKit transport or push delivery.
- iOS Simulator and development-signed Mac Catalyst compile; localization passes **232 keys**.
- Signed Release archives for iPad arm64 and Catalyst arm64/x86_64 verify as **0.1.0 (7)**. A live Development smoke on two isolated, sequential clients on the same Mac confirms upload, cover-only receipt, on-demand download, bidirectional reading progress, and conflict recovery. The reproduced initial CKError 14 conflict now completes through a bounded awaited retry; mixed or unknown errors remain failures. See [the evidence record](test-results/build-7/LIVE_SMOKE.md); physical cross-device and Production behavior are not established by this test.
- Remaining live-service scenarios, large-library performance, Production runtime and TestFlight cross-device sync remain tracked in [the build 7 test plan](ICLOUD_BUILD7_TEST_PLAN.md). Physical Mac+iPad and TestFlight sync are gates for wider testing or public release, not claims established by this internal prototype upload. Build 6 runtime results below are not proof of build 7 iCloud behavior.

## Build 6 verification — 2026-11-10

Build 6 artifact paths in this historical section refer to the parent checkout
`/Users/yfwu/Developer/VN-Reader`, not this build 7 worktree.

The current repair release uses build **6** for iPad and Mac Catalyst; the separate iCloud prototype uses build **7**. Both **0.1.0 (6)** binaries were uploaded successfully on 2026-11-10. After processing, App Store Connect showed **Ready to Submit** for both platforms and the **Internal** group with **2 testers**. This is TestFlight build/distribution status, not App Store approval or evidence of installation on a physical device. The CI table below records older runs and is not evidence for the current binary.

| Platform | App Store Connect build ID | Final archive | Upload evidence |
|---|---|---|---|
| iPad | `c766b5d3-08b0-4dff-b31f-d986517726eb` | `build/release-6-ios-v2/VNReader.xcarchive` | `build/release-6-ios-v2/export.log`: upload and export succeeded |
| Mac Catalyst | `499d8b96-f6fa-4aca-9f0d-521505253a22` | `build/release-6-mac-v2/VNReader.xcarchive` | `build/release-6-mac-v2/export.log`: upload and export succeeded |

Source/archive hashes, rebuild commands, and the local source snapshot are indexed in
[the build 6 provenance record](test-results/build-6/README.md). This release includes
uncommitted changes; the Git base commit alone cannot reproduce it. Private signing
configuration and credentials are excluded from the snapshot.

- `ComicCore`: **79 tests, 77 passed and 2 opt-in stress tests skipped**, with no failures. Coverage includes recovery without deleting uncatalogued archives, unreadable/future-schema write protection, backup integrity, and exact app-owned Inbox boundaries (including symlink escapes).
- An app-model fault-injection harness compiled the actual `LibraryStore` and `ImportCoordinator`: **12 checks passed**, covering durable import publication, failed save/delete retention, cancellation, and Inbox ownership.
- Localization: **208 keys**, no missing translations or punctuation warnings.
- Signed Release archives were built for iPad arm64 and Mac Catalyst arm64/x86_64 with Xcode 27.2 (27B52). The final `v2` archives include the Inbox ownership and book-menu fixes; both exports/uploads succeeded. Earlier archives without `-v2` are retained as intermediate artifacts and are not the uploaded release.
- Mac runtime smoke checks cover guide rendering, page navigation, Escape, persisted progress, and importing CBZ/RAR4/RAR5 comics through the document picker. All three original sample files remained byte-identical after import.
- The expanded iPad simulator run completed with **14/15 passing**; its only failure was an outdated accessibility-string expectation. After updating that assertion, the targeted progress and final book-menu tests both passed (**2/2**) on the iPad Pro simulator. The suite plus targeted rerun therefore verifies all 15 scenarios, with the caveat that the original full run itself was not green. XCTest keyboard animation waits made editing tests unusually slow; they completed successfully.
- The final Mac book menu was visually checked: a single ellipsis aligns beside the title, with no large background, down arrow, or cover overlap. Native File → Import Comics opens the picker. Cmd-O is registered but did not respond during CUA smoke testing and remains unverified.

## Historical delivery status

| Status | Result | Evidence |
|---|---|---|
| 原始碼完成 (source complete) | ✅ P0 complete; P1 items 1–6 implemented; iPhone layout not started | this repository |
| 編譯成功 (builds) | ✅ Simulator (Debug) and device `iphoneos` arm64 (Release archive) with Xcode 26.3 (17C529), iOS SDK 26.2, macOS 15.8.2 runner | `docs/test-results/ci/SUMMARY.md` |
| 模擬器測試通過 (simulator tests) | ✅ core 53 tests (51 run + 2 opt-in stress skipped) pass on macOS host and iPad mini 6 simulator; **UI 8/8 on iPad mini 6 and 8/8 on iPad Pro 13** (iOS 26.2), all on the first iteration (no retries) — [run 41896232490](https://github.com/yfwu/VN-Reader/actions/runs/41896232490), commit `95220b9`; re-verified after the static-review fixes in [run 41965308253](https://github.com/yfwu/VN-Reader/actions/runs/41965308253), commit `9a99072` (8/8 + 8/8) | `docs/test-results/ci/` |
| 實機 Archive 成功 (device archive) | Historical CI: **unsigned** archive (`CODE_SIGNING_ALLOWED=NO`). Signed build 6 archives are now available; see the current verification section above. | `deliverables/UNSIGNED-IPA-INFO.txt` |
| IPA 匯出成功 (IPA export) | ⚠️ Only `VNReader-0.1.0-1-UNSIGNED.ipa` (packaged, **cannot be installed**). Historical unsigned export only; see current build 6 verification above | `deliverables/` |
| 指定 iPad 安裝並啟動成功 (installed on iPad) | ✅ **Reported by the owner (2026-11-05):** built from Xcode on a Mac and installed on their iPad; "運作良好" (works well). Not an automated test; iPad model, iPadOS version and signing method (Personal Team vs paid Team) not recorded; no performance numbers taken | owner report |

## Environments

| Id | Environment | Used for |
|---|---|---|
| L | Linux x86_64 container, Swift 6.0.3, 4 vCPU / 15 GB | core unit tests, 1 GB stress tests, fixture generation |
| CI-L | GitHub Actions `ubuntu-24.04`, `swift:6.0-noble` | core unit tests |
| M | GitHub Actions `macos-15` (macOS 15.8.2, Apple silicon), Xcode 26.3 | core unit tests (host), all Xcode builds |
| S-mini | Simulator "VN iPad mini 6" (iPad mini 6th generation, 744×1133 pt), iOS 26.2 | core tests on iOS, UI tests, screenshots |
| S-pro | Simulator "VN iPad Pro 13" (iPad Pro 13-inch M4, 1032×1376 pt), iOS 26.2 | UI tests, screenshots |

## Unit test coverage (Packages/ComicCore)

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
| test05ProgressSurvivesBackgroundAndRelaunch | go to background without closing, kill, relaunch → localized continue-reading summary and reader on page 3; fit width on tall strips scrolls |
| test06RenameDeleteAndMenu | rename via menu, delete with confirmation, search |
| test07RepeatedOpenClose | open/close two books 5× with page turns |
| test08VerticalScrollMode | vertical continuous mode advances logical page, jump works |
| test09EditInfoAndBatchEdit | book info editor + generated US-style name, writer search, select all → batch series + auto-numbering + manga-style names, per-book fields survive the batch |
| test10SliderPreview | preview captured mid-drag in LTR portrait and RTL landscape, releasing jumps to the page under the thumb |
| test11Magnifier | a long press opens the lens above the finger without turning the page and also drags it, toolbars hide, lens moves, magnification cycles, **pages still turn under the lens**, resize, size and magnification remembered after reopening |
| test12JumpToPageButton | the toolbar's jump button goes to the page typed in |
| test13SharePage | the toolbar's share button opens the share sheet, closing it leaves the page unchanged, and it opens again |

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
| 7 | Offline reading after import | testImportEveryFormatAndReadOffline (source deleted before reading); local reading works with optional sync disabled | airplane-mode run on device |
| 8 | Large books, rapid paging, random jumps, repeated open/close | StressTests 1 GB (L), test03 rapid taps, test07 | iPad-mini memory/time measurements |
| 9 | Corrupt, no images, broken image, unsupported method, low disk | ArchiveReadingTests, LibraryAndImportTests, PageSourceTests (injected disk-space provider) | broken-image page appearance not UI-tested; real full disk |
| 10 | Delete keeps the user's original | testDeleteKeepsUserOriginal (byte-identical check) | — |
| 11 | iPad mini vs large iPad, portrait/landscape | UI tests + screenshots on S-mini and S-pro | — |
| 12 | Device build and IPA install | signed build 6 archives; both TestFlight uploads processed and assigned to Internal (2 testers); owner-reported earlier iPad install | current TestFlight installation and physical-device regression pending |

## Performance (measured, Linux container — NOT iPad)

From `docs/test-results/stress-linux.txt` (1000 pages × ~1 MB, release build):

| Archive (≈1 GB) | Import (copy + CRC + list) | 200 random page reads | Solid: first page | Solid: page 500 | Solid: full preparation | Peak RSS |
|---|---|---|---|---|---|---|
| ZIP (stored) | 3.1 s | 0.08 s | — | — | — | 30 MB |
| RAR5 non-solid | 0.8 s | 0.42 s | — | — | — | 34 MB |
| RAR5 solid | 2.0 s | 0.04 s (from cache) | 0.014 s | 6.3 s | 8.0 s | 73 MB |
| RAR4 solid | 0.8 s | 0.03 s (from cache) | 0.014 s | 5.8 s | 9.4 s | 73 MB |

Memory stays flat with book size because only single entries are ever held in memory.

`LargeFileImportTests` measures `phys_footprint`, the number iOS holds against the app's memory limit, because
Peak RSS on Linux above cannot see autoreleased memory. With `VN_LARGE_MB=3072` on macOS, importing a 3 GB file grows
the footprint by 0 MB, by copy and by clone. Before the fix, a 128 MB file grew it by 129 MB.
Expect the iPad mini 6 (A15) to be slower for solid preparation; measure on the device.

## Not tested

* Systematic checks on a physical iPad: the owner confirmed the app installs and works well, but there is no recorded per-criterion pass/fail, no memory/thermal/performance measurement, and no test of large (≈1 GB or 3 GB) books on the device.
* iCloud Drive / third-party File Provider downloads (code path present, needs a signed-in device).
* VoiceOver end-to-end audit; Dynamic Type at the largest accessibility sizes.
* Split View / Stage Manager window resizing (supported in code; not exercised in UI tests).
* Open-in / drag-and-drop import (implemented; not in UI tests).
