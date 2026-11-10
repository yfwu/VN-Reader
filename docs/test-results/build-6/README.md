# Build 6 release provenance

Recorded 2026-11-10 for **VN Reader 0.1.0 (6)**, bundle ID `org.yfwu.VNReader`,
App Store Connect app `6831459455`. Build 6 is the offline repair release for iPad
and Mac Catalyst. iCloud development is separate build 7 work.

Both upload logs end in `Upload succeeded.` and `EXPORT SUCCEEDED`. The root release
agent subsequently observed **Ready to Submit** on both platform build pages in
the authenticated App Store Connect browser, with the **Internal** group and
**2 testers**. No current TestFlight installation on a physical iPad or Mac has
been verified. This record does not claim App Store approval or public release.

| Platform | ASC build ID | Archive | Upload completed (Asia/Taipei) |
|---|---|---|---|
| iPad, arm64 | `c766b5d3-08b0-4dff-b31f-d986517726eb` | `build/release-6-ios-v2/VNReader.xcarchive` | 2026-11-10 15:41 |
| Mac Catalyst, arm64/x86_64 | `499d8b96-f6fa-4aca-9f0d-521505253a22` | `build/release-6-mac-v2/VNReader.xcarchive` | 2026-11-10 17:57 |

## Source and artifact identity

- [provenance.json](provenance.json) records version, platform, SDK, archive paths,
  build IDs, environment, and the source snapshot digest.
- [source-inputs.sha256](source-inputs.sha256) covers 305 app, package, resource,
  configuration, project, test, and build-tool files.
- [artifact-files.sha256](artifact-files.sha256) covers the two final archives,
  their archive/upload logs and export options, plus the compressed source snapshot.
- The local source snapshot is `build/release-6-provenance/source-inputs.tar.gz`.
  It is intentionally outside Git, alongside the archives. Preserve these local
  artifacts when moving or cleaning the checkout.
- Test evidence is [core.txt](core.txt), [app-persistence.txt](app-persistence.txt),
  and [ui-summary.txt](ui-summary.txt); the current interpretation is in
  [TEST_REPORT.md](../../TEST_REPORT.md).

The Git base is `8af02b690cafb117b5e840d0a10a874e3b170fc3`, with **uncommitted
changes**. No release commit was created. The snapshot was captured after upload
from the source frozen for the final archives; it is not a build-time attestation.
The base commit by itself does not reconstruct this release. The snapshot excludes
`Config/Signing.xcconfig`, signing certificates/profiles, Xcode user state, build
output, and unrelated untracked files. Archive hashes identify the preserved signed
binaries; a rebuild can produce different signatures, timestamps, and UUIDs.

The archives and direct-upload logs are retained under each `build/release-6-*-v2/`
directory. Direct upload did not retain a separate exported IPA/PKG in these
directories. Older non-`v2` archives are intermediate artifacts and must not be
substituted for the uploaded release.

From the repository root, verify the recorded files:

```bash
shasum -a 256 -c docs/test-results/build-6/source-inputs.sha256
shasum -a 256 -c docs/test-results/build-6/artifact-files.sha256
```

Source checks will deliberately fail if the working tree has moved on. To inspect
the frozen source without replacing the checkout, unpack the snapshot into a new,
empty directory and verify `source-inputs.sha256` from there using its absolute path.
The snapshot includes all listed source inputs and the signing **template**, but
requires an independently configured developer account for a signed rebuild.

## Rebuild and local export

Original archives used **Xcode 27.2 (27B52)** on **macOS 27.2 (26B123)**.
Deployment minimums are iPadOS 18.0 and macOS 15.0. The exact original archive
invocations are preserved at the start of each platform's `archive.log`.

For a rebuild, first restore/verify the source snapshot. Choose a new output
directory and use the existing release script, which refuses to replace an archive:

```bash
BUILD_NUMBER=6 scripts/archive-and-export.sh app-store-connect build/rebuild-6-ios ios
BUILD_NUMBER=6 scripts/archive-and-export.sh app-store-connect build/rebuild-6-mac catalyst
```

These commands export locally. Do not re-upload build 6: both platform numbers
are already used. A future upload needs an unused build number. The final upload
options in the existing artifacts specify `destination=upload`,
`manageAppVersionAndBuildNumber=false`, automatic signing, and the app's team.
No passwords, keys, or signing credentials are stored in this index.

## Verification limits

The core suite passed 77 tests with 2 opt-in skips; the app persistence harness
passed 12 checks. The iPad UI full run passed 14/15, then both targeted progress
and final-menu checks passed after correcting a stale accessibility assertion.
The original full run remains recorded as failed rather than being rewritten as
an all-green run.

Mac smoke testing used an isolated app identity/library. It covered comic import,
cover/page rendering, navigation, progress, and the corrected compact book menu.
Three original CBZ/CBR fixtures remained byte-identical. File → Import Comics
opened the picker; Cmd-O was registered but did not respond during automated
keyboard testing. The final Mac archive's signature validation passed. Its only
app entitlements are App Sandbox and user-selected file read/write access, with
no CloudKit entitlement. Physical-device regression and real TestFlight
installation remain pending.
