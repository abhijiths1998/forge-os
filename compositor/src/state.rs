//! The compositor's state: the Wayland protocols it speaks (through
//! Smithay), the windows and where they are, and Forge's own bookkeeping
//! for each window (its title bar, minimised and maximised state).

use std::{
    cell::RefCell,
    ffi::OsString,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    },
    time::Instant,
};

use smithay::{
    desktop::{PopupManager, Space, Window},
    input::{Seat, SeatState},
    output::Output,
    reexports::{
        calloop::{EventLoop, Interest, LoopHandle, LoopSignal, Mode, PostAction, generic::Generic},
        wayland_protocols_misc::server_decoration::server::org_kde_kwin_server_decoration_manager::Mode as DefaultMode,
        wayland_server::{
            Display, DisplayHandle,
            backend::{ClientData, ClientId, DisconnectReason},
            protocol::wl_surface::WlSurface,
        },
    },
    utils::{Logical, Point, Rectangle},
    wayland::{
        compositor::{CompositorClientState, CompositorState},
        output::OutputManagerState,
        selection::{data_device::DataDeviceState, primary_selection::PrimarySelectionState},
        shell::{
            kde::decoration::KdeDecorationState,
            wlr_layer::WlrLayerShellState,
            xdg::{XdgShellState, decoration::XdgDecorationState},
        },
        shm::ShmState,
        socket::ListeningSocketSource,
    },
};

use smithay::wayland::seat::WaylandFocus;

use crate::{deco::{Button, TitleBar}, ipc::Ipc, theme::ThemeWatch};

pub struct Forge {
    pub start_time: Instant,
    pub socket_name: OsString,
    pub display_handle: DisplayHandle,
    pub loop_handle: LoopHandle<'static, Forge>,
    pub loop_signal: LoopSignal,

    pub space: Space<Window>,
    pub popups: PopupManager,
    /// Minimised windows, out of the space until something brings them back.
    pub minimized: Vec<Window>,
    pub output: Option<Output>,

    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    // Held only to keep their globals alive.
    #[allow(dead_code)]
    pub xdg_decoration_state: XdgDecorationState,
    pub kde_decoration_state: KdeDecorationState,
    pub layer_shell_state: WlrLayerShellState,
    pub shm_state: ShmState,
    #[allow(dead_code)]
    pub output_manager_state: OutputManagerState,
    pub seat_state: SeatState<Forge>,
    pub data_device_state: DataDeviceState,
    pub primary_selection_state: PrimarySelectionState,
    pub seat: Seat<Forge>,

    pub theme: ThemeWatch,
    /// The title-bar button the pointer is over.
    pub hover: Option<(Window, Button)>,
    /// Super is down and nothing else has happened since: releasing it
    /// opens the start menu.
    pub super_alone: bool,
    /// When and where the last title-bar click was, for double-clicks.
    pub last_bar_click: Option<(Instant, Window)>,
    pub ipc: Ipc,
    /// Where to save the next frame as a PNG (IPC "screenshot").
    pub screenshot: Option<std::path::PathBuf>,
    /// Where to save the glass's textures next frame (IPC "glass_dump").
    pub glass_dump: Option<std::path::PathBuf>,
    /// What the pointer looks like, as the client under it asked.
    pub cursor_status: smithay::input::pointer::CursorImageStatus,
    pub dmabuf: Option<(smithay::wayland::dmabuf::DmabufState, smithay::wayland::dmabuf::DmabufGlobal)>,
    /// The real-screen backend, when running as the desktop.
    pub udev: Option<crate::udev::Udev>,
    /// X11 apps: the window manager side of XWayland, and its display.
    pub xwm: Option<smithay::xwayland::X11Wm>,
    pub xdisplay: Option<u32>,
    pub xwayland_shell_state: smithay::wayland::xwayland_shell::XWaylandShellState,
    #[allow(dead_code)]
    pub screencopy_state: crate::capture::ScreencopyState,
    /// Screen copies waiting for their output's next frame.
    pub screencopies: Vec<crate::capture::PendingCopy>,
    /// Windows and shell layers on their way out (closing, minimising).
    pub ghosts: Vec<crate::anim::Ghost>,
    /// The renderer's context, for keeping a closing window's textures.
    pub render_ctx: Option<smithay::backend::renderer::ContextId<smithay::backend::renderer::gles::GlesTexture>>,
    /// When the last frame was drawn (for animations that follow time).
    pub last_frame: Instant,
}

/// Forge's own data for a window, kept in its user data.
pub struct WinData {
    pub id: u64,
    /// The compositor draws its title bar (the client asked for server-side
    /// decorations, or accepted them).
    pub ssd: bool,
    /// Where it was before it was maximised.
    pub restore: Option<Rectangle<i32, Logical>>,
    /// Placed on screen yet (done on its first commit, once it has a size).
    pub placed: bool,
    /// Where it was when it was minimised, to come back to.
    pub parked: Option<Point<i32, Logical>>,
    pub fullscreen: bool,
    pub bar: TitleBar,
    /// What it's animating (opening, a glide to a new size, a click).
    pub anim: Option<crate::anim::Anim>,
    /// Being dragged by its title bar; `lift` eases toward it.
    pub moving: bool,
    pub lift: f64,
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

pub fn win_data<T>(window: &Window, f: impl FnOnce(&mut WinData) -> T) -> T {
    let map = window.user_data();
    map.insert_if_missing(|| {
        RefCell::new(WinData {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            ssd: false,
            restore: None,
            placed: false,
            parked: None,
            fullscreen: false,
            bar: TitleBar::new(),
            anim: None,
            moving: false,
            lift: 0.0,
        })
    });
    f(&mut map.get::<RefCell<WinData>>().unwrap().borrow_mut())
}

impl Forge {
    pub fn new(event_loop: &mut EventLoop<'static, Forge>, display: Display<Forge>) -> Self {
        let dh = display.handle();

        let compositor_state = CompositorState::new::<Self>(&dh);
        let xdg_shell_state = XdgShellState::new::<Self>(&dh);
        let xdg_decoration_state = XdgDecorationState::new::<Self>(&dh);
        let kde_decoration_state = KdeDecorationState::new::<Self>(&dh, DefaultMode::Server);
        let layer_shell_state = WlrLayerShellState::new::<Self>(&dh);
        let shm_state = ShmState::new::<Self>(&dh, vec![]);
        let output_manager_state = OutputManagerState::new_with_xdg_output::<Self>(&dh);
        let data_device_state = DataDeviceState::new::<Self>(&dh);
        let primary_selection_state = PrimarySelectionState::new::<Self>(&dh);
        let mut seat_state = SeatState::new();
        let mut seat: Seat<Self> = seat_state.new_wl_seat(&dh, "seat0");
        seat.add_keyboard(Default::default(), 300, 30).expect("no keyboard");
        seat.add_pointer();

        let dh_for_x = dh.clone();
        let socket_name = Self::listen(display, event_loop);
        let ipc = Ipc::new(&event_loop.handle(), &socket_name);

        Forge {
            start_time: Instant::now(),
            socket_name,
            display_handle: dh,
            loop_handle: event_loop.handle(),
            loop_signal: event_loop.get_signal(),
            space: Space::default(),
            popups: PopupManager::default(),
            minimized: Vec::new(),
            output: None,
            compositor_state,
            xdg_shell_state,
            xdg_decoration_state,
            kde_decoration_state,
            layer_shell_state,
            shm_state,
            output_manager_state,
            seat_state,
            data_device_state,
            primary_selection_state,
            seat,
            theme: ThemeWatch::new(),
            hover: None,
            super_alone: false,
            last_bar_click: None,
            ipc,
            screenshot: None,
            glass_dump: None,
            cursor_status: smithay::input::pointer::CursorImageStatus::default_named(),
            dmabuf: None,
            udev: None,
            xwm: None,
            xdisplay: None,
            xwayland_shell_state: smithay::wayland::xwayland_shell::XWaylandShellState::new::<Self>(&dh_for_x),
            screencopy_state: crate::capture::ScreencopyState::new(&dh_for_x),
            screencopies: Vec::new(),
            ghosts: Vec::new(),
            render_ctx: None,
            last_frame: Instant::now(),
        }
    }

    /// The Wayland socket clients connect to (wayland-N).
    fn listen(display: Display<Forge>, event_loop: &mut EventLoop<'static, Forge>) -> OsString {
        let socket = ListeningSocketSource::new_auto().expect("no Wayland socket");
        let name = socket.socket_name().to_os_string();
        let handle = event_loop.handle();
        handle
            .insert_source(socket, |stream, _, state| {
                if let Err(e) = state.display_handle.insert_client(stream, Arc::new(ClientState::default())) {
                    tracing::warn!("client refused: {e}");
                }
            })
            .expect("socket source");
        handle
            .insert_source(Generic::new(display, Interest::READ, Mode::Level), |_, display, state| {
                // Safety: the display isn't dropped while it's being dispatched.
                unsafe {
                    display.get_mut().dispatch_clients(state).unwrap();
                }
                Ok(PostAction::Continue)
            })
            .expect("display source");
        name
    }

    /// The window a surface (or one of its subsurfaces' root) belongs to,
    /// minimised ones included.
    pub fn window_for(&self, surface: &WlSurface) -> Option<Window> {
        self.space
            .elements()
            .chain(self.minimized.iter())
            .find(|w| w.wl_surface().is_some_and(|s| *s == *surface))
            .cloned()
    }

    /// Starts a program in this session, with this compositor's display.
    pub fn spawn(&self, command: &str) {
        self.spawn_child(command);
    }

    /// Starts a program in Forge's environment, handing back its process.
    pub fn spawn_child(&self, command: &str) -> Option<std::process::Child> {
        let mut cmd = std::process::Command::new("/bin/sh");
        cmd.arg("-c")
            .arg(command)
            .env("WAYLAND_DISPLAY", &self.socket_name)
            .env("FORGE_COMPOSITOR_SOCKET", self.ipc.path())
            .env("XDG_CURRENT_DESKTOP", "Forge")
            .env("XDG_SESSION_TYPE", "wayland")
            .env("GDK_BACKEND", "wayland")
            .env("QT_QPA_PLATFORM", "wayland")
            .env_remove("HYPRLAND_INSTANCE_SIGNATURE");
        match self.xdisplay {
            Some(n) => {
                cmd.env("DISPLAY", format!(":{n}"));
            }
            None => {
                cmd.env_remove("DISPLAY");
            }
        }
        cmd.spawn().inspect_err(|e| tracing::warn!("couldn't start {command}: {e}")).ok()
    }
}

#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {}
    fn disconnected(&self, _client_id: ClientId, _reason: DisconnectReason) {}
}
