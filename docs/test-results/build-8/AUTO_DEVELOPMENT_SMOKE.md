# Build 8 automatic sync — same-Mac Development round trip

The root coordinator observed this sequence through native Mac UI and verified the explicit smoke launches. The supporting logs were independently read and copied as filtered, durable evidence. This is **one Mac, two isolated local catalogues, sequential clients, CloudKit Development**. It is not two physical devices, TestFlight, or Production.

## Scope and source stage

- DEBUG smoke run `20261110vn8auto`, clients `macA` and `macB`, with independent library directories/preferences and shared smoke CloudKit zones. Synthetic bundled-guide content only.
- Automatic-sync code was frozen with 17 scheduler, 37 reader-model, 21 coordinator and 20 layout checks. This native run predates the final subsequent Library/Reader glass appearance and final UI QA. Do not treat it as verification of a later release archive.
- The existing imported guide has content-ID prefix `1fc298…`. The subsequently regenerated bundled guide has a different content-ID prefix, `9267…`; regeneration does not replace an already imported book. The round trip concerns the existing test book, not the newer bundle's bytes.
- Client B's first launch enabled sync once and did not seed a local guide. Client A's return launch omitted both force-enable and seeding arguments, allowing its saved preference and normal `appOpened` automatic path to be exercised.
- No Sync Now action was used to drive this automatic round trip. First-run opt-in/initial enable is distinct from a recurring manual sync checkpoint.

## Observed sequence (UTC)

| Stage | Log evidence | Native UI observation reported by the coordinator |
| --- | --- | --- |
| A reads human page 4 and closes | Engine saved one record at 15:29:57 and 15:30:01; book-close automatic cycle 15:30:04–15:30:06 completes | A navigated to page 4, then returned to library |
| B starts with an empty catalogue | 15:32:22 starts with zero books; 15:32:25 fetch modifies one record and completes with one book | A cover-only guide appears at page 4; opening downloads/renders pages 4 and 5 |
| B reads human page 8 and closes | Engine saved one record at 15:36:29 and 15:36:36; book-close automatic cycle 15:36:40–15:36:41 completes | B navigated to page 8 and returned to library |
| A returns without force-enable/seeding | `appOpened` debounce at 15:38:57; automatic cycle 15:38:58–15:39:01 | Library displays page 8; opening renders pages 8 and 9 |
| A resolves a concurrent record version | At 15:39:00: saved=0, failed=1, CKError 14; awaited resolved-conflict retry attempt 2; at 15:39:01 saved=1, failed=0, then completed | Final visible position remains page 8 |

The record-save log counts do not contain page payloads. Page assertions above come from the coordinator's UI observations, while timing, request origin, successful sends and conflict handling come from the retained logs. The return fetch event is logged after the explicit cycle completion in the same second; a completed status alone is not used as the proof of displayed progress.

## Trigger/coalescing observations

- At 15:17:39, A logged two `appActive` requests but only one subsequent explicit cycle, completing at 15:17:44.
- At 15:21:35, A's `bookClosed` and `bookOpened` requests merged into one cycle at 15:21:36–15:21:37.
- At 15:36:13, B received duplicate activation/reader-foreground requests during a busy cycle. They produced one pending follow-up, which ran 15:36:15–15:36:16 and ended with `followUp=false`.
- In these snapshots, explicit cycles are bounded and do not overlap: A initial log 8 starts/8 finishes, B 5/5, A return 2/2, maximum one active explicit cycle in each log. Background CKSyncEngine saves can occur outside these explicit checkpoints; those are not incorrectly counted as parallel coordinator cycles.

## Durable evidence

- [A initial session](auto-development-macA.txt)
- [B fresh catalogue and return send](auto-development-macB.txt)
- [A saved-preference return and conflict retry](auto-development-macA-return.txt)

Each file retains only `SyncSmoke` status, reason, counts and error-code lines, with the original log's SHA-256. No account identifiers, tokens or record payloads are copied.

## Limits

This establishes an automatic **A page 4 → B page 4 → A page 8** round trip between isolated Development clients on one Mac, including cover-only first receipt and conflict recovery. Build 7's separate physical Mac+iPad Production manual round trip is recorded in `PHYSICAL_PRODUCTION_SYNC.md`; neither result substitutes for the other.

Still distinct: automatic Build 8 physical iPad/Mac Production delivery, cold-open timing on signed release devices, large-file/upload latency, offline interruptions, account switching, and final changed-UI validation. A checkpoint may wait behind an in-flight archive upload. The final source and release artifacts were not frozen/rebuilt or uploaded as part of this evidence update.
