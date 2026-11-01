//! Forge's window management: every window floats. New ones open in the
//! middle of the free area (the screen less the bar and dock). Windows are
//! raised and focused by a click, minimised out of the space (the dock
//! brings them back), maximised to the free area and back.

use smithay::{
    desktop::{
        PopupKind, Window, WindowSurfaceType, find_popup_root_surface, get_popup_toplevel_coords,
        layer_map_for_output,
    },
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::{Logical, Point, Rectangle, SERIAL_COUNTER},
    wayland::shell::{
        wlr_layer::{KeyboardInteractivity, Layer},
        xdg::PopupSurface,
    },
};

use crate::{
    anim,
    win,
    deco::{BAR_HEIGHT, Button, button_at},
    grabs::ResizeEdge,
    state::{Forge, win_data},
};

/// How far outside a window's frame the pointer can grab an edge to resize.
const EDGE: f64 = 8.0;

/// What's under the pointer.
pub enum Hit {
    /// A client surface, and where its origin is on screen.
    Surface(WlSurface, Point<f64, Logical>),
    /// A window's title bar, and the button there if any.
    Bar(Window, Option<Button>),
    Edge(Window, ResizeEdge),
    Nothing,
}

impl Forge {
    /// The screen area left for windows: the output less the bar's and
    /// dock's reserved space.
    pub fn usable_area(&self) -> Rectangle<i32, Logical> {
        let Some(output) = self.output.as_ref() else {
            return Rectangle::from_size((1280, 720).into());
        };
        let geo = self.space.output_geometry(output).unwrap_or_default();
        let mut zone = layer_map_for_output(output).non_exclusive_zone();
        zone.loc += geo.loc;
        zone
    }

    /// The whole window as drawn: its title bar (if Forge draws one) and
    /// its content.
    pub fn frame(&self, window: &Window) -> Option<Rectangle<i32, Logical>> {
        let loc = self.space.element_location(window)?;
        let size = window.geometry().size;
        let bar = if self.has_bar(window) { BAR_HEIGHT } else { 0 };
        Some(Rectangle::new((loc.x, loc.y - bar).into(), (size.w, size.h + bar).into()))
    }

    pub fn has_bar(&self, window: &Window) -> bool {
        win_data(window, |d| d.ssd && !d.fullscreen)
    }

    /// Puts a window at `loc` (its content's top-left), telling X11 windows
    /// where they now are.
    pub fn move_window(&mut self, window: &Window, loc: Point<i32, Logical>, activate: bool) {
        self.space.map_element(window.clone(), loc, activate);
        if window.x11_surface().is_some() {
            win::configure(window, loc, None);
        }
    }

    /// Centres a new window in the free area, its title bar included, and
    /// nudges it down-right if another window sits exactly there.
    pub fn place_new_window(&mut self, window: &Window) {
        let zone = self.usable_area();
        let size = window.geometry().size;
        let bar = if self.has_bar(window) { BAR_HEIGHT } else { 0 };
        let mut loc = Point::<i32, Logical>::from((
            zone.loc.x + (zone.size.w - size.w).max(0) / 2,
            zone.loc.y + bar + (zone.size.h - size.h - bar).max(0) / 2,
        ));
        while self.space.elements().any(|w| w != window && self.space.element_location(w) == Some(loc)) {
            loc += Point::from((28, 28));
        }
        self.move_window(window, loc, true);
        self.animate(window, anim::Kind::Open, anim::OPEN_MS);
    }

    /// Starts an animation on a window (nothing when they're off).
    pub fn animate(&mut self, window: &Window, kind: anim::Kind, ms: u64) {
        let a = anim::Anim::new(kind, ms, self.theme.theme.animations as f64);
        win_data(window, |d| d.anim = a);
    }

    /// A click brought `window` forward: a small press, if it wasn't
    /// already in front.
    pub fn click_focus(&mut self, window: &Window) {
        let was = self.focused_window();
        self.focus_window(window);
        if was.as_ref() != Some(window) && win_data(window, |d| d.anim.is_none()) {
            self.animate(window, anim::Kind::Pop, anim::POP_MS);
        }
    }

    /// Raises a window, gives it the keyboard and marks it active.
    pub fn focus_window(&mut self, window: &Window) {
        if win::is_override_redirect(window) {
            return;
        }
        self.space.raise_element(window, true);
        if let (Some(xwm), Some(x)) = (self.xwm.as_mut(), window.x11_surface()) {
            let _ = xwm.raise_window(x);
        }
        let surface = win::surface(window);
        let keyboard = self.seat.get_keyboard().unwrap();
        keyboard.set_focus(self, surface, SERIAL_COUNTER.next_serial());
        for w in self.space.elements() {
            win::send(w);
        }
        self.ipc_changed();
    }

    pub fn unfocus(&mut self) {
        for w in self.space.elements() {
            w.set_activated(false);
            win::send(w);
        }
        let keyboard = self.seat.get_keyboard().unwrap();
        keyboard.set_focus(self, None, SERIAL_COUNTER.next_serial());
        self.ipc_changed();
    }

    /// The focused window, if a window has the keyboard.
    pub fn focused_window(&self) -> Option<Window> {
        let focus = self.seat.get_keyboard()?.current_focus()?;
        self.window_for(&focus)
    }

    /// The window on top that can take focus.
    pub fn top_window(&self) -> Option<Window> {
        self.space.elements().rev().find(|w| !win::is_override_redirect(w)).cloned()
    }

    pub fn minimize(&mut self, window: &Window) {
        let Some(loc) = self.space.element_location(window) else { return };
        crate::render::start_ghost(self, window, true);
        win_data(window, |d| d.parked = Some(loc));
        window.set_activated(false);
        self.space.unmap_elem(window);
        self.minimized.push(window.clone());
        match self.top_window() {
            Some(top) => self.focus_window(&top),
            None => self.unfocus(),
        }
    }

    /// Back from minimised (if it was) and focused.
    pub fn activate(&mut self, window: &Window) {
        if let Some(i) = self.minimized.iter().position(|w| w == window) {
            let window = self.minimized.remove(i);
            let loc = win_data(&window, |d| d.parked.take()).unwrap_or(self.usable_area().loc);
            // Back from wherever its minimise got to (or the dock).
            let from = self.ghosts.iter().find(|g| g.window() == Some(&window)).map(|g| g.look(std::time::Instant::now()).rect);
            self.ghosts.retain(|g| g.window() != Some(&window));
            self.move_window(&window, loc, true);
            if let Some(frame) = self.frame(&window) {
                let from = from.unwrap_or_else(|| anim::shrunk_at(frame.to_f64(), self.dock_point(frame)));
                self.animate(&window, anim::Kind::Restore { from }, anim::RESTORE_MS);
            }
        }
        self.focus_window(window);
    }

    pub fn close(&mut self, window: &Window) {
        win::close(window);
    }

    /// Fills the free area (title bar included), or goes back to where it
    /// was before.
    pub fn toggle_maximize(&mut self, window: &Window) {
        let before = self.frame(window);
        let restore = win_data(window, |d| d.restore.take());
        match restore {
            Some(rect) => {
                win::set_state(window, win::State::Maximized, false);
                win::configure(window, rect.loc, Some(rect.size));
                self.space.map_element(window.clone(), rect.loc, true);
            }
            None => {
                let Some(loc) = self.space.element_location(window) else { return };
                win_data(window, |d| d.restore = Some(Rectangle::new(loc, window.geometry().size)));
                let zone = self.usable_area();
                let bar = if self.has_bar(window) { BAR_HEIGHT } else { 0 };
                let at = Point::from((zone.loc.x, zone.loc.y + bar));
                win::set_state(window, win::State::Maximized, true);
                win::configure(window, at, Some((zone.size.w, zone.size.h - bar).into()));
                self.space.map_element(window.clone(), at, true);
            }
        }
        self.glide(window, before);
        self.focus_window(window);
    }

    /// The frame glides from `before` to the size the window was just
    /// asked to take.
    fn glide(&mut self, window: &Window, before: Option<Rectangle<i32, Logical>>) {
        let Some(before) = before else { return };
        let Some(loc) = self.space.element_location(window) else { return };
        let size = match window.toplevel() {
            Some(t) => t.with_pending_state(|s| s.size).unwrap_or(window.geometry().size),
            None => window.geometry().size,
        };
        let bar = if self.has_bar(window) { BAR_HEIGHT } else { 0 };
        let to = Rectangle::<i32, Logical>::new((loc.x, loc.y - bar).into(), (size.w, size.h + bar).into());
        // Mid-glide: from where it's drawn now.
        let now = std::time::Instant::now();
        let from = match win_data(window, |d| d.anim) {
            Some(a) if !a.done(now) => anim::window_look(before, Some(&a), 0.0, now).rect,
            _ => before.to_f64(),
        };
        self.animate(window, anim::Kind::Morph { from, to: to.to_f64() }, anim::MORPH_MS);
    }

    /// Where minimised windows go: the dock's middle, or the bottom of the
    /// screen without one.
    pub fn dock_point(&self, fallback: Rectangle<i32, Logical>) -> Point<f64, Logical> {
        let Some(output) = self.output.as_ref() else { return fallback.loc.to_f64() };
        let out = self.space.output_geometry(output).unwrap_or_default();
        match crate::render::find_layer(output, "forge-dock") {
            Some((_, g)) => Point::from((out.loc.x as f64 + g.loc.x as f64 + g.size.w as f64 / 2.0, out.loc.y as f64 + g.loc.y as f64 + g.size.h as f64 / 2.0)),
            None => Point::from((out.loc.x as f64 + out.size.w as f64 / 2.0, (out.loc.y + out.size.h) as f64)),
        }
    }

    /// Fullscreen covers the whole screen, bar and dock too (games, video).
    pub fn set_fullscreen(&mut self, window: &Window, on: bool) {
        let Some(output) = self.output.clone() else { return };
        let was = win_data(window, |d| d.fullscreen);
        if on == was {
            win::send(window);
            return;
        }
        let before = self.frame(window);
        if on {
            let loc = self.space.element_location(window).unwrap_or_default();
            win_data(window, |d| {
                d.fullscreen = true;
                d.parked = Some(loc);
            });
            let geo = self.space.output_geometry(&output).unwrap_or_default();
            win::set_state(window, win::State::Fullscreen, true);
            win::configure(window, geo.loc, Some(geo.size));
            self.space.map_element(window.clone(), geo.loc, true);
        } else {
            let loc = win_data(window, |d| {
                d.fullscreen = false;
                d.parked.take()
            });
            win::set_state(window, win::State::Fullscreen, false);
            let loc = loc.unwrap_or_else(|| self.usable_area().loc);
            win::configure(window, loc, None);
            self.space.map_element(window.clone(), loc, true);
        }
        // No glide in or out of fullscreen: games and videos would stretch
        // for a moment, and the size it comes back to isn't known yet.
        let _ = before;
        win_data(window, |d| d.anim = None);
        self.focus_window(window);
    }

    /// A layer surface that asks for the keyboard outright (a launcher, a
    /// lock screen) gets it as soon as it's there.
    pub fn focus_exclusive_layer(&mut self) {
        let Some(output) = self.output.clone() else { return };
        let surface = {
            let map = layer_map_for_output(&output);
            map.layers()
                .rev()
                .find(|l| {
                    matches!(l.layer(), Layer::Top | Layer::Overlay)
                        && l.cached_state().keyboard_interactivity == KeyboardInteractivity::Exclusive
                })
                .map(|l| l.wl_surface().clone())
        };
        if let Some(surface) = surface {
            let keyboard = self.seat.get_keyboard().unwrap();
            if keyboard.current_focus().as_ref() != Some(&surface) {
                keyboard.set_focus(self, Some(surface), SERIAL_COUNTER.next_serial());
            }
        }
    }

    /// What's at a point: the shell's top layers first, then windows front
    /// to back (their edges, title bars, then content), then the layers
    /// under the windows (the wallpaper).
    pub fn under(&self, pos: Point<f64, Logical>) -> Hit {
        let Some(output) = self.output.as_ref() else { return Hit::Nothing };
        let out_loc = self.space.output_geometry(output).unwrap_or_default().loc.to_f64();

        let layer_hit = |layers: &[Layer]| {
            let map = layer_map_for_output(output);
            for layer in map.layers().rev().filter(|l| layers.contains(&l.layer())) {
                let geo = map.layer_geometry(layer).unwrap_or_default();
                let local = pos - out_loc - geo.loc.to_f64();
                if let Some((surface, at)) = layer.surface_under(local, WindowSurfaceType::ALL) {
                    return Some(Hit::Surface(surface, (at + geo.loc).to_f64() + out_loc));
                }
            }
            None
        };

        // A fullscreen window on top covers the bar and dock.
        let fullscreen_top = self.space.elements().last().is_some_and(|w| win_data(w, |d| d.fullscreen));
        if !fullscreen_top {
            if let Some(hit) = layer_hit(&[Layer::Overlay, Layer::Top]) {
                return hit;
            }
        } else if let Some(hit) = layer_hit(&[Layer::Overlay]) {
            return hit;
        }

        for window in self.space.elements().rev() {
            let Some(frame) = self.frame(window) else { continue };
            let loc = self.space.element_location(window).unwrap();
            let bar = self.has_bar(window);
            let resizable = bar && win_data(window, |d| d.restore.is_none());

            // Content (and popups, which can reach outside the frame).
            let origin = (loc - window.geometry().loc).to_f64();
            if let Some((surface, at)) = window.surface_under(pos - origin, WindowSurfaceType::ALL) {
                return Hit::Surface(surface, at.to_f64() + origin);
            }
            let f = frame.to_f64();
            if bar && pos.x >= f.loc.x && pos.x < f.loc.x + f.size.w && pos.y >= f.loc.y && pos.y < f.loc.y + BAR_HEIGHT as f64 {
                let local = pos - f.loc;
                // The top edge stays grabbable along the bar's top few pixels.
                if resizable && local.y < 3.0 {
                    return Hit::Edge(window.clone(), ResizeEdge::TOP);
                }
                return Hit::Bar(window.clone(), button_at(frame.size.w, local));
            }
            if resizable {
                let grown = Rectangle::new(f.loc - Point::from((EDGE, EDGE)), f.size + (2.0 * EDGE, 2.0 * EDGE).into());
                if grown.contains(pos) && !f.contains(pos) {
                    let mut edges = ResizeEdge::empty();
                    if pos.x < f.loc.x + EDGE {
                        edges |= ResizeEdge::LEFT;
                    } else if pos.x > f.loc.x + f.size.w - EDGE {
                        edges |= ResizeEdge::RIGHT;
                    }
                    if pos.y < f.loc.y + EDGE {
                        edges |= ResizeEdge::TOP;
                    } else if pos.y > f.loc.y + f.size.h - EDGE {
                        edges |= ResizeEdge::BOTTOM;
                    }
                    return Hit::Edge(window.clone(), edges);
                }
            }
        }

        layer_hit(&[Layer::Bottom, Layer::Background]).unwrap_or(Hit::Nothing)
    }

    /// Keeps a popup (a menu) on screen.
    pub fn unconstrain_popup(&self, popup: &PopupSurface) {
        let Ok(root) = find_popup_root_surface(&PopupKind::Xdg(popup.clone())) else { return };
        let Some(window) = self.window_for(&root) else { return };
        let Some(output) = self.output.as_ref() else { return };
        let Some(window_geo) = self.space.element_geometry(&window) else { return };
        let mut target = self.space.output_geometry(output).unwrap_or_default();
        target.loc -= get_popup_toplevel_coords(&PopupKind::Xdg(popup.clone()));
        target.loc -= window_geo.loc;
        popup.with_pending_state(|state| {
            state.geometry = state.positioner.get_unconstrained_geometry(target);
        });
    }
}
