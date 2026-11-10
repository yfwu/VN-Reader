# Mac reader UI smoke — 2026-11-10

Local Debug preview only; build 8 remains on user-requested release hold.
The latest reader-progress fix was not yet present in this preview, so these
observations concern layout and controls rather than sync correctness.

## Observed

- Explicit launch: `-sync-smoke-test 20261110vn8glass -sync-smoke-client macUI -sync-smoke-seed-guide`; process arguments were verified after CUA attached. Sync was not enabled. The synthetic guide and repository `02 城市速寫.cbz` were the test books.
- Default guide cover is standalone; Next shows pages 2 and 3 without changing layout settings.
- Compact native Liquid Glass controls are round (icons) and capsule-shaped (Back/page count). Opaque gray button rectangles and the full-width gray reader bars are absent. The page content stays within the dedicated top/bottom control rows.
- Native library navigation controls disappear while reading and return in the library.
- Reader settings and thumbnails retain their title/Done controls.
- A local single-page choice survives closing/reopening and preserves the logical page (observed in the earlier pre-glass build 8 preview).
- Enter Full Screen retains the two pages, compact controls and full image boundaries.
- Importing the repository synthetic CBZ through the native file picker succeeds. Selecting thumbnail 8 shows `reader.page.7`, accessibility label `Page 8`, and one complete original wide image, with all four border edges visible and no extra neighboring page.
- The final guide intro accurately describes iPad/Mac support and optional iCloud.

## Not yet observed

Native narrow-window resizing, white background, zoom/pan under control-row
changes, complete slider/RTL interactions, and macOS 15 material fallback.
The UIKit geometry harness covers wide/two-portrait images and viewport size
changes, but does not substitute for these native interaction checks.
No physical or Production iCloud success is claimed here.

## Environment caveat

During the earlier preview session, a task-owned build 8 executable was observed
restarted without smoke arguments. It was stopped and the explicit isolated
launch above was used for subsequent glass and wide-page checks. Do not label all
earlier native observations as guaranteed isolated. No normal library was reset,
deleted or intentionally uploaded during this work.
