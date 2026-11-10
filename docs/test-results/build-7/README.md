# Build 7 source and release artifacts

Recorded 2026-11-10 for **VN Reader 0.1.0 (7)**, bundle ID `org.yfwu.VNReader`,
App Store Connect app `6831459455`. This is the iCloud prototype on branch
`codex/build-7-icloud`. The durable source root is
`/Users/yfwu/Developer/VN-Reader/.worktrees/build-7`; commands and paths below are
relative to that root, not the parent build 6 checkout.

Both final `v2` upload logs report `Upload succeeded.` and `EXPORT SUCCEEDED`.
App Store Connect subsequently showed **Ready to Submit** on both platforms,
with the **Internal** group and **2 testers**. Platform IDs and direct links are
recorded in [app-store-connect.json](app-store-connect.json). This does not establish
a TestFlight installation or physical cross-device synchronization.
Traditional Chinese What to Test notes were saved for both platforms, including
the build 7 downgrade limitation; see [testflight-notes.json](testflight-notes.json).

| Platform | Final archive | Retained local export | Upload log |
|---|---|---|---|
| iPad, arm64 | `build/release-7-ios-v2/VNReader.xcarchive` | `build/release-7-ios-v2/local-export/VNReader.ipa` | `build/release-7-ios-v2/upload.log` |
| Mac Catalyst, arm64/x86_64 | `build/release-7-mac-v2/VNReader.xcarchive` | `build/release-7-mac-v2/local-export/VNReader.pkg` | `build/release-7-mac-v2/upload.log` |

## Identity and preservation

- [provenance.json](provenance.json) records the source root, Git base, snapshot
  hash, platform artifacts, upload evidence, and export-verification results.
- [source-inputs.sha256](source-inputs.sha256) identifies **319 files**: app,
  resources, package, project, configuration, tests, and build tools.
- The earlier [source-sha256.json](source-sha256.json) has **300 entries**; all
  matched the working tree when this snapshot was created. It is preserved as
  separate evidence, rather than being replaced by the expanded manifest.
- The source ZIP is `build/release-7-provenance/source-inputs.zip`. Every entry
  was read back and compared with its source SHA-256 after creation.
- [artifact-files.sha256](artifact-files.sha256) identifies the final archives,
  local IPA/PKG exports, export/upload logs and settings, source ZIP, and original
  archive/export verification records.
- Each `build/release-7-*-v2/archive.log` preserves the original archive command
  and output, copied from temporary storage. Retain the complete `v2` directories
  and source ZIP when moving or cleaning this checkout.

The source snapshot was captured at **2026-11-10 10:20:37 UTC**. Its frozen scope
is the 319 source/resource/configuration/test/build-tool files in the manifest;
release documentation is not included and can be updated as upload/ASC evidence
arrives without changing that snapshot.

The Git base is `8af02b690cafb117b5e840d0a10a874e3b170fc3`; this release has
**uncommitted source changes** and no new release commit. A checkout of that commit
alone cannot reproduce the release. The ZIP was created after the archives from
the frozen source. Its digest identifies those saved bytes; it is **not a
build-time attestation** or proof of deterministic compiler output. Rebuilt binary
signatures, timestamps, and UUIDs may differ.

The ZIP excludes Git metadata, `Config/Signing.xcconfig`, keys/certificates/profiles,
Xcode user state, the unrelated `sudo` file, generated build output, logs, release documentation, and
private user data. It contains the signing template and CloudKit schema source.
The preserved signed packages naturally contain their public provisioning data;
only artifact hashes and verification summaries are indexed in documentation.

Verify from the build 7 root:

```bash
shasum -a 256 -c docs/test-results/build-7/source-inputs.sha256
shasum -a 256 -c docs/test-results/build-7/artifact-files.sha256
```

The source check is expected to fail after later source edits. To inspect the
saved version, extract the ZIP into a new empty directory and run the source
check there using the manifest's absolute path. Do not unpack over the active
working tree. Private signing configuration must be supplied independently.

## Archive versus distribution configuration

The final archives were built using **Xcode 27.2 (27B52)**. They are development
signed and their archive CloudKit environment is **Development**, as recorded in
[release-v2-archives.json](release-v2-archives.json).

The distribution export explicitly selects `iCloudContainerEnvironment=Production`.
Both retained local exports were inspected and their signatures verified:

- Version/build: `0.1.0 (7)`; bundle ID: `org.yfwu.VNReader`.
- CloudKit environment: `Production`; container: `iCloud.org.yfwu.VNReader`.
- Push environment: `production`; debugging: disabled.

Evidence: [production-export-verification.json](production-export-verification.json).
Correct signed entitlements do not by themselves prove Production CloudKit operations
succeed. The Book/BookFile schema was separately deployed to Production on 2026-11-10,
and the exported definition is saved in
[CloudKit.schema.ckdb](../../../Config/CloudKit.schema.ckdb). Production runtime
behavior remains a separate check.
The uploaded package is generated by Xcode's upload export from the final archive
using the recorded upload options; the retained local export is a separately
generated verification artifact and is not asserted byte-identical to that upload.

To rebuild and export locally from the saved source, choose fresh output paths:

```bash
BUILD_NUMBER=7 scripts/archive-and-export.sh app-store-connect build/rebuild-7-ios ios
BUILD_NUMBER=7 scripts/archive-and-export.sh app-store-connect build/rebuild-7-mac catalyst
```

Do not re-upload build 7: both platform upload numbers have already been used.
Future uploads require an unused build number. Older non-`v2` archives predate the
final conflict-status fix and are not substitutes for the uploaded artifacts.

## Test evidence and limits

| Evidence | Result |
|---|---|
| [core.txt](core.txt) | 92 total: 90 passed, 2 opt-in stress skips, no failures |
| [app-persistence.txt](app-persistence.txt) | 12 actual app-model persistence checks passed |
| [offline-sync.txt](offline-sync.txt) | 21 actual coordinator/model checks passed without a live backend |
| [LIVE_SMOKE.md](LIVE_SMOKE.md) and linked diagnostic logs | Real Development CloudKit round trip, cover-only receipt, initial download/read, returned progress, and awaited conflict recovery |

The live smoke used synthetic guide data and two isolated catalogues on one Mac,
run sequentially. It is not a two-device or Production test. The final live rerun
reproduced the record conflict, awaited a second send, and completed successfully;
page 6 progress was observed. Removing its download retained the cover and progress.
The subsequent re-download started, but the machine locked before page rendering
was observed, so re-download-and-resume completion remains unverified.

Outstanding checks include TestFlight installation and tester availability,
Production runtime verification, a physical iPad and Mac pair, account
switching, interruption/quota/network failures, offline conflicts, background push,
and 20–30 GB library behavior. These limits are retained in
[ICLOUD_BUILD7_TEST_PLAN.md](../../ICLOUD_BUILD7_TEST_PLAN.md) and
[TEST_REPORT.md](../../TEST_REPORT.md).
