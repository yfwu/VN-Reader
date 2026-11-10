# Reading progress correction — Build 8

Build 8 remains unuploaded after completing the recorded source/local reader/UI acceptance scope. The published Build 7's small-guide physical Production round trip and Build 8's same-Mac Development automatic round trip are now recorded separately below. Neither replaces tests of the other build/environment.

## Reproduced blocker and correction

Build 7 and the earlier Build 8 snapshot treated archive attachment and every renderer callback as a new reading action. Opening an old local page before or after an incoming fetch could stamp it as newer and overwrite the remote position. Passive reflow could do the same after a remote update. The actual-source harness reproduced both event orders and reflow overwrite; closing alone preserved the merged library position. [Pre-fix evidence](progress-race-before-fix.txt) remains intact.

- Initial display, archive attachment, wide-page discovery/re-pairing, resize, settings reload and remote restoration do not write progress. Only explicit navigation carries `userInitiated: true` and changes the canonical position/sync stamp.
- While initially opening and before deliberate navigation, the reader follows latest merged progress. An actively navigating reader does not unexpectedly jump when a remote update arrives.
- A real background/active transition resets that navigation gate and adopts the current merged position, continuing to observe later fetches until the user navigates again. Transient inactive/active states request metadata but preserve an already navigating reader's gate. Mac Command-Tab may therefore update the catalogue while retaining the open reader's page; close/reopen adopts the latest position.
- Enabled app opening/activation and book opening/closing automatically request synchronization. Requests share a 500 ms debounce; a busy run retains one follow-up rather than dropping it. Reading never waits for that work. A large archive upload can delay the next metadata checkpoint; see [AUTOMATIC_SYNC.md](AUTOMATIC_SYNC.md).
- Closing/backgrounding persists the canonical library rather than an old reader snapshot. Final spreads preserve exact focused logical page and separately mark completion when the final page is visible during deliberate navigation.
- Optional, atomically written `reader-activity.json` preserves local opening recency for Continue/filter/sort presentation. `book(id)`, raw/persisted books, library JSON, metadata saves and outgoing CloudKit payloads retain canonical progress. Local reset clears local opening activity; newer remote reset supersedes it. Corrupt/unwritable optional activity cannot overwrite or block the catalogue.

No CloudKit schema or ComicCore data-format change was needed.

## Verification by layer

| Layer | Current recorded result | Scope |
| --- | --- | --- |
| Actual reader/library/merge models | **37/37**, [log](reader-progress-after-auto.txt) | Both initial-fetch orderings, passive/stale callbacks, navigation precedence, foreground/close, offline persistence, final-spread focus/completion, local recency isolation, and automatic open/close requests. Rendering stubbed; no backend. |
| Actual coordinator automatic scheduler | **17/17**, [log](automatic-sync.txt) | Burst debounce, busy follow-up, disable/halt/generation cancellation, manual retry and no self-loop. Transport and debounce wait injected; scheduler runs unchanged. |
| Actual UIKit controller/loader/geometry/intent | **56/56**, [log](reader-spreads.txt) | Navigation intent, transition precedence, wide layouts, cached vertical aspect sizing and late height correction. |
| Coordinator/layout regressions | **21/21** coordinator; **12 Mac + 8 iPad** layout | Actual source, no CloudKit backend. |
| Earlier persistence/core runs | **12/12** persistence; **91 passed + 2 stress skips** Core | Retained earlier unchanged-layer evidence. |
| Final native-toolbar app build and UI smoke | Signed Mac Debug **BUILD SUCCEEDED**, [log](mac-native-final-v2-build.txt); [native observations](MAC_NATIVE_TOOLBAR.md) | Readable title, two-image share popover, jump/cancel, hidden chrome/Escape and retained library position observed; listed native edge cases remain unverified. |
| Latest affected full-app iPad 05/08 | **2/2 passed, 79.957 seconds**, [log](ipad-native-final.txt), [summary](ipad-native-final-summary.json) | Two SwiftUI runtime warnings retained; selected tests, not a full-suite rerun. |

The original 32-model log remains [historical evidence](reader-progress.txt); the expanded current model count is 37. The early 4/4 full-app progress run and 1/1 vertical follow-up also remain historical, with their recorded SwiftUI warnings. A subsequent [integration attempt](ipad-auto-integration-initial.txt) passed 03/05/14 but failed vertical swipe synthesis; test05 took 948.963 seconds. That 3/4 run remains failed in the record. The later 05/08 rerun passed 2/2 in 79.957 seconds with host sleep inhibited, after the cached/late vertical sizing corrections. It retains two publishing-during-view-update warnings and does not establish a definitive cause for all earlier timing symptoms.

Two later vertical bugs were independently reproduced and corrected: a passive row correction could suppress the next real same-row report, and cached/late image aspect information could size a tall page using fallback dimensions or an incorrect height delta. The 56 UIKit checks include these sequences. Pre-fix records remain in `reader-vertical-progress-before-fix.txt`, `reader-vertical-cached-before-fix.txt` and `reader-vertical-estimates-before-fix.txt`; source inputs are in `reader-spreads-source-sha256.txt`.

## Live evidence with explicit boundaries

- [Physical Production, TestFlight 7](PHYSICAL_PRODUCTION_SYNC.md): **Mac page 4 → iPad page 4 → Mac page 8**, followed by Mac termination/relaunch and cover-only removal/redownload retaining page 8. iPad receipt is user-reported; Mac observations and app-scoped diagnostics are separately identified. Reverse arrival was delayed across completed rounds. This is a manual happy-path transport test, not Build 8 automatic or cold-open correction coverage.
- [Same-Mac Development, Build 8](AUTO_DEVELOPMENT_SMOKE.md): **A page 4 → fresh cover-only B page 4 → returning A page 8** using independent catalogues without Sync Now driving the round trip. A return exercised saved-preference `appOpened` and awaited retry 2 after a record conflict. This is one Mac, not two physical devices or Production. It predates the final subsequent native-toolbar UI.

A completed status on one client alone does not prove another has received that position. These live results use receiver observations in addition to operation logs and retain the delayed/conflicted stages.

## Remaining acceptance matrix

| Scenario | Required outcome / current limit |
| --- | --- |
| Basic send/receive and reopen | Observed in the scoped Build 7 Production and Build 8 Development sessions above; environments remain distinct |
| Cold opening before remote fetch | Must not stamp the stale local position; covered offline, physical release-device timing remains unverified |
| True background/foreground with late fetch | Adopt latest merged position before new navigation; model-covered, automatic physical Production delivery remains unverified |
| Active-reader remote arrival or Mac activation | Catalogue may update without a sudden reader jump; later explicit navigation is a real edit |
| Rotation/re-pair/settings/late vertical correction | No passive progress write; current UIKit tests and affected iPad 05/08 rerun pass; final Mac UI corrections passed their separately recorded scoped native check |
| Mac final spread → single-page device | Focus and completion remain separate; model-covered, explicit physical final-spread case remains unverified |
| Offline reconnection, account switch, large uploads | Not established by the small-guide smoke sessions |

Retained Build 8 v1/v2 archives/exports are stale. Final source/local-QA acceptance is now recorded, but new archive/export/signature verification and delivery have not been performed. Historical manifests/provenance retain their original scope. The single Build 8 `README.md` is now the release checklist; existing evidence is retained without further per-candidate maintenance.
