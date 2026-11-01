//! Window animations: how a window's frame is drawn while it opens,
//! closes, minimises to the dock and comes back, maximises (its frame
//! glides to the new size), is dragged (it lifts a little) or is brought
//! to the front by a click (a small press).
//!
//! Animations never change where a window really is: input, placement and
//! the clients all see the real geometry. They only change where the frame
//! is drawn (`Look`), by scaling and moving its render elements.
//!
//! A closing window is gone before its animation ends, so what it last
//! showed is kept as textures (`Snapshot`). A minimising one is still
//! there, just out of the space, so it's drawn live (`Ghost::Live`).
//!
//! theme.json's `animations` scales their speed: 1 normal, 2 twice as
//! fast, 0 off.

use std::{
    f64::consts::PI,
    time::{Duration, Instant},
};

use smithay::{
    backend::renderer::{
        element::{Id, memory::MemoryRenderBuffer},
        gles::GlesTexture,
        utils::RendererSurfaceStateUserData,
    },
    desktop::Window,
    reexports::wayland_server::{backend::ObjectId, protocol::wl_surface::WlSurface},
    utils::{Logical, Point, Rectangle, Size, Transform},
    wayland::compositor::{TraversalAction, with_surface_tree_downward},
};

pub type RectF = Rectangle<f64, Logical>;

pub const OPEN_MS: u64 = 260;
pub const CLOSE_MS: u64 = 200;
pub const MINIMIZE_MS: u64 = 340;
pub const RESTORE_MS: u64 = 300;
pub const MORPH_MS: u64 = 260;
pub const POP_MS: u64 = 170;
pub const LAYER_MS: u64 = 200;

// --- Easing --------------------------------------------------------------------------

pub fn ease_out_cubic(t: f64) -> f64 {
    1.0 - (1.0 - t).powi(3)
}

pub fn ease_in_out_cubic(t: f64) -> f64 {
    if t < 0.5 { 4.0 * t * t * t } else { 1.0 - (-2.0 * t + 2.0).powi(3) / 2.0 }
}

/// Overshoots a touch and settles: windows open with a little spring.
pub fn ease_out_back(t: f64) -> f64 {
    let c1 = 1.25;
    let c3 = c1 + 1.0;
    1.0 + c3 * (t - 1.0).powi(3) + c1 * (t - 1.0).powi(2)
}

pub fn ease_out_quint(t: f64) -> f64 {
    1.0 - (1.0 - t).powi(5)
}

fn lerp(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

pub fn lerp_rect(a: RectF, b: RectF, t: f64) -> RectF {
    Rectangle::new(
        (lerp(a.loc.x, b.loc.x, t), lerp(a.loc.y, b.loc.y, t)).into(),
        (lerp(a.size.w, b.size.w, t), lerp(a.size.h, b.size.h, t)).into(),
    )
}

/// `r` grown or shrunk by `s` about its centre.
pub fn scale_about_centre(r: RectF, s: f64) -> RectF {
    let c = (r.loc.x + r.size.w / 2.0, r.loc.y + r.size.h / 2.0);
    let (w, h) = (r.size.w * s, r.size.h * s);
    Rectangle::new((c.0 - w / 2.0, c.1 - h / 2.0).into(), (w, h).into())
}

/// A small rect at `p`, `r`'s shape: where a minimised window shrinks to.
pub fn shrunk_at(r: RectF, p: Point<f64, Logical>) -> RectF {
    let (w, h) = (r.size.w * 0.08, r.size.h * 0.08);
    Rectangle::new((p.x - w / 2.0, p.y - h / 2.0).into(), (w, h).into())
}

// --- One window's animation ---------------------------------------------------------

#[derive(Clone, Copy, Debug)]
pub enum Kind {
    /// A new window: grows from a little smaller and fades in.
    Open,
    /// Back from the dock.
    Restore { from: RectF },
    /// Maximise, restore, fullscreen: the frame glides from one rect to
    /// the other, the content stretched until the app catches up.
    Morph { from: RectF, to: RectF },
    /// A click brought it to the front.
    Pop,
}

#[derive(Clone, Copy, Debug)]
pub struct Anim {
    pub kind: Kind,
    start: Instant,
    dur: Duration,
}

impl Anim {
    /// None when animations are off (`speed` 0).
    pub fn new(kind: Kind, ms: u64, speed: f64) -> Option<Self> {
        if speed <= 0.0 {
            return None;
        }
        Some(Anim { kind, start: Instant::now(), dur: Duration::from_secs_f64(ms as f64 / 1000.0 / speed) })
    }

    pub fn t(&self, now: Instant) -> f64 {
        (now.saturating_duration_since(self.start).as_secs_f64() / self.dur.as_secs_f64()).clamp(0.0, 1.0)
    }

    pub fn done(&self, now: Instant) -> bool {
        self.t(now) >= 1.0
    }
}

/// Where a frame is drawn, and how opaque.
#[derive(Clone, Copy, Debug)]
pub struct Look {
    pub rect: RectF,
    pub alpha: f32,
}

/// A window's look this frame, from its real frame, its animation and
/// how lifted it is (0: resting, 1: being dragged).
pub fn window_look(frame: Rectangle<i32, Logical>, anim: Option<&Anim>, lift: f64, now: Instant) -> Look {
    let f = frame.to_f64();
    let mut look = Look { rect: f, alpha: 1.0 };
    if let Some(a) = anim {
        let t = a.t(now);
        match a.kind {
            Kind::Open => {
                look.rect = scale_about_centre(f, lerp(0.86, 1.0, ease_out_back(t)));
                look.alpha = ease_out_cubic((t * 1.7).min(1.0)) as f32;
            }
            Kind::Restore { from } => {
                let e = ease_out_cubic(t);
                look.rect = lerp_rect(from, f, e);
                look.alpha = lerp(0.0, 1.0, (t * 2.0).min(1.0)) as f32;
            }
            Kind::Morph { from, to } => {
                look.rect = lerp_rect(from, to, ease_out_quint(t));
            }
            Kind::Pop => {
                look.rect = scale_about_centre(f, 1.0 - 0.014 * (PI * t).sin());
            }
        }
    }
    if lift > 0.001 {
        look.rect = scale_about_centre(look.rect, 1.0 - 0.018 * lift);
        look.alpha *= (1.0 - 0.12 * lift) as f32;
    }
    look
}

/// Eases `lift` toward 1 while dragged, 0 otherwise; `dt` since the last
/// frame.
pub fn step_lift(lift: f64, target: f64, dt: f64, speed: f64) -> f64 {
    if speed <= 0.0 {
        return target;
    }
    let k = 1.0 - (-dt * speed / 0.07).exp();
    let next = lift + (target - lift) * k;
    if (next - target).abs() < 0.002 { target } else { next }
}

// --- Windows on their way out ------------------------------------------------------

/// One surface of a closed window, as it last looked.
pub struct Snap {
    pub tex: GlesTexture,
    pub id: Id,
    /// From the window's content origin.
    pub offset: Point<i32, Logical>,
    pub size: Size<i32, Logical>,
    pub src: Rectangle<f64, Logical>,
    pub scale: i32,
    pub transform: Transform,
}

/// What a closed window's surface tree last showed, while its textures are
/// still there (call before the surfaces are destroyed). Empty if it had
/// nothing on screen.
pub fn snapshot(surface: &WlSurface, ctx: &smithay::backend::renderer::ContextId<GlesTexture>) -> Vec<Snap> {
    let mut snaps = Vec::new();
    with_surface_tree_downward(
        surface,
        Point::<i32, Logical>::from((0, 0)),
        |_, states, loc| {
            let Some(data) = states.data_map.get::<RendererSurfaceStateUserData>() else {
                return TraversalAction::SkipChildren;
            };
            match data.lock().unwrap().view() {
                Some(view) => TraversalAction::DoChildren(*loc + view.offset),
                None => TraversalAction::SkipChildren,
            }
        },
        |_, states, loc| {
            let Some(data) = states.data_map.get::<RendererSurfaceStateUserData>() else { return };
            let data = data.lock().unwrap();
            let (Some(view), Some(tex)) = (data.view(), data.texture::<GlesTexture>(ctx.clone())) else { return };
            snaps.push(Snap {
                tex: tex.clone(),
                id: Id::new(),
                offset: *loc + view.offset,
                size: view.dst,
                src: view.src,
                scale: data.buffer_scale(),
                transform: data.buffer_transform(),
            });
        },
        |_, _, _| true,
    );
    snaps
}

pub enum Body {
    /// Still alive, out of the space (minimising).
    Live(Window),
    /// Gone; what it last showed (closing).
    Snapshot(Vec<Snap>),
}

/// A window on its way out: closing, or minimising to the dock.
pub struct Ghost {
    pub body: Body,
    /// The whole frame, title bar included, when it started.
    pub frame: Rectangle<i32, Logical>,
    /// The content's rect then (for its rounded corners).
    pub content: Rectangle<i32, Logical>,
    /// Where the surface's origin was (the content less its own shadow
    /// margins).
    pub origin: Point<i32, Logical>,
    pub bar: Option<MemoryRenderBuffer>,
    pub key: ObjectId,
    pub radius: f32,
    pub glass: bool,
    pub to: RectF,
    pub anim: Anim,
    pub minimizing: bool,
}

impl Ghost {
    pub fn look(&self, now: Instant) -> Look {
        let t = self.anim.t(now);
        let from = self.frame.to_f64();
        if self.minimizing {
            let e = ease_in_out_cubic(t);
            Look { rect: lerp_rect(from, self.to, e), alpha: (1.0 - ease_in_out_cubic((t * 1.15).min(1.0))) as f32 }
        } else {
            let e = ease_out_cubic(t);
            Look { rect: lerp_rect(from, self.to, e), alpha: (1.0 - e) as f32 }
        }
    }

    pub fn window(&self) -> Option<&Window> {
        match &self.body {
            Body::Live(w) => Some(w),
            Body::Snapshot(_) => None,
        }
    }
}
