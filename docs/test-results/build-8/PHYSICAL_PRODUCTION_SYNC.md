# Physical Production sync — Build 7 observations

Build 8 remains on the user's explicit release hold. This record tests the already-published Build 7 transport; it does not prove that the Build 8 progress correction runs correctly on physical devices.

## Setup observed

- The connected physical iPad reports `org.yfwu.VNReader` version `0.1.0 (7)` through a read-only, bundle-filtered `devicectl` check. The user performed the update. No separate SyncTest app was installed.
- The official Mac App Store installed TestFlight. TestFlight lists VN Reader macOS `0.1.0 (7)` and installed it at `/Applications/VNReader.app`.
- The installed Mac app's signed entitlements explicitly name `iCloud.org.yfwu.VNReader`, `Production`, production push and `get-task-allow=false`.
- The known isolated Development preview was no longer running before opening the TestFlight app. The Mac UI initially showed one book, the bundled bilingual User Guide. No personal comic import, app removal or library reset was performed.
- Mac iCloud sync was enabled for this one-book library; its settings visibly reached **This sync has completed**.
- The user reports the iPad library is small and its sync status has completed.

## Live sequence

1. On Mac, opened the User Guide, navigated to the spread starting at human page 4, and returned to the library. Both the Continue Reading control and book row visibly showed page 4 of 12.
2. Pressed Sync Now. Observed the transient syncing state followed by **This sync has completed** and the button re-enabling.
3. The user confirmed that the iPad displayed page 4, then navigated to page 8 and pressed Sync. This receiving-side observation is user-reported, not a remotely captured iPad screen.
4. The first subsequent Mac manual sync completed but still displayed page 4. A full Mac app termination/relaunch and its startup sync also initially showed page 4. No Mac reader was opened between sending page 4 and receiving page 8.
5. A read-only, app-scoped `devicectl` snapshot verified that the iPad's local book and sync progress register both held zero-based page 7 (human page 8), saved at `2026-11-10T14:31:21Z`. Its cached server record modification date was `14:35:15.527Z`, and its last saved fetch date was `14:35:17.122Z`. Private serialized engine state appeared to contain zero pending/in-flight records; these internals are diagnostic hints, not a documented server-delivery guarantee. Raw account identifiers/tokens are not included in this repository.
6. After another Mac manual synchronization at approximately `14:38:13Z`, the library and Continue Reading control visibly displayed page 8 of 12. Opening the book then rendered **Page 8 and Page 9**, accessibility ID `reader.page.7`. Returning to the library retained page 8.

The basic round trip is observed: **Mac page 4 → iPad page 4 → Mac page 8**, using the published Build 7. Reverse delivery was delayed across completed rounds; this session does not establish an exact transport latency because sender button/completion timings were not instrumented. The failure to see page 8 in an earlier round must not be erased from the record. No confirmed coordinator defect was inferred from that latency alone.

Post-page-8 process restart also retained page 8 in the library. Native Quit attempts were confounded by a subsequent reopen/activation request cancelling deferred termination; an app-specific process sample showed a normal event-loop main thread rather than a demonstrated app hang. The test therefore used SIGTERM on the verified test process and relaunched `/Applications/VNReader.app`. This is a termination/relaunch durability check, not evidence of normal Quit behavior.

Cover-only removal/redownload then passed through the native UI:

1. Chose **Remove Download** on the test guide. Earlier accessibility menu-action attempts were interrupted/timed out; the observed selection followed by Return activated the command successfully.
2. The library visibly showed **Cover only · download to read** alongside **Page 8 of 12**, while retaining the cover and Continue Reading position.
3. Opened the guide. Observed **Downloading comic…**, then the actual reader rendered **Page 8 and Page 9**, accessibility ID `reader.page.7`.

This verifies a small Production asset redownload and retained logical progress on Mac. It does not establish large-file interruption/recovery behavior.

## Limits and remaining checks

- A completed sync status on one client alone is not evidence that the other device received its progress. This session separately observed/reported both directions and a Mac reader reopen; later automatic-sync behavior and a cold-launch race remain distinct tests.
- Build 7 retains the passive-opening progress-write race documented in `READING_PROGRESS.md`. This initial happy-path deliberately finishes receiving sync before opening the book. It does not test cold opening during an in-flight fetch.
- A protected-container file read was denied by macOS, so no local guide-content hash or stored progress was obtained from that container. The test currently identifies the book by the visible title; duplicate-title/content mismatches must be investigated if they appear.
- Mac cover-only availability, on-demand redownload and retained progress are now observed for this small guide. Foreground timing, offline recovery, account switching and large-library behavior remain unverified by this physical session.
- The user subsequently requested automatic synchronization on app opening/foreground and book switching. That is new Build 8 work; the Build 7 manual-sync result above does not validate it. Build 8 remains unuploaded while this work and verification continue.
