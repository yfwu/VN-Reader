# Build, test and install

Everything below runs on a Mac with **Xcode 16 or newer** (the project uses Xcode 16's
folder-synchronised groups, `objectVersion = 77`). CI uses the newest non-beta Xcode on
GitHub's `macos-15` runner — see `docs/TEST_REPORT.md` for the exact version used.
No package manager, no project generator: open `VNReader.xcodeproj` directly.

| Item | Value |
|---|---|
| Bundle ID (default) | `org.yfwu.VNReader` (change via `VN_BUNDLE_ID`) |
| Version / build | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `Config/Base.xcconfig` |
| Minimum OS | iPadOS 18.0 |
| Devices | iPad (`TARGETED_DEVICE_FAMILY = 2`) |
| Scheme | `VNReader` (app + UI tests) ; `ComicCore` (package tests) |

## 0. Get the code

```bash
git clone https://github.com/yfwu/VN-Reader.git
cd VN-Reader
```

## 1. Unit tests (no simulator needed)

```bash
cd Packages/ComicCore && swift test
```

This also works on Linux (Swift 6.0+, `zlib1g-dev`). To run the same tests on an iPad simulator:

```bash
scripts/test-core.sh "iPad mini (A17 Pro)"
```

## 2. Simulator

```bash
scripts/build-sim.sh "iPad mini (A17 Pro)"
```

Or open `VNReader.xcodeproj`, choose the **VNReader** scheme and an iPad simulator, press ⌘R.
The simulator needs no signing. To try the app with sample books, edit the scheme
(Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments) and add `-ui-testing -seed-samples`.

UI tests (also export screenshots to `artifacts/ui/attachments`):

```bash
scripts/ci/simulators.sh            # creates "VN iPad mini 6" and "VN iPad Pro 13", prints UDIDs
scripts/test-ui.sh <UDID> artifacts/ui
```

## 3. Your own iPad with a free Personal Team

Works without the paid program; limits: the app expires after **7 days** (re-run from
Xcode to renew), at most 3 apps per device, no TestFlight / Ad Hoc IPA export.

1. Xcode ▸ Settings ▸ Accounts ▸ **+** ▸ Apple ID — sign in. A "(Personal Team)" appears.
2. `cp Config/Signing.xcconfig.template Config/Signing.xcconfig` and set
   * `DEVELOPMENT_TEAM` = your team ID (Xcode shows it under Accounts ▸ team ▸ *Team ID*;
     or select the team once in the target's *Signing & Capabilities* tab and copy the value).
   * `VN_BUNDLE_ID` = something unique, e.g. `com.<yourname>.VNReader`
     (a Personal Team cannot use an ID someone else registered).
3. Connect the iPad with USB (or same Wi-Fi after pairing), unlock it, tap **Trust**.
4. On the iPad enable **Settings ▸ Privacy & Security ▸ Developer Mode** (iPadOS asks to restart).
5. In Xcode select the iPad as run destination and press ⌘R.
6. First launch only: on the iPad go to **Settings ▸ General ▸ VPN & Device Management**,
   tap your Apple ID developer profile and **Trust** it, then open VN Reader.

## 4. Paid Apple Developer Program: signed IPA

After joining the program (team ID shown at developer.apple.com ▸ Membership):

1. Xcode ▸ Settings ▸ Accounts: sign in with the account of that team.
2. `Config/Signing.xcconfig`: `DEVELOPMENT_TEAM = <TEAMID>` and the final `VN_BUNDLE_ID`.
3. For **development** or **ad-hoc** IPAs the iPad's UDID must be registered:
   connect it once and run from Xcode (automatic signing registers it), or add it at
   developer.apple.com ▸ Certificates, IDs & Profiles ▸ Devices
   (UDID: Finder ▸ iPad ▸ click the serial number line until "UDID" shows ▸ right-click ▸ Copy).
4. Build and export:

```bash
scripts/archive-and-export.sh development
```

```bash
scripts/archive-and-export.sh ad-hoc
```

```bash
scripts/archive-and-export.sh app-store-connect
```

Output: `build/export-<method>/VNReader.ipa` and `IPA-INFO.txt` (version, bundle ID,
minimum OS, signing identity). `-allowProvisioningUpdates` lets Xcode create the
certificate/profile automatically. Set `BUILD_NUMBER=<n>` to bump the build number.

### Installing the IPA

* **development / ad-hoc** (iPad UDID must be in the profile):
  Finder (macOS 13+) ▸ select the iPad ▸ drag `VNReader.ipa` onto the window; or
  Apple Configurator 2 ▸ Add ▸ Apps; or Xcode ▸ Window ▸ Devices and Simulators ▸ **+** under Installed Apps.
  Developer Mode must be enabled on the iPad for development-signed apps.
* **app-store-connect**: upload with Xcode Organizer (Distribute App) or
  `xcrun altool`/Transporter, then install through **TestFlight** (no UDID needed).

### TestFlight

1. App Store Connect ▸ Apps ▸ **+**: create the app with the bundle ID from
   `Config/Signing.xcconfig`. The record must exist before the first upload.
2. Raise `CURRENT_PROJECT_VERSION` for every upload (or set `BUILD_NUMBER=<n>`); a build
   number can be used only once per version.
3. Archive and upload in one step:

```bash
scripts/archive-and-export.sh testflight
```

4. When processing finishes, add the build to a tester group in the app's TestFlight tab.
   External groups need Test Information and TestFlight App Review for the first build of
   a version, and can then be shared by email invitation or public link.

The app is iPad only, so testers need an iPad on iPadOS 18 or later. Export compliance is
answered by `ITSAppUsesNonExemptEncryption` in `Config/App.xcconfig`, required-reason APIs
are declared in `App/Resources/PrivacyInfo.xcprivacy`, and the privacy policy is
`docs/PRIVACY.md`. Update the manifest when code starts using another covered API.

## 5. Unsigned device build (no account at all)

```bash
scripts/build-unsigned-ipa.sh build/device
```

Produces `VNReader-<version>-<build>-UNSIGNED.ipa`. It proves the app and the C++ unrar
code compile and link for `arm64` iPadOS, but **it cannot be installed** on an iPad — it
must be signed first (sections 3/4). CI uploads this file as an artifact on every push.

## 6. Regenerating test data

```bash
pip install pillow
python3 scripts/fixtures/generate_fixtures.py --rar /path/to/rar --out Packages/ComicCore/Tests/ComicCoreTests/Fixtures
python3 scripts/fixtures/generate_samples.py  --rar /path/to/rar --out App/Resources/Samples
python3 scripts/fixtures/generate_stress.py   --rar /path/to/rar --out /tmp/vn-stress
VN_STRESS_DIR=/tmp/vn-stress swift test -c release -Xswiftc -enable-testing --filter StressTests   # in Packages/ComicCore
```

`rar` must be RARLAB rar **6.x** (7.x can no longer create RAR4). On macOS:
https://www.rarlab.com/rar/rarmacos-arm-624.tar.gz (or x64). On Ubuntu the `rar`
package from multiverse (`rar_6.23-1~22.04.1`) was used for the committed fixtures.

## Security notes

`Config/Signing.xcconfig`, `*.p12`, `*.mobileprovision` and `*.cer` are git-ignored.
Never commit certificates, private keys or passwords; automatic signing keeps them in your
login keychain / Xcode account.
