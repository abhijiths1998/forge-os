#!/usr/bin/env python3
"""Generate the "Forge Glass" branding assets.

Everything here is procedural so the look can be re-tuned and re-rendered
instead of hand-edited: wallpapers (light + dark), the glass logo tile,
SDDM/GRUB backgrounds and Plymouth assets.

    python3 branding-source/glass/generate.py [--preview]

Writes into branding-source/glass/out/; `install.sh` next to this file
copies the results into profile/airootfs.
"""
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
EMBLEM = HERE.parent / "forge-os-emblem-minimal.png"
# Plus Jakarta Sans (variable) for the baked wordmark: the copy shipped in
# the profile, so rendering needs nothing installed on the host.
UI_FONT = Path(os.environ.get(
    "FORGE_UI_TTF",
    HERE.parents[1] / "profile/airootfs/usr/share/fonts/plus-jakarta-sans/PlusJakartaSans-Variable.ttf"))
TAGLINE = "Built hot. Runs cool."

# Palette: the five pastels plus the two working colours. Kept in sync with
# the colour schemes in profile/airootfs/usr/share/color-schemes/.
ICE = (157, 190, 240)
ROSE = (242, 184, 198)
PEACH = (246, 207, 168)
LILAC = (195, 183, 238)
SAGE = (191, 214, 195)
PERIWINKLE = (108, 124, 240)
EMBER = (243, 150, 112)
NAVY = (30, 33, 64)


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def to_img(a):
    return Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))


def to_arr(im):
    return np.asarray(im, dtype=np.float32) / 255.0


def blur(a, r):
    """Gaussian blur a float HxW or HxWx3 array via PIL (8-bit is plenty here)."""
    return to_arr(to_img(a).filter(ImageFilter.GaussianBlur(r)))


def mesh_background(w, h, base, blobs):
    """Soft mesh gradient: a base colour with large gaussian colour blobs."""
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


def bezier(p0, p1, p2, p3, n=200):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2, p3 = map(np.array, (p0, p1, p2, p3))
    return ((1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1
            + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3)


def blade_polygon(base_l, base_r, tip, curl, w, h):
    """A flame-like blade rising from the bottom edge and curling at the tip.

    Coordinates are in units of screen height (x may exceed 1 on 16:9)."""
    tx, ty = tip
    # Left edge sweeps up in an S; right edge dips into a hollow just below
    # the tip, which is what makes it read as a flame rather than a hill.
    left = bezier((base_l, 1.08), (base_l + 0.10, 0.70),
                  (tx - 0.22 - curl * 0.25, ty + 0.18), (tx, ty))
    right = bezier((tx, ty), (tx - 0.10 - curl * 0.15, ty + 0.10),
                   (base_r - 0.12, 0.62), (base_r, 1.08))
    pts = np.vstack([left, right])
    return [(float(x) * h, float(y) * h) for x, y in pts]


def mask_from_polygon(poly, w, h, ss=2):
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).polygon([(x * ss, y * ss) for x, y in poly], fill=255)
    return m, m.resize((w, h), Image.LANCZOS)


def glass_layer(canvas, mask_big, mask, col_bottom, col_top, opacity, dark):
    """Composite one frosted-glass shape onto canvas (float HxWx3)."""
    h, w = canvas.shape[:2]
    m = to_arr(mask)[..., None]

    # Soft drop shadow, slightly below the shape.
    shadow = blur(to_arr(mask), h * 0.03)
    dy = int(h * 0.012)
    shadow = np.concatenate([np.zeros_like(shadow[:dy]), shadow[:-dy]])[..., None]
    canvas = canvas * (1 - shadow * (0.22 if dark else 0.10))

    # Frost: what's behind the glass is blurred and tinted.
    behind = blur(canvas, h * 0.02)
    yy = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    tint = (np.array(col_top, np.float32) * (1 - yy)
            + np.array(col_bottom, np.float32) * yy) / 255
    glass = behind * (1 - opacity) + tint * opacity

    # Fresnel-ish inner glow: brighter towards the edges of the shape.
    inner = to_arr(mask) - blur(to_arr(mask), h * 0.025)
    inner = np.clip(inner * 2.2, 0, 1)[..., None]
    glass = glass + (1 - glass) * inner * (0.35 if dark else 0.55)

    canvas = canvas * (1 - m) + glass * m

    # Thin bright rim line.
    ss = mask_big.size[0] // w
    er = mask_big.filter(ImageFilter.MinFilter(2 * ss + 1))
    rim = ImageChops.subtract(mask_big, er).resize((w, h), Image.LANCZOS)
    rim = to_arr(rim)[..., None]
    rim_col = np.array((235, 238, 255) if dark else (255, 255, 255), np.float32) / 255
    canvas = canvas * (1 - rim * (0.45 if dark else 0.85)) + rim_col * rim * (0.45 if dark else 0.85)
    return canvas


def wallpaper(w, h, dark=False):
    if dark:
        bg = mesh_background(w, h, (16, 18, 38), [
            (0.15, 0.10, 0.45, (42, 52, 120), 0.85),
            (0.95, 0.15, 0.40, (78, 44, 92), 0.75),
            (0.55, 1.05, 0.35, (110, 56, 48), 0.55),
            (0.45, 0.45, 0.30, (36, 40, 88), 0.5),
        ])
        blades = [
            # base_l, base_r, tip, curl, bottom colour, top colour, opacity
            (0.20, 0.85, (0.80, 0.10), 0.0, (70, 64, 140), (104, 126, 214), 0.45),
            (0.85, 1.40, (1.30, 0.20), 0.2, (128, 66, 104), (96, 86, 176), 0.45),
            (-0.30, 0.35, (0.30, 0.34), 0.1, (54, 72, 146), (92, 84, 168), 0.45),
            (1.25, 1.95, (1.78, 0.30), 0.3, (170, 88, 70), (126, 74, 120), 0.48),
            (0.45, 1.05, (0.98, 0.44), 0.2, (190, 104, 78), (104, 94, 180), 0.5),
            (1.05, 1.55, (1.44, 0.58), 0.1, (206, 120, 86), (150, 92, 140), 0.5),
        ]
    else:
        bg = mesh_background(w, h, (238, 238, 248), [
            (0.10, 0.08, 0.45, (190, 212, 246), 0.95),
            (0.95, 0.12, 0.40, (246, 205, 216), 0.85),
            (0.55, 1.05, 0.35, (250, 222, 196), 0.7),
            (0.45, 0.40, 0.30, (214, 205, 244), 0.6),
        ])
        blades = [
            (0.20, 0.85, (0.80, 0.10), 0.0, LILAC, ICE, 0.40),
            (0.85, 1.40, (1.30, 0.20), 0.2, ROSE, LILAC, 0.40),
            (-0.30, 0.35, (0.30, 0.34), 0.1, ICE, LILAC, 0.38),
            (1.25, 1.95, (1.78, 0.30), 0.3, PEACH, ROSE, 0.40),
            (0.45, 1.05, (0.98, 0.44), 0.2, PEACH, ICE, 0.42),
            (1.05, 1.55, (1.44, 0.58), 0.1, PEACH, ROSE, 0.42),
        ]
    canvas = bg
    for (bl, br, tip, curl, cb, ct, op) in blades:
        poly = blade_polygon(bl, br, tip, curl, w, h)
        mb, m = mask_from_polygon(poly, w, h)
        canvas = glass_layer(canvas, mb, m, cb, ct, op, dark)

    # Very light film grain so gradients don't band on 8-bit panels.
    rng = np.random.default_rng(7)
    canvas = canvas + rng.normal(0, 0.006, canvas.shape).astype(np.float32)
    return to_img(canvas)


def rounded_rect_mask(size, radius, ss=4):
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size * ss - 1, size * ss - 1),
                                        radius=radius * ss, fill=255)
    return m, m.resize((size, size), Image.LANCZOS)


def emblem_gradient_fill(size, inset):
    """The forge emblem in its own colours, centred in a size x size square.

    The emblem's shading (the folds of the F) is part of the mark, so its
    colours are kept rather than refilled from the palette."""
    src = Image.open(EMBLEM).convert("RGBA")
    inner = size - 2 * inset
    src = to_arr(src.resize((inner, inner), Image.LANCZOS))
    a = np.zeros((size, size), np.float32)
    rgb = np.zeros((size, size, 3), np.float32)
    a[inset:inset + inner, inset:inset + inner] = src[..., 3]
    rgb[inset:inset + inner, inset:inset + inner] = src[..., :3]
    return rgb, a


def logo_tile(size=1024, dark=False):
    """App-icon-style glass tile with the forge emblem on it (RGBA)."""
    pad = int(size * 0.06)          # room for the shadow
    tile = size - 2 * pad
    radius = int(tile * 0.24)

    # Tile face: a crop of the wallpaper look, blurred heavily.
    face = wallpaper(tile * 2, tile, dark).crop((tile // 2, 0, tile // 2 + tile, tile))
    face = to_arr(face.filter(ImageFilter.GaussianBlur(tile * 0.03)))
    face = face * 0.75 + (0.04 if dark else 0.25)

    rgb, a = emblem_gradient_fill(tile, int(tile * 0.12))
    # Soft glow under the emblem, then the emblem itself with a white inner edge.
    glow = blur(a, tile * 0.02)[..., None]
    face = face * (1 - glow * 0.25) + np.array([1, 1, 1], np.float32) * glow * 0.25
    am = a[..., None]
    edge = np.clip((a - blur(a, tile * 0.006)) * 3, 0, 1)[..., None]
    em = rgb + (1 - rgb) * edge * 0.6
    face = face * (1 - am) + em * am

    big, m = rounded_rect_mask(tile, radius)
    rim = ImageChops.subtract(big, big.filter(ImageFilter.MinFilter(9))).resize((tile, tile), Image.LANCZOS)
    rim = to_arr(rim)[..., None]
    face = face * (1 - rim * 0.9) + rim * 0.9

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow = Image.new("L", (size, size), 0)
    shadow.paste(m, (pad, pad + int(size * 0.015)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.025))
    sh = Image.new("RGBA", (size, size), NAVY + (0,))
    sh.putalpha(shadow.point(lambda v: int(v * 0.35)))
    out.alpha_composite(sh)
    face_im = to_img(face).convert("RGBA")
    face_im.putalpha(m)
    out.alpha_composite(face_im, (pad, pad))
    return out


def emblem_only(size=512):
    """Bare gradient emblem on transparent background (small UI sizes)."""
    rgb, a = emblem_gradient_fill(size, int(size * 0.04))
    im = to_img(rgb).convert("RGBA")
    im.putalpha(to_img(a))
    return im


def ui_font(size, weight):
    from PIL import ImageFont
    f = ImageFont.truetype(str(UI_FONT), size)
    f.set_variation_by_axes([weight])  # wght is the only axis
    return f


def spaced(draw, xy, text, font, fill=None, word_gap=0.3):
    """Draw (or, with draw=None, measure) text with a word gap in ems.

    Plus Jakarta Sans has a narrow space (0.17em) that makes small, light
    text like the tagline run together."""
    gap = font.size * word_gap
    x, y = xy
    for i, word in enumerate(text.split(" ")):
        if i:
            x += gap
        if draw is not None:
            draw.text((x, y), word, font=font, fill=fill)
        x += font.getlength(word)
    return x - xy[0]


def lockup(scale=1.0, dark=False):
    """Logo tile + two-weight "Forge OS" wordmark + tagline, transparent bg.

    Plymouth can't count on fonts in the initramfs, so this is baked."""
    ink = (236, 238, 250) if dark else NAVY
    soft = (150, 156, 196) if dark else (110, 115, 150)
    tile = logo_tile(int(300 * scale), dark)
    f_bold, f_reg = ui_font(int(76 * scale), 650), ui_font(int(76 * scale), 350)
    f_tag = ui_font(int(24 * scale), 450)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    w1 = probe.textlength("Forge ", font=f_bold)
    w2 = probe.textlength("OS", font=f_reg)
    wt = spaced(None, (0, 0), TAGLINE, f_tag)
    W = int(max(w1 + w2, wt, tile.width) + 40 * scale)
    H = int(tile.height + 150 * scale)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.alpha_composite(tile, ((W - tile.width) // 2, 0))
    d = ImageDraw.Draw(out)
    x = (W - (w1 + w2)) / 2
    y = tile.height - 10 * scale
    d.text((x, y), "Forge ", font=f_bold, fill=ink)
    d.text((x + w1, y), "OS", font=f_reg, fill=soft)
    spaced(d, ((W - wt) / 2, y + 92 * scale), TAGLINE, f_tag, fill=soft)
    return out


def plymouth_assets():
    """Progress bar track + fill in the glass palette."""
    w, h = 320, 6
    box = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(box).rounded_rectangle((0, 0, w - 1, h - 1), radius=3, fill=(30, 33, 64, 40))
    bar = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    grad = np.zeros((h, w, 3), np.float32)
    t = np.linspace(0, 1, w, dtype=np.float32)[None, :, None]
    grad[:] = (np.array(EMBER, np.float32) * (1 - t) + np.array(PERIWINKLE, np.float32) * t) / 255
    g = to_img(grad).convert("RGBA")
    mk = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mk).rounded_rectangle((0, 0, w - 1, h - 1), radius=3, fill=255)
    g.putalpha(mk)
    bar.alpha_composite(g)
    return box, bar


def main():
    preview = "--preview" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    sizes = [(1280, 720)] if preview else [(3840, 2160)]
    for (w, h) in sizes:
        for dark in (False, True):
            name = f"wallpaper-{'dark' if dark else 'light'}-{w}x{h}.png"
            im = wallpaper(w, h, dark)
            im.save(OUT / name, optimize=True)
            print("wrote", name)
            if not preview:
                # 1080p copy for GRUB, Plymouth and Calamares, where size matters.
                im.resize((1920, 1080), Image.LANCZOS).save(
                    OUT / f"wallpaper-{'dark' if dark else 'light'}-1920x1080.png", optimize=True)
    if preview:
        return
    logo_tile(1024).save(OUT / "logo-tile-light.png", optimize=True)
    logo_tile(1024, dark=True).save(OUT / "logo-tile-dark.png", optimize=True)
    emblem_only(512).save(OUT / "emblem-gradient.png", optimize=True)
    box, bar = plymouth_assets()
    box.save(OUT / "progress_box.png")
    bar.save(OUT / "progress_bar.png")
    lockup(0.8).save(OUT / "lockup-light.png", optimize=True)
    lockup(0.8, dark=True).save(OUT / "lockup-dark.png", optimize=True)
    print("wrote logo/plymouth assets")


if __name__ == "__main__":
    main()
