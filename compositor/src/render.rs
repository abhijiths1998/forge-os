//! What one frame of an output is made of, front to back: the shell's top
//! layers (bar, dock, Control Center) each over its glass pane, windows on
//! their way out (closing, minimising), the windows (content with rounded
//! corners, title bar, glass pane behind both), then the bottom layers (the
//! wallpaper). A fullscreen window on top covers the bar and dock, and gets
//! no glass or rounding.
//!
//! Animations (anim.rs) only change where things are drawn: each window's
//! elements are scaled and moved from its real frame to its animated one
//! (`Warp`); glass panes and rounded corners are made at the animated rect.

use std::{cell::RefCell, time::Instant};

use smithay::{
    backend::renderer::{
        element::{
            AsRenderElements, Kind,
            memory::MemoryRenderBufferRenderElement,
            render_elements,
            surface::{WaylandSurfaceRenderElement, render_elements_from_surface_tree},
            texture::TextureRenderElement,
            utils::{Relocate, RelocateRenderElement, RescaleRenderElement},
        },
        gles::{GlesRenderer, GlesTexture, element::TextureShaderElement},
    },
    desktop::{LayerSurface, PopupManager, Window, layer_map_for_output},
    output::Output,
    reexports::wayland_server::{Resource, protocol::wl_surface::WlSurface},
    utils::{Logical, Physical, Point, Rectangle, Scale},
    wayland::shell::wlr_layer::Layer,
};

use crate::{
    anim::{self, Anim, Body, Ghost, Look, RectF},
    deco::{BAR_HEIGHT, BarLook},
    glass::{Glass, Rounded},
    state::{Forge, win_data},
};

render_elements! {
    pub InnerElement<=GlesRenderer>;
    Surface=WaylandSurfaceRenderElement<GlesRenderer>,
    Bar=MemoryRenderBufferRenderElement<GlesRenderer>,
    Rounded=Rounded<WaylandSurfaceRenderElement<GlesRenderer>>,
    Snapshot=TextureRenderElement<GlesTexture>,
    RoundedSnapshot=Rounded<TextureRenderElement<GlesTexture>>,
}

render_elements! {
    pub ForgeElement<=GlesRenderer>;
    Surface=WaylandSurfaceRenderElement<GlesRenderer>,
    Bar=MemoryRenderBufferRenderElement<GlesRenderer>,
    Glass=TextureShaderElement,
    Inner=InnerElement,
    Warped=RelocateRenderElement<RescaleRenderElement<InnerElement>>,
}

/// The shell's surfaces that sit on glass, and their corner radius (as
/// Forge Shell and Forge Control draw them).
fn shell_glass(namespace: &str, theme_radius: f32) -> Option<f32> {
    match namespace {
        "forge-bar" => Some(theme_radius.clamp(6.0, 17.0)),
        "forge-dock" => Some(22.0),
        "forge-control" => Some(20.0),
        _ => None,
    }
}

/// Draws elements made for the rect `from` (logical, global) at `to`
/// instead: scaled from `from`'s corner, then moved.
#[derive(Clone, Copy)]
struct Warp {
    from: RectF,
    to: RectF,
    scale: f64,
    out_loc: Point<f64, Logical>,
}

impl Warp {
    fn new(from: Rectangle<i32, Logical>, to: RectF, scale: f64, out_loc: Point<i32, Logical>) -> Self {
        Warp { from: from.to_f64(), to, scale, out_loc: out_loc.to_f64() }
    }

    fn identity(&self) -> bool {
        let d = |a: f64, b: f64| (a - b).abs() < 0.01;
        d(self.from.loc.x, self.to.loc.x) && d(self.from.loc.y, self.to.loc.y) && d(self.from.size.w, self.to.size.w) && d(self.from.size.h, self.to.size.h)
    }

    fn k(&self) -> (f64, f64) {
        (self.to.size.w / self.from.size.w.max(1.0), self.to.size.h / self.from.size.h.max(1.0))
    }

    /// Where a rect (logical, global) inside `from` is drawn, in output pixels.
    fn rect_px(&self, r: Rectangle<i32, Logical>) -> Rectangle<i32, Physical> {
        let (kx, ky) = self.k();
        let r = r.to_f64();
        let x = self.to.loc.x + (r.loc.x - self.from.loc.x) * kx - self.out_loc.x;
        let y = self.to.loc.y + (r.loc.y - self.from.loc.y) * ky - self.out_loc.y;
        Rectangle::<f64, Logical>::new((x, y).into(), (r.size.w * kx, r.size.h * ky).into())
            .to_physical(self.scale)
            .to_i32_round()
    }

    fn radius(&self, r: f32) -> f32 {
        let (kx, ky) = self.k();
        r * kx.min(ky) as f32
    }

    fn wrap(&self, e: impl Into<InnerElement>) -> ForgeElement {
        let e = e.into();
        if self.identity() {
            return ForgeElement::Inner(e);
        }
        let (kx, ky) = self.k();
        let origin: Point<i32, Physical> = (self.from.loc - self.out_loc).to_physical(self.scale).to_i32_round();
        let target: Point<i32, Physical> = (self.to.loc - self.out_loc).to_physical(self.scale).to_i32_round();
        let rescaled = RescaleRenderElement::from_element(e, origin, Scale { x: kx, y: ky });
        ForgeElement::Warped(RelocateRenderElement::from_element(rescaled, target - origin, Relocate::Relative))
    }
}

/// The wallpaper layers drawn and blurred again if they changed. Called
/// before the output's own framebuffer is bound: drawing into the glass's
/// textures in the middle of a frame loses the window surface.
pub fn update_glass(state: &mut Forge, renderer: &mut GlesRenderer, output: &Output, glass: &mut Glass) {
    let scale = output.current_scale().fractional_scale();
    let size = output.current_mode().map(|m| m.size).unwrap_or_default();
    let map = layer_map_for_output(output);
    let mut wallpaper: Vec<ForgeElement> = Vec::new();
    for layer in map.layers().rev().filter(|l| matches!(l.layer(), Layer::Bottom | Layer::Background)) {
        let geo = map.layer_geometry(layer).unwrap_or_default();
        wallpaper.extend(layer.render_elements::<ForgeElement>(renderer, geo.loc.to_physical_precise_round(scale), scale.into(), 1.0));
    }
    drop(map);
    if let Err(e) = glass.update(renderer, size, scale, &wallpaper) {
        tracing::warn!("glass: {e}");
    }
    glass.retain_panes(|id| {
        state.space.elements().any(|w| crate::win::surface(w).is_some_and(|s| &s.id() == id))
            || state.ghosts.iter().any(|g| &g.key == id)
            || layer_map_for_output(output).layers().any(|l| &l.wl_surface().id() == id)
    });
    if let Some(dir) = state.glass_dump.take() {
        if let Err(e) = glass.dump(renderer, &dir) {
            tracing::warn!("glass dump: {e}");
        }
    }
}

/// A layer's open animation, kept in its user data: started when it first
/// shows something.
#[derive(Default)]
struct LayerAnim {
    shown: bool,
    anim: Option<Anim>,
}

/// How a shell layer comes in: the bar drops in, the dock rises, menus
/// and panels grow and fade in; the wallpaper just appears.
pub fn layer_look(namespace: &str, layer: Layer, geo: Rectangle<i32, Logical>, anim: Option<&Anim>, now: Instant) -> Look {
    let f = geo.to_f64();
    let Some(a) = anim else { return Look { rect: f, alpha: 1.0 } };
    let t = a.t(now);
    let e = anim::ease_out_cubic(t);
    let alpha = anim::ease_out_cubic((t * 1.5).min(1.0)) as f32;
    let shifted = |dy: f64| Rectangle::new((f.loc.x, f.loc.y + dy).into(), f.size);
    match namespace {
        "forge-bar" => Look { rect: shifted(-(f.size.h + 10.0) * (1.0 - e)), alpha },
        "forge-dock" => Look { rect: shifted((f.size.h + 18.0) * (1.0 - e)), alpha },
        // The popups' overlay covers the screen: it fades and settles.
        "forge-popups" => Look { rect: shifted(10.0 * (1.0 - e)), alpha },
        _ if matches!(layer, Layer::Top | Layer::Overlay) => {
            Look { rect: anim::scale_about_centre(f, 0.94 + 0.06 * anim::ease_out_back(t)), alpha }
        }
        _ => Look { rect: f, alpha: 1.0 },
    }
}

/// `flip`: the framebuffer's rows run bottom-up relative to the output
/// (the nested window); the rounding shader needs to know.
pub fn elements(state: &mut Forge, renderer: &mut GlesRenderer, output: &Output, glass: Option<&Glass>, flip: bool) -> Vec<ForgeElement> {
    let scale = output.current_scale().fractional_scale();
    let int_scale = output.current_scale().integer_scale();
    let out_geo = state.space.output_geometry(output).unwrap_or_default();
    let out_loc = out_geo.loc;
    let out_size = output.current_mode().map(|m| m.size).unwrap_or_default();
    let fb_h = out_size.h;
    let theme = state.theme.theme.clone();
    let radius = theme.corner_radius;
    let speed = theme.animations as f64;
    let now = Instant::now();
    let dt = now.saturating_duration_since(state.last_frame).as_secs_f64().min(0.1);
    state.last_frame = now;
    let mut out: Vec<ForgeElement> = Vec::new();

    let layer_elements = |renderer: &mut GlesRenderer, which: &[Layer], glass: Option<&Glass>| -> Vec<ForgeElement> {
        let mut v = Vec::new();
        let map = layer_map_for_output(output);
        for layer in map.layers().rev().filter(|l| which.contains(&l.layer())) {
            let geo = map.layer_geometry(layer).unwrap_or_default();
            let animates = !matches!(layer.layer(), Layer::Background | Layer::Bottom);
            layer.user_data().insert_if_missing(|| RefCell::new(LayerAnim::default()));
            let data = layer.user_data().get::<RefCell<LayerAnim>>().unwrap();
            let draw = |renderer: &mut GlesRenderer, alpha: f32| {
                layer.render_elements::<InnerElement>(renderer, geo.loc.to_physical_precise_round(scale), scale.into(), alpha)
            };
            let current = data.borrow().anim.filter(|a| !a.done(now));
            let look = layer_look(layer.namespace(), layer.layer(), geo, current.as_ref(), now);
            let mut elems = draw(renderer, look.alpha);
            let mut look = look;
            if elems.is_empty() {
                *data.borrow_mut() = LayerAnim::default();
                continue;
            }
            if animates && !data.borrow().shown {
                let a = Anim::new(anim::Kind::Pop, anim::LAYER_MS, speed);
                *data.borrow_mut() = LayerAnim { shown: true, anim: a };
                look = layer_look(layer.namespace(), layer.layer(), geo, a.as_ref(), now);
                elems = draw(renderer, look.alpha);
            }
            data.borrow_mut().shown = true;
            let global = Rectangle::new(geo.loc + out_loc, geo.size);
            let rect_global = Rectangle::new(look.rect.loc + out_loc.to_f64(), look.rect.size);
            let warp = Warp::new(global, rect_global, scale, out_loc);
            v.extend(elems.into_iter().map(|e| warp.wrap(e)));
            if let (Some(glass), Some(r)) = (glass, shell_glass(layer.namespace(), radius)) {
                let rect = warp.rect_px(global);
                v.extend(glass.pane(renderer, &layer.wl_surface().id(), rect, [warp.radius(r) * scale as f32; 4], &theme, 0.22, look.alpha).map(ForgeElement::Glass));
            }
        }
        v
    };

    let wallpaper = layer_elements(renderer, &[Layer::Bottom, Layer::Background], None);

    let fullscreen_top = state.space.elements().last().is_some_and(|w| win_data(w, |d| d.fullscreen));
    if fullscreen_top {
        out.extend(layer_elements(renderer, &[Layer::Overlay], glass));
    } else {
        out.extend(layer_elements(renderer, &[Layer::Overlay, Layer::Top], glass));
    }

    // Windows on their way out, over the rest.
    state.ghosts.retain(|g| !g.anim.done(now));
    let ghosts = std::mem::take(&mut state.ghosts);
    for ghost in ghosts.iter().rev() {
        out.extend(ghost_elements(renderer, ghost, glass, &theme, scale, out_loc, fb_h, flip, now));
    }
    state.ghosts = ghosts;

    let focused = state.focused_window();
    let windows: Vec<_> = state.space.elements().rev().cloned().collect();
    for window in windows {
        let Some(loc) = state.space.element_location(&window) else { continue };
        let geo = window.geometry();
        let origin: Point<i32, Logical> = loc - geo.loc;
        let (fullscreen, maximized, moving) = win_data(&window, |d| (d.fullscreen, d.restore.is_some(), d.moving));
        let bar = state.has_bar(&window);
        let r = if fullscreen || maximized { 0.0 } else { radius };
        let frame = state.frame(&window).unwrap_or_default();

        // This frame's look: its animation (dropped once done) and lift.
        let (anim, lift) = win_data(&window, |d| {
            if d.anim.is_some_and(|a| a.done(now)) {
                d.anim = None;
            }
            d.lift = anim::step_lift(d.lift, if moving { 1.0 } else { 0.0 }, dt, speed);
            (d.anim, d.lift)
        });
        let look = anim::window_look(frame, anim.as_ref(), lift, now);
        let morph = matches!(anim.map(|a| a.kind), Some(anim::Kind::Morph { .. }));
        let frame_warp = Warp::new(frame, look.rect, scale, out_loc);
        // A gliding frame keeps its title bar's height: the content fills
        // the rest.
        let content_rect = Rectangle::new(loc, geo.size);
        let content_warp = if morph {
            let b = if bar { BAR_HEIGHT as f64 } else { 0.0 };
            let to = Rectangle::new((look.rect.loc.x, look.rect.loc.y + b).into(), (look.rect.size.w, (look.rect.size.h - b).max(1.0)).into());
            Warp::new(content_rect, to, scale, out_loc)
        } else {
            frame_warp
        };
        out.extend(popups(renderer, &window, (origin - out_loc).to_physical_precise_round(scale), scale, look.alpha).into_iter().map(|e| content_warp.wrap(e)));

        let Some(surface) = crate::win::surface(&window) else { continue };
        out.extend(content(renderer, &surface, origin, content_rect, glass, bar && r > 0.0, r, &content_warp, scale, out_loc, fb_h, flip, look.alpha));

        if bar {
            let at = if morph { look.rect.loc } else { frame.loc.to_f64() };
            let width = if morph { look.rect.size.w.round() as i32 } else { frame.size.w };
            if let Some(e) = title_bar(state, renderer, &window, at - out_loc.to_f64(), width, scale, int_scale, focused.as_ref() == Some(&window), look.alpha) {
                out.push(if morph { ForgeElement::Bar(e) } else { frame_warp.wrap(e) });
            }
        }
        if let Some(g) = glass {
            if !fullscreen {
                let rect = frame_warp.rect_px(frame);
                let rs = frame_warp.radius(r) * scale as f32;
                out.extend(g.pane(renderer, &surface.id(), rect, [rs; 4], &theme, 0.30, look.alpha).map(ForgeElement::Glass));
            }
        }
    }

    if fullscreen_top {
        out.extend(layer_elements(renderer, &[Layer::Top], glass));
    }
    out.extend(wallpaper);
    out
}

/// A window's content: its surface tree, with its corners rounded when
/// Forge draws its title bar (clients that draw their own decide their own
/// corners).
#[allow(clippy::too_many_arguments)]
fn content(
    renderer: &mut GlesRenderer,
    surface: &WlSurface,
    origin: Point<i32, Logical>,
    content_rect: Rectangle<i32, Logical>,
    glass: Option<&Glass>,
    round: bool,
    r: f32,
    warp: &Warp,
    scale: f64,
    out_loc: Point<i32, Logical>,
    fb_h: i32,
    flip: bool,
    alpha: f32,
) -> Vec<ForgeElement> {
    let elems: Vec<WaylandSurfaceRenderElement<GlesRenderer>> =
        render_elements_from_surface_tree(renderer, surface, (origin - out_loc).to_physical_precise_round(scale), scale, alpha, Kind::Unspecified);
    match glass {
        Some(g) if round => {
            let rect = warp.rect_px(content_rect);
            let rs = warp.radius(r) * scale as f32;
            elems.into_iter().map(|e| warp.wrap(g.clip(e, rect, rs, fb_h, flip))).collect()
        }
        _ => elems.into_iter().map(|e| warp.wrap(e)).collect(),
    }
}

/// A closing or minimising window, where its animation has got to.
#[allow(clippy::too_many_arguments)]
fn ghost_elements(
    renderer: &mut GlesRenderer,
    ghost: &Ghost,
    glass: Option<&Glass>,
    theme: &crate::theme::Theme,
    scale: f64,
    out_loc: Point<i32, Logical>,
    fb_h: i32,
    flip: bool,
    now: Instant,
) -> Vec<ForgeElement> {
    let look = ghost.look(now);
    let warp = Warp::new(ghost.frame, look.rect, scale, out_loc);
    let round = ghost.bar.is_some() && ghost.radius > 0.0;
    let mut v = Vec::new();
    match &ghost.body {
        Body::Live(window) => {
            if let Some(surface) = crate::win::surface(window) {
                if surface.is_alive() {
                    v.extend(content(renderer, &surface, ghost.origin, ghost.content, glass, round, ghost.radius, &warp, scale, out_loc, fb_h, flip, look.alpha));
                }
            }
        }
        Body::Snapshot(snaps) => {
            let content_px = warp.rect_px(ghost.content);
            let rs = warp.radius(ghost.radius) * scale as f32;
            for s in snaps {
                let at = (ghost.origin + s.offset - out_loc).to_f64().to_physical(scale);
                let e = TextureRenderElement::from_static_texture(
                    s.id.clone(),
                    smithay::backend::renderer::Renderer::context_id(renderer),
                    at,
                    s.tex.clone(),
                    s.scale,
                    s.transform,
                    Some(look.alpha),
                    Some(s.src),
                    Some(s.size),
                    None,
                    Kind::Unspecified,
                );
                match glass {
                    Some(g) if round => v.push(warp.wrap(g.clip(e, content_px, rs, fb_h, flip))),
                    _ => v.push(warp.wrap(e)),
                }
            }
        }
    }
    if let Some(bar) = &ghost.bar {
        let at = (ghost.frame.loc - out_loc).to_f64().to_physical(scale);
        if let Ok(e) = MemoryRenderBufferRenderElement::from_buffer(renderer, at, bar, Some(look.alpha), None, None, Kind::Unspecified) {
            v.push(warp.wrap(e));
        }
    }
    if let (Some(g), true) = (glass, ghost.glass) {
        let rect = warp.rect_px(ghost.frame);
        let rs = warp.radius(ghost.radius) * scale as f32;
        v.extend(g.pane(renderer, &ghost.key, rect, [rs; 4], theme, 0.30, look.alpha).map(ForgeElement::Glass));
    }
    v
}

/// A window's menus and tooltips, never clipped by its corners.
fn popups(renderer: &mut GlesRenderer, window: &Window, origin: Point<i32, Physical>, scale: f64, alpha: f32) -> Vec<WaylandSurfaceRenderElement<GlesRenderer>> {
    let Some(toplevel) = window.toplevel() else { return Vec::new() };
    let mut v = Vec::new();
    for (popup, offset) in PopupManager::popups_for_surface(toplevel.wl_surface()) {
        let at = origin + (window.geometry().loc + offset - popup.geometry().loc).to_physical_precise_round(scale);
        v.extend(render_elements_from_surface_tree(renderer, popup.wl_surface(), at, scale, alpha, Kind::Unspecified));
    }
    v
}

/// A window's title bar, `width` wide at `at` (output-local).
#[allow(clippy::too_many_arguments)]
fn title_bar(
    state: &Forge,
    renderer: &mut GlesRenderer,
    window: &Window,
    at: Point<f64, Logical>,
    width: i32,
    scale: f64,
    int_scale: i32,
    focused: bool,
    alpha: f32,
) -> Option<MemoryRenderBufferRenderElement<GlesRenderer>> {
    let title = crate::win::title(window);
    let look = BarLook {
        title,
        width,
        scale: int_scale,
        focused,
        hover: state.hover.as_ref().filter(|(w, _)| w == window).map(|(_, b)| *b),
        maximized: win_data(window, |d| d.restore.is_some()),
        theme: state.theme.theme.clone(),
    };
    let buffer = win_data(window, |d| {
        d.bar.update(look);
        d.bar.buffer.clone()
    })?;
    MemoryRenderBufferRenderElement::from_buffer(renderer, at.to_physical(scale), &buffer, Some(alpha), None, None, Kind::Unspecified).ok()
}

/// The layer surfaces of `output` whose namespace is `ns`.
pub fn find_layer(output: &Output, ns: &str) -> Option<(LayerSurface, Rectangle<i32, Logical>)> {
    let map = layer_map_for_output(output);
    let layer = map.layers().find(|l| l.namespace() == ns)?.clone();
    let geo = map.layer_geometry(&layer)?;
    Some((layer, geo))
}

/// Starts a window's ghost: what it last showed shrinking away (closing),
/// or the live window heading for the dock (minimising).
pub fn start_ghost(state: &mut Forge, window: &Window, minimizing: bool) {
    let speed = state.theme.theme.animations as f64;
    let Some(frame) = state.frame(window) else { return };
    let Some(loc) = state.space.element_location(window) else { return };
    let Some(surface) = crate::win::surface(window) else { return };
    let geo = window.geometry();
    let (fullscreen, maximized) = win_data(window, |d| (d.fullscreen, d.restore.is_some()));
    let to = if minimizing {
        let target = state
            .output
            .as_ref()
            .and_then(|o| {
                let out_loc = state.space.output_geometry(o)?.loc;
                match find_layer(o, "forge-dock") {
                    Some((_, g)) => Some(Point::from((g.loc.x as f64 + g.size.w as f64 / 2.0, g.loc.y as f64 + g.size.h as f64 / 2.0)) + out_loc.to_f64()),
                    None => {
                        let g = state.space.output_geometry(o)?;
                        Some(Point::from((g.loc.x as f64 + g.size.w as f64 / 2.0, (g.loc.y + g.size.h) as f64)))
                    }
                }
            })
            .unwrap_or_else(|| Point::from((frame.loc.x as f64, frame.loc.y as f64)));
        anim::shrunk_at(frame.to_f64(), target)
    } else {
        anim::scale_about_centre(frame.to_f64(), 0.9)
    };
    let (body, ms) = if minimizing {
        (Body::Live(window.clone()), anim::MINIMIZE_MS)
    } else {
        let Some(ctx) = state.render_ctx.clone() else { return };
        let snaps = anim::snapshot(&surface, &ctx);
        if snaps.is_empty() {
            return;
        }
        (Body::Snapshot(snaps), anim::CLOSE_MS)
    };
    let Some(anim) = Anim::new(anim::Kind::Open, ms, speed) else { return };
    let bar = if state.has_bar(window) { win_data(window, |d| d.bar.buffer.clone()) } else { None };
    state.ghosts.retain(|g| g.window() != Some(window));
    state.ghosts.push(Ghost {
        body,
        frame,
        content: Rectangle::new(loc, geo.size),
        origin: loc - geo.loc,
        bar,
        key: surface.id(),
        radius: if fullscreen || maximized { 0.0 } else { state.theme.theme.corner_radius },
        glass: !fullscreen,
        to,
        anim,
        minimizing,
    });
}

/// A shell layer (a menu, the launcher) as it goes: what it last showed
/// fades away. Called while its textures are still there.
pub fn start_layer_ghost(state: &mut Forge, layer: &LayerSurface, geo: Rectangle<i32, Logical>) {
    let speed = state.theme.theme.animations as f64;
    if matches!(layer.layer(), Layer::Background | Layer::Bottom) {
        return;
    }
    let Some(ctx) = state.render_ctx.clone() else { return };
    let snaps = anim::snapshot(layer.wl_surface(), &ctx);
    if snaps.is_empty() {
        return;
    }
    let Some(anim) = Anim::new(anim::Kind::Open, anim::CLOSE_MS, speed) else { return };
    let out_loc = state.output.as_ref().and_then(|o| state.space.output_geometry(o)).map(|g| g.loc).unwrap_or_default();
    let global = Rectangle::new(geo.loc + out_loc, geo.size);
    let f = global.to_f64();
    let to = match layer.namespace() {
        "forge-popups" => Rectangle::new((f.loc.x, f.loc.y + 8.0).into(), f.size),
        _ => anim::scale_about_centre(f, 0.95),
    };
    let glass = shell_glass(layer.namespace(), state.theme.theme.corner_radius);
    state.ghosts.push(Ghost {
        body: Body::Snapshot(snaps),
        frame: global,
        content: global,
        origin: global.loc,
        bar: None,
        key: layer.wl_surface().id(),
        radius: glass.unwrap_or(0.0),
        glass: glass.is_some(),
        to,
        anim,
        minimizing: false,
    });
}
