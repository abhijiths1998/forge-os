//! A window, whichever kind it is: a Wayland toplevel (xdg-shell) or an X11
//! window through XWayland. The rest of the compositor asks these, so it
//! never has to care which.

use smithay::{
    desktop::{Window, WindowSurface},
    reexports::{wayland_protocols::xdg::shell::server::xdg_toplevel, wayland_server::protocol::wl_surface::WlSurface},
    utils::{Logical, Point, Rectangle, Size},
    wayland::{compositor::with_states, seat::WaylandFocus, shell::xdg::XdgToplevelSurfaceData},
};

pub fn surface(w: &Window) -> Option<WlSurface> {
    w.wl_surface().map(|s| s.into_owned())
}

pub fn title(w: &Window) -> String {
    match w.underlying_surface() {
        WindowSurface::Wayland(t) => with_states(t.wl_surface(), |s| {
            s.data_map.get::<XdgToplevelSurfaceData>().and_then(|d| d.lock().unwrap().title.clone())
        })
        .unwrap_or_default(),
        WindowSurface::X11(x) => x.title(),
    }
}

/// The app id (Wayland) or the window class (X11): what the dock matches
/// to an app.
pub fn app_id(w: &Window) -> String {
    match w.underlying_surface() {
        WindowSurface::Wayland(t) => with_states(t.wl_surface(), |s| {
            s.data_map.get::<XdgToplevelSurfaceData>().and_then(|d| d.lock().unwrap().app_id.clone())
        })
        .unwrap_or_default(),
        WindowSurface::X11(x) => x.class(),
    }
}

/// X11 menus and tooltips: windows the X client places itself, never
/// focused, decorated or listed.
pub fn is_override_redirect(w: &Window) -> bool {
    w.x11_surface().is_some_and(|x| x.is_override_redirect())
}

pub fn close(w: &Window) {
    match w.underlying_surface() {
        WindowSurface::Wayland(t) => t.send_close(),
        WindowSurface::X11(x) => {
            let _ = x.close();
        }
    }
}

/// Asks the window to take a size (None: its own choice) at `loc`. X11
/// windows are told their position too, so their menus open in the right
/// place.
pub fn configure(w: &Window, loc: Point<i32, Logical>, size: Option<Size<i32, Logical>>) {
    match w.underlying_surface() {
        WindowSurface::Wayland(t) => {
            t.with_pending_state(|s| s.size = size);
            if t.is_initial_configure_sent() {
                t.send_pending_configure();
            }
        }
        WindowSurface::X11(x) => {
            let size = size.unwrap_or_else(|| x.geometry().size);
            let _ = x.configure(Rectangle::new(loc, size));
        }
    }
}

#[derive(Clone, Copy)]
pub enum State {
    Maximized,
    Fullscreen,
    Resizing,
}

pub fn set_state(w: &Window, state: State, on: bool) {
    match w.underlying_surface() {
        WindowSurface::Wayland(t) => {
            let s = match state {
                State::Maximized => xdg_toplevel::State::Maximized,
                State::Fullscreen => xdg_toplevel::State::Fullscreen,
                State::Resizing => xdg_toplevel::State::Resizing,
            };
            t.with_pending_state(|p| {
                if on {
                    p.states.set(s);
                } else {
                    p.states.unset(s);
                }
            });
        }
        WindowSurface::X11(x) => {
            let _ = match state {
                State::Maximized => x.set_maximized(on),
                State::Fullscreen => x.set_fullscreen(on),
                State::Resizing => Ok(()),
            };
        }
    }
}

/// Sends what's pending (Wayland; X11 changes go out at once).
pub fn send(w: &Window) {
    if let Some(t) = w.toplevel() {
        if t.is_initial_configure_sent() {
            t.send_pending_configure();
        }
    }
}

/// The smallest and largest size the window takes (0: no limit).
pub fn size_limits(w: &Window) -> (Size<i32, Logical>, Size<i32, Logical>) {
    match w.underlying_surface() {
        WindowSurface::Wayland(t) => with_states(t.wl_surface(), |states| {
            let mut guard = states.cached_state.get::<smithay::wayland::shell::xdg::SurfaceCachedState>();
            let d = guard.current();
            (d.min_size, d.max_size)
        }),
        WindowSurface::X11(x) => (x.min_size().unwrap_or_default(), x.max_size().unwrap_or_default()),
    }
}
