# Page ordering rules

Implemented in `Packages/ComicCore/Sources/ComicCore/Pages/NaturalSort.swift` and
`PageFilter.swift`; tested in `PageOrderingTests.swift`. The rules are locale-independent,
so the same archive always produces the same order on every device.

## Which entries are pages

An entry is a page when **all** hold:

1. It is not a directory (or a RAR link / redirection entry).
2. No path component is `__MACOSX`, and no directory starts with `.` (hidden folders).
3. The file name does not start with `.` — this excludes AppleDouble `._*`, `.DS_Store`, dot-files.
4. The name is not `Thumbs.db` / `desktop.ini` (case-insensitive).
5. The extension is an image type: `jpg jpeg jpe jfif png webp gif heic heif avif bmp tif tiff` (case-insensitive).
6. Its uncompressed size is greater than zero.

Everything else (text files, `ComicInfo.xml`, NFO, …) is counted as "ignored" and never shown.
`ComicInfo.xml` is read separately for metadata.

## Sort order

Paths are compared component by component (`/` separated):

1. **Files before sub-folders** at the first level where the paths differ
   (`cover.jpg` comes before `ch01/001.jpg`).
2. Names are **NFKC-normalised** (full-width `１２` → `12`) and compared **case-insensitively**.
3. The **stem is compared before the extension** (`1.jpg` < `1-1.jpg` < `1a.jpg`).
4. Runs of ASCII digits compare by **numeric value**: `1 < 2 < 10`, `001 < 002 < 010`.
   Digits sort before non-digits at the same position.
5. Other characters compare by Unicode scalar value (deterministic, not locale dependent),
   e.g. `第1話 < 第2話 < 第10話`.
6. Ties are broken by: fewer leading zeros first (`1.jpg` before `01.jpg`), then the exact
   original Unicode scalars (so `A.jpg` / `a.jpg` are stable), then the entry's position in
   the archive (exact duplicate paths keep archive order).

## Stability

At import the sorted list is written to `Books/<id>/manifest.json` as
`(archiveIndex, path, size, type)` per logical page. Reading always uses this frozen
manifest, so page *N* refers to the same file forever, even if these rules change in a
later version. Reading direction (LTR/RTL) never reorders the manifest: page 0 is always
the first page of the book.

## Name decoding (ZIP)

* UTF-8 flag (bit 11) set → UTF-8.
* Info-ZIP Unicode Path extra field (0x7075) with matching CRC → that name.
* Otherwise all legacy names of the archive are decoded with **one** encoding chosen by
  scoring candidates (UTF-8, Shift_JIS/CP932, Big5-HKSCS, GB18030, CP1252, Latin-1) on the
  whole name set: kana / CJK ideographs score up, half-width katakana, private-use and
  control characters score down.

RAR stores names as Unicode; unrar converts them and we normalise `\` to `/`.

Archive entry names are only labels: the app never writes files using names from the
archive (the solid-RAR cache uses `<logical page>.page`), so `../` or absolute names cannot
escape the app's directories.
