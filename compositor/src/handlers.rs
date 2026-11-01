//! What the compositor does when clients talk to it: surfaces committing
//! new content, windows (xdg-shell) and their decoration choice, the shell's
//! layer surfaces (Forge Shell's bar, dock and wallpaper), the seat and the
//! clipboard. Window management itself is in wm.rs.

use smithay::{
    backend::renderer::utils::on_commit_buffer_handler,
    delegate_compositor, delegate_data_device, delegate_kde_decoration, delegate_layer_shell,
    delegate_output, delegate_primary_selection, delegate_seat, delegate_shm, delegate_xdg_decoration,
    delegate_xdg_shell,
    desktop::{LayerSurface, PopupKind, Window, WindowSurfaceType, layer_map_for_output},
    input::{Seat, SeatHandler, SeatState, pointer::CursorImageStatus},
    output::Output,
    reexports::{
        wayland_protocols::xdg::{decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode as XdgMode, shell::server::xdg_toplevel},
        wayland_protocols_misc::server_decoration::server::org_kde_kwin_server_decoration::{
            Mode as KdeMode, OrgKdeKwinServerDecoration,
        },
        wayland_server::{
            Client, Resource, WEnum,
            protocol::{wl_buffer::WlBuffer, wl_output::WlOutput, wl_seat::WlSeat, wl_surface::WlSurface},
        },
    },
    utils::Serial,
    wayland::{
        buffer::BufferHandler,
        compositor::{CompositorClientState, CompositorHandler, CompositorState, get_parent, is_sync_subsurface, with_states},
        output::OutputHandler,
        selection::{
            SelectionHandler,
            data_device::{ClientDndGrabHandler, DataDeviceHandler, DataDeviceState, ServerDndGrabHandler, set_data_device_focus},
            primary_selection::{PrimarySelectionHandler, PrimarySelectionState, set_primary_focus},
        },
        shell::{
            kde::decoration::{KdeDecorationHandler, KdeDecorationState},
            wlr_layer::{Layer, LayerSurface as WlrLayerSurface, LayerSurfaceData, WlrLayerShellHandler, WlrLayerShellState},
            xdg::{
                PopupSurface, PositionerState, ToplevelSurface, XdgShellHandler, XdgShellState, XdgToplevelSurfaceData,
                decoration::XdgDecorationHandler,
            },
        },
        shm::{ShmHandler, ShmState},
    },
};

use crate::{
    grabs::{self, ResizeEdge},
    state::{ClientState, Forge, win_data},
};

// --- Surfaces -------------------------------------------------------------------

impl CompositorHandler for Forge {
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(&self, client: &'a Client) -> &'a CompositorClientState {
        // XWayland is a client too, with its own client data.
        if let Some(x) = client.get_data::<smithay::xwayland::XWaylandClientData>() {
            return &x.compositor_state;
        }
        &client.get_data::<ClientState>().unwrap().compositor_state
    }

    fn commit(&mut self, surface: &WlSurface) {
        // A shell layer taking its buffer away (a menu closing): keep what
        // it showed for its fade-out, before the textures go.
        self.layer_unmapping(surface);
        on_commit_buffer_handler::<Self>(surface);
        if !is_sync_subsurface(surface) {
            let mut root = surface.clone();
            while let Some(parent) = get_parent(&root) {
                root = parent;
            }
            if let Some(window) = self.window_for(&root) {
                window.on_commit();
            }
        }

        // A window's first commits: the initial configure, then placing it
        // once it knows its size.
        if let Some(toplevel) = self.window_for(surface).as_ref().and_then(|w| w.toplevel().cloned()) {
            let window = self.window_for(surface).unwrap();
            let configured = with_states(surface, |states| {
                states.data_map.get::<XdgToplevelSurfaceData>().unwrap().lock().unwrap().initial_configure_sent
            });
            if !configured {
                toplevel.send_configure();
            } else if !win_data(&window, |d| d.placed) && window.geometry().size.w > 0 {
                win_data(&window, |d| d.placed = true);
                self.place_new_window(&window);
            }
        }

        self.popups.commit(surface);
        if let Some(PopupKind::Xdg(popup)) = self.popups.find_popup(surface) {
            if !popup.is_initial_configure_sent() {
                popup.send_configure().ok();
            }
        }

        self.layer_commit(surface);
        grabs::resize_commit(self, surface);
    }
}

impl Forge {
    fn layer_unmapping(&mut self, surface: &WlSurface) {
        let removed = with_states(surface, |states| {
            matches!(
                states.cached_state.get::<smithay::wayland::compositor::SurfaceAttributes>().current().buffer,
                Some(smithay::wayland::compositor::BufferAssignment::Removed)
            )
        });
        if !removed {
            return;
        }
        let Some(output) = self.output.clone() else { return };
        let found = {
            let map = layer_map_for_output(&output);
            map.layer_for_surface(surface, WindowSurfaceType::TOPLEVEL)
                .cloned()
                .and_then(|l| map.layer_geometry(&l).map(|g| (l, g)))
        };
        if let Some((layer, geo)) = found {
            crate::render::start_layer_ghost(self, &layer, geo);
        }
    }

    /// Layer surfaces: arrange their output and answer the first commit.
    fn layer_commit(&mut self, surface: &WlSurface) {
        let Some(output) = self.space.outputs().find(|o| {
            layer_map_for_output(o).layer_for_surface(surface, WindowSurfaceType::TOPLEVEL).is_some()
        }) else {
            return;
        };
        let configured = with_states(surface, |states| {
            states.data_map.get::<LayerSurfaceData>().unwrap().lock().unwrap().initial_configure_sent
        });
        let mut map = layer_map_for_output(output);
        map.arrange();
        if !configured {
            if let Some(layer) = map.layer_for_surface(surface, WindowSurfaceType::TOPLEVEL) {
                layer.layer_surface().send_configure();
            }
        }
        drop(map);
        // A layer that wants the keyboard when it appears (a launcher) gets it.
        self.focus_exclusive_layer();
    }
}

impl BufferHandler for Forge {
    fn buffer_destroyed(&mut self, _buffer: &WlBuffer) {}
}

impl ShmHandler for Forge {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}

delegate_compositor!(Forge);
delegate_shm!(Forge);

// --- Seat and clipboard -----------------------------------------------------------

impl SeatHandler for Forge {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Forge> {
        &mut self.seat_state
    }

    fn cursor_image(&mut self, _seat: &Seat<Self>, image: CursorImageStatus) {
        self.cursor_status = image;
    }

    fn focus_changed(&mut self, seat: &Seat<Self>, focused: Option<&WlSurface>) {
        let dh = &self.display_handle;
        let client = focused.and_then(|s| dh.get_client(s.id()).ok());
        set_data_device_focus(dh, seat, client.clone());
        set_primary_focus(dh, seat, client);
    }
}

impl SelectionHandler for Forge {
    type SelectionUserData = ();

    // The clipboard reaches X11 apps through XWayland.
    fn new_selection(&mut self, ty: smithay::wayland::selection::SelectionTarget, source: Option<smithay::wayland::selection::SelectionSource>, _seat: Seat<Self>) {
        if let Some(xwm) = self.xwm.as_mut() {
            if let Err(e) = xwm.new_selection(ty, source.map(|s| s.mime_types())) {
                tracing::warn!("X11 clipboard: {e}");
            }
        }
    }

    fn send_selection(&mut self, ty: smithay::wayland::selection::SelectionTarget, mime_type: String, fd: std::os::fd::OwnedFd, _seat: Seat<Self>, _user_data: &()) {
        if let Some(xwm) = self.xwm.as_mut() {
            if let Err(e) = xwm.send_selection(ty, mime_type, fd, self.loop_handle.clone()) {
                tracing::warn!("X11 clipboard: {e}");
            }
        }
    }
}

impl DataDeviceHandler for Forge {
    fn data_device_state(&self) -> &DataDeviceState {
        &self.data_device_state
    }
}

impl ClientDndGrabHandler for Forge {}
impl ServerDndGrabHandler for Forge {}

impl PrimarySelectionHandler for Forge {
    fn primary_selection_state(&self) -> &PrimarySelectionState {
        &self.primary_selection_state
    }
}

impl OutputHandler for Forge {}

delegate_seat!(Forge);

// Clients' GPU buffers.
impl smithay::wayland::dmabuf::DmabufHandler for Forge {
    fn dmabuf_state(&mut self) -> &mut smithay::wayland::dmabuf::DmabufState {
        &mut self.dmabuf.as_mut().expect("dmabuf global without state").0
    }

    fn dmabuf_imported(
        &mut self,
        _global: &smithay::wayland::dmabuf::DmabufGlobal,
        _dmabuf: smithay::backend::allocator::dmabuf::Dmabuf,
        notifier: smithay::wayland::dmabuf::ImportNotifier,
    ) {
        // The renderer imports it when it's first drawn.
        let _ = notifier.successful::<Forge>();
    }
}
smithay::delegate_dmabuf!(Forge);
delegate_data_device!(Forge);
delegate_primary_selection!(Forge);
delegate_output!(Forge);

// --- Windows ------------------------------------------------------------------------

impl XdgShellHandler for Forge {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        &mut self.xdg_shell_state
    }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        // Windows float; it's placed properly once it has a size.
        surface.with_pending_state(|state| {
            for s in [
                xdg_toplevel::State::TiledLeft,
                xdg_toplevel::State::TiledRight,
                xdg_toplevel::State::TiledTop,
                xdg_toplevel::State::TiledBottom,
            ] {
                state.states.unset(s);
            }
        });
        let window = Window::new_wayland_window(surface);
        let zone = self.usable_area();
        self.space.map_element(window.clone(), zone.loc, false);
        self.focus_window(&window);
        self.ipc_changed();
    }

    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        self.minimized.retain(|w| w.toplevel().is_none_or(|t| t != &surface));
        self.ghosts.retain(|g| g.window().and_then(|w| w.toplevel()) != Some(&surface));
        if let Some(window) = self.window_for(surface.wl_surface()) {
            // What it last showed shrinks and fades away.
            if self.space.element_location(&window).is_some() {
                crate::render::start_ghost(self, &window, false);
            }
            self.space.unmap_elem(&window);
        }
        // Focus what's now on top.
        match self.space.elements().last().cloned() {
            Some(top) => self.focus_window(&top),
            None => self.unfocus(),
        }
        self.ipc_changed();
    }

    fn title_changed(&mut self, _surface: ToplevelSurface) {
        self.ipc_changed();
    }

    fn app_id_changed(&mut self, _surface: ToplevelSurface) {
        self.ipc_changed();
    }

    fn new_popup(&mut self, surface: PopupSurface, _positioner: PositionerState) {
        self.unconstrain_popup(&surface);
        let _ = self.popups.track_popup(PopupKind::Xdg(surface));
    }

    fn reposition_request(&mut self, surface: PopupSurface, positioner: PositionerState, token: u32) {
        surface.with_pending_state(|state| {
            state.geometry = positioner.get_geometry();
            state.positioner = positioner;
        });
        self.unconstrain_popup(&surface);
        surface.send_repositioned(token);
    }

    fn grab(&mut self, _surface: PopupSurface, _seat: WlSeat, _serial: Serial) {}

    // Clients that draw their own title bar ask to be moved and resized.
    fn move_request(&mut self, surface: ToplevelSurface, _seat: WlSeat, serial: Serial) {
        if let Some(window) = self.window_for(surface.wl_surface()) {
            grabs::start_move(self, &window, serial);
        }
    }

    fn resize_request(&mut self, surface: ToplevelSurface, _seat: WlSeat, serial: Serial, edges: xdg_toplevel::ResizeEdge) {
        if let Some(window) = self.window_for(surface.wl_surface()) {
            grabs::start_resize(self, &window, ResizeEdge::from(edges), serial);
        }
    }

    fn maximize_request(&mut self, surface: ToplevelSurface) {
        if let Some(window) = self.window_for(surface.wl_surface()) {
            if win_data(&window, |d| d.restore.is_none()) {
                self.toggle_maximize(&window);
            }
        }
        surface.send_configure();
    }

    fn unmaximize_request(&mut self, surface: ToplevelSurface) {
        if let Some(window) = self.window_for(surface.wl_surface()) {
            if win_data(&window, |d| d.restore.is_some()) {
                self.toggle_maximize(&window);
            }
        }
    }

    fn minimize_request(&mut self, surface: ToplevelSurface) {
        if let Some(window) = self.window_for(surface.wl_surface()) {
            self.minimize(&window);
        }
    }

    fn fullscreen_request(&mut self, surface: ToplevelSurface, _output: Option<WlOutput>) {
        if let Some(window) = self.window_for(surface.wl_surface()) {
            self.set_fullscreen(&window, true);
        }
    }

    fn unfullscreen_request(&mut self, surface: ToplevelSurface) {
        if let Some(window) = self.window_for(surface.wl_surface()) {
            self.set_fullscreen(&window, false);
        }
    }
}

delegate_xdg_shell!(Forge);

// --- Title bars: who draws them -----------------------------------------------------
// Forge draws them unless the client says it draws its own (GTK 4, Chromium
// with its own tabs). Windows that never say anything draw their own too.

impl XdgDecorationHandler for Forge {
    fn new_decoration(&mut self, toplevel: ToplevelSurface) {
        self.set_ssd(&toplevel, true);
    }

    fn request_mode(&mut self, toplevel: ToplevelSurface, mode: XdgMode) {
        self.set_ssd(&toplevel, mode == XdgMode::ServerSide);
    }

    fn unset_mode(&mut self, toplevel: ToplevelSurface) {
        self.set_ssd(&toplevel, true);
    }
}

impl KdeDecorationHandler for Forge {
    fn kde_decoration_state(&self) -> &KdeDecorationState {
        &self.kde_decoration_state
    }

    fn request_mode(&mut self, surface: &WlSurface, decoration: &OrgKdeKwinServerDecoration, mode: WEnum<KdeMode>) {
        if let WEnum::Value(mode) = mode {
            decoration.mode(mode);
            if let Some(window) = self.window_for(surface) {
                win_data(&window, |d| d.ssd = mode == KdeMode::Server);
            }
        }
    }
}

impl Forge {
    fn set_ssd(&mut self, toplevel: &ToplevelSurface, ssd: bool) {
        toplevel.with_pending_state(|state| {
            state.decoration_mode = Some(if ssd { XdgMode::ServerSide } else { XdgMode::ClientSide });
        });
        if toplevel.is_initial_configure_sent() {
            toplevel.send_pending_configure();
        }
        if let Some(window) = self.window_for(toplevel.wl_surface()) {
            win_data(&window, |d| d.ssd = ssd);
        }
    }
}

delegate_xdg_decoration!(Forge);
delegate_kde_decoration!(Forge);

// --- The shell's surfaces (wlr-layer-shell) ----------------------------------------------

impl WlrLayerShellHandler for Forge {
    fn shell_state(&mut self) -> &mut WlrLayerShellState {
        &mut self.layer_shell_state
    }

    fn new_layer_surface(&mut self, surface: WlrLayerSurface, output: Option<WlOutput>, _layer: Layer, namespace: String) {
        let Some(output) = output
            .as_ref()
            .and_then(Output::from_resource)
            .or_else(|| self.space.outputs().next().cloned())
        else {
            return;
        };
        let mut map = layer_map_for_output(&output);
        if let Err(e) = map.map_layer(&LayerSurface::new(surface, namespace)) {
            tracing::warn!("layer surface refused: {e}");
        }
    }

    fn layer_destroyed(&mut self, surface: WlrLayerSurface) {
        for output in self.space.outputs() {
            let mut map = layer_map_for_output(output);
            let layer = map.layers().find(|l| l.layer_surface() == &surface).cloned();
            if let Some(layer) = layer {
                map.unmap_layer(&layer);
            }
        }
        // Whatever had the keyboard before a launcher-like layer gets it back.
        if let Some(top) = self.space.elements().last().cloned() {
            self.focus_window(&top);
        }
    }

    fn new_popup(&mut self, _parent: WlrLayerSurface, popup: PopupSurface) {
        let _ = self.popups.track_popup(PopupKind::Xdg(popup));
    }
}

delegate_layer_shell!(Forge);
