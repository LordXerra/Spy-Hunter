#!/usr/bin/env python3
"""
Spy Hunter asset pipeline.

Reads the original ripped sprite sheet and produces the runtime assets:

  Sources/SpyHunter/Resources/spritesheet.png   sheet with the mint-green
                                                background key made transparent
  Sources/SpyHunter/Resources/title.jpg         title screen art (copied)
  Sources/SpyHunter/Resources/Music.mp3         music (copied)

The sprite *rectangles* live in Swift (Support/SpriteAtlas.swift) so they can be
tuned without re-running this script; this tool only does the colour-keying and
can additionally dump a segmentation report (--report) used to derive them.
"""

import json
import os
import shutil
import sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET_SRC = os.path.join(ROOT, "Sprites", "Spy Hunter Sprite Sheet.png")
TITLE_SRC = os.path.join(ROOT, "Sprites", "Spy Hunter Title Screen.jpg")
MUSIC_SRC = os.path.join(ROOT, "Music", "Music.mp3")
TITLE_MUSIC_SRC = os.path.join(ROOT, "Music", "Title Music.mp3")
RES = os.path.join(ROOT, "Sources", "SpyHunter", "Resources")

# The mint-green key colour used by the sheet's background.
BG = (186, 254, 202, 255)


def build_sheet():
    im = Image.open(SHEET_SRC).convert("RGBA")
    w, h = im.size
    px = im.load()
    cleared = 0
    for y in range(h):
        for x in range(w):
            if px[x, y] == BG:
                px[x, y] = (0, 0, 0, 0)
                cleared += 1
    out = os.path.join(RES, "spritesheet.png")
    im.save(out)
    print(f"spritesheet.png  {w}x{h}  ({cleared} background px -> transparent)")


# ---------------------------------------------------------------- font atlas
#
# The sheet stores its font as white letters on opaque black cells, which would
# render as black boxes over artwork. We re-emit the glyphs as a white-on-
# transparent alpha mask packed into a 16-column grid, so SpriteKit can tint
# text to any colour. Punctuation the arcade sheet lacks is drawn procedurally.

FONT_CELL = 16
FONT_COLS = 16
# Grid order. Space is a blank cell; everything after the digits is synthesised.
FONT_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:'-!?/<>"


def _sheet_glyph_positions():
    """char -> (x, y) of its 16x16 cell in the raw sheet."""
    pos = {}
    for i, ch in enumerate("ABCDEFGHIJKLMN"):        # y = 864
        pos[ch] = (240 + 24 * i, 864)
    for i, ch in enumerate("OPQRSTUVWXYZ"):          # y = 888
        pos[ch] = (8 + 24 * i, 888)
    for i, ch in enumerate("0123456789"):            # y = 888
        pos[ch] = (296 + 24 * i, 888)
    return pos


def _draw_punctuation(img, ch, ox, oy):
    """Draw white punctuation into the cell at (ox, oy)."""
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    W = (255, 255, 255, 255)

    def box(x0, y0, x1, y1):
        d.rectangle([ox + x0, oy + y0, ox + x1, oy + y1], fill=W)

    if ch == ".":
        box(6, 12, 8, 14)
    elif ch == ",":
        box(6, 11, 8, 13); box(5, 14, 7, 15)
    elif ch == ":":
        box(6, 4, 8, 6); box(6, 11, 8, 13)
    elif ch == "'":
        box(7, 2, 9, 6)
    elif ch == "-":
        box(3, 8, 12, 10)
    elif ch == "!":
        box(6, 2, 8, 10); box(6, 12, 8, 14)
    elif ch == "?":
        box(4, 2, 11, 4); box(9, 4, 11, 7); box(6, 7, 9, 9)
        box(6, 12, 8, 14)
    elif ch == "/":
        for k in range(13):
            d.rectangle([ox + 11 - k * 8 // 13, oy + 2 + k,
                         ox + 12 - k * 8 // 13, oy + 2 + k], fill=W)
    elif ch in "<>":
        # Solid triangles, used as the selector arrows.
        for k in range(6):
            y0, y1 = 8 - k, 8 + k
            x = (4 + k) if ch == "<" else (11 - k)
            d.rectangle([ox + x, oy + y0, ox + x, oy + y1], fill=W)


def build_font():
    src = Image.open(SHEET_SRC).convert("RGBA")
    spx = src.load()
    rows = (len(FONT_CHARS) + FONT_COLS - 1) // FONT_COLS
    out = Image.new("RGBA", (FONT_COLS * FONT_CELL, rows * FONT_CELL), (0, 0, 0, 0))
    opx = out.load()
    pos = _sheet_glyph_positions()

    for i, ch in enumerate(FONT_CHARS):
        ox = (i % FONT_COLS) * FONT_CELL
        oy = (i // FONT_COLS) * FONT_CELL
        if ch in pos:
            sx, sy = pos[ch]
            for yy in range(FONT_CELL):
                for xx in range(FONT_CELL):
                    r, g, b, a = spx[sx + xx, sy + yy]
                    if (r, g, b, a) == BG:
                        continue
                    # Luminance becomes alpha: white letter -> opaque,
                    # black cell -> fully transparent.
                    lum = (r * 299 + g * 587 + b * 114) // 1000
                    opx[ox + xx, oy + yy] = (255, 255, 255, lum)
        elif ch != " ":
            _draw_punctuation(out, ch, ox, oy)

    out.save(os.path.join(RES, "font.png"))
    print(f"font.png  {out.size[0]}x{out.size[1]}  ({len(FONT_CHARS)} glyphs)")


def copy_simple():
    # Renamed without the space so the bundle lookup key is simple.
    for src, name in ((TITLE_SRC, "title.jpg"),
                      (MUSIC_SRC, "Music.mp3"),
                      (TITLE_MUSIC_SRC, "TitleMusic.mp3")):
        if not os.path.exists(src):
            print(f"  !! missing {src}", file=sys.stderr)
            continue
        shutil.copy2(src, os.path.join(RES, name))
        print(f"{name}  ({os.path.getsize(src)} bytes)")


def report():
    """Dump band/column segmentation of the raw sheet (used to derive rects)."""
    im = Image.open(SHEET_SRC).convert("RGBA")
    w, h = im.size
    px = im.load()
    occ = [[px[x, y] != BG for x in range(w)] for y in range(h)]
    rowhas = [any(r) for r in occ]
    bands, y = [], 0
    while y < h:
        if rowhas[y]:
            y0 = y
            while y < h and rowhas[y]:
                y += 1
            bands.append((y0, y - 1))
        else:
            y += 1
    boxes = []
    for bi, (a, b) in enumerate(bands):
        colhas = [any(occ[yy][x] for yy in range(a, b + 1)) for x in range(w)]
        runs, x = [], 0
        while x < w:
            if colhas[x]:
                x0 = x
                while x < w and colhas[x]:
                    x += 1
                runs.append((x0, x - 1))
            else:
                x += 1
        for ri, (x0, x1) in enumerate(runs):
            ys = [yy for yy in range(a, b + 1)
                  if any(occ[yy][xx] for xx in range(x0, x1 + 1))]
            boxes.append(dict(band=bi, idx=ri, x=x0, y=min(ys),
                              w=x1 - x0 + 1, h=max(ys) - min(ys) + 1))
    print(json.dumps(boxes, indent=1))


if __name__ == "__main__":
    if "--report" in sys.argv:
        report()
    else:
        os.makedirs(RES, exist_ok=True)
        build_sheet()
        build_font()
        copy_simple()
        print("assets ok")
