# Screenshots

Captured automatically by the UI tests on simulators (iOS 26.2) and published by CI to
`docs/screenshots/`. Sample books are procedurally generated (`scripts/fixtures/generate_samples.py`).

| | iPad mini (6th gen) | iPad Pro 13-inch |
|---|---|---|
| Empty library | ![](screenshots/01-empty-library-ipad-mini-portrait.jpg) | ![](screenshots/01-empty-library-ipad-13in-portrait.jpg) |
| Library | ![](screenshots/02-library-ipad-mini-portrait.jpg) | ![](screenshots/02-library-ipad-13in-landscape.jpg) |
| Reader (portrait) | ![](screenshots/03-reader-ipad-mini-portrait.jpg) | ![](screenshots/03-reader-ipad-13in-portrait.jpg) |
| Zoomed in | ![](screenshots/04-reader-zoomed-ipad-mini-portrait.jpg) | ![](screenshots/04-reader-zoomed-ipad-13in-portrait.jpg) |
| Thumbnails / jump | ![](screenshots/05-thumbnails-ipad-mini-portrait.jpg) | ![](screenshots/05-thumbnails-ipad-13in-portrait.jpg) |
| Reader (landscape) | ![](screenshots/06-reader-ipad-mini-landscape.jpg) | ![](screenshots/06-reader-ipad-13in-landscape.jpg) |
| Double-page layout (wide spread alone) | ![](screenshots/07-reader-double-page-ipad-mini-landscape.jpg) | ![](screenshots/07-reader-double-page-ipad-13in-landscape.jpg) |
| Library after reading | ![](screenshots/08-library-continue-ipad-mini-portrait.jpg) | ![](screenshots/08-library-continue-ipad-13in-portrait.jpg) |
| RTL manga (toolbar visible) | ![](screenshots/09-reader-rtl-ipad-mini-portrait.jpg) | ![](screenshots/09-reader-rtl-ipad-13in-portrait.jpg) |
| Fit width, tall strip | ![](screenshots/10-reader-fit-width-tall-ipad-mini-portrait.jpg) | ![](screenshots/10-reader-fit-width-tall-ipad-13in-portrait.jpg) |
| Vertical scrolling | ![](screenshots/11-reader-vertical-ipad-mini-portrait.jpg) | ![](screenshots/11-reader-vertical-ipad-13in-portrait.jpg) |

UI tests also record screen videos inside the `.xcresult` bundles (CI artifact `apple-build`
on GitHub Actions); they are not committed because of size.
