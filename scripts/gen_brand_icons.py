#!/usr/bin/env python3
"""Draw the self-hosted fork's brand icons from a source mark (the operator's
GitHub avatar: a black mark on white).

    uv run --with pillow python scripts/gen_brand_icons.py path/to/avatar.png

Writes, under src/missingmcp/static/:
    icon.png              256x256  header logo — white rounded tile, black mark
    favicon-32.png         32x32   same tile, small
    apple-touch-icon.png  180x180  full-bleed white square (iOS rounds it itself)

The file names are upstream's, so templates and tests keep working. The source is
small (200px), so the mark is re-cut as a clean mask at high resolution before
being scaled down — a plain resize of the avatar looks soft in the header.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATIC = os.path.join(ROOT, "src", "missingmcp", "static")

TILE = (255, 255, 255, 255)
MARK = (14, 16, 19, 255)          # --bg of the dark theme: a soft black
WORK = 2048                       # working canvas; every output is scaled down from it
MARK_SHARE = 0.66                 # mark's longest side as a share of the tile
RADIUS_SHARE = 0.22               # rounded-tile corner radius


def mark_mask(src_path: str):
    """The mark as a crisp high-resolution alpha mask, cropped to its bounds."""
    from PIL import Image, ImageFilter
    g = Image.open(src_path).convert("L")
    scale = max(1, (WORK * 2) // max(g.size))
    g = g.resize((g.width * scale, g.height * scale), Image.LANCZOS)
    g = g.filter(ImageFilter.GaussianBlur(scale * 0.6))      # round off pixel steps
    mask = g.point(lambda v: 255 if v < 128 else 0)          # dark pixels are the mark
    return mask.crop(mask.getbbox())


def tile(mask, rounded: bool):
    from PIL import Image, ImageDraw
    img = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle((0, 0, WORK - 1, WORK - 1), radius=int(WORK * RADIUS_SHARE), fill=TILE)
    else:
        d.rectangle((0, 0, WORK, WORK), fill=TILE)
    side = int(WORK * MARK_SHARE)
    k = side / max(mask.size)
    m = mask.resize((max(1, round(mask.width * k)), max(1, round(mask.height * k))), Image.LANCZOS)
    ink = Image.new("RGBA", m.size, MARK)
    img.paste(ink, ((WORK - m.width) // 2, (WORK - m.height) // 2), m)
    return img


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        from PIL import Image
    except ImportError:
        sys.exit("Pillow missing — run: uv run --with pillow python scripts/gen_brand_icons.py <avatar>")
    mask = mark_mask(sys.argv[1])
    for name, size, rounded in (("icon.png", 256, True),
                                ("favicon-32.png", 32, True),
                                ("apple-touch-icon.png", 180, False)):
        out = tile(mask, rounded).resize((size, size), Image.LANCZOS)
        out.save(os.path.join(STATIC, name), optimize=True)
        print(f"wrote {name} ({size}x{size})")


if __name__ == "__main__":
    main()
