# Build 8 automatic synchronization — implementation and scoped native evidence

The user requested synchronization on app opening/foreground and book switching without requiring Sync Now. Build 8 implements these checkpoints and a same-Mac isolated Development automatic round trip has now passed, but Build 8 remains unuploaded. The physical Build 7 manual-sync observations in `PHYSICAL_PRODUCTION_SYNC.md` do not prove Build 8 automatic behavior.

## Request behavior

- `startIfEnabled()` requests an automatic app-opening checkpoint. Opt-in remains required.
- The app requests on scene activation and `UIApplication.didBecomeActiveNotification`. The UIKit notification covers Catalyst reactivation when a window's SwiftUI scene phase stays active across Command-Tab. Both signals use the same coordinator.
- Reader opening, reader closing after a local flush, and reader foreground transitions request checkpoints. They never await network before showing a downloaded book. A closing reader does not cancel another reader's shared sync request.
- Idle automatic requests use one trailing 500 ms debounce. Rapid app/reader/book-switch events merge into a single run. Manual Sync Now cancels the debounce and starts immediately.
- A request during a busy run sets one follow-up flag. On completion or failure, an already-requested follow-up runs after the debounce; requests are not discarded and no same-generation parallel synchronization is started.
- Errors do not create retries by themselves. An external request already received during the failed run may cause one follow-up. CloudKit's existing automatic engine retry remains enabled. Disable/halt cancels queued requests, and generation checks prevent old completions from altering a new run.
- Only newly observed, unbound books with an available local archive request import preparation. Ordinary progress/metadata saves enqueue engine changes; they do not create repeated full cycles. Missing-archive orphan rows and unchanged unbound rows cannot cause a completion/save retry loop.

## Reader policy and latency limits

Network triggers are separate from progress-writing intent. Initial rendering and remote restoration remain passive. An inactive/active bounce can request metadata without resetting an already navigating reader's position policy. A real background/active transition resets that gate and can adopt merged progress before the next deliberate navigation.

On Mac, Command-Tab may only produce activation/inactive signals. In that case the catalogue synchronizes, but an already navigating open reader intentionally does not jump. Closing and reopening adopts the latest catalogue position. This is not a promise that every Mac activation automatically moves the visible reader.

A follow-up checkpoint currently waits for the entire in-flight cycle, including any large archive upload. This change does not split metadata and file transport into parallel workers. Downloaded books remain available offline, but metadata latency during a large upload is not bounded. Background notification delivery and exact cross-device latency are not guaranteed.

## Offline verification

- `python3 scripts/tests/automatic-sync/run.py --disable-swiftpm-sandbox`: **17 checks** against the actual coordinator scheduler, injecting only an awaitable fake transport and a cooperative debounce yield. Covers rapid requests, busy coalescing, immediate manual retry, failure without self-loop, disable/halt, stale generations, missing archives, ordinary saves and new imports during a run. No backend or real preferences.
- `python3 scripts/tests/reader-progress/run.py --disable-swiftpm-sandbox`: **37 checks** against actual reader/library/merge models, retaining the prior progress race cases and adding automatic open/close calls, nonblocking local opening, and inactive-return navigation protection. Its network request entry is intercepted; it does not prove scheduling or delivery.
- Existing coordinator **21/21**, Mac/iPad layout **20/20**, localization **233**. The current actual UIKit harness passes **56 checks**, including cached/late vertical geometry. Earlier 4/4 and 1/1 full-app runs remain historical. A later 3/4 integration run failed vertical swipe synthesis; the latest affected 05/08 rerun passes **2/2 in 79.957 seconds**, retaining two SwiftUI runtime warnings. Automatic-sync native checks below pass independently; subsequent Mac title-contrast/share corrections passed their final signed Debug build and scoped native UI acceptance, recorded in `MAC_NATIVE_TOOLBAR.md`.

## Native evidence and remaining acceptance

The root coordinator observed **A page 4 → B page 4 → A page 8** without Sync Now actions, using two independent catalogues sequentially on one Mac and the CloudKit Development smoke run `20261110vn8auto`. Client B first received a cover-only book and opened pages 4/5. Client A returned without force-enable/seeding arguments, logged the saved-preference `appOpened` checkpoint, recovered from a record-version conflict through awaited retry 2, and displayed/opened pages 8/9.

See [AUTO_DEVELOPMENT_SMOKE.md](AUTO_DEVELOPMENT_SMOKE.md) for UTC timing, native-versus-log attribution, filtered logs and source-stage limits. Native app activation and close/open duplicate events coalesced as expected; busy activation events produced one follow-up. This is **one Mac with two Development catalogues**, not two physical devices or Production.

Automatic Build 8 physical iPad/Mac Production verification remains distinct from this result and from the separately completed Build 7 manual Production round trip. The later native title/share fixes and scoped Mac UI checks are now passed; untested native interaction cases remain explicitly listed in `MAC_NATIVE_TOOLBAR.md`. The affected iPad 05/08 rerun now passes 2/2; its earlier 3/4 integration attempt and unusually slow background/relaunch timing remain in the record rather than being relabeled as a passing run. The final source/local-QA snapshot is coordinated by the root agent; no new Release archive/upload is implied.

For subsequent testing, keep explicit isolated DEBUG smoke arguments. Reason/count/error-code diagnostics contain no record/account identifiers or payloads. Test app reactivation, book opening/closing and saved-preference relaunch without force-enabling sync on every launch; distinguish catalogue updates from the active-reader no-jump policy. Do not infer exact delivery latency or large-library behavior from this small guide.

No archive/export/upload was performed for this change. Retained Build 8 v1/v2 release artifacts remain stale and must be rebuilt after final verification and release authorization.
