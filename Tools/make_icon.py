#!/usr/bin/env python3
"""
Builds the macOS app icon from the project's own sprites.

Draws the G-6155 Interceptor on a stretch of road, in the game's palette, at
every size macOS asks for. Writes an .iconset directory; build_app.sh turns it
into AppIcon.icns with iconutil.
"""

import os
import sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = os.path.join(ROOT, "Sprites", "Spy Hunter Sprite Sheet.png")
BG = (186, 254, 202, 255)

# Player car, straight pose, from the sprite sheet.
CAR = (8, 12, 27, 44)

ROAD = (66, 66, 71, 255)
VERGE = (28, 107, 38, 255)
LINE = (235, 235, 235, 255)
EDGE = (245, 245, 245, 255)


def car_sprite():
    sheet = Image.open(SHEET).convert("RGBA")
    x, y, w, h = CAR
    car = sheet.crop((x, y, x + w, y + h))
    px = car.load()
    for yy in range(h):
        for xx in range(w):
            if px[xx, yy] == BG:
                px[xx, yy] = (0, 0, 0, 0)
    return car


def render(size, car):
    """Draws the icon at `size` px, keeping everything on a crisp pixel grid."""
    img = Image.new("RGBA", (size, size), VERGE)
    d = ImageDraw.Draw(img)

    # Road down the middle, with a margin of verge either side.
    road_w = int(size * 0.62)
    road_x0 = (size - road_w) // 2
    road_x1 = road_x0 + road_w
    d.rectangle([road_x0, 0, road_x1 - 1, size - 1], fill=ROAD)

    # Edge lines.
    ew = max(1, size // 64)
    d.rectangle([road_x0, 0, road_x0 + ew - 1, size - 1], fill=EDGE)
    d.rectangle([road_x1 - ew, 0, road_x1 - 1, size - 1], fill=EDGE)

    # Dashed centre line.
    dash_w = max(1, size // 96)
    dash_h = size // 10
    cx = size // 2
    yy = dash_h // 2
    while yy < size:
        d.rectangle([cx - dash_w, yy, cx + dash_w - 1, min(size - 1, yy + dash_h - 1)],
                    fill=LINE)
        yy += dash_h * 2

    # The car, scaled by an integer factor so the pixel art stays sharp.
    target_h = int(size * 0.60)
    scale = max(1, round(target_h / car.height))
    sprite = car.resize((car.width * scale, car.height * scale), Image.NEAREST)
    img.alpha_composite(sprite,
                        ((size - sprite.width) // 2, (size - sprite.height) // 2))
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.iconset"
    os.makedirs(out, exist_ok=True)
    car = car_sprite()
    # macOS iconset: each size at 1x and 2x.
    for base in (16, 32, 128, 256, 512):
        render(base, car).save(os.path.join(out, f"icon_{base}x{base}.png"))
        render(base * 2, car).save(os.path.join(out, f"icon_{base}x{base}@2x.png"))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
