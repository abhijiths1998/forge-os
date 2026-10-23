#!/usr/bin/env python3
"""Write the Forge Glass Plasma theme: macOS-style dots in the dock.

    python3 branding-source/glass/desktoptheme.py

The theme only ships widgets/tasks.svg; every other element falls back to
the default (Breeze) Plasma theme. Running apps get a small dot under
their icon (brighter for the active window) instead of Breeze's
highlight bar.

How it works: the task manager draws each task's state as a FrameSvg from
widgets/tasks, and FrameSvg can't centre a fixed-size shape (edges tile
or stretch from the frame's corners). So these frames have no edges at
all, only a centre piece, which FrameSvg stretches over the whole task.
With the margin hints along the dock's length at 0, an icon-only task is
exactly square (LayoutMetrics.preferredMaxWidth: the panel's thickness
plus those margins), so the square centre piece scales evenly and the dot
stays round at any dock size.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "profile" / "airootfs" / "usr" / "share"
THEME = ROOT / "plasma" / "desktoptheme" / "forge-glass"

S = 100            # side of each square centre piece, in SVG units
DOT_R = 4.5        # dot radius
DOT_EDGE = 6       # dot centre's distance from the dock-side edge
HOVER_INSET = 3    # hover tile inset and corner radius
HOVER_RADIUS = 22
# Margins in px: the dot sits in the gap on the dock-edge side; the
# margins across the dock's thickness are what space the icons apart.
EDGE_MARGIN = 6
FAR_MARGIN = 4

# Dock edge -> element prefix and where the dot goes. "" is the bottom
# edge: the task manager tries "south-<state>" then "<state>", so the
# plain names cover it.
EDGES = {
    "": "bottom",
    "north-": "top",
    "west-": "left",
    "east-": "right",
}

# Task state -> (dot colour class, dot opacity); None draws no dot.
STATES = {
    "normal": ("ColorScheme-Text", 0.5),     # running, not focused
    "focus": ("ColorScheme-Text", 1.0),      # the active window
    "minimized": ("ColorScheme-Text", 0.3),
    "attention": ("ColorScheme-NeutralText", 1.0),
    "launcher": None,                        # pinned, not running
}

STYLE = """<style type="text/css" id="current-color-scheme">
.ColorScheme-Text { color:#232629; }
.ColorScheme-NeutralText { color:#f67400; }
.ColorScheme-Highlight { color:#3daee9; }
</style>"""


def dot_xy(side):
    mid = S / 2
    return {
        "bottom": (mid, S - DOT_EDGE),
        "top": (mid, DOT_EDGE),
        "left": (DOT_EDGE, mid),
        "right": (S - DOT_EDGE, mid),
    }[side]


def margins(side):
    """Margin hints: EDGE_MARGIN on the dot side, FAR_MARGIN opposite, and
    none along the dock so each task is square."""
    if side in ("bottom", "top"):
        m = dict(top=FAR_MARGIN, bottom=FAR_MARGIN)
    else:
        m = dict(left=FAR_MARGIN, right=FAR_MARGIN)
    m[side] = EDGE_MARGIN
    return m


def piece(elem_id, x, y, dot=None, side="bottom", hover=False):
    """One centre piece at (x, y) on the sheet: a transparent square
    (fixes the element's size), an optional hover tile and dot."""
    parts = [f'<rect width="{S}" height="{S}" fill="#000" fill-opacity="0"/>']
    if hover:
        side_len = S - 2 * HOVER_INSET
        parts.append(
            f'<rect class="ColorScheme-Text" x="{HOVER_INSET}" y="{HOVER_INSET}" '
            f'width="{side_len}" height="{side_len}" rx="{HOVER_RADIUS}" '
            f'fill="currentColor" fill-opacity="0.12"/>')
    if dot:
        cls, opacity = dot
        cx, cy = dot_xy(side)
        parts.append(
            f'<circle class="{cls}" cx="{cx}" cy="{cy}" r="{DOT_R}" '
            f'fill="currentColor" fill-opacity="{opacity}"/>')
    return (f'<g id="{elem_id}" transform="translate({x} {y})">'
            + "".join(parts) + "</g>")


def tasks_svg():
    pieces, hints = [], []
    pitch = S + 20
    y = 0
    for prefix, side in EDGES.items():
        x = 0
        for state, dot in STATES.items():
            if state != "launcher":
                pieces.append(piece(f"{prefix}{state}-center", x, y, dot, side))
                x += pitch
            # Hovered: "<state>-hover", or "launcher-hover" for pinned icons.
            pieces.append(piece(f"{prefix}{state}-hover-center", x, y, dot, side, hover=True))
            x += pitch
        # Progress (e.g. downloads): a tint stretched over the done part.
        pieces.append(
            f'<rect id="{prefix}progress-center" class="ColorScheme-Highlight" '
            f'x="{x}" y="{y}" width="{S}" height="{S}" fill="currentColor" '
            f'fill-opacity="0.3"/>')
        x += pitch
        # Margin hints: only the rect's width (left/right) or height
        # (top/bottom) matters; they read from the "normal" frame.
        for name, px in margins(side).items():
            w, h = (px, 1) if name in ("left", "right") else (1, px)
            hints.append(
                f'<rect id="{prefix}normal-hint-{name}-margin" x="{x}" y="{y}" '
                f'width="{w}" height="{h}" fill="none"/>')
            x += 10
        y += pitch

    width = pitch * 12
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!-- Generated by branding-source/glass/desktoptheme.py; edit that, not this. -->\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" version="1.1" '
        f'width="{width}" height="{y}" viewBox="0 0 {width} {y}">\n'
        f"<defs>{STYLE}</defs>\n"
        + "\n".join(pieces + hints)
        + "\n</svg>\n")


METADATA = {
    "KPlugin": {
        "Authors": [{"Name": "forge-os"}],
        "Category": "",
        "Description": "Forge Glass: Breeze with macOS-style dots in the dock",
        "EnabledByDefault": True,
        "Id": "forge-glass",
        "License": "LGPL",
        "Name": "Forge Glass",
        "Version": "1.0",
    },
    "X-Plasma-API": "5.0",
}


def main():
    (THEME / "widgets").mkdir(parents=True, exist_ok=True)
    (THEME / "widgets" / "tasks.svg").write_text(tasks_svg())
    (THEME / "metadata.json").write_text(json.dumps(METADATA, indent=4) + "\n")
    print(f"wrote {THEME.relative_to(ROOT.parents[1])}")


if __name__ == "__main__":
    main()
