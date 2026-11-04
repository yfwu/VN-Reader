# Format compatibility

**Legend:** ✅ passes · ⚠️ partial · ⛔ not supported (clear message shown) · — not tested

Environments where the automated tests ran (see `docs/TEST_REPORT.md` for runs):

* **L**: Linux x86_64, Swift 6.0.3 (this development container and CI `swift:6.0-noble`)
* **M**: macOS 15 arm64 host, GitHub Actions `macos-15` (Xcode, `swift test`)
* **S**: iPad mini (6th generation) **simulator**, iOS 26.2 runtime (`xcodebuild test -scheme ComicCore`)
* **D**: real iPad — **not tested yet** (no signing / device available to the build environment)

All RAR fixtures are **real RAR data** produced by RARLAB `rar` 6.23
(`Packages/ComicCore/Tests/ComicCoreTests/Fixtures`, generator `scripts/fixtures/generate_fixtures.py`).
A ZIP renamed to `.cbr` is only used to check that the *extension is ignored*.

## Archives

| Case | Fixture | Expected | L | M | S | D |
|---|---|---|---|---|---|---|
| CBZ, Deflate | `cbz_basic.cbz` | read all pages | ✅ | ✅ | ✅ | — |
| CBZ, Stored | `cbz_stored_padded.cbz` | read | ✅ | ✅ | ✅ | — |
| CBZ, ZIP64 records | `cbz_zip64.cbz` | read | ✅ | ✅ | ✅ | — |
| CBZ, UTF-8 CJK names in nested folders | `cbz_nested_cjk.cbz` | correct names & order | ✅ | ✅ | ✅ | — |
| CBZ, Shift_JIS names without UTF-8 flag | `cbz_cp932_names.cbz` | decoded as Japanese | ⛔¹ | ✅ | ✅ | — |
| **RAR4 non-solid** (`-ma4 -m3`) | `rar4_nonsolid.cbr` | read, random access | ✅ | ✅ | ✅ | — |
| **RAR4 solid** (`-ma4 -s`) | `rar4_solid.cbr` | read via sequential cache | ✅ | ✅ | ✅ | — |
| RAR4 stored (`-m0`) | `rar4_stored.cbr` | read | ✅ | ✅ | ✅ | — |
| RAR4 solid, CJK nested names | `rar4_nested_cjk.cbr` | correct names & order | ✅ | ✅ | ✅ | — |
| **RAR5 non-solid** (`-ma5 -m3`) | `rar5_nonsolid.cbr` | read, random access | ✅ | ✅ | ✅ | — |
| **RAR5 solid** (`-ma5 -s`) | `rar5_solid.cbr` | read via sequential cache | ✅ | ✅ | ✅ | — |
| RAR5 stored | `rar5_stored.cbr` | read | ✅ | ✅ | ✅ | — |
| RAR5 non-solid CJK names | `rar5_nested_cjk.cbr` | correct | ✅ | ✅ | ✅ | — |
| RAR5 solid, `-m5`, WebP + PNG | `rar5_solid_webp_png.cbr` | read | ✅ | ✅ | ✅ | — |
| Same page bytes across ZIP / RAR4 / RAR5 | (all simple fixtures) | identical bytes | ✅ | ✅ | ✅ | — |
| ZIP with `.cbr` extension | `zip_named_as.cbr` | detected as ZIP | ✅ | ✅ | ✅ | — |
| 1 GB / 1000 pages: ZIP, RAR5 non-solid, RAR5 solid, RAR4 solid | generated (`generate_stress.py`) | import + random reads + full solid preparation | ✅² | — | — | — |

¹ swift-corelibs-foundation on Linux has no Shift_JIS converter; Apple platforms do (the test is skipped on Linux).
² Timings in `docs/test-results/stress-linux.txt` (Linux container — **not** iPad performance).

## Recognised but not supported (first version)

Each case is detected and shown with a specific message (see `ErrorMessages.swift`), never as "corrupt".

| Case | Fixture | Result / message | L | M | S |
|---|---|---|---|---|---|
| RAR5 encrypted file data (`-p`) | `rar5_encrypted.cbr` | ⛔ "檔案有密碼保護" | ✅ | ✅ | ✅ |
| RAR5 encrypted headers (`-hp`) | `rar5_encrypted_headers.cbr` | ⛔ "檔案有密碼保護" | ✅ | ✅ | ✅ |
| RAR4 encrypted (`-p`) | `rar4_encrypted.cbr` | ⛔ "檔案有密碼保護" | ✅ | ✅ | ✅ |
| ZIP encrypted (ZipCrypto) | `cbz_encrypted.cbz` | ⛔ "檔案有密碼保護" | ✅ | ✅ | ✅ |
| RAR5 multi-volume, first part | `rar5_multivolume.part1.cbr` | ⛔ "不支援分卷壓縮檔" | ✅ | ✅ | ✅ |
| RAR4 multi-volume, first part | `rar4_multivolume.part1.cbr` | ⛔ "不支援分卷壓縮檔" | ✅ | ✅ | ✅ |
| ZIP BZIP2 method (12) | `cbz_bzip2.cbz` | ⛔ "不支援的壓縮方式：BZIP2" | ✅ | ✅ | ✅ |
| ZIP LZMA / Deflate64 / Zstd / XZ / PPMd | (by method id) | ⛔ method named in message | unit-mapped | | |
| 7z (`.cb7`) | `sevenzip.cb7.cbz` | ⛔ "不支援的壓縮格式：7z" | ✅ | ✅ | ✅ |
| PDF named `.cbz` | `not_an_archive.cbz` | ⛔ "檔案內容是 PDF" | ✅ | ✅ | ✅ |
| Truncated ZIP (no end record) | `cbz_truncated.cbz` | ⛔ "檔案不完整" | ✅ | ✅ | ✅ |
| Truncated RAR5 | `rar5_truncated.cbr` | ⚠️ listing stops early; missing pages fail individually | ✅ | ✅ | ✅ |
| RAR5 solid with corrupted data | `rar5_corrupt_data.cbr` | ⛔ "資料檢查碼不符" / structure error | ✅ | ✅ | ✅ |
| No images (only text / `__MACOSX`) | `cbz_no_images.cbz` | ⛔ "找不到漫畫頁面" | ✅ | ✅ | ✅ |
| RAR with dictionary > 4 GB (RAR 7) | — | ⛔ "RAR 字典過大" (unrar callback refuses) | — | — | — |
| Self-extracting RAR (.exe) | — | ⛔ not detected as RAR (magic not at offset 0) | — | — | — |

## Images

Decoding uses ImageIO on Apple platforms; tests on M and S.

| Format | Status | Notes |
|---|---|---|
| JPEG | ✅ | baseline + progressive via ImageIO |
| PNG | ✅ | |
| WebP | ✅ | ImageIO (iOS 14+); fixture `cbz_webp.cbz`, `rar5_solid_webp_png.cbr` |
| GIF | ✅ | first frame only |
| HEIC / HEIF, AVIF | ✅ (by ImageIO) | AVIF needs iOS 16+; no fixture yet |
| BMP / TIFF | ✅ (by ImageIO) | no fixture yet |
| Broken image data | ⚠️ | page shows "此頁無法顯示" with reason; other pages readable (`cbz_broken_image.cbz`) |
| Images > 400 megapixels | ⛔ | refused for memory safety ("圖片尺寸 … 超過安全上限") |

## Limits (configurable in code)

| Limit | Value | Where |
|---|---|---|
| Archive file size | 8 GB | `ImportLimits.maxFileSize` |
| Entries per archive | 20 000 | `ArchiveLimits.maxEntries` |
| Pages per book | 10 000 | `ImportLimits.maxPages` |
| Single decompressed entry | 256 MB | `ArchiveLimits.maxEntrySize` |
| Decoded bitmap per page | 24 MP (~96 MB) | `ImageDecoder.maxDecodedPixels` |
| Free space kept in reserve | 200 MB | `DiskSpacePolicy.reserve` |
| Solid-RAR cache (LRU, all books) | 3 GB | `LibraryStore.init` |
