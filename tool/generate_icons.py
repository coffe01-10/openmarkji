"""Render the app's Material book glyph into platform icons.

Usage: python tool/generate_icons.py <Flutter SDK>/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf
Requires Pillow.
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = sys.argv[1]
SIZE = 2048
INK = "#425f98"
PAPER = "#faf9ff"


def book(fraction):
    image = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, round(SIZE * fraction))
    glyph = chr(0xF59C)  # Icons.auto_stories_rounded
    left, top, right, bottom = draw.textbbox((0, 0), glyph, font=font)
    draw.text(
        ((SIZE - right - left) / 2, (SIZE - bottom - top) / 2),
        glyph,
        font=font,
        fill=INK,
    )
    return image


def tile():
    mask = Image.new("L", (SIZE, SIZE))
    points = []
    for index in range(512):
        angle = math.tau * index / 512
        x, y = math.cos(angle), math.sin(angle)
        points.append((
            SIZE / 2 + (SIZE / 2 - 1) * math.copysign(abs(x) ** .45, x),
            SIZE / 2 + (SIZE / 2 - 1) * math.copysign(abs(y) ** .45, y),
        ))
    ImageDraw.Draw(mask).polygon(points, fill=255)
    image = Image.new("RGBA", (SIZE, SIZE), PAPER)
    image.alpha_composite(book(.64))
    image.putalpha(mask)
    return image


def save(image, relative, size):
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(path)


icon = tile()
save(icon, "assets/logo/app_icon.png", 1024)
foreground = book(.5)
for density, legacy, adaptive in [
    ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
]:
    base = f"android/app/src/main/res/mipmap-{density}"
    save(icon, f"{base}/ic_launcher.png", legacy)
    save(foreground, f"{base}/ic_launcher_foreground.png", adaptive)

maskable = Image.new("RGBA", (SIZE, SIZE), PAPER)
maskable.alpha_composite(book(.58))
for size in (192, 512):
    save(icon, f"web/icons/Icon-{size}.png", size)
    save(maskable, f"web/icons/Icon-maskable-{size}.png", size)
save(icon, "web/favicon.png", 64)
icon.resize((256, 256), Image.Resampling.LANCZOS).save(
    ROOT / "windows/runner/resources/app_icon.ico",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
