# Third-party notices

VN Reader has **one** third-party source dependency and uses one system library.
No package manager downloads are involved; everything is vendored at a fixed version.

| Component | Version | Source | License | Used for | Distribution notes |
|---|---|---|---|---|---|
| unRAR source code (RARLAB, Alexander Roshal) | 7.23 (`unrarsrc` as packaged by Debian/Ubuntu `unrar-nonfree_7.2.7.orig.tar.gz`, SHA-256 `01d903a7dcf413cb2925696d7796e48e38d471f79bfe7ef3ad2aebf6c12dbefd`) | http://archive.ubuntu.com/ubuntu/pool/multiverse/u/unrar-nonfree/ (upstream: https://www.rarlab.com/rar_add.htm) | unRAR license (freeware, not OSI) — full text below | Decompressing RAR4/RAR5 (CBR) | Free use in any software to *extract* RAR, including commercial / App Store distribution, as long as it is not used to create a RAR-compatible archiver. The license text must accompany the app's documentation. |
| zlib | provided by iOS (`libz.tbd`) | Apple SDK | zlib license | Inflating Deflate entries in CBZ | System library, nothing is bundled. |

Location in the repo: `Packages/ComicCore/Sources/CUnrar/unrar/` (unmodified upstream files;
`*.vcxproj` and `dll.rc` removed because they are Windows-only). Our own C shim is
`Packages/ComicCore/Sources/CUnrar/vnrar.cpp` / `include/vnrar.h`.

Test-only tools (not shipped): RARLAB `rar` 6.23 for Linux (shareware, trial) was used to
*create* the RAR test fixtures; Pillow (HPND license) to draw test images; WenQuanYi Zen Hei
font (GPL v2 with font embedding exception) to render CJK titles into generated sample images.

## unRAR license (verbatim)

```
 ******    *****   ******   UnRAR - free utility for RAR archives
 **   **  **   **  **   **  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 ******   *******  ******    License for use and distribution of
 **   **  **   **  **   **   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 **   **  **   **  **   **         FREE portable version
                                   ~~~~~~~~~~~~~~~~~~~~~

      The source code of UnRAR utility is freeware. This means:

   1. All copyrights to RAR and the utility UnRAR are exclusively
      owned by the author - Alexander Roshal.

   2. UnRAR source code may be used in any software to handle
      RAR archives without limitations free of charge, but cannot be
      used to develop RAR (WinRAR) compatible archiver and to
      re-create RAR compression algorithm, which is proprietary.
      Distribution of modified UnRAR source code in separate form
      or as a part of other software is permitted, provided that
      full text of this paragraph, starting from "UnRAR source code"
      words, is included in license, or in documentation if license
      is not available, and in source code comments of resulting package.

   3. The UnRAR utility may be freely distributed. It is allowed
      to distribute UnRAR inside of other software packages.

   4. THE RAR ARCHIVER AND THE UnRAR UTILITY ARE DISTRIBUTED "AS IS".
      NO WARRANTY OF ANY KIND IS EXPRESSED OR IMPLIED.  YOU USE AT 
      YOUR OWN RISK. THE AUTHOR WILL NOT BE LIABLE FOR DATA LOSS, 
      DAMAGES, LOSS OF PROFITS OR ANY OTHER KIND OF LOSS WHILE USING
      OR MISUSING THIS SOFTWARE.

   5. Installing and using the UnRAR utility signifies acceptance of
      these terms and conditions of the license.

   6. If you don't agree with terms of the license you must remove
      UnRAR files from your storage devices and cease to use the
      utility.

      Thank you for your interest in RAR and UnRAR.


                                            Alexander L. Roshal
```
