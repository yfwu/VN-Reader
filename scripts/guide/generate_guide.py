#!/usr/bin/env python3
"""Generates the bundled user guide, one CBZ with Traditional Chinese and English side by side.

Pages are drawn here on macOS. UI labels come from App/Resources/Localizable.xcstrings ({key} in
the text below), so the guide keeps the app's wording.
    python3 scripts/guide/generate_guide.py
"""
import glob, io, json, math, os, re, zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "App", "Resources", "Localizable.xcstrings")
ICON = os.path.join(ROOT, "App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
OUT = os.path.join(ROOT, "App", "Resources", "Guide")
NAME = "VN Reader 使用說明 User Guide"

W, H = 1536, 2048
MARGIN = 110
PAPER, INK, MUTED = (251, 249, 244), (31, 36, 51), (104, 110, 124)
ACCENT, TINT, LINE = (38, 99, 214), (222, 233, 251), (205, 208, 214)
SCREEN, BAR = (255, 255, 255), (238, 239, 242)
COVERS = [(214, 92, 76), (72, 142, 120), (221, 170, 70), (92, 104, 190), (150, 96, 170), (70, 140, 190)]

PINGFANG = glob.glob("/System/Library/AssetsV2/com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc")[0]
FACES = {  # (path, ttc index) for regular and bold
    "zh-Hant": ((PINGFANG, 2), (PINGFANG, 10)),
    "en": (("/System/Library/Fonts/HelveticaNeue.ttc", 0), ("/System/Library/Fonts/HelveticaNeue.ttc", 1)),
}

# Each page: title, intro (or None), diagram name, then items. "n:" items carry a number shown in the diagram.
# The two languages list the same pages and items, which are shown one above the other.
TEXT = {
    "zh-Hant": {
        "subtitle": "離線閱讀你的 CBZ 與 CBR 漫畫",
        "hint": "向左滑動，或點畫面右側，翻到下一頁",
        "zone.toolbar": "顯示工具列",
        "formats": "格式",
        "pages": [
            ("開始之前", None, "welcome", [
                "VN Reader 是 iPad 的離線漫畫閱讀器，不需要帳號，也不會連網。",
                "支援 CBZ 與 CBR（RAR4、RAR5），頁面可以是 JPEG、PNG、WebP、GIF、HEIC 或 AVIF。",
                "App 不附帶漫畫，請匯入你自己的檔案。這本說明也是書庫裡的一本書，可以直接用它練習接下來介紹的操作。",
                "加密、分卷、7z 或 PDF 檔案無法匯入，App 會說明原因。"]),
            ("匯入漫畫", None, "import", [
                "1:點書庫右上角的「+」，從「檔案」App 選擇一本或多本。iCloud 雲碟的檔案會先下載。",
                "2:也可以把檔案拖進書庫，或從其他 App 用「打開方式」、AirDrop 傳給 VN Reader。",
                "3:檔案會複製到 App 內，之後可離線閱讀，原始檔不受影響。內容相同的檔案不會重複匯入。"]),
            ("書庫", None, "library", [
                "1:「{library.continue}」帶你回到上次讀到的地方。",
                "2:用搜尋列找書名、系列、作者或出版社。",
                "3:「{library.sort}」可以排序，也能只看{status.unread}、{status.reading}、{status.finished}或{library.filter.favorites}的書。",
                "4:點書上的「⋯」或長按封面，可以{book.rename}、{book.info.edit}、{book.favorite}或{book.delete}。刪除只影響 App 內的副本。",
                "5:點「{library.select}」可以一次編輯多本書的資訊。"]),
            ("翻頁", None, "zones", [
                "向左滑動或點畫面右側，到下一頁；向右滑動或點左側，回上一頁。",
                "點畫面中央，顯示或隱藏工具列。",
                "由右至左的書，左右方向會對調。",
                "接上實體鍵盤時，可以用方向鍵和空白鍵翻頁。",
                "不想點按翻頁的話，可以在「{settings.title}」關閉「{settings.tap}」。"]),
            ("工具列", "點畫面中央叫出工具列。", "toolbar", [
                "1:{reader.back}", "2:{reader.bookmark.add}", "3:{reader.settings}",
                "4:{reader.thumbnails}：瀏覽所有頁面，點一下就跳過去。",
                "5:拖動滑桿，快速移到任何一頁。",
                "6:點頁碼，輸入數字跳頁。"]),
            ("縮放", None, "zoom", [
                "兩指開合可以縮放，放大後用手指拖動畫面。",
                "點兩下放大，再點兩下還原。",
                "放大時不會翻頁，縮回原本大小後才能繼續翻頁。"]),
            ("閱讀設定", "在工具列打開「{reader.settings}」。每本書會各自記住方向、頁面顯示和版面。", "layouts", [
                "{reader.direction}：日本漫畫選「{reader.direction.rtl}」，切換後仍停在同一頁。",
                "{reader.fit}：「{reader.fit.page}」看完整頁面，「{reader.fit.width}」適合文字小的頁面，長條頁面可以上下捲動。",
                "{reader.layout}：{reader.layout.single}、{reader.layout.double}或{reader.layout.vertical}。",
                "新書的預設值可以在書庫左上角的「{settings.title}」更改。"]),
            ("書籤與進度", None, "bookmarks", [
                "點工具列的書籤圖示標記目前頁面，再點一次取消。",
                "在「{reader.thumbnails}」切換到「{reader.bookmarks}」，可以看到所有標記過的頁面。",
                "閱讀進度會自動儲存。下次打開同一本書，會回到離開時的那一頁。"]),
            ("隱私與這本說明", None, "shield", [
                "App 不使用網路、不蒐集資料，也沒有廣告或追蹤。",
                "書籍、進度和書籤都只存在 App 自己的儲存空間。刪除 App 時會一併刪除。",
                "讀完可以刪除這本說明。想再看的話，到「{settings.title}」的「{settings.about}」點「{guide.add}」。"]),
        ],
    },
    "en": {
        "subtitle": "Read your CBZ and CBR comics offline",
        "hint": "Swipe left or tap the right side to turn the page",
        "zone.toolbar": "Show toolbar",
        "formats": "Formats",
        "pages": [
            ("Before You Start", None, "welcome", [
                "VN Reader is an offline comic reader for iPad. It needs no account and never goes online.",
                "It opens CBZ and CBR (RAR4, RAR5) files, with pages in JPEG, PNG, WebP, GIF, HEIC or AVIF.",
                "The app comes without comics, so import your own files. This guide is a book in your library too: use it to try everything described on the next pages.",
                "Encrypted, multi-volume, 7z and PDF files can't be imported. The app explains why."]),
            ("Import Comics", None, "import", [
                "1:Tap + at the top right of the library and pick one or more books in the Files app. Files in iCloud Drive are downloaded first.",
                "2:You can also drag files into the library, or send them to VN Reader with Open in or AirDrop from another app.",
                "3:Books are copied into the app so they read offline, and your original files stay as they are. A file with identical content isn't imported twice."]),
            ("Library", None, "library", [
                "1:{library.continue} takes you back to where you stopped.",
                "2:Search by title, series, writer or publisher.",
                "3:{library.sort} changes the order, or shows only books that are {status.unread}, {status.reading}, {status.finished} or in {library.filter.favorites}.",
                "4:Tap … on a book or touch and hold its cover for Rename, Edit Info, Add to Favorites and Delete. Deleting only removes the app's copy.",
                "5:Tap {library.select} to edit the info of several books at once."]),
            ("Turning Pages", None, "zones", [
                "Swipe left or tap the right side for the next page. Swipe right or tap the left side to go back.",
                "Tap the center to show or hide the toolbar.",
                "In right-to-left books, left and right swap.",
                "With a hardware keyboard, use the arrow keys and the space bar.",
                "Prefer swiping only? Turn off “{settings.tap}” in {settings.title}."]),
            ("Toolbar", "Tap the center of the page to bring up the toolbar.", "toolbar", [
                "1:{reader.back}", "2:{reader.bookmark.add}", "3:{reader.settings}",
                "4:{reader.thumbnails}: browse all pages and tap one to jump to it.",
                "5:Drag the slider to move quickly to any page.",
                "6:Tap the page number and type a page to go to."]),
            ("Zoom", None, "zoom", [
                "Pinch to zoom, then drag to move around the page.",
                "Double-tap to zoom in, and double-tap again to reset.",
                "Pages don't turn while zoomed in. Zoom back out to keep reading."]),
            ("Reader Settings", "Open {reader.settings} in the toolbar. Each book remembers its own direction, page fit and layout.", "layouts", [
                "{reader.direction}: choose “{reader.direction.rtl}” for Japanese manga. You stay on the same page when you switch.",
                "{reader.fit}: {reader.fit.page} shows the whole page, {reader.fit.width} suits small text, and tall pages scroll up and down.",
                "{reader.layout}: {reader.layout.single}, {reader.layout.double} or {reader.layout.vertical}.",
                "Defaults for new books are in {settings.title}, at the top left of the library."]),
            ("Bookmarks and Progress", None, "bookmarks", [
                "Tap the bookmark icon in the toolbar to mark this page. Tap it again to remove the mark.",
                "In {reader.thumbnails}, switch to {reader.bookmarks} to see every marked page.",
                "Your progress is saved automatically. Open the book again and you're back on the same page."]),
            ("Privacy and This Guide", None, "shield", [
                "The app uses no network and collects no data. There are no ads and no tracking.",
                "Books, progress and bookmarks stay in the app's own storage. Deleting the app deletes them.",
                "You can delete this guide when you're done. To read it again, go to {settings.title}, {settings.about}, and tap {guide.add}."]),
        ],
    },
}

ZH, EN = "zh-Hant", "en"
NO_LINE_START = set("、。，．！？：；）」』”’〉》】～ー・…?!,.:;)%")
NO_LINE_END = set("（「『“‘〈《【(")


def load_font(lang, size, bold=False):
    path, index = FACES[lang][1 if bold else 0]
    return ImageFont.truetype(path, size, index=index)


def tokens(text):
    """Unbreakable pieces: words and numbers stay whole, CJK breaks between characters."""
    parts = re.findall(r"[A-Za-z0-9+/.,:;!?'’“”()%\-]+\s*|\s+|.", text)
    out = []
    for p in parts:
        if out and p[0] in NO_LINE_START:
            out[-1] += p
        elif out and out[-1][-1] in NO_LINE_END:
            out[-1] += p
        else:
            out.append(p)
    return out


def wrap(text, font, width):
    lines, line = [], ""
    for t in tokens(text):
        if line and font.getlength((line + t).rstrip()) > width:
            lines.append(line.rstrip())
            line = t.lstrip()
        else:
            line += t
    if line:
        lines.append(line.rstrip())
    return lines


def filled(s, lang):
    return re.sub(r"\{([\w.]+)\}", lambda m: label(m.group(1), lang), s)


def label(key, lang):
    if key in TEXT[lang]:
        return TEXT[lang][key]
    return STRINGS[key]["localizations"][lang]["stringUnit"]["value"]


def both(key):
    return f"{label(key, ZH)} {label(key, EN)}"


def badge(d, cx, cy, n, lang, r=34):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT)
    d.text((cx, cy), str(n), fill=(255, 255, 255), font=load_font("en", int(r * 1.25), True), anchor="mm")


def tablet(d, box):
    x0, y0, x1, y1 = box
    d.rounded_rectangle([x0 - 22, y0 - 22, x1 + 22, y1 + 22], radius=44, fill=(44, 48, 60))
    d.rounded_rectangle(box, radius=16, fill=SCREEN)


def arrow(d, a, b, color=ACCENT, width=10, head=26):
    d.line([a, b], fill=color, width=width)
    t = math.atan2(b[1] - a[1], b[0] - a[0])
    for s in (2.6, -2.6):
        d.line([b, (b[0] + head * math.cos(t + s), b[1] + head * math.sin(t + s))], fill=color, width=width)


def mini_page(d, box, seed=0):
    x0, y0, x1, y1 = box
    d.rectangle(box, fill=(246, 246, 248), outline=LINE, width=3)
    m = (x1 - x0) // 12
    mid = y0 + (y1 - y0) * (45 + seed * 7 % 15) // 100
    d.rectangle([x0 + m, y0 + m, x1 - m, mid - m // 3], outline=MUTED, width=3)
    split = x0 + (x1 - x0) * (40 + seed * 11 % 25) // 100
    d.rectangle([x0 + m, mid + m // 3, split - m // 3, y1 - m], outline=MUTED, width=3)
    d.rectangle([split + m // 3, mid + m // 3, x1 - m, y1 - m], outline=MUTED, width=3)


def plus(d, cx, cy, r, color, width=8):
    d.line([cx - r, cy, cx + r, cy], fill=color, width=width)
    d.line([cx, cy - r, cx, cy + r], fill=color, width=width)


def ribbon(d, cx, y0, w, h, color):
    d.polygon([(cx - w, y0), (cx + w, y0), (cx + w, y0 + h), (cx, y0 + h - w), (cx - w, y0 + h)], fill=color)


def doc_icon(d, x, y, text, lang):
    d.rounded_rectangle([x, y, x + 220, y + 280], radius=20, fill=SCREEN, outline=INK, width=6)
    d.text((x + 110, y + 150), text, fill=INK, font=load_font("en", 64, True), anchor="mm")


def diagram_welcome(d, y, lang):
    x = MARGIN
    for name in ("CBZ", "CBR"):
        doc_icon(d, x + 150, y + 10, name, lang)
        x += 300
    arrow(d, (x + 190, y + 150), (x + 330, y + 150))
    tablet(d, (x + 390, y + 10, x + 620, y + 290))
    mini_page(d, (x + 415, y + 35, x + 595, y + 265), 2)
    return 310


def diagram_import(d, y, lang):
    doc_icon(d, MARGIN + 40, y + 90, "CBZ", lang)
    arrow(d, (MARGIN + 300, y + 230), (MARGIN + 470, y + 230))
    box = (MARGIN + 540, y + 22, W - MARGIN - 22, y + 438)
    tablet(d, box)
    x0, y0, x1, _ = box
    d.rectangle([x0, y0, x1, y0 + 92], fill=BAR)
    plus(d, x1 - 60, y0 + 46, 24, ACCENT)
    d.text((x0 + 40, y0 + 46), both("library.title"), fill=INK, font=load_font(lang, 40, True), anchor="lm")
    for i in range(3):
        cx = x0 + 50 + i * 200
        d.rounded_rectangle([cx, y0 + 130, cx + 160, y0 + 370], radius=8, fill=COVERS[i])
    badge(d, x1 - 60, y0 + 140, 1, lang)
    badge(d, MARGIN + 385, y + 170, 2, lang)
    badge(d, x0 + 130, y0 + 250, 3, lang)
    return 470


def diagram_library(d, y, lang):
    box = (MARGIN + 22, y + 22, W - MARGIN - 22, y + 560)
    tablet(d, box)
    x0, y0, x1, y1 = box
    d.rectangle([x0, y0, x1, y0 + 84], fill=BAR)
    d.text((x0 + 36, y0 + 42), both("library.title"), fill=INK, font=load_font(lang, 38, True), anchor="lm")
    sort_x = x1 - 72
    d.ellipse([sort_x - 22, y0 + 20, sort_x + 22, y0 + 64], outline=ACCENT, width=5)
    for i, half in enumerate((13, 9, 5)):
        d.line([sort_x - half, y0 + 32 + i * 10, sort_x + half, y0 + 32 + i * 10], fill=ACCENT, width=4)
    d.rounded_rectangle([x0 + 36, y0 + 104, x1 - 36, y0 + 164], radius=16, fill=BAR)
    d.text((x0 + 62, y0 + 134), both("library.search"), fill=MUTED, font=load_font(lang, 30), anchor="lm")
    d.rounded_rectangle([x0 + 36, y0 + 184, x1 - 36, y0 + 284], radius=14, fill=TINT)
    d.rectangle([x0 + 54, y0 + 198, x0 + 110, y0 + 270], fill=COVERS[0])
    d.text((x0 + 132, y0 + 234), both("library.continue"), fill=INK, font=load_font(lang, 34, True), anchor="lm")
    for i in range(5):
        cx = x0 + 44 + i * 232
        d.rounded_rectangle([cx, y0 + 304, cx + 190, y0 + 496], radius=8, fill=COVERS[i + 1])
    d.text((x0 + 44 + 232 + 165, y0 + 332), "⋯", fill=(255, 255, 255), font=load_font("zh-Hant", 48, True), anchor="mm")
    badge(d, x1 - 110, y0 + 234, 1, lang)
    badge(d, x1 - 110, y0 + 134, 2, lang)
    badge(d, sort_x - 96, y0 + 42, 3, lang)
    badge(d, x0 + 44 + 232 + 95, y0 + 410, 4, lang)
    w = load_font(lang, 34).getlength(both("library.select"))
    d.text((sort_x - 150 - w, y0 + 42), both("library.select"), fill=ACCENT, font=load_font(lang, 34), anchor="lm")
    badge(d, sort_x - 200 - w, y0 + 42, 5, lang)
    return 590


def diagram_zones(d, y, lang):
    box = (MARGIN + 22, y + 22, W - MARGIN - 22, y + 480)
    tablet(d, box)
    x0, y0, x1, y1 = box
    width = x1 - x0
    side = int(width * 0.3)
    d.rectangle([x0, y0, x0 + side, y1], fill=(230, 233, 240))
    d.rectangle([x1 - side, y0, x1, y1], fill=TINT)
    d.line([x0 + side, y0, x0 + side, y1], fill=LINE, width=3)
    d.line([x1 - side, y0, x1 - side, y1], fill=LINE, width=3)
    cy = (y0 + y1) // 2
    font = load_font(lang, 38, True)
    arrow(d, (x0 + side // 2 + 60, cy - 60), (x0 + side // 2 - 60, cy - 60), MUTED)
    arrow(d, (x1 - side // 2 - 60, cy - 60), (x1 - side // 2 + 60, cy - 60))
    for text, cx, color in ((both("reader.prev"), x0 + side // 2, MUTED), (both("zone.toolbar"), x0 + width // 2, INK),
                            (both("reader.next"), x1 - side // 2, ACCENT)):
        for i, line in enumerate(wrap(text, font, side - 30)):
            d.text((cx, cy + 40 + i * 50), line, fill=color, font=font, anchor="mm")
    d.ellipse([x0 + width // 2 - 34, cy - 94, x0 + width // 2 + 34, cy - 26], outline=INK, width=6)
    return 510


def diagram_toolbar(d, y, lang):
    box = (MARGIN + 22, y + 22, W - MARGIN - 22, y + 450)
    tablet(d, box)
    x0, y0, x1, y1 = box
    mid = (x0 + x1) // 2
    mini_page(d, (mid - 130, y0 + 120, mid + 130, y1 - 120), 3)
    d.rectangle([x0, y0, x1, y0 + 100], fill=BAR)
    d.rectangle([x0, y1 - 100, x1, y1], fill=BAR)
    d.line([(x0 + 54, y0 + 28), (x0 + 30, y0 + 50), (x0 + 54, y0 + 72)], fill=ACCENT, width=7, joint="curve")
    badge(d, x0 + 116, y0 + 50, 1, lang)
    ribbon(d, x1 - 220, y0 + 26, 18, 52, ACCENT)
    badge(d, x1 - 150, y0 + 50, 2, lang)
    for i, knob in enumerate((30, -14, 18)):
        ly = y0 + 34 + i * 16
        d.line([x1 - 96, ly, x1 - 36, ly], fill=ACCENT, width=4)
        d.ellipse([x1 - 66 + knob - 6, ly - 6, x1 - 66 + knob + 6, ly + 6], fill=ACCENT)
    badge(d, x1 - 66, y0 + 142, 3, lang)
    by = y1 - 50
    for i in range(3):
        for j in range(3):
            gx, gy = x0 + 28 + i * 18, by - 24 + j * 18
            d.rectangle([gx, gy, gx + 12, gy + 12], fill=ACCENT)
    badge(d, x0 + 130, by, 4, lang)
    d.line([x0 + 210, by, x1 - 280, by], fill=LINE, width=8)
    d.line([x0 + 210, by, mid + 40, by], fill=ACCENT, width=8)
    d.ellipse([mid + 16, by - 24, mid + 64, by + 24], fill=SCREEN, outline=LINE, width=3)
    badge(d, mid + 40, by - 76, 5, lang)
    d.text((x1 - 180, by), "12 / 30", fill=INK, font=load_font("en", 36), anchor="mm")
    badge(d, x1 - 58, by, 6, lang)
    return 480


def diagram_zoom(d, y, lang):
    box = (MARGIN + 300, y + 22, W - MARGIN - 300, y + 560)
    tablet(d, box)
    x0, y0, x1, y1 = box
    mini_page(d, (x0 + 50, y0 + 44, x1 - 50, y1 - 44), 1)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    for sx, sy in ((-1, 1), (1, -1)):
        px, py = cx + sx * 70, cy + sy * 70
        d.ellipse([px - 42, py - 42, px + 42, py + 42], fill=(*ACCENT, ), outline=SCREEN, width=6)
        arrow(d, (px + sx * 56, py + sy * 56), (px + sx * 150, py + sy * 150))
    return 590


def diagram_layouts(d, y, lang):
    gap, tile = 40, (W - 2 * MARGIN - 2 * 40) // 3
    font = load_font(lang, 30, True)
    for i, key in enumerate(("reader.layout.single", "reader.layout.double", "reader.layout.vertical")):
        x = MARGIN + i * (tile + gap)
        d.rounded_rectangle([x, y, x + tile, y + 400], radius=20, fill=TINT)
        cx = x + tile // 2
        if i == 0:
            mini_page(d, (cx - 95, y + 34, cx + 95, y + 290), 0)
        elif i == 1:
            mini_page(d, (cx - 180, y + 66, cx, y + 280), 1)
            mini_page(d, (cx, y + 66, cx + 180, y + 280), 2)
        else:
            mini_page(d, (cx - 80, y + 34, cx + 80, y + 150), 3)
            mini_page(d, (cx - 80, y + 174, cx + 80, y + 290), 4)
            arrow(d, (cx + 130, y + 80), (cx + 130, y + 250))
        for j, line in enumerate(wrap(both(key), font, tile - 24)):
            d.text((cx, y + 326 + j * 38), line, fill=INK, font=font, anchor="mm")
    return 430


def diagram_bookmarks(d, y, lang):
    gap, tile = 30, 200
    start = (W - (tile * 5 + gap * 4)) // 2
    for i in range(5):
        x = start + i * (tile + gap)
        mini_page(d, (x, y + 20, x + tile, y + 290), i)
        d.text((x + tile // 2, y + 326), str(i + 1), fill=MUTED, font=load_font("en", 32), anchor="mm")
        if i in (1, 3):
            ribbon(d, x + tile - 44, y + 20, 20, 74, ACCENT)
    return 360


def diagram_shield(d, y, lang):
    cx = W // 2
    d.polygon([(cx - 130, y + 30), (cx, y), (cx + 130, y + 30), (cx + 130, y + 170), (cx, y + 280), (cx - 130, y + 170)], fill=TINT)
    d.rounded_rectangle([cx - 54, y + 100, cx + 54, y + 186], radius=10, fill=ACCENT)
    d.arc([cx - 36, y + 54, cx + 36, y + 136], 180, 360, fill=ACCENT, width=12)
    return 300


DIAGRAMS = {"welcome": diagram_welcome, "import": diagram_import, "library": diagram_library, "zones": diagram_zones,
            "toolbar": diagram_toolbar, "zoom": diagram_zoom, "layouts": diagram_layouts,
            "bookmarks": diagram_bookmarks, "shield": diagram_shield}


def cover():
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    size = 520
    icon = Image.open(ICON).convert("RGB").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=size, fill=255)
    img.paste(icon, ((W - size) // 2, 400), mask.resize((size, size), Image.LANCZOS))
    d.text((W // 2, 1070), "VN Reader", fill=INK, font=load_font(EN, 120, True), anchor="mm")
    d.text((W // 2, 1210), "使用說明", fill=INK, font=load_font(ZH, 96, True), anchor="mm")
    d.text((W // 2, 1320), "User Guide", fill=INK, font=load_font(EN, 72), anchor="mm")
    d.text((W // 2, 1430), label("subtitle", ZH), fill=MUTED, font=load_font(ZH, 46), anchor="mm")
    d.text((W // 2, 1496), label("subtitle", EN), fill=MUTED, font=load_font(EN, 42), anchor="mm")
    d.text((W // 2, H - 260), label("hint", ZH), fill=ACCENT, font=load_font(ZH, 42, True), anchor="mm")
    d.text((W // 2, H - 196), label("hint", EN), fill=ACCENT, font=load_font(EN, 38, True), anchor="mm")
    return img


def paragraph(d, x, y, text, width, zh_color, en_color):
    """Chinese above English; returns the y after both."""
    for lang, size, leading, color, s in ((ZH, 44, 62, zh_color, text[0]), (EN, 37, 49, en_color, text[1])):
        font = load_font(lang, size)
        for line in wrap(filled(s, lang), font, width):
            d.text((x, y), line, fill=color, font=font, anchor="lm")
            y += leading
    return y


def page(number, total, zh, en):
    title, intro, diagram, items = zh
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    d.text((MARGIN, 130), filled(title, ZH), fill=INK, font=load_font(ZH, 80, True), anchor="lm")
    d.text((MARGIN, 214), filled(en[0], EN), fill=MUTED, font=load_font(EN, 48), anchor="lm")
    y = 280
    if intro:
        y = paragraph(d, MARGIN, y, (intro, en[1]), W - 2 * MARGIN, MUTED, MUTED)
    y += 24
    y += DIAGRAMS[diagram](d, y, ZH) + 44
    indent = 84
    for zh_item, en_item in zip(items, en[3], strict=True):
        n = None
        if re.match(r"\d:", zh_item):
            n, zh_item, en_item = int(zh_item[0]), zh_item[2:], en_item[2:]
        if n:
            badge(d, MARGIN + 30, y + 4, n, ZH, 30)
        else:
            d.ellipse([MARGIN + 18, y - 8, MARGIN + 42, y + 16], fill=ACCENT)
        y = paragraph(d, MARGIN + indent, y, (zh_item, en_item), W - 2 * MARGIN - indent, INK, MUTED) + 24
    if y > H - 110:
        raise SystemExit(f"page {number} overflows by {y - (H - 110)}px: {title}")
    d.text((W // 2, H - 70), f"{number} / {total}", fill=MUTED, font=load_font(EN, 34), anchor="mm")
    return img


def png(img):
    b = io.BytesIO()
    img.quantize(colors=128, dither=Image.Dither.NONE).save(b, "PNG", optimize=True)
    return b.getvalue()


def main():
    os.makedirs(OUT, exist_ok=True)
    specs = list(zip(TEXT[ZH]["pages"], TEXT[EN]["pages"], strict=True))
    total = len(specs) + 1
    pages = [cover()] + [page(i + 2, total, zh, en) for i, (zh, en) in enumerate(specs)]
    path = os.path.join(OUT, NAME + ".cbz")
    # A fixed timestamp keeps the file, and so its duplicate fingerprint, stable between runs.
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
        for i, p in enumerate(pages, 1):
            z.writestr(zipfile.ZipInfo(f"{i:02d}.png", date_time=(2026, 1, 1, 0, 0, 0)), png(p))
    print(os.path.getsize(path), os.path.basename(path))


STRINGS = json.load(open(CATALOG, encoding="utf-8"))["strings"]

if __name__ == "__main__":
    main()
