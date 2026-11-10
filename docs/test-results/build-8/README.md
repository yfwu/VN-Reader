# Build 8 release checklist

Goal: deliver one corrected **VN Reader 0.1.0 (8)** for iPad and Mac Catalyst, covering reader UI and synchronization. This is the current release checklist; older evidence stays available for reference and does not need ongoing per-build maintenance.

**Delivered to TestFlight on 2026-11-11 (Asia/Taipei).** Both platforms finished Apple processing and are available to the existing Internal group (2 testers). Build-specific test notes and the beta app description were updated; no new testers were invited.

## Included fixes

- Mac device-local double-page default, preserved vertical layout, standalone original wide pages and stable logical focus across page changes/resizing.
- Native Mac top toolbar, readable title, dedicated bottom controls, working two-image share popover, Select icon, settings/thumbnails and Escape back to library. Comics stay within the reader viewport.
- Passive opening/reflow no longer overwrites remote progress. Explicit navigation saves exact focus; completion is separate. Opening recency remains local and does not become a sync edit.
- Enabled iCloud sync automatically runs on app opening/activation and book switching. Rapid requests debounce; busy requests retain one follow-up. Reading never waits for network; Sync Now remains a manual retry.
- Correct vertical cached/late image sizing and progress intent. Updated bilingual guide and all four UI languages.

## Verified

- [Reader models](reader-progress-after-auto.txt) **37/37**, [automatic scheduler](automatic-sync.txt) **17/17**, [coordinator](cloud-sync-after-auto.txt) **21/21**, [layout](reader-layout-after-auto.txt) **20/20**, [UIKit/controller/geometry](reader-spreads.txt) **56/56**.
- [Latest iPad background/relaunch + vertical tests](ipad-native-final.txt): **2/2 passed**, 79.957 seconds. Two SwiftUI runtime warnings remain. The earlier 3/4 run with a swipe-synthesis timeout is retained, not relabeled as a passing run.
- [Final signed Mac Debug build](mac-native-final-v2-build.txt) succeeded. [Native UI checks](MAC_NATIVE_TOOLBAR.md) verified readable toolbar, complete pages 8/9, two-image share popover, jump/cancel, hidden controls/Escape and retained page 8. Select/settings/thumbnails passed before the final bar/share-only adjustment.
- [Physical Mac+iPad Production test on published version 7](PHYSICAL_PRODUCTION_SYNC.md): page **4 → 4 → 8**, Mac restart and cover-only redownload preserve progress. Reverse delivery was delayed; this used manual sync.
- [Version 8 automatic Development test](AUTO_DEVELOPMENT_SMOKE.md): page **4 → 4 → 8** between two isolated catalogues on one Mac, without Sync Now driving the sequence; startup, activation, book switching and conflict recovery observed.
- Localization **233 keys** passed. Final ReaderScreen hash: `a94bdbd00d5eec024bcc449a37381f09c8b0fa96c1817aea26b650b59d3a2193`. Bundled guide matches the signed Debug product: `9267179470f3c5c0b381cf22335535e1cfb534fdb0eec57839c3c39930461f12`.

## Limits to retain

Automatic version 8 physical Production delivery, cold-open races on physical release devices, large libraries/uploads, interruption/account-switch recovery, narrow/white reader layouts, complete zoom/RTL/slider interactions and older-OS appearance are not established by these tests. Large uploads can delay the next metadata checkpoint. Active Mac readers need not jump when the catalogue updates. Back works but appears in the right-hand toolbar group on this Catalyst runtime.

Apple's [standard icon guidance](https://developer.apple.com/jp/design/human-interface-guidelines/icons) lists `checkmark.circle` for Select; this is a documented option, not a claim that it is the only mandatory choice.

## Delivery

- [x] UI and automatic-sync source fixes; scoped local/native verification.
- [x] Fresh iPad and Mac Catalyst Release archives from this source: `build/release-8-final-ios` and `build/release-8-final-mac`. Older Build 8 archives/exports are stale.
- [x] Exported version/build, Distribution signatures, Production CloudKit/push entitlements and bundled guide verified. Each final artifact directory contains `verification.json` and `upload.log`.
- [x] [iPad TestFlight build 8](https://appstoreconnect.apple.com/teams/cc353b18-d5a9-4c26-bd89-2e83ea77c7c2/apps/6831459455/testflight/ios/002f8981-a25c-47f8-b098-114056f082b9): processed, Internal group assigned, test notes saved.
- [x] [Mac TestFlight build 8](https://appstoreconnect.apple.com/teams/cc353b18-d5a9-4c26-bd89-2e83ea77c7c2/apps/6831459455/testflight/macos/7d787848-e66a-4fb1-bc70-057006ed9530): processed, Internal group assigned, test notes saved.
- [x] Installed Mac build 8 through TestFlight. Actual installed bundle version/Production entitlements verified; the existing book retained page 8 and rendered pages 8/9 with the new native toolbar. iPad build 8 installation and physical automatic roundtrip remain follow-up acceptance checks.

The isolated Debug session is closed and the Mac now runs TestFlight build 8; user data was not reset. Historical manifests/provenance retain their original scope and do not attest these final binaries. Final release results are the two artifact directories and TestFlight records linked above.
