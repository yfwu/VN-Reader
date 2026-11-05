#!/usr/bin/env python3
"""Generates the app icon (light, dark, tinted): a hand holding a comic book.

    python3 scripts/icon/generate_app_icon.py App/Resources/Assets.xcassets/AppIcon.appiconset [--preview]

Requires Pillow. --preview also writes final_preview.png (light / dark / tinted +
small sizes) to the current directory (not into the asset catalog).
"""
import sys, math
from PIL import Image, ImageDraw, ImageFilter
S = 4096
OUT = sys.argv[1]
INDIGO, CORAL = (92, 88, 222), (238, 88, 112)
P1, P2, P3 = (112, 108, 232), (238, 98, 124), (255, 168, 116)
SKIN, SKIN_D = (255, 206, 170), (238, 172, 136)

def gradient(c1, c2):
    b = Image.new("RGB", (256, 256)); px = b.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return b.resize((S, S), Image.BICUBIC).convert("RGBA")

def rotated_shape(size, draw_fn, angle, center):
    """Draw on an axis-aligned layer, rotate, and return a full-canvas RGBA layer."""
    w, h = size
    pad = int(max(w, h) * 0.75)
    layer = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer), pad, pad, w, h)
    layer = layer.rotate(angle, resample=Image.BICUBIC, expand=False)
    full = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    full.alpha_composite(layer, (int(center[0] - layer.width / 2), int(center[1] - layer.height / 2)))
    return full

def capsule(color, length, width, angle, center):
    def f(d, x, y, w, h):
        d.rounded_rectangle([x, y, x + w, y + h], h // 2, fill=color)
    return rotated_shape((length, width), f, angle, center)

def drop_shadow(layer, blur, dy, alpha):
    a = layer.split()[3].point(lambda v: v * alpha // 255)
    sh = Image.new("RGBA", (S, S), (40, 0, 50, 0)); sh.putalpha(a)
    sh = sh.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -dy)).filter(ImageFilter.GaussianBlur(blur))
    return sh

PAGE_ANGLE = 6
PAGE_C = (2080, 1700)
PAGE_W, PAGE_H = 2050, 2640

def page_layer(fill, panel_colors, edge):
    def f(d, x, y, w, h):
        # book thickness: page block peeking out to the right / bottom
        d.rounded_rectangle([x + 70, y + 60, x + w + 70, y + h + 60], 150, fill=edge)
        d.rounded_rectangle([x, y, x + w, y + h], 150, fill=fill)
        m, g, r = 160, 110, 90
        x0, y0, x1, y1 = x + m, y + m, x + w - m, y + h - m
        mid = y0 + (y1 - y0) * 0.40
        d.rounded_rectangle([x0, y0, x1, mid - g / 2], r, fill=panel_colors[0])
        top, bot = mid + g / 2, y1
        sx_t, sx_b = x0 + (x1 - x0) * 0.60, x0 + (x1 - x0) * 0.46
        d.polygon([(x0 + r, top), (sx_t - g / 2, top), (sx_b - g / 2, bot), (x0 + r, bot)], fill=panel_colors[1])
        d.rounded_rectangle([x0, top, x0 + 2 * r, bot], r, fill=panel_colors[1])
        d.polygon([(sx_t + g / 2, top), (x1 - r, top), (x1 - r, bot), (sx_b + g / 2, bot)], fill=panel_colors[2])
        d.rounded_rectangle([x1 - 2 * r, top, x1, bot], r, fill=panel_colors[2])
    return rotated_shape((PAGE_W + 80, PAGE_H + 70), f, PAGE_ANGLE, PAGE_C)

def blob(color, box):
    l = Image.new("RGBA", (S, S), (0, 0, 0, 0)); ImageDraw.Draw(l).ellipse(box, fill=color); return l

def render(bg, page_fill, panels, skin, skin_d, edge=(214, 208, 240, 255), shadows=True):
    img = bg.copy() if bg is not None else Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # --- behind the book: wrist, palm and fingertips wrapping around the right edge ---
    back = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    back.alpha_composite(capsule(skin_d, 1700, 1080, 80, (1800, 3980)))       # wrist (off-canvas)
    back.alpha_composite(blob(skin_d, [1050, 2650, 2650, 3900]))              # palm
    for cy in (1990, 2290, 2590):                                             # fingertips on the right
        back.alpha_composite(capsule(skin, 900, 280, 6, (3040, cy)))
    if shadows: img.alpha_composite(drop_shadow(back, 60, 30, 60))
    img.alpha_composite(back)
    page = page_layer(page_fill, panels, edge)
    if shadows: img.alpha_composite(drop_shadow(page, 110, 70, 130))
    img.alpha_composite(page)
    # --- in front: thumb gripping the lower-left of the cover ---
    front = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # thumb: base inside the palm, tip resting on the cover's lower-left
    front.alpha_composite(blob(skin, [1150, 2860, 1850, 3480]))               # thenar (thumb root)
    front.alpha_composite(capsule(skin, 1250, 420, 56, (1560, 2760)))
    if shadows: img.alpha_composite(drop_shadow(front, 50, 35, 110))
    img.alpha_composite(front)
    return img.resize((1024, 1024), Image.LANCZOS)

light = render(gradient(INDIGO, CORAL), (255, 255, 255, 255), [P1, P2, P3], SKIN + (255,), SKIN_D + (255,))
light.convert("RGB").save(f"{OUT}/AppIcon.png")
dark = render(None, (236, 236, 244, 255), [(130, 126, 240), (240, 110, 134), (255, 178, 130)],
              (240, 196, 164, 255), (214, 162, 130, 255), edge=(170, 166, 200, 255), shadows=False)
dark.save(f"{OUT}/AppIcon-dark.png")
tinted = render(None, (255, 255, 255, 255), [(150, 150, 150), (110, 110, 110), (185, 185, 185)],
                (205, 205, 205, 255), (170, 170, 170, 255), edge=(225, 225, 225, 255), shadows=False)
tinted.save(f"{OUT}/AppIcon-tinted.png")

if "--preview" in sys.argv:
    prev = Image.new("RGB", (1640, 640), (236, 236, 242))
    def mask(n):
        mk = Image.new("L", (n, n), 0); ImageDraw.Draw(mk).rounded_rectangle([0, 0, n - 1, n - 1], int(n * 0.2237), fill=255); return mk
    def on(bgc, im, n):
        t = Image.new("RGBA", (n, n), bgc + (255,)); t.alpha_composite(im.convert("RGBA").resize((n, n), Image.LANCZOS)); return t.convert("RGB")
    t = tinted.convert("RGBA").resize((440, 440), Image.LANCZOS); r, g, b, a = t.split()
    tcol = Image.merge("RGBA", (r.point(lambda v: int(v * .98)), r.point(lambda v: int(v * .78)), r.point(lambda v: int(v * .40)), a))
    for i, tile in enumerate([on((0, 0, 0), light, 440), on((28, 28, 32), dark, 440), on((24, 22, 18), tcol, 440)]):
        prev.paste(tile, (40 + i * 540, 40), mask(440))
    for j, n in enumerate([120, 76, 40]):
        prev.paste(light.convert("RGB").resize((n, n), Image.LANCZOS), (60 + j * 170, 520 - n // 2 + 40), mask(n))
    prev.save("final_preview.png")
