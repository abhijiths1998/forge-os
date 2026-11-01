//! X11 apps, through XWayland: started with the compositor, its window
//! manager side here. X11 windows go into the same space as Wayland ones
//! and get the same treatment (placement, Forge title bar unless they draw
//! their own, minimise, maximise, fullscreen); their menus and tooltips
//! (override-redirect windows) sit where the app puts them.

use std::{os::fd::OwnedFd, process::Stdio};

use smithay::{
    desktop::Window,
    utils::{Logical, Rectangle},
    wayland::{
        selection::{
            SelectionTarget,
            data_device::{clear_data_device_selection, current_data_device_selection_userdata, request_data_device_client_selection, set_data_device_selection},
            primary_selection::{clear_primary_selection, current_primary_selection_userdata, request_primary_client_selection, set_primary_selection},
        },
        xwayland_shell::{XWaylandShellHandler, XWaylandShellState},
    },
    xwayland::{
        X11Surface, X11Wm, XWayland, XWaylandEvent, XwmHandler,
        xwm::{Reorder, ResizeEdge as X11ResizeEdge, XwmId},
    },
};

use crate::{
    grabs::{self, ResizeEdge},
    state::{Forge, win_data},
};

impl Forge {
    pub fn start_xwayland(&mut self) {
        let spawned = XWayland::spawn(&self.display_handle, None, std::iter::empty::<(String, String)>(), true, Stdio::null(), Stdio::null(), |_| ());
        let (xwayland, client) = match spawned {
            Ok(x) => x,
            Err(e) => {
                tracing::warn!("no XWayland (X11 apps won't run): {e}");
                return;
            }
        };
        let inserted = self.loop_handle.insert_source(xwayland, move |event, _, state| match event {
            XWaylandEvent::Ready { x11_socket, display_number } => {
                match X11Wm::start_wm(state.loop_handle.clone(), x11_socket, client.clone()) {
                    Ok(wm) => {
                        state.xwm = Some(wm);
                        state.xdisplay = Some(display_number);
                        tracing::info!("XWayland on :{display_number}");
                    }
                    Err(e) => tracing::warn!("X11 window manager didn't start: {e}"),
                }
            }
            XWaylandEvent::Error => tracing::warn!("XWayland failed to start"),
        });
        if let Err(e) = inserted {
            tracing::warn!("XWayland not watched: {e}");
        }
    }

    fn x11_window(&self, surface: &X11Surface) -> Option<Window> {
        self.space
            .elements()
            .chain(self.minimized.iter())
            .find(|w| w.x11_surface() == Some(surface))
            .cloned()
    }
}

impl XWaylandShellHandler for Forge {
    fn xwayland_shell_state(&mut self) -> &mut XWaylandShellState {
        &mut self.xwayland_shell_state
    }

    /// An X11 window's Wayland surface arrives after the window is shown:
    /// the moment it can take the keyboard, if it's the one on top.
    fn surface_associated(&mut self, _xwm: XwmId, _wl_surface: smithay::reexports::wayland_server::protocol::wl_surface::WlSurface, surface: X11Surface) {
        if surface.is_override_redirect() {
            return;
        }
        if let Some(window) = self.x11_window(&surface) {
            if self.top_window().as_ref() == Some(&window) {
                self.focus_window(&window);
            }
        }
    }
}
smithay::delegate_xwayland_shell!(Forge);

impl XwmHandler for Forge {
    fn xwm_state(&mut self, _xwm: XwmId) -> &mut X11Wm {
        self.xwm.as_mut().unwrap()
    }

    fn new_window(&mut self, _xwm: XwmId, _window: X11Surface) {}
    fn new_override_redirect_window(&mut self, _xwm: XwmId, _window: X11Surface) {}

    fn map_window_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        let _ = surface.set_mapped(true);
        let window = Window::new_x11_window(surface.clone());
        // Forge's title bar unless the app draws its own (Steam, most games).
        win_data(&window, |d| {
            d.ssd = !surface.is_decorated();
            d.placed = true;
        });
        self.space.map_element(window.clone(), surface.geometry().loc, true);
        self.place_new_window(&window);
        self.focus_window(&window);
        self.ipc_changed();
    }

    fn mapped_override_redirect_window(&mut self, _xwm: XwmId, surface: X11Surface) {
        let loc = surface.geometry().loc;
        self.space.map_element(Window::new_x11_window(surface), loc, false);
    }

    fn unmapped_window(&mut self, _xwm: XwmId, surface: X11Surface) {
        let window = self.space.elements().find(|w| w.x11_surface() == Some(&surface)).cloned();
        if let Some(window) = window {
            if !surface.is_override_redirect() {
                crate::render::start_ghost(self, &window, false);
            }
            self.space.unmap_elem(&window);
        }
        if !surface.is_override_redirect() {
            let _ = surface.set_mapped(false);
            if let Some(top) = self.top_window() {
                self.focus_window(&top);
            }
        }
        self.ipc_changed();
    }

    fn destroyed_window(&mut self, _xwm: XwmId, surface: X11Surface) {
        self.minimized.retain(|w| w.x11_surface() != Some(&surface));
        self.ghosts.retain(|g| g.window().and_then(|w| w.x11_surface()) != Some(&surface));
        self.ipc_changed();
    }

    fn configure_request(&mut self, _xwm: XwmId, surface: X11Surface, x: Option<i32>, y: Option<i32>, w: Option<u32>, h: Option<u32>, _reorder: Option<Reorder>) {
        // Sizes are the app's to ask for; positions only before it's shown
        // (Forge places windows).
        let mut geo = surface.geometry();
        if let Some(w) = w {
            geo.size.w = w as i32;
        }
        if let Some(h) = h {
            geo.size.h = h as i32;
        }
        if self.x11_window(&surface).is_none() {
            if let Some(x) = x {
                geo.loc.x = x;
            }
            if let Some(y) = y {
                geo.loc.y = y;
            }
        }
        let _ = surface.configure(geo);
    }

    fn configure_notify(&mut self, _xwm: XwmId, surface: X11Surface, geometry: Rectangle<i32, Logical>, _above: Option<u32>) {
        // Menus and tooltips move themselves.
        if surface.is_override_redirect() {
            let window = self.space.elements().find(|w| w.x11_surface() == Some(&surface)).cloned();
            if let Some(window) = window {
                self.space.map_element(window, geometry.loc, false);
            }
        }
    }

    fn maximize_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            if win_data(&window, |d| d.restore.is_none()) {
                self.toggle_maximize(&window);
            }
        }
    }

    fn unmaximize_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            if win_data(&window, |d| d.restore.is_some()) {
                self.toggle_maximize(&window);
            }
        }
    }

    fn fullscreen_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.set_fullscreen(&window, true);
        }
    }

    fn unfullscreen_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.set_fullscreen(&window, false);
        }
    }

    fn minimize_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.minimize(&window);
        }
    }

    fn unminimize_request(&mut self, _xwm: XwmId, surface: X11Surface) {
        if let Some(window) = self.x11_window(&surface) {
            self.activate(&window);
        }
    }

    fn resize_request(&mut self, _xwm: XwmId, surface: X11Surface, _button: u32, edges: X11ResizeEdge) {
        if let Some(window) = self.x11_window(&surface) {
            let edges = ResizeEdge::from_bits_truncate(edges as u32);
            grabs::start_resize(self, &window, edges, smithay::utils::SERIAL_COUNTER.next_serial());
        }
    }

    fn move_request(&mut self, _xwm: XwmId, surface: X11Surface, _button: u32) {
        if let Some(window) = self.x11_window(&surface) {
            grabs::start_move(self, &window, smithay::utils::SERIAL_COUNTER.next_serial());
        }
    }

    // The clipboard between X11 and Wayland apps.
    fn allow_selection_access(&mut self, xwm: XwmId, _selection: SelectionTarget) -> bool {
        self.focused_window()
            .and_then(|w| w.x11_surface().and_then(|x| x.xwm_id()))
            .is_some_and(|id| id == xwm)
    }

    fn send_selection(&mut self, _xwm: XwmId, selection: SelectionTarget, mime_type: String, fd: OwnedFd) {
        let result = match selection {
            SelectionTarget::Clipboard => request_data_device_client_selection(&self.seat, mime_type, fd).map_err(|e| e.to_string()),
            SelectionTarget::Primary => request_primary_client_selection(&self.seat, mime_type, fd).map_err(|e| e.to_string()),
        };
        if let Err(e) = result {
            tracing::warn!("clipboard to X11: {e}");
        }
    }

    fn new_selection(&mut self, _xwm: XwmId, selection: SelectionTarget, mime_types: Vec<String>) {
        match selection {
            SelectionTarget::Clipboard => set_data_device_selection(&self.display_handle, &self.seat, mime_types, ()),
            SelectionTarget::Primary => set_primary_selection(&self.display_handle, &self.seat, mime_types, ()),
        }
    }

    fn cleared_selection(&mut self, _xwm: XwmId, selection: SelectionTarget) {
        match selection {
            SelectionTarget::Clipboard => {
                if current_data_device_selection_userdata(&self.seat).is_some() {
                    clear_data_device_selection(&self.display_handle, &self.seat)
                }
            }
            SelectionTarget::Primary => {
                if current_primary_selection_userdata(&self.seat).is_some() {
                    clear_primary_selection(&self.display_handle, &self.seat)
                }
            }
        }
    }
}
