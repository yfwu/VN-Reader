# Build 7 live CloudKit development smoke

Date: 2026-11-10. Environment: development-signed Mac Catalyst, CloudKit private
database in `iCloud.org.yfwu.VNReader`, zones `Smoke-20261110vn7-Library` and
`Smoke-20261110vn7-BookFiles`. Tests used the bundled synthetic user guide only.

Fixture size: 948070 bytes. SHA-256: `0909c3e7bf66b9618a94525406cddf6599a7dd75d768534421380d7bd60bc466`.
This is the expected content ID; an independent downloaded-file comparison remains
unperformed because the app sandbox was not read through filesystem tools.

macA and macB were separate local catalogues/preferences on the **same Mac**, run
sequentially with distinct `-sync-smoke-client` values. macB had no seed flag.
This exercises a real CloudKit server round trip, not distinct physical devices,
Production, TestFlight, or simultaneous background push delivery.

| Time (UTC) | Observation | Evidence |
|---|---|---|
| 09:56:42–09:56:50 | macA starts with 0 books, imports the bundled guide, hashes it, uploads and reports complete with 1 book. | `smoke-macA.txt` |
| 09:57:33–09:57:36 | Unseeded macB starts with 0 books and finishes sync with 1 book. | `smoke-macB.txt` |
| After initial sync | Root agent observed the actual cover and accessibility label “Cover only · download to read”. | Live CUA observation reported by root; no standalone screenshot retained here. |
| On opening | Guide downloads and renders page 1. Arrow navigation reaches page 4; Escape returns to the library showing page 4 of 12 and no cover-only label. | Live CUA observation; successful opening passed the app's SHA-256/archive-manifest verification path. No independent filesystem hash comparison was performed. |
| 09:59:42–09:59:44 | macB manual sync completes after reading. | `smoke-macB.txt` |
| 10:03:44–10:03:47 | Restarted macA displays the returned page 4 progress, but the initial send reports a failure. Manual sync at 10:05:50–10:05:52 succeeds. | Root live CUA observation; receive succeeded despite the send status. |
| 10:09:24–10:09:28 | After macA advances to page 5, macB receives it. Diagnostic restart reports a record conflict (`CKErrorDomain:14` inside partial failure `:2`), then the engine automatically saves successfully while the UI still shows failure. | `smoke-conflict-before-fix.txt` |
| 10:13:35–10:13:37 | Final fix reproduces a record conflict, performs awaited retry attempt 2, saves successfully and reports completed without a failure status. | `smoke-conflict-after-fix.txt` |
| Final UI check | macA displays page 6. Remove Download changes the book to cover-only while retaining page 6 progress. Reopening shows “Downloading comic…”. | Root live CUA observation. The Mac locked before the second download's page rendering was observed, so redownload-and-resume completion is **not** marked passed. |

The stale failure status was traced to a handled server record conflict: the
delegate merged the incoming server state and requeued the record, but the
original `sendChanges()` still threw its aggregate error. The fix awaits a
bounded replacement send only when every error is a record conflict and this
attempt successfully merged one. It allows at most three send attempts; mixed,
unhandled, empty, quota and other errors still fail. The 21-check offline
coordinator audit includes seven checks for this policy. Final live rerun
reproduced the same conflict and passed with
`retry resolved-conflict attempt=2`, `sent saved=1 failed=0`, then completion.
The earlier failed-status run is retained as regression evidence.

Other outstanding checks include distinct physical Mac+iPad devices, offline
conflicts, account changes, quota/network failures, interrupted uploads,
redownload-and-resume completion, 20–30 GB scale, and Production/TestFlight
behavior. The first download and reading on macB passed; these are separate from
the interrupted observation of the second download on macA.

No normal user library was uploaded or reset. The smoke flags isolate local
roots and CloudKit zones; stderr diagnostics include status, client and book
count and sanitized error codes only. Command-O did not trigger during the separate Catalyst automation
smoke, while native File → Import Comics opened the picker; keyboard import is
therefore not marked verified.
