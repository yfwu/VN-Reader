#!/usr/bin/env python3
"""Generate the CBZ/CBR test fixtures used by ComicCoreTests.

All images are generated here (no third-party artwork). CBR fixtures are
created with RARLAB `rar` (6.23 is used because RAR 7.x can no longer
create RAR4 archives). Usage:

    python3 scripts/fixtures/generate_fixtures.py --rar /path/to/rar \
        --out Packages/ComicCore/Tests/ComicCoreTests/Fixtures

Requires Pillow (pip install pillow==12.*). Output is deterministic except
for archive timestamps, which are pinned via -tl / ZipInfo.date_time.
"""
import argparse, io, os, shutil, subprocess, sys, tempfile, zipfile
from PIL import Image, ImageDraw, ImageFont

COLORS = [(230, 80, 80), (80, 160, 230), (90, 190, 120), (230, 180, 60), (160, 100, 220),
          (60, 190, 190), (220, 120, 170), (140, 140, 140)]


def page_image(label, size=(400, 600), index=0):
    w, h = size
    img = Image.new("RGB", size, COLORS[index % len(COLORS)])
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.load_default(size=max(24, w // 6))
        small = ImageFont.load_default(size=max(14, w // 20))
    except TypeError:
        font = small = ImageFont.load_default()
    d.rectangle([8, 8, w - 9, h - 9], outline=(255, 255, 255), width=6)
    d.text((w // 2, h // 2), label, fill=(255, 255, 255), font=font, anchor="mm")
    # Orientation marker: top-left triangle, so mirrored rendering is detectable.
    d.polygon([(8, 8), (w // 4, 8), (8, h // 6)], fill=(0, 0, 0))
    d.text((w // 2, h - 40), f"page {label}", fill=(0, 0, 0), font=small, anchor="mm")
    return img


def encode(img, fmt):
    b = io.BytesIO()
    if fmt == "jpg":
        img.save(b, "JPEG", quality=60)
    elif fmt == "png":
        img.quantize(32).save(b, "PNG", optimize=True)
    elif fmt == "webp":
        img.save(b, "WEBP", quality=50)
    elif fmt == "gif":
        img.quantize(32).save(b, "GIF")
    else:
        raise ValueError(fmt)
    return b.getvalue()


def write_zip(path, entries, compression=zipfile.ZIP_DEFLATED, force_zip64=False):
    """entries: list of (name, bytes) — name may be str (UTF-8 flag set when non-ASCII)."""
    with zipfile.ZipFile(path, "w", compression) as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=(2024, 1, 1, 0, 0, 0))
            info.compress_type = compression
            z.writestr(info, data) if not force_zip64 else z.open(info, "w", force_zip64=True).write(data)


def write_zip_raw_names(path, entries):
    """Write entries whose names are raw bytes (e.g. CP932) without the UTF-8 flag.

    Python's zipfile always writes non-ASCII names as UTF-8 (flag 0x800), so we
    write ASCII placeholders of identical length and patch the bytes afterwards.
    """
    placeholders = []
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for n, (raw, data) in enumerate(entries):
            ph = (f"P{n}" + "x" * len(raw))[: len(raw)]
            placeholders.append((ph.encode("ascii"), raw))
            info = zipfile.ZipInfo(ph, date_time=(2024, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    blob = open(path, "rb").read()
    for ph, raw in placeholders:
        assert blob.count(ph) == 2, ph
        blob = blob.replace(ph, raw)
    open(path, "wb").write(blob)


def make_tree(root, entries):
    for name, data in entries:
        p = os.path.join(root, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data)


def rar(rar_bin, out, src_dir, *flags):
    if os.path.exists(out):
        os.remove(out)
    cmd = [rar_bin, "a", "-r", "-ep1", "-idq", "-y", "-tsm-", "-tsc-", "-tsa-"] + list(flags) + [out, os.path.join(src_dir, "*")]
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rar", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = a.out
    os.makedirs(out, exist_ok=True)

    # --- Page sets -------------------------------------------------------
    simple = [(f"{i}.jpg", encode(page_image(str(i), index=i), "jpg")) for i in range(1, 13)]
    junk = [("__MACOSX/._1.jpg", b"\x00\x05\x16\x07AppleDouble"), ("._2.jpg", b"\x00\x05\x16\x07AppleDouble"),
            (".DS_Store", b"\x00\x00\x00\x01Bud1"), ("Thumbs.db", b"\xd0\xcf\x11\xe0"),
            ("readme.txt", "這是說明文字".encode("utf-8")),
            ("ComicInfo.xml", ("<?xml version=\"1.0\" encoding=\"utf-8\"?><ComicInfo><Title>測試標題</Title>"
                               "<Series>測試系列</Series><Number>3</Number><Writer>作者</Writer>"
                               "<PageCount>12</PageCount><Manga>YesAndRightToLeft</Manga></ComicInfo>").encode("utf-8"))]
    padded = [(f"{i:03d}.png", encode(page_image(f"{i:03d}", index=i), "png")) for i in range(1, 11)]
    nested = []
    for ch in (1, 2, 10):
        for p in (1, 2, 10):
            nested.append((f"第{ch}話/ページ {p}.jpg", encode(page_image(f"{ch}-{p}", index=ch + p), "jpg")))
    nested += [("cover.jpg", encode(page_image("cover", index=0), "jpg")),
               ("特殊 字元 #&()[]'!/01.jpg", encode(page_image("S1", index=3), "jpg"))]
    webp = [(f"p{i:02d}.webp", encode(page_image(f"W{i}", index=i), "webp")) for i in range(1, 6)]
    mixed = [("01.jpg", encode(page_image("J", index=1), "jpg")), ("02.png", encode(page_image("P", index=2), "png")),
             ("03.webp", encode(page_image("W", index=3), "webp")), ("04.gif", encode(page_image("G", index=4), "gif"))]
    tall = [("01.jpg", encode(page_image("TALL", size=(300, 3000), index=5), "jpg")),
            ("02.jpg", encode(page_image("WIDE", size=(1200, 600), index=6), "jpg"))]

    # --- CBZ ---------------------------------------------------------------
    write_zip(f"{out}/cbz_basic.cbz", simple + junk)
    write_zip(f"{out}/cbz_stored_padded.cbz", padded, compression=zipfile.ZIP_STORED)
    write_zip(f"{out}/cbz_nested_cjk.cbz", nested)
    write_zip(f"{out}/cbz_webp.cbz", webp)
    write_zip(f"{out}/cbz_mixed_formats.cbz", mixed)
    write_zip(f"{out}/cbz_tall_wide.cbz", tall)
    write_zip(f"{out}/cbz_zip64.cbz", padded[:3], force_zip64=True)
    # Shift_JIS (CP932) names without the UTF-8 flag, as produced by old Japanese Windows tools.
    write_zip_raw_names(f"{out}/cbz_cp932_names.cbz",
                        [("第01話/ページ01.jpg".encode("cp932"), simple[0][1]),
                         ("第01話/ページ02.jpg".encode("cp932"), simple[1][1])])
    write_zip(f"{out}/cbz_no_images.cbz", [("readme.txt", b"no images"), ("__MACOSX/._a.jpg", b"x")])
    write_zip(f"{out}/cbz_broken_image.cbz", [simple[0], ("2.jpg", b"\xff\xd8\xff\xe0 this is not a jpeg"), simple[2]])
    write_zip(f"{out}/cbz_bzip2.cbz", simple[:2], compression=zipfile.ZIP_BZIP2)
    # Real ZIP renamed to .cbr — must be detected as ZIP by content.
    write_zip(f"{out}/zip_named_as.cbr", simple[:3])
    # Truncated ZIP (no central directory).
    full = open(f"{out}/cbz_basic.cbz", "rb").read()
    open(f"{out}/cbz_truncated.cbz", "wb").write(full[: len(full) // 2])
    # Not an archive at all.
    open(f"{out}/not_an_archive.cbz", "wb").write(b"%PDF-1.4\n" + b"0" * 512)
    open(f"{out}/sevenzip.cb7.cbz", "wb").write(b"7z\xbc\xaf\x27\x1c\x00\x04" + b"\x00" * 64)
    # Encrypted ZIP (ZipCrypto) via Info-ZIP `zip -P`.
    if shutil.which("zip"):
        with tempfile.TemporaryDirectory() as t:
            make_tree(t, simple[:2])
            p = os.path.abspath(f"{out}/cbz_encrypted.cbz")
            if os.path.exists(p):
                os.remove(p)
            subprocess.run(["zip", "-q", "-P", "secret", "-j", p, f"{t}/1.jpg", f"{t}/2.jpg"], check=True)

    # --- CBR (real RAR data) ------------------------------------------------
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "simple")
        make_tree(src, simple + junk)
        rar(a.rar, f"{out}/rar4_nonsolid.cbr", src, "-ma4", "-m3")
        rar(a.rar, f"{out}/rar4_solid.cbr", src, "-ma4", "-m3", "-s")
        rar(a.rar, f"{out}/rar4_stored.cbr", src, "-ma4", "-m0")
        rar(a.rar, f"{out}/rar5_nonsolid.cbr", src, "-ma5", "-m3")
        rar(a.rar, f"{out}/rar5_solid.cbr", src, "-ma5", "-m3", "-s")
        rar(a.rar, f"{out}/rar5_stored.cbr", src, "-ma5", "-m0")
        rar(a.rar, f"{out}/rar5_encrypted.cbr", src, "-ma5", "-psecret")
        rar(a.rar, f"{out}/rar5_encrypted_headers.cbr", src, "-ma5", "-hpsecret")
        rar(a.rar, f"{out}/rar4_encrypted.cbr", src, "-ma4", "-psecret")
        src2 = os.path.join(t, "nested")
        make_tree(src2, nested)
        rar(a.rar, f"{out}/rar4_nested_cjk.cbr", src2, "-ma4", "-s")
        rar(a.rar, f"{out}/rar5_nested_cjk.cbr", src2, "-ma5")
        src3 = os.path.join(t, "webp")
        make_tree(src3, webp + padded)
        rar(a.rar, f"{out}/rar5_solid_webp_png.cbr", src3, "-ma5", "-s", "-m5")
        # Multi-volume (first volume only is imported → must be recognised).
        mv = os.path.join(t, "mv")
        os.makedirs(mv)
        rnd = __import__("random").Random(42)
        def noise(i):
            img = Image.frombytes("RGB", (160, 160), bytes(rnd.getrandbits(8) for _ in range(160 * 160 * 3)))
            b = io.BytesIO(); img.save(b, "PNG"); return b.getvalue()
        big = [(f"{i:02d}.png", noise(i)) for i in range(1, 6)]
        make_tree(os.path.join(t, "mvsrc"), big)
        rar(a.rar, os.path.join(mv, "multi.rar"), os.path.join(t, "mvsrc"), "-ma5", "-m0", "-v40k")
        vols = sorted(os.listdir(mv))
        shutil.copy(os.path.join(mv, vols[0]), f"{out}/rar5_multivolume.part1.cbr")
        mv4 = os.path.join(t, "mv4")
        os.makedirs(mv4)
        rar(a.rar, os.path.join(mv4, "multi.rar"), os.path.join(t, "mvsrc"), "-ma4", "-m0", "-v40k")
        vols4 = sorted(os.listdir(mv4))
        shutil.copy(os.path.join(mv4, vols4[0]), f"{out}/rar4_multivolume.part1.cbr")
    full = open(f"{out}/rar5_nonsolid.cbr", "rb").read()
    open(f"{out}/rar5_truncated.cbr", "wb").write(full[: len(full) * 2 // 3])
    # Corrupt payload: flip bytes in the middle of the data area.
    bad = bytearray(open(f"{out}/rar5_solid.cbr", "rb").read())
    for i in range(len(bad) // 2, len(bad) // 2 + 64):
        bad[i] ^= 0x5A
    open(f"{out}/rar5_corrupt_data.cbr", "wb").write(bytes(bad))
    print("fixtures written to", out)
    for f in sorted(os.listdir(out)):
        print(f"{os.path.getsize(os.path.join(out, f)):>9}  {f}")


if __name__ == "__main__":
    main()
