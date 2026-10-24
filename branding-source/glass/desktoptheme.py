#!/usr/bin/env python3
"""Write the Forge Glass Plasma theme: macOS-style dots in the dock and a
dock with big, macOS-style rounded corners.

    python3 branding-source/glass/desktoptheme.py

The theme ships widgets/tasks.svg and widgets/panel-background.svg (plus
its solid/ twin); every other element falls back to the default (Breeze)
Plasma theme. Running apps get a small dot under their icon (brighter for
the active window) instead of Breeze's highlight bar.

The panel background is Breeze's, read from the installed Plasma theme,
with "south-" and "north-" frame, mask and margin-hint elements added.
Plasma tries "<edge>-<element>" before "<element>" (Panel.qml), so bottom
panels, i.e. the dock, get the DOCK_RADIUS corners and top panels (the top
bar) TOP_RADIUS, Breeze's own, minus the light line Breeze draws along a
panel's top edge: the glass runs to the edge with no border.
Keep DOCK_RADIUS in step with [Effect-blurplus] DockCornerRadius in kwinrc,
which rounds the glass frost behind it.

Breeze's panel shadow ("shadow-*") is left out: plasmashell gives every
panel the same shadow, with no edge prefix, and its corners hug Breeze's
6px panel corners, so around the dock's rounder ones it left a lighter
square-ish patch. The glass itself defines the
panels instead.

How it works: the task manager draws each task's state as a FrameSvg from
widgets/tasks, and FrameSvg can't centre a fixed-size shape (edges tile
or stretch from the frame's corners). So these frames have no edges at
all, only a centre piece, which FrameSvg stretches over the whole task.
With the margin hints along the dock's length at 0, an icon-only task is
exactly square (LayoutMetrics.preferredMaxWidth: the panel's thickness
plus those margins), so the square centre piece scales evenly and the dot
stays round at any dock size.
"""
import gzip
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

# Dock background: corner radius and content margins, in px at 1x.
BREEZE = Path("/usr/share/plasma/desktoptheme/default")
DOCK_RADIUS = 18
TOP_RADIUS = 6
DOCK_MARGIN = 4
EDGE = 32          # length of the stretched edge and centre pieces

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


def edge_frame(edge, r, x0, y0, opacity):
    """A panel frame for `edge` ("south", "north"): "<edge>-" pieces with
    corners of radius r at (x0, y0) on the sheet, the matching
    "mask-<edge>-" pieces (what Plasma blurs) and margin hints. Plain fills,
    no edge lines."""
    e = EDGE
    cls = 'class="ColorScheme-Background" fill="currentColor"'
    # name -> (x, y, w, h) of each piece in a 3x3 grid
    grid = {
        "topleft": (0, 0, r, r), "top": (r, 0, e, r), "topright": (r + e, 0, r, r),
        "left": (0, r, r, e), "center": (r, r, e, e), "right": (r + e, r, r, e),
        "bottomleft": (0, r + e, r, r), "bottom": (r, r + e, e, r),
        "bottomright": (r + e, r + e, r, r),
    }
    # Quarter circles, centred on the corner piece's inner corner.
    arcs = {
        "topleft": f"M {r},0 A {r},{r} 0 0 0 0,{r} H {r} Z",
        "topright": f"M 0,0 A {r},{r} 0 0 1 {r},{r} H 0 Z",
        "bottomleft": f"M 0,0 A {r},{r} 0 0 0 {r},{r} V 0 Z",
        "bottomright": f"M {r},0 A {r},{r} 0 0 1 0,{r} V 0 Z",
    }
    out = []
    for prefix, fill in ((f"{edge}-", f'{cls} fill-opacity="{opacity}"'), (f"mask-{edge}-", 'fill="#000"')):
        oy = y0 if prefix == f"{edge}-" else y0 + 2 * r + e + 10
        for name, (x, y, w, h) in grid.items():
            if name in arcs:
                out.append(f'<path id="{prefix}{name}" transform="translate({x0 + x} {oy + y})" '
                           f'd="{arcs[name]}" {fill}/>')
            else:
                out.append(f'<rect id="{prefix}{name}" x="{x0 + x}" y="{oy + y}" '
                           f'width="{w}" height="{h}" {fill}/>')
    hx = x0 + 2 * r + e + 10
    for i, side in enumerate(("top", "bottom", "left", "right")):
        out.append(f'<rect id="{edge}-hint-{side}-margin" x="{hx}" y="{y0 + 10 * i}" '
                   f'width="{DOCK_MARGIN}" height="{DOCK_MARGIN}" fill="none"/>')
    width = hx + DOCK_MARGIN + 10 - x0
    height = 2 * (2 * r + e) + 10
    return "\n".join(out), width, height


def drop_shadow(svg):
    """Remove the elements plasmashell builds panel shadows from
    ("shadow-top", ..., "shadow-hint-*"); the gradients they used stay in
    <defs>, unreferenced."""
    import re
    for elem_id in sorted(set(re.findall(r'id="(shadow-(?:top|bottom|left|right|center|hint)[^"]*)"', svg))):
        m = re.search(r'<(\w+)\b[^>]*\bid="' + re.escape(elem_id) + r'"', svg)
        start, tag = m.start(), m.group(1)
        # Self-closing element, or a <g> whose children have no nested <g>.
        end_self = svg.index(">", m.end())
        if svg[end_self - 1] == "/":
            end = end_self + 1
        else:
            end = svg.index(f"</{tag}>", m.end()) + len(f"</{tag}>")
            assert "<g" not in svg[end_self:end], elem_id
        svg = svg[:start] + svg[end:]
    return svg


def panel_background_svg(breeze_svgz, opacity):
    """Breeze's panel background with the dock's "south-" and the top
    bar's "north-" frames added on the right of the sheet."""
    import re
    svg = gzip.decompress(breeze_svgz.read_bytes()).decode()
    svg = drop_shadow(svg)
    m = re.search(r'<svg\b[^>]*>', svg)
    head = m.group(0)
    w = float(re.search(r'\bwidth="([\d.]+)', head).group(1))
    h = float(re.search(r'\bheight="([\d.]+)', head).group(1))
    x0 = int(w) + 20
    south, sw, sh = edge_frame("south", DOCK_RADIUS, x0, 0, opacity)
    north, tw, th = edge_frame("north", TOP_RADIUS, x0 + sw, 0, opacity)
    frame = south + "\n" + north
    nw, nh = x0 + sw + tw, max(h, sh, th)
    new_head = re.sub(r'\bwidth="[\d.]+"', f'width="{nw}"', head, count=1)
    new_head = re.sub(r'\bheight="[\d.]+"', f'height="{nh}"', new_head, count=1)
    new_head = re.sub(r'\bviewBox="[^"]*"', f'viewBox="0 0 {nw} {nh}"', new_head, count=1)
    note = "<!-- Breeze's panel-background plus the Forge Glass dock and top bar frames, generated by branding-source/glass/desktoptheme.py; edit that, not this. -->"
    svg = svg.replace(head, new_head + "\n" + note, 1)
    i = svg.rindex("</svg>")
    return svg[:i] + frame + "\n" + svg[i:]


METADATA = {
    "KPlugin": {
        "Authors": [{"Name": "forge-os"}],
        "Category": "",
        "Description": "Forge Glass: Breeze with a macOS-style dock",
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
    (THEME / "widgets" / "panel-background.svg").write_text(
        panel_background_svg(BREEZE / "widgets" / "panel-background.svgz", 0.85))
    (THEME / "solid" / "widgets").mkdir(parents=True, exist_ok=True)
    (THEME / "solid" / "widgets" / "panel-background.svg").write_text(
        panel_background_svg(BREEZE / "solid" / "widgets" / "panel-background.svgz", 1))
    (THEME / "metadata.json").write_text(json.dumps(METADATA, indent=4) + "\n")
    print(f"wrote {THEME.relative_to(ROOT.parents[1])}")


if __name__ == "__main__":
    main()
