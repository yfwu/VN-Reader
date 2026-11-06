#!/usr/bin/env python3
"""Generates the sample books used by UI tests / screenshots.

All artwork is procedurally drawn here (no third-party images).
    python3 scripts/fixtures/generate_samples.py --rar /path/to/rar --out UITests/Samples
"""
import argparse, io, os, random, subprocess, tempfile, zipfile
from PIL import Image, ImageDraw, ImageFont

CJK_FONTS = ["/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
             "/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/Hiragino Sans GB.ttc"]

def font(size):
    for f in CJK_FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()

PALETTES = [((250, 246, 238), (40, 40, 48)), ((238, 244, 250), (30, 44, 70)), ((246, 240, 250), (60, 30, 70))]

def manga_page(n, total, w=1000, h=1500, rtl=False, seed=0, title=""):
    rnd = random.Random(seed * 1000 + n)
    bg, ink = PALETTES[seed % len(PALETTES)]
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    m = 50
    # Panel grid: 3 rows, random splits.
    rows = [m, int(h * 0.36), int(h * 0.66), h - m - 60]
    for r in range(3):
        y0, y1 = rows[r] + (0 if r == 0 else 18), rows[r + 1]
        split = rnd.choice([None, 0.4, 0.55, 0.62])
        boxes = [(m, w - m)] if split is None else [(m, int(w * split) - 9), (int(w * split) + 9, w - m)]
        if rtl:
            boxes = boxes[::-1]
        for (x0, x1) in boxes:
            d.rectangle([x0, y0, x1, y1], outline=ink, width=6)
            # Simple "scene": horizon, sun/moon and a character silhouette.
            hy = rnd.randint(y0 + (y1 - y0) // 2, y1 - 30)
            d.line([x0 + 6, hy, x1 - 6, hy], fill=ink, width=3)
            cx = rnd.randint(x0 + 60, max(x0 + 61, x1 - 60))
            d.ellipse([cx - 28, hy - 150, cx + 28, hy - 94], outline=ink, width=5)
            d.line([cx, hy - 94, cx, hy - 20], fill=ink, width=5)
            d.line([cx, hy - 70, cx - 34, hy - 40], fill=ink, width=5)
            d.line([cx, hy - 70, cx + 34, hy - 40], fill=ink, width=5)
            if rnd.random() < 0.6 and x1 - x0 > 260:
                bx = x0 + 30 if cx > (x0 + x1) / 2 else x1 - 230
                d.rounded_rectangle([bx, y0 + 24, bx + 200, y0 + 110], radius=40, fill=(255, 255, 255), outline=ink, width=4)
                for i in range(3):
                    d.line([bx + 30, y0 + 48 + i * 20, bx + 170 - rnd.randint(0, 50), y0 + 48 + i * 20], fill=(150, 150, 150), width=6)
    d.text((w // 2, h - 40), f"{title}  {n} / {total}", fill=ink, font=font(32), anchor="mm")
    d.text((w // 2, h // 2), str(n), fill=(*ink, ), font=font(220), anchor="mm", stroke_width=8, stroke_fill=bg)
    return img

def spread_page(n, total, w=2000, h=1500):
    img = Image.new("RGB", (w, h), (232, 240, 236))
    d = ImageDraw.Draw(img)
    for i in range(0, w, 80):
        d.line([i, h * 0.7, i + 400, h * 0.25], fill=(170, 190, 180), width=4)
    d.rectangle([40, 40, w - 40, h - 40], outline=(40, 60, 50), width=8)
    d.text((w // 2, h // 2), f"跨頁 {n}-{n+1}", fill=(40, 60, 50), font=font(160), anchor="mm")
    d.text((w // 2, h - 80), f"wide spread · {n} / {total}", fill=(40, 60, 50), font=font(36), anchor="mm")
    return img

def tall_page(n, total, w=800, h=4000):
    img = Image.new("RGB", (w, h), (252, 250, 245))
    d = ImageDraw.Draw(img)
    for k in range(6):
        y = 80 + k * 650
        d.rounded_rectangle([60, y, w - 60, y + 560], radius=30, outline=(50, 50, 60), width=6,
                            fill=[(255, 236, 230), (230, 244, 255), (236, 255, 236)][k % 3])
        d.text((w // 2, y + 280), f"{n}-{k + 1}", fill=(50, 50, 60), font=font(120), anchor="mm")
    d.text((w // 2, h - 60), f"strip {n} / {total}", fill=(50, 50, 60), font=font(32), anchor="mm")
    return img

def jpeg(img, q=55):
    b = io.BytesIO(); img.save(b, "JPEG", quality=q, optimize=True); return b.getvalue()

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--rar", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    comicinfo_rtl = '<?xml version="1.0" encoding="utf-8"?><ComicInfo><Title>星之旅人 第1卷</Title><Series>星之旅人</Series><Number>1</Number><Manga>YesAndRightToLeft</Manga></ComicInfo>'
    with tempfile.TemporaryDirectory() as t:
        # 1. RTL manga, RAR5 solid (requires sequential preparation)
        src = os.path.join(t, "a"); os.makedirs(src)
        total = 30
        for n in range(1, total + 1):
            open(os.path.join(src, f"{n:03d}.jpg"), "wb").write(jpeg(manga_page(n, total, rtl=True, seed=1, title="星之旅人")))
        open(os.path.join(src, "ComicInfo.xml"), "w", encoding="utf-8").write(comicinfo_rtl)
        out = os.path.join(a.out, "01 星之旅人 第1卷.cbr")
        if os.path.exists(out): os.remove(out)
        subprocess.run([a.rar, "a", "-ma5", "-s", "-m3", "-ep1", "-idq", "-y", out, os.path.join(src, "*")], check=True)
        # 2. LTR comic with one wide spread, ZIP
        total = 16
        with zipfile.ZipFile(os.path.join(a.out, "02 城市速寫.cbz"), "w", zipfile.ZIP_STORED) as z:
            n = 1
            while n <= total:
                if n == 8:
                    z.writestr(f"page {n}-{n+1}.jpg", jpeg(spread_page(n, total))); n += 2; continue
                z.writestr(f"page {n}.jpg", jpeg(manga_page(n, total, seed=2, title="城市速寫"))); n += 1
        # 3. Webtoon-style tall strips, RAR4 non-solid
        src = os.path.join(t, "c"); os.makedirs(src)
        total = 6
        for n in range(1, total + 1):
            open(os.path.join(src, f"{n}.jpg"), "wb").write(jpeg(tall_page(n, total)))
        out = os.path.join(a.out, "03 長條漫畫.cbr")
        if os.path.exists(out): os.remove(out)
        subprocess.run([a.rar, "a", "-ma4", "-m3", "-ep1", "-idq", "-y", out, os.path.join(src, "*")], check=True)
    for f in sorted(os.listdir(a.out)):
        print(os.path.getsize(os.path.join(a.out, f)), f)

if __name__ == "__main__":
    main()
