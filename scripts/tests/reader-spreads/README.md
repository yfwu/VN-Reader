# Reader spread regression harness

This macOS harness compiles the **current** `ReaderViewController`,
`VerticalReaderController`, `SpreadPageController`, `SpreadZoomView`,
`PageImageLoader`, and `ImageDecoder`
against real UIKit and the local `ComicCore` Catalyst build products.

First build this checkout for Debug Mac Catalyst, then run:

```sh
xcodebuild -project VNReader.xcodeproj -scheme VNReader -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/VNReaderSpreadAudit CODE_SIGNING_ALLOWED=NO build
python3 scripts/tests/reader-spreads/run.py --derived-data /tmp/VNReaderSpreadAudit
```

The runner creates a separate temporary, ad hoc signed Catalyst app with a
scene-based lifecycle. Its UIKit window stays hidden and does not take focus.
Only a stub reader model/settings and display/error strings replace app services;
no real library, preferences, account, or CloudKit coordinator is opened. A small
fixture archive is imported into a new temporary folder for the image loader.

The 56 checks cover:

- Mac double-page layout in a narrow viewport, retaining the requested logical page.
- Late wide-image discovery, stale paired controllers, and consecutive wide pages.
- Stable unit indices during transitions, stale completion tokens, queued jumps,
  cancelled swipes, and zoom callbacks preserving the paging lock.
- Explicit user intent for next/previous/jump and committed swipes, with passive
  initial display, re-pairing, settings, resizing, remote restores and cancellation.
- Queued user jumps and committed swipes taking priority over pending remote restores.
- Vertical drag/deceleration and indirect-pan intent, while programmatic row-height
  corrections, remote positioning and detached readers cannot generate user writes.
- A later real scroll into a row first reported by passive correction still records
  progress, including when both events occur within the same drag gesture.
- Cached tall images filling the viewport width on first layout and after resize,
  and delayed decoding above the viewport retaining its exact scroll position
  without progress writes, even after the loader has populated its image cache.
- Shared and cached image consumers receiving dimensions before rendering.
- Wide-image and paired-portrait fit-page frames staying completely visible and
  centered across 1200×800 → 1200×696 → 1200×800 → 600×900 viewport changes.

Small adapters are appended only to temporary source copies to drive completion
callbacks, synthetic scroll states, and a shared decode task deterministically.
The model stub follows the real contract: passive callbacks update visible pages;
only user callbacks update logical focus. Persistence itself is covered by the
separate actual-model `reader-progress` harness. This exercises actual
UIKit controllers and geometry; it does not measure native animation timing or
replace visual testing of the complete app and its toolbars.

No production source is rewritten. Sources, executable, and synthetic data are
removed afterward; add `--keep-workspace` to retain them. Run in a normal macOS
terminal: an agent sandbox may prevent UIKit application initialization. Any
compile failure, assertion failure, or 60-second timeout exits nonzero.

The separate `SpreadLayoutInvariantTests` in `ComicCore` exercises the public
layout API across 8,188 combinations without changing its pairing algorithm.
