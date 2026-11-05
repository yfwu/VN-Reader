#!/usr/bin/env python3
"""Generates the app icon (light, dark, tinted) into the asset catalog.

    python3 scripts/icon/generate_app_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset

Requires Pillow. Add --preview to also write final_preview.png (light / dark / tinted +
small sizes) to the current directory (not into the asset catalog).
"""
import sys
from PIL import Image, ImageDraw, ImageFilter
S = 4096
OUT = sys.argv[1]

INDIGO, CORAL = (92, 88, 222), (238, 88, 112)
P1, P2, P3 = (112, 108, 232), (238, 98, 124), (255, 168, 116)

def gradient(c1, c2):
    # diagonal gradient, top-left -> bottom-right
    w = h = S
    base = Image.new("RGB", (256, 256))
    px = base.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return base.resize((w, h), Image.BICUBIC).convert("RGBA")

BUBBLE = [620, 700, 3476, 3060]   # rounded body
RADIUS = 880
TAIL = [(1520, 2860), (1080, 3500), (2180, 2990)]

def bubble_mask():
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(BUBBLE, RADIUS, fill=255)
    d.polygon(TAIL, fill=255)
    return m

def panels(draw, colors):
    x0, y0, x1, y1 = 1100, 1180, 2996, 2600
    g = 120
    midy = y0 + (y1 - y0) * 0.46
    r = 110
    draw.rounded_rectangle([x0, y0, x1, midy - g / 2], r, fill=colors[0])
    # bottom row with a diagonal gutter
    top, bot = midy + g / 2, y1
    sx_top, sx_bot = x0 + (x1 - x0) * 0.62, x0 + (x1 - x0) * 0.50
    left = Image.new("L", (S, S), 0); dl = ImageDraw.Draw(left)
    dl.rounded_rectangle([x0, top, x1, bot], r, fill=255)
    cut = Image.new("L", (S, S), 0); dc = ImageDraw.Draw(cut)
    dc.polygon([(x0, top), (sx_top - g / 2, top), (sx_bot - g / 2, bot), (x0, bot)], fill=255)
    lmask = Image.composite(left, Image.new("L", (S, S), 0), cut)
    cut2 = Image.new("L", (S, S), 0); dc2 = ImageDraw.Draw(cut2)
    dc2.polygon([(sx_top + g / 2, top), (x1, top), (x1, bot), (sx_bot + g / 2, bot)], fill=255)
    rmask = Image.composite(left, Image.new("L", (S, S), 0), cut2)
    return lmask, rmask

def render(background, bubble_fill, colors, shadow_alpha):
    img = background.copy() if background is not None else Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = bubble_mask()
    if shadow_alpha:
        sh = Image.new("RGBA", (S, S), (30, 0, 40, 0))
        sh.putalpha(m.point(lambda v: v * shadow_alpha // 255))
        sh = sh.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -70)).filter(ImageFilter.GaussianBlur(90))
        img.alpha_composite(sh)
    body = Image.new("RGBA", (S, S), bubble_fill)
    img.paste(body, (0, 0), m)
    d = ImageDraw.Draw(img)
    lmask, rmask = panels(d, colors)
    img.paste(Image.new("RGBA", (S, S), colors[1]), (0, 0), lmask)
    img.paste(Image.new("RGBA", (S, S), colors[2]), (0, 0), rmask)
    return img.resize((1024, 1024), Image.LANCZOS)

light = render(gradient(INDIGO, CORAL), (255, 255, 255, 255), [P1, P2, P3], 120)
light.convert("RGB").save(f"{OUT}/AppIcon.png")
# Dark: transparent background (system supplies the dark backdrop), softened glyph.
dark = render(None, (236, 236, 244, 255), [(130, 126, 240), (240, 110, 134), (255, 178, 130)], 0)
dark.save(f"{OUT}/AppIcon-dark.png")
# Tinted: grayscale glyph on transparent; the system applies the user's tint.
tinted = render(None, (255, 255, 255, 255), [(150, 150, 150), (110, 110, 110), (185, 185, 185)], 0)
tinted.save(f"{OUT}/AppIcon-tinted.png")

# Preview: light / dark / tinted on home-screen-like backdrops, plus small sizes.
prev = Image.new("RGB", (1640, 640), (236, 236, 242))
def mask(n):
    mk = Image.new("L", (n, n), 0); ImageDraw.Draw(mk).rounded_rectangle([0, 0, n - 1, n - 1], int(n * 0.2237), fill=255); return mk
def on(bg, im, n):
    t = Image.new("RGBA", (n, n), bg + (255,)); t.alpha_composite(im.convert("RGBA").resize((n, n), Image.LANCZOS)); return t.convert("RGB")
tint = tinted.convert("RGBA").resize((440, 440), Image.LANCZOS)
r, g, b, a = tint.split(); gray = r
tcol = Image.merge("RGBA", (gray.point(lambda v: int(v * 0.98)), gray.point(lambda v: int(v * 0.78)), gray.point(lambda v: int(v * 0.40)), a))
tiles = [on((0, 0, 0), light, 440), on((28, 28, 32), dark, 440), on((24, 22, 18), tcol, 440)]
for i, t in enumerate(tiles):
    prev.paste(t, (40 + i * 540, 40), mask(440))
for j, n in enumerate([120, 76, 40]):
    prev.paste(light.convert("RGB").resize((n, n), Image.LANCZOS), (60 + j * 170, 520 - n // 2 + 40), mask(n))
if "--preview" in sys.argv:
    prev.save("final_preview.png")
