# Mac native toolbar — local build 8 verification

Observed on 2026-11-10 (UTC), macOS 27.2, using a signed Debug Catalyst build from this worktree. This is local UI verification, not a TestFlight build 8 or Production iCloud acceptance test. No build 8 archive or upload was made.

## Final implementation

- Reader top controls now use a native NavigationStack toolbar, like the library. Native toolbar items do not receive an additional custom glass effect.
- A visible system bar background keeps the title readable against a black reading background. Back, jump, bookmark, share and settings retain their localized accessibility labels.
- Bottom controls use the system glass button style on supported OS versions and a bordered fallback on older versions. The row occupies its own space outside the comic viewport.
- Library Select uses the `checkmark.circle` SF Symbol with its existing localized Select accessibility label/help. Selection mode still has its existing Done, Select All and Edit Info controls.
- The Mac share presenter is attached to the reading content host. Its original placement inside a native toolbar item did not present a share sheet during QA. iPad retains its existing button anchor and reader chrome.

## Native observations

The current Development smoke catalogue `macA` was opened with explicit isolation arguments. It resumed the existing 12-page guide at human page 8. That previously imported guide has content hash `1fc298b80ba488fa16abf2bf12ebb8550858db31471abc80def90f55bbc3f935`; it was not silently replaced with the newly bundled guide.

| Case | Observed result |
| --- | --- |
| Library Select icon | Checkmark circle visible; enters selection mode; Done returns to normal library. |
| Reader toolbar | Native circular glass buttons, readable title and system bar background; no duplicate library Settings/Import controls. |
| Double pages and viewport | Pages 8 and 9 render together, including both complete page edges and printed page numbers. Showing and hiding chrome does not overlay their content. |
| Sharing, final revision | Native share popover opens and describes two images, 146 KB. Dismissed without choosing a recipient or transmitting files. |
| Jump, final revision | Go to Page alert opens with the 1–12 range; Cancel returns to the reader. |
| Settings and thumbnails | Settings shows Two Pages selected; Done returns. Thumbnails shows all 12 pages and its Done button returns. These checks preceded the final bar-background/share-anchor-only correction. |
| Hidden controls and Escape, final revision | Toolbar disappears; Escape returns to the library; its controls and human page 8 are restored. |
| Automatic triggers, final revision | Diagnostic log records bookOpened and bookClosed automatic cycles completing, without Sync Now. This is not a new cross-device roundtrip test. |

Although Back is requested with `.navigation` placement, this Catalyst runtime renders it at the start of the right-hand toolbar group. It works and is not claimed to have moved to the left. The current QA did not establish older-OS fallback appearance, narrow-window resizing, white reader background, or every zoom/RTL/slider interaction.

## Build and source identity

- Final signed build log: `/private/tmp/vn-reader-build8-native-final-v2.log` (`BUILD SUCCEEDED`).
- Runtime diagnostic log: `/private/tmp/vn-reader-build8-native-final-v2-smoke.log`.
- Product: `/private/tmp/vn-reader-build8-mac-auto/Build/Products/Debug-maccatalyst/VNReader.app`.
- `ReaderScreen.swift` SHA-256: `a94bdbd00d5eec024bcc449a37381f09c8b0fa96c1817aea26b650b59d3a2193`.
- `LibraryView.swift` SHA-256: `0b45469762c35cef776e1552128e5b375e6438b54754708fcdbb11ef66e58b1c`.
- Bundled guide SHA-256, verified in the signed product: `9267179470f3c5c0b381cf22335535e1cfb534fdb0eec57839c3c39930461f12`.

Native screenshot/AX evidence was observed through the computer-use session; this document does not invent exported screenshot files. After the final automatic close cycle completed, the isolated Debug process was stopped and the already-installed `/Applications/VNReader.app` TestFlight build 7 was reopened. TestFlight user data was not reset.

## Standard icon reference

Apple’s [Human Interface Guidelines: Icons](https://developer.apple.com/jp/design/human-interface-guidelines/icons) lists `checkmark.circle` for Select in its Standard Icons selection table. This supports the chosen symbol; it is not described here as the only mandatory choice for every selection interface.

Durable excerpts: [final signed build](mac-native-final-v2-build.txt) and [sanitized final runtime diagnostics](mac-native-final-v2-smoke.txt). The runtime excerpt contains three completed automatic cycles (app opening, book opening, book closing) and is not a new cross-device round-trip test.
