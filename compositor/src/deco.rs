//! Forge title bars: drawn by the compositor for every window that lets it
//! (server-side decorations), as one image per window, redrawn only when
//! its title, width, focus, hover or the theme change.
//!
//!   ┌──────────────────── Konsole ──────────────── (−) (+) (×) ┐
//!
//! Glass in the window colour, the title centred in Plus Jakarta Sans, and
//! round minimise / maximise / close buttons on the right, as on Plasma.
//! Their glyphs show while the pointer is over any of them.

use std::sync::OnceLock;

use smithay::{
    backend::{allocator::Fourcc, renderer::element::memory::MemoryRenderBuffer},
    utils::{Logical, Point, Rectangle, Transform},
};
use tiny_skia::{FillRule, LineCap, Paint, PathBuilder, Pixmap, Stroke, Transform as Tf};

use crate::theme::{Rgba, Theme};

pub const BAR_HEIGHT: i32 = 36;
const BUTTON: f32 = 14.0;
const BUTTON_GAP: f32 = 9.0;
const PADDING: f32 = 14.0;
const TITLE_SIZE: f32 = 13.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Button {
    Close,
    Maximize,
    Minimize,
}

/// Right to left, as they sit on the bar.
const BUTTONS: [Button; 3] = [Button::Close, Button::Maximize, Button::Minimize];

/// A button's circle in bar coordinates.
fn button_rect(bar_width: i32, i: usize) -> Rectangle<f64, Logical> {
    let x = bar_width as f64 - PADDING as f64 - BUTTON as f64 - i as f64 * (BUTTON + BUTTON_GAP) as f64;
    let y = (BAR_HEIGHT as f64 - BUTTON as f64) / 2.0;
    Rectangle::new((x, y).into(), (BUTTON as f64, BUTTON as f64).into())
}

/// The button under a point in bar coordinates, with a little slack around
/// each circle so they're easy to hit.
pub fn button_at(bar_width: i32, p: Point<f64, Logical>) -> Option<Button> {
    BUTTONS.iter().enumerate().find_map(|(i, &b)| {
        let r = button_rect(bar_width, i);
        let slack = 4.0;
        let hit = p.x >= r.loc.x - slack
            && p.x <= r.loc.x + r.size.w + slack
            && p.y >= r.loc.y - slack
            && p.y <= r.loc.y + r.size.h + slack;
        hit.then_some(b)
    })
}

fn font() -> Option<&'static fontdue::Font> {
    static FONT: OnceLock<Option<fontdue::Font>> = OnceLock::new();
    FONT.get_or_init(|| {
        [
            "/usr/share/fonts/plus-jakarta-sans/PlusJakartaSans-Variable.ttf",
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/usr/share/fonts/noto/NotoSans-Regular.ttf",
        ]
        .iter()
        .find_map(|path| {
            let bytes = std::fs::read(path).ok()?;
            fontdue::Font::from_bytes(bytes, fontdue::FontSettings::default()).ok()
        })
    })
    .as_ref()
}

fn paint(c: Rgba) -> Paint<'static> {
    let mut p = Paint::default();
    p.set_color_rgba8(
        (c.0 * 255.0) as u8,
        (c.1 * 255.0) as u8,
        (c.2 * 255.0) as u8,
        (c.3 * 255.0) as u8,
    );
    p.anti_alias = true;
    p
}

/// What a bar looks like; the cache key for its image.
#[derive(Clone, Debug, PartialEq)]
pub struct BarLook {
    pub title: String,
    pub width: i32,
    pub scale: i32,
    pub focused: bool,
    pub hover: Option<Button>,
    pub maximized: bool,
    pub theme: Theme,
}

pub struct TitleBar {
    look: Option<BarLook>,
    pub buffer: Option<MemoryRenderBuffer>,
}

impl TitleBar {
    pub fn new() -> Self {
        TitleBar { look: None, buffer: None }
    }

    /// Repaints if the look changed.
    pub fn update(&mut self, look: BarLook) {
        if self.look.as_ref() == Some(&look) || look.width <= 0 {
            return;
        }
        self.buffer = draw(&look);
        self.look = Some(look);
    }
}

fn draw(look: &BarLook) -> Option<MemoryRenderBuffer> {
    let s = look.scale as f32;
    let (w, h) = (look.width as f32, BAR_HEIGHT as f32);
    let mut pixmap = Pixmap::new((w * s) as u32, (h * s) as u32)?;
    let t = &look.theme;
    let to = Tf::from_scale(s, s);

    // The glass: the window colour, rounded at the top (square when
    // maximised, as it meets the screen edge), over the compositor's
    // frosted pane, as see-through as the theme's windows.
    let glass = t.window().with_alpha((t.glass + 0.12).clamp(0.3, 0.92));
    let r = if look.maximized { 0.0 } else { t.corner_radius.clamp(0.0, h) };
    let mut pb = PathBuilder::new();
    pb.move_to(0.0, h);
    pb.line_to(0.0, r);
    pb.quad_to(0.0, 0.0, r, 0.0);
    pb.line_to(w - r, 0.0);
    pb.quad_to(w, 0.0, w, r);
    pb.line_to(w, h);
    pb.close();
    pixmap.fill_path(&pb.finish()?, &paint(glass), FillRule::Winding, to, None);

    // Buttons: coloured when the window is focused, quiet grey otherwise;
    // their glyphs while the pointer is over the group.
    let colours = t.buttons();
    let show_glyphs = look.hover.is_some();
    for (i, &b) in BUTTONS.iter().enumerate() {
        let rect = button_rect(look.width, i);
        let (cx, cy) = (rect.loc.x as f32 + BUTTON / 2.0, rect.loc.y as f32 + BUTTON / 2.0);
        let fill = if look.focused || look.hover.is_some() {
            colours[i]
        } else {
            t.dim_text().with_alpha(0.35)
        };
        let fill = if look.hover == Some(b) { fill } else { fill.with_alpha(fill.3 * 0.92) };
        if let Some(circle) = PathBuilder::from_circle(cx, cy, BUTTON / 2.0) {
            pixmap.fill_path(&circle, &paint(fill), FillRule::Winding, to, None);
        }
        if show_glyphs {
            let ink = Rgba(0.0, 0.0, 0.0, 0.55);
            let a = 3.4;
            let mut g = PathBuilder::new();
            match b {
                Button::Close => {
                    g.move_to(cx - a, cy - a);
                    g.line_to(cx + a, cy + a);
                    g.move_to(cx + a, cy - a);
                    g.line_to(cx - a, cy + a);
                }
                Button::Maximize => {
                    g.move_to(cx - a, cy);
                    g.line_to(cx + a, cy);
                    g.move_to(cx, cy - a);
                    g.line_to(cx, cy + a);
                }
                Button::Minimize => {
                    g.move_to(cx - a, cy);
                    g.line_to(cx + a, cy);
                }
            }
            if let Some(path) = g.finish() {
                let stroke = Stroke { width: 1.6, line_cap: LineCap::Round, ..Stroke::default() };
                pixmap.stroke_path(&path, &paint(ink), &stroke, to, None);
            }
        }
    }

    // The title, centred on the whole bar, cut short before the buttons.
    let buttons_width = PADDING + 3.0 * BUTTON + 2.0 * BUTTON_GAP + PADDING;
    let room = w - 2.0 * buttons_width;
    let ink = if look.focused { t.text() } else { t.dim_text() };
    if let Some(font) = font() {
        if room > 20.0 {
            draw_text(&mut pixmap, font, &look.title, w / 2.0, h / 2.0, room, s, ink);
        }
    }

    // tiny-skia's premultiplied RGBA bytes are ABGR8888 in DRM's naming.
    Some(MemoryRenderBuffer::from_slice(
        pixmap.data(),
        Fourcc::Abgr8888,
        (pixmap.width() as i32, pixmap.height() as i32),
        look.scale,
        Transform::Normal,
        None,
    ))
}

/// Draws `text` centred on (cx, cy), ending in "…" if it's wider than
/// `room`. Glyph coverage is blended straight into the premultiplied pixels.
#[allow(clippy::too_many_arguments)]
fn draw_text(pixmap: &mut Pixmap, font: &fontdue::Font, text: &str, cx: f32, cy: f32, room: f32, s: f32, ink: Rgba) {
    let size = TITLE_SIZE * s;
    let advance = |c: char| font.metrics(c, size).advance_width;
    let mut shown: String = text.chars().collect();
    let width = |t: &str| t.chars().map(advance).sum::<f32>();
    if width(&shown) > room * s {
        while !shown.is_empty() && width(&shown) + advance('…') > room * s {
            shown.pop();
        }
        shown = shown.trim_end().to_string() + "…";
    }
    let Some(lines) = font.horizontal_line_metrics(size) else { return };
    let mut x = cx * s - width(&shown) / 2.0;
    let baseline = cy * s + (lines.ascent + lines.descent) / 2.0;
    let (pw, ph) = (pixmap.width() as i32, pixmap.height() as i32);
    let data = pixmap.data_mut();
    for c in shown.chars() {
        let (m, bitmap) = font.rasterize(c, size);
        let gx = (x + m.xmin as f32).round() as i32;
        let gy = (baseline - m.height as f32 - m.ymin as f32).round() as i32;
        for row in 0..m.height as i32 {
            for col in 0..m.width as i32 {
                let (px, py) = (gx + col, gy + row);
                if px < 0 || py < 0 || px >= pw || py >= ph {
                    continue;
                }
                let cov = bitmap[(row * m.width as i32 + col) as usize] as f32 / 255.0 * ink.3;
                if cov <= 0.0 {
                    continue;
                }
                let i = ((py * pw + px) * 4) as usize;
                let under = &mut data[i..i + 4];
                for (k, ch) in [ink.0, ink.1, ink.2, 1.0].into_iter().enumerate() {
                    let src = ch * cov * 255.0;
                    under[k] = (src + under[k] as f32 * (1.0 - cov)).round().min(255.0) as u8;
                }
            }
        }
        x += m.advance_width;
    }
}
