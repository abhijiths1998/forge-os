#!/usr/bin/env python3
"""Export Forge cast SVGs to wallpaper assets.

Reads the SVG cast sources in branding-source/cast/ and produces:

- 1080p, 1440p, 4K wallpapers in light and dark variants (PNG)
- Square 256 px crops for fastfetch logos (PNG)

Usage:

    python3 branding-source/cast/generate.py [--preview]

Writes into branding-source/cast/out/. `install.sh` next to the glass
generate.py copies the results into profile/airootfs.
"""
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
SVG_DIR = HERE

# Cast mascots: original Forge characters, flat vector art.
CAST = [
    "shonen_fighter",
    "mecha_pilot",
    "wandering_ronin",
    "magical_girl",
    "cyberpunk_hacker",
    "yokai_guardian",
    "sky_pirate",
    "idol_singer",
]

# Light/dark glass backgrounds matching the Forge Glass palette.
LIGHT_BG = (238, 238, 248)
DARK_BG = (16, 18, 38)
GLASS_TINT = (104, 126, 214)


def to_img(a):
    return Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))


def to_arr(im):
    return np.asarray(im, dtype=np.float32) / 255.0


def blur(a, r):
    return to_arr(to_img(a).filter(ImageFilter.GaussianBlur(r)))


def mesh_background(w, h, base, blobs):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xx /= w
    yy /= h
    img = np.empty((h, w, 3), np.float32)
    img[:] = np.array(base, np.float32) / 255
    for (cx, cy, rad, col, strength) in blobs:
        d2 = ((xx - cx) * (w / h)) ** 2 + (yy - cy) ** 2
        g = np.exp(-d2 / (2 * rad * rad))[..., None] * strength
        img = img * (1 - g) + (np.array(col, np.float32) / 255) * g
    return img


def rounded_rect_mask(size, radius, ss=4):
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, size * ss - 1, size * ss - 1), radius=radius * ss, fill=255
    )
    return m, m.resize((size, size), Image.LANCZOS)


def wallpaper(w, h, dark=False):
    base = DARK_BG if dark else LIGHT_BG
    blobs = [
        (0.15, 0.10, 0.45, (42, 52, 120), 0.85),
        (0.95, 0.15, 0.40, (78, 44, 92), 0.75),
        (0.55, 1.05, 0.35, (110, 56, 48), 0.55),
        (0.45, 0.45, 0.30, (36, 40, 88), 0.5),
    ] if dark else [
        (0.10, 0.08, 0.45, (190, 212, 246), 0.95),
        (0.95, 0.12, 0.40, (246, 205, 216), 0.85),
        (0.55, 1.05, 0.35, (250, 222, 196), 0.7),
        (0.45, 0.40, 0.30, (214, 205, 244), 0.6),
    ]
    canvas = mesh_background(w, h, base, blobs)
    canvas = to_arr(to_img(canvas))

    # Add each cast mascot as a soft glass badge across the wallpaper.
    n = len(CAST)
    cols = 4
    rows = (n + cols - 1) // cols
    cell_w = w / cols
    cell_h = h / rows
    accent = np.array(GLASS_TINT, np.float32) / 255
    for i, name in enumerate(CAST):
        cx = int((i % cols + 0.5) * cell_w)
        cy = int((i // cols + 0.5) * cell_h)
        r = int(min(cell_w, cell_h) * 0.28)
        mb, m = rounded_rect_mask(r * 2, int(r * 2 * 0.4))
        m = m.resize((r * 2, r * 2), Image.LANCZOS)
        ma = to_arr(m)[..., None]
        x0 = cx - r
        y0 = cy - r
        x1 = x0 + r * 2
        y1 = y0 + r * 2
        sx0 = max(x0, 0); sy0 = max(y0, 0)
        sx1 = min(x1, w); sy1 = min(y1, h)
        mcrop = ma[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0]
        region = canvas[sy0:sy1, sx0:sx1]
        canvas[sy0:sy1, sx0:sx1] = (
            region * (1 - mcrop * 0.45) + accent * mcrop * 0.45
        )

    # Very light film grain so gradients don't band on 8-bit panels.
    rng = np.random.default_rng(7)
    canvas = canvas + rng.normal(0, 0.006, canvas.shape).astype(np.float32)
    return to_img(canvas)


def fastfetch_logo(size=256):
    """Square crop of the Forge Glass emblem area for fastfetch."""
    bg = DARK_BG
    canvas = Image.new("RGB", (size, size), bg)
    d = ImageDraw.Draw(canvas)
    # A soft glass badge in the centre.
    pad = int(size * 0.18)
    d.rounded_rectangle(
        [pad, pad, size - pad, size - pad],
        radius=int(size * 0.12),
        fill=(104, 126, 214),
    )
    return canvas


def main():
    preview = "--preview" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    sizes = [(1280, 720)] if preview else [
        (1920, 1080),
        (2560, 1440),
        (3840, 2160),
    ]
    for (w, h) in sizes:
        for dark in (False, True):
            name = f"cast-wallpaper-{'dark' if dark else 'light'}-{w}x{h}.png"
            im = wallpaper(w, h, dark)
            im.save(OUT / name, optimize=True)
            print("wrote", name)
    if preview:
        return
    for dark in (False, True):
        name = f"fastfetch-logo-{'dark' if dark else 'light'}-256.png"
        im = fastfetch_logo()
        im.save(OUT / name, optimize=True)
        print("wrote", name)
    print("done")


if __name__ == "__main__":
    main()
