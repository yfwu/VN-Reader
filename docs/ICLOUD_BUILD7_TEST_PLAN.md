# Build 7 iCloud prototype: validation and release gates

Build 6 is the separately released safety/Catalyst build. Build 7 adds optional
CloudKit sync; it must not be called production-verified based on compilation or
merge tests alone.

## Current validation status (2026-11-10)

- iOS Simulator and Mac Catalyst compile successfully. Signed Release archives
  are available for iPad arm64 and Catalyst arm64/x86_64, version 0.1.0 (7); both
  signatures verify and include the registered container and development push.
  Archive signing uses Development; both local distribution exports were verified
  with Production CloudKit and push entitlements, debugging disabled, and valid
  signatures. See [export verification](test-results/build-7/production-export-verification.json).
  Both Internal TestFlight prototype uploads succeeded. App Store Connect showed
  Ready to Submit and the Internal group with 2 testers on both platforms.
- Core merge/migration tests and an independent 21-check offline coordinator
  harness pass. The harness covers durable providers, coalesced progress edits,
  metadata edits made while an editor is open, reader leases, persistence failure
  and fractional date save/reload. It does not exercise Apple's transport.
- The live Development smoke confirms upload from macA and a cover-only receipt
  in independently initialized macB on the same Mac. Opening on macB downloads
  and renders the guide; progress reached page 4 of 12 and manual sync completed.
  See [durable smoke evidence](test-results/build-7/LIVE_SMOKE.md). Progress
  returned to macA (page 4), and a subsequent page 5 change reached macB. A
  startup record conflict exposed a stale failure status; the bounded retry fix
  reproduced that conflict and completed successfully in the final live rerun.
  Remove Download retained the cover and page 6 progress. A second download was
  started, but its rendering was not observed before the Mac locked. The initial
  macB download/read passed. This is not a physical Mac+iPad test.
- The Book/BookFile schema was deployed to Production on 2026-11-10. Physical
  Mac+iPad validation and TestFlight sync verification remain gates for wider
  testing or public release; the Internal TestFlight prototype is already uploaded.
  A signed build alone is not evidence that any record reached iCloud.

## Implemented scope

- Explicit opt-in; default offline. Current Apple ID is bound to the local sync
  state. Switching account stops synchronization without deleting local files.
- `Library` zone: one Book record per SHA-256 archive revision, stamped field-level
  metadata/favourite/direction, grouped progress and per-page bookmark tombstones.
  Fit/layout remain device-local. Cover and manifest are separate lightweight assets.
- `BookFiles` zone: immutable archive CKAsset records, excluded from **all** engine
  fetches. New devices get cover-only books. Opening downloads, verifies SHA-256
  and manifest indexes against archive entries, then atomically exposes the archive.
- Uploads are serialized with persisted long-lived operation IDs. Reopening checks
  both operation state and immutable remote identity; concurrent identical uploads
  are reconciled. Book transfers disallow cellular access.
- Remove Download checks the current account, remote content ID and byte size,
  active transfers and per-reader leases. It preserves metadata/cover/manifest.
- No remote delete or automatic trash purge in this prototype. Synced originals
  stay in iCloud; the UI does not expose destructive cloud deletion.
- Local schema 2 accepts schema 1 and preserves `library.before-v2.json` before its
  first v2 write. Build 6 rejects schema 2 rather than stripping sync fields.
- Received data is durably saved before engine tokens. Pending coalesced edits are
  stamped before merge. Upload providers read the last durable library snapshot.

## Migration and rollback

Schema migration happens when build 7 first saves the normal local library, even
if iCloud is still off. The byte-identical pre-migration snapshot is preserved
before any v2 write. A failed backup or library write aborts the save; records are
not silently discarded. New imports and edits made after that snapshot are not
part of the old snapshot. Archive files and book folders are not pruned by this
migration.

Build 6 intentionally refuses a v2 library and leaves it untouched. Returning to
build 6 requires a deliberate backup and restoration of the pre-v2 snapshot;
blindly restoring it would hide later imports and edits from the catalogue. Do
not change the schema number by hand. DEBUG smoke uses its own local roots and
never migrates the user's normal library.

## Isolated DEBUG smoke environment

Use the same run ID on participating devices, and a distinct client name for each
local test library. These flags do not exist in Release behavior.

```
-sync-smoke-test 20261110vn7
-sync-smoke-client macA
-sync-smoke-enable
-sync-smoke-seed-guide
```

The seed flag imports the app's bundled synthetic guide, requiring no access to
files outside the app sandbox. For multiple CBZ/CBR fixtures, import them through
the Mac document picker; `-seed-samples /absolute/path/to/UITests/Samples` is only
reliable on a simulator. Run client `macB` without any seed flag. The run uses only
`Smoke-20261110vn7-Library` and `Smoke-20261110vn7-BookFiles` zones and isolated sync
preferences. Its local data resides under the app's normal Application Support
parent at `VNReader/SyncSmoke/20261110vn7/<client>/`. `smoke-events.log` records sync
status and counts; the same diagnostics go to stderr in smoke mode and can be
captured with `open --stderr /private/tmp/vn-smoke-macA.log … --args …`. No book
names or account IDs are logged. The normal library is not read, deleted, or uploaded. The
standard `-ui-testing` destructive reset hook is bypassed in smoke mode.

Use the developer-signed DEBUG Catalyst app and a signed-in iCloud account.
A local second client proves independent local state and a real server round trip,
but it is not a substitute for eventual physical Mac+iPad tests.

## Required real-service checks

1. macA imports only synthetic fixture comics. Confirm metadata and archives appear
   in the isolated development zones; compare SHA-256.
2. macB/simulator receives cover, manifest, metadata and progress **without** archive.
3. Open one remote-only book. Confirm downloaded SHA-256 equals the original,
   actual pages render, and all other books remain cover-only.
4. Edit distinct fields on both clients offline, reconnect and confirm both survive.
   Set then remove a bookmark, and reset progress; stale values must not return.
5. Remove a verified download, reopen and redownload; test while another reader
   lease exists and during an upload. These operations must preserve the last copy.
6. Quit and reopen during transfer; test Wi-Fi interruption and failed local writes.
   Verify local files remain available and status never reports success on errors.
7. Test no account/account change/quota exhaustion on dedicated devices/accounts.
8. Test a 20–30 GB synthetic library plus large individual files on real hardware.

## TestFlight preparation

- Container: `iCloud.org.yfwu.VNReader`, assigned to `org.yfwu.VNReader`.
- iOS CloudKit + push; Catalyst adds sandbox outgoing networking and user-selected
  file access. UIBackgroundModes contains remote-notification.
- Build 7 must use Production iCloud environment when exported for TestFlight.
  The following schemas were deployed from Development to Production on 2026-11-10:
  `Book` (`payload`: Bytes, `manifest`: Asset, `cover`: Asset) and `BookFile`
  (`contentID`: String, `size`: Int64, `archive`: Asset). The app looks up record IDs
  and zone changes directly, so the deployed query indexes are not used by this
  prototype. The exact Console export is [CloudKit.schema.ckdb](../Config/CloudKit.schema.ckdb).
  Book and BookFile grant only `_creator` WRITE; their default `_world` READ and
  `_icloud` CREATE grants were removed. The Users type was left unchanged.
  The app itself accesses only the private database. Deployment does not prove
  the exported TestFlight app can synchronize in Production.
- The local exported apps' signed entitlements were verified to contain the intended
  container, Production iCloud environment and distribution push environment, with
  debugging disabled and signatures verified. Evidence is retained in
  [production-export-verification.json](test-results/build-7/production-export-verification.json).
  Keep the iOS
  and Catalyst bundle identity/container assignment consistent. Merely setting a
  Debug xcconfig or using an archive is insufficient.
- Do not deploy smoke records themselves or claim development-zone results prove
  Production sync. Retest with TestFlight on distinct devices before wider testing.
- Schema 2 is a forward migration. To return to build 6, restore the preserved
  pre-v2 snapshot deliberately; do not relabel the schema number or discard stamps.

## Known prototype boundaries

The first prototype keeps progress and metadata in the same logical Book payload;
progress-only record separation and larger-library performance remain future work.
There is no WebDAV, automatic eviction, export/restore UI, cloud trash, multi-account
library switch UI, or promised byte-range continuation of arbitrary-size CKAssets.
A persistent local-state/validation failure halts synchronization; local files stay
intact and the UI asks for diagnosis/restart rather than silently skipping records.

## Build 8 delivery hold and cross-device progress acceptance

The owner explicitly requested that build 8 wait for reading-progress sync testing.
Do not upload or deliver it merely because local builds pass. The Mac local Debug
preview uses CloudKit Development; both physical test devices must use TestFlight
build 7 (Production), the same Apple account, and identical comic bytes for a valid
Production comparison. The updated build 8 guide has a different content hash from
the build 7 guide; do not use those two different revisions as one test book.

Use a small synthetic comic. Enabling sync uploads the current local library, so
confirm the intended test library first. For each case record device, build,
network state, starting and resulting logical page, visible sync status and whether
the app/reader was already open. Do not count a locally displayed page as proof of
server synchronization.

1. Mac reads page 4, returns to Library and completes Sync Now. iPad syncs, opens
   the same book and must resume page 4 without downloading unrelated books.
2. iPad reads page 8, returns and syncs. Relaunch Mac, sync and open: page 8 must
   appear. Repeating the exchange must not reset progress.
3. Repeat while immediately opening the stale copy after relaunch, and while the
   reader remains open in the background on the receiving device. Record behavior
   separately; it must not silently upload the old position over the newer one.
4. Read offline, quit/reopen, then reconnect and sync. The other device must receive
   the completed local progress update. Test concurrent distinct positions and
   verify a deterministic result without recurring back-and-forth changes.
5. Repeat with a two-page spread and an already-wide image. Switching Mac layout
   or showing/hiding its controls must not count as reading a different logical page.
6. Remove a local download and reopen. Cover, progress and bookmarks must survive;
   the downloaded bytes must identify the same book.

Status: physical iPad was unavailable to developer tools at the latest check.
The existing same-Mac Development smoke is useful transport evidence, but does
not satisfy this distinct-device Production gate.
