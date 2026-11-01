//! Running as the desktop (`forge-compositor`, started from the login
//! screen): the GPU's display outputs through DRM/KMS, buffers through GBM,
//! drawing through EGL/GLES, keyboard, mouse and touchpad through libinput,
//! and the seat through libseat (logind/seatd), which also switches to other
//! virtual terminals (Ctrl+Alt+F1-F12).
//!
//! One GPU: the one the seat says is primary. Forge's laptops run the
//! NVIDIA card alone (MUX), and a hybrid laptop's displays hang off its
//! integrated GPU, which is then the primary. Every connected screen gets
//! an output, side by side.

use std::{collections::HashMap, time::Duration};

use smithay::{
    backend::{
        allocator::{
            Fourcc,
            gbm::{GbmAllocator, GbmBufferFlags, GbmDevice},
        },
        drm::{
            DrmDevice, DrmDeviceFd, DrmEvent, DrmNode, NodeType,
            compositor::FrameFlags,
            exporter::gbm::GbmFramebufferExporter,
            output::{DrmOutput, DrmOutputManager, DrmOutputRenderElements},
        },
        egl::{EGLContext, EGLDevice, EGLDisplay},
        input::InputEvent,
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        renderer::{
            ImportDma, ImportEgl, ImportMemWl,
            element::{Kind, memory::MemoryRenderBufferRenderElement, surface::render_elements_from_surface_tree},
            gles::GlesRenderer,
        },
        session::{Event as SessionEvent, Session, libseat::LibSeatSession},
        udev::{UdevBackend, UdevEvent, all_gpus, primary_gpu},
    },
    input::pointer::CursorImageStatus,
    output::{Mode as WlMode, Output, PhysicalProperties},
    reexports::{
        calloop::{
            EventLoop,
            timer::{TimeoutAction, Timer},
        },
        drm::control::{ModeTypeFlags, connector, crtc},
        input::{DeviceCapability, Libinput},
        rustix::fs::OFlags,
        wayland_server::backend::GlobalId,
    },
    utils::{DeviceFd, IsAlive, Point, Transform},
    wayland::{
        compositor::with_states,
        dmabuf::{DmabufFeedbackBuilder, DmabufState},
    },
};
use smithay::reexports::drm::Device as _;
use smithay_drm_extras::drm_scanner::{DrmScanEvent, DrmScanner};

use crate::{
    cursor::Cursors,
    glass::Glass,
    render::{self, ForgeElement},
    state::Forge,
};

type Manager = DrmOutputManager<GbmAllocator<DrmDeviceFd>, GbmFramebufferExporter<DrmDeviceFd>, (), DrmDeviceFd>;
type Out = DrmOutput<GbmAllocator<DrmDeviceFd>, GbmFramebufferExporter<DrmDeviceFd>, (), DrmDeviceFd>;

const FORMATS: &[Fourcc] = &[Fourcc::Abgr8888, Fourcc::Argb8888];

pub struct Udev {
    pub session: LibSeatSession,
    renderer: GlesRenderer,
    manager: Manager,
    scanner: DrmScanner,
    screens: HashMap<crtc::Handle, Screen>,
    cursors: Cursors,
    libinput: Libinput,
}

struct Screen {
    output: Output,
    drm: Out,
    global: GlobalId,
    glass: Option<Glass>,
    /// A frame is on its way to the screen; the next waits for its vblank.
    queued: bool,
    /// A redraw is already scheduled (by timer).
    scheduled: bool,
}

pub fn run(event_loop: &mut EventLoop<'static, Forge>, state: &mut Forge) -> Result<(), Box<dyn std::error::Error>> {
    let (mut session, notifier) = LibSeatSession::new()?;
    let seat = session.seat();

    let gpu_path = primary_gpu(&seat)?
        .or_else(|| all_gpus(&seat).ok()?.into_iter().next())
        .ok_or("no GPU")?;
    let node = DrmNode::from_path(&gpu_path)?;
    let primary = node.node_with_type(NodeType::Primary).and_then(|n| n.ok()).unwrap_or(node);
    tracing::info!("GPU {}", primary);

    let udev = UdevBackend::new(&seat)?;
    let path = udev
        .device_list()
        .find(|(id, _)| *id == primary.dev_id())
        .map(|(_, p)| p.to_path_buf())
        .unwrap_or(gpu_path);

    let fd = session.open(&path, OFlags::RDWR | OFlags::CLOEXEC | OFlags::NOCTTY | OFlags::NONBLOCK)?;
    let fd = DrmDeviceFd::new(DeviceFd::from(fd));
    let (drm, drm_events) = DrmDevice::new(fd.clone(), true)?;
    let gbm = GbmDevice::new(fd)?;
    let display = unsafe { EGLDisplay::new(gbm.clone())? };
    let render_node = EGLDevice::device_for_display(&display).ok().and_then(|d| d.try_get_render_node().ok().flatten());
    let context = EGLContext::new(&display)?;
    let mut renderer = unsafe { GlesRenderer::new(context)? };

    // Clients' GPU buffers: dmabuf, and EGL's own wl_drm where it's there.
    let _ = renderer.bind_wl_display(&state.display_handle);
    state.render_ctx = Some(smithay::backend::renderer::Renderer::context_id(&renderer));
    state.shm_state.update_formats(renderer.shm_formats());
    let feedback = DmabufFeedbackBuilder::new(render_node.unwrap_or(primary).dev_id(), renderer.dmabuf_formats()).build()?;
    let mut dmabuf = DmabufState::new();
    let global = dmabuf.create_global_with_default_feedback::<Forge>(&state.display_handle, &feedback);
    state.dmabuf = Some((dmabuf, global));

    let render_formats = renderer.egl_context().dmabuf_render_formats().clone();
    let manager = DrmOutputManager::new(
        drm,
        GbmAllocator::new(gbm.clone(), GbmBufferFlags::RENDERING | GbmBufferFlags::SCANOUT),
        GbmFramebufferExporter::new(gbm.clone(), render_node),
        Some(gbm),
        FORMATS.iter().copied(),
        render_formats,
    );

    let handle = event_loop.handle();
    handle.insert_source(drm_events, |event, _, state| match event {
        DrmEvent::VBlank(crtc) => state.vblank(crtc),
        DrmEvent::Error(e) => tracing::warn!("DRM: {e}"),
    })?;

    // Input.
    let mut libinput = Libinput::new_with_udev::<LibinputSessionInterface<LibSeatSession>>(session.clone().into());
    libinput.udev_assign_seat(&seat).map_err(|_| "libinput couldn't take the seat")?;
    handle.insert_source(LibinputInputBackend::new(libinput.clone()), |mut event, _, state| {
        if let InputEvent::DeviceAdded { device } = &mut event {
            // Touchpads: tap to click, natural scrolling, off while typing.
            if device.config_tap_finger_count() > 0 {
                let _ = device.config_tap_set_enabled(true);
                let _ = device.config_dwt_set_enabled(true);
                if device.config_scroll_has_natural_scroll() {
                    let _ = device.config_scroll_set_natural_scroll_enabled(true);
                }
            }
            let _ = device.has_capability(DeviceCapability::Keyboard);
        }
        state.process_input_event(event);
    })?;

    // Switching away to another virtual terminal and back.
    handle.insert_source(notifier, |event, _, state| {
        let Some(udev) = state.udev.as_mut() else { return };
        match event {
            SessionEvent::PauseSession => {
                udev.libinput.suspend();
                udev.manager.pause();
            }
            SessionEvent::ActivateSession => {
                if udev.libinput.resume().is_err() {
                    tracing::warn!("libinput didn't resume");
                }
                if let Err(e) = udev.manager.activate(false) {
                    tracing::warn!("DRM didn't resume: {e}");
                }
                let crtcs: Vec<_> = udev.screens.keys().copied().collect();
                for crtc in crtcs {
                    state.render_screen(crtc);
                }
            }
        }
    })?;

    // Screens plugged in and out.
    handle.insert_source(udev, |event, _, state| {
        if let UdevEvent::Changed { .. } = event {
            state.scan_screens();
        }
    })?;

    state.udev = Some(Udev {
        session,
        renderer,
        manager,
        scanner: DrmScanner::new(),
        screens: HashMap::new(),
        cursors: Cursors::new(),
        libinput,
    });
    state.scan_screens();
    if state.output.is_none() {
        return Err("no screen connected".into());
    }
    Ok(())
}

impl Forge {
    pub fn change_vt(&mut self, vt: i32) {
        if let Some(udev) = self.udev.as_mut() {
            if let Err(e) = udev.session.change_vt(vt) {
                tracing::warn!("couldn't switch to VT {vt}: {e}");
            }
        }
    }

    fn scan_screens(&mut self) {
        let Some(udev) = self.udev.as_mut() else { return };
        let events = match udev.scanner.scan_connectors(udev.manager.device()) {
            Ok(r) => r.into_iter().collect::<Vec<_>>(),
            Err(e) => {
                tracing::warn!("couldn't scan screens: {e}");
                return;
            }
        };
        for event in events {
            match event {
                DrmScanEvent::Connected { connector, crtc: Some(crtc) } => self.screen_connected(connector, crtc),
                DrmScanEvent::Disconnected { crtc: Some(crtc), .. } => self.screen_disconnected(crtc),
                _ => {}
            }
        }
    }

    fn screen_connected(&mut self, connector: connector::Info, crtc: crtc::Handle) {
        let x = self.space.outputs().map(|o| self.space.output_geometry(o).map(|g| g.size.w).unwrap_or(0)).sum::<i32>();
        let udev = self.udev.as_mut().unwrap();
        let name = format!("{}-{}", connector.interface().as_str(), connector.interface_id());
        let Some(mode) = connector
            .modes()
            .iter()
            .find(|m| m.mode_type().contains(ModeTypeFlags::PREFERRED))
            .or_else(|| connector.modes().first())
            .copied()
        else {
            return;
        };
        let wl_mode = WlMode::from(mode);
        let (w, h) = connector.size().unwrap_or((0, 0));
        let output = Output::new(
            name.clone(),
            PhysicalProperties { size: (w as i32, h as i32).into(), subpixel: connector.subpixel().into(), make: "Forge".into(), model: name.clone() },
        );
        let global = output.create_global::<Forge>(&self.display_handle);
        output.set_preferred(wl_mode);
        output.change_current_state(Some(wl_mode), Some(Transform::Normal), None, Some((x, 0).into()));
        self.space.map_output(&output, (x, 0));

        let device = udev.manager.device();
        let mut planes = match device.planes(&crtc) {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!("{name}: no planes: {e}");
                return;
            }
        };
        // Overlay planes misbehave on NVIDIA.
        let nvidia = device.get_driver().map(|d| d.name().to_string_lossy().to_lowercase().contains("nvidia")).unwrap_or(false);
        if nvidia {
            planes.overlay.clear();
        }
        let drm = match udev.manager.initialize_output::<_, ForgeElement>(
            crtc,
            mode,
            &[connector.handle()],
            &output,
            Some(planes),
            &mut udev.renderer,
            &DrmOutputRenderElements::default(),
        ) {
            Ok(d) => d,
            Err(e) => {
                tracing::warn!("{name}: couldn't start the screen: {e}");
                return;
            }
        };
        let glass = Glass::new(&mut udev.renderer).inspect_err(|e| tracing::warn!("no glass: {e}")).ok();
        tracing::info!("screen {name}: {}x{}@{}", wl_mode.size.w, wl_mode.size.h, wl_mode.refresh / 1000);
        udev.screens.insert(crtc, Screen { output: output.clone(), drm, global, glass, queued: false, scheduled: false });
        if self.output.is_none() {
            self.output = Some(output);
        }
        self.loop_handle.insert_idle(move |state| state.render_screen(crtc));
    }

    fn screen_disconnected(&mut self, crtc: crtc::Handle) {
        let Some(udev) = self.udev.as_mut() else { return };
        let Some(screen) = udev.screens.remove(&crtc) else { return };
        self.space.unmap_output(&screen.output);
        self.display_handle.remove_global::<Forge>(screen.global);
        if self.output.as_ref() == Some(&screen.output) {
            self.output = self.space.outputs().next().cloned();
        }
    }

    fn vblank(&mut self, crtc: crtc::Handle) {
        let Some(udev) = self.udev.as_mut() else { return };
        let Some(screen) = udev.screens.get_mut(&crtc) else { return };
        if let Err(e) = screen.drm.frame_submitted() {
            tracing::warn!("frame not submitted: {e}");
        }
        screen.queued = false;
        let output = screen.output.clone();
        self.after_frame(&output);
        self.render_screen(crtc);
    }

    /// Draws a screen if anything changed; otherwise looks again a frame later.
    pub fn render_screen(&mut self, crtc: crtc::Handle) {
        let Some(mut udev) = self.udev.take() else { return };
        let rendered = self.draw(&mut udev, crtc);
        if let Some(screen) = udev.screens.get(&crtc) {
            let output = screen.output.clone();
            if let Some(path) = self.screenshot.take() {
                if let Err(e) = crate::winit::screenshot(self, &mut udev.renderer, &output, screen.glass.as_ref(), &path) {
                    tracing::warn!("screenshot failed: {e}");
                }
            }
            if !self.screencopies.is_empty() {
                self.fulfil_screencopies(&mut udev.renderer, &output, screen.glass.as_ref());
            }
        }
        let refresh = udev.screens.get(&crtc).and_then(|s| s.output.current_mode()).map(|m| m.refresh).unwrap_or(60_000);
        let output = udev.screens.get(&crtc).map(|s| s.output.clone());
        let schedule = match udev.screens.get_mut(&crtc) {
            Some(screen) if !rendered && !screen.scheduled && !screen.queued => {
                screen.scheduled = true;
                true
            }
            _ => false,
        };
        self.udev = Some(udev);
        if let (false, Some(output)) = (rendered, output) {
            self.after_frame(&output);
        }
        if schedule {
            let frame = Duration::from_micros(1_000_000_000 / refresh.max(1) as u64);
            let _ = self.loop_handle.insert_source(Timer::from_duration(frame), move |_, _, state| {
                if let Some(screen) = state.udev.as_mut().and_then(|u| u.screens.get_mut(&crtc)) {
                    screen.scheduled = false;
                }
                state.render_screen(crtc);
                TimeoutAction::Drop
            });
        }
    }

    /// One frame; true if it went to the screen.
    fn draw(&mut self, udev: &mut Udev, crtc: crtc::Handle) -> bool {
        if !udev.session.is_active() {
            return false;
        }
        let Some(screen) = udev.screens.get_mut(&crtc) else { return false };
        if screen.queued {
            return false;
        }
        let output = screen.output.clone();
        if let Some(glass) = screen.glass.as_mut() {
            render::update_glass(self, &mut udev.renderer, &output, glass);
        }
        let mut elements = self.cursor_elements(&mut udev.renderer, &mut udev.cursors, &output);
        elements.extend(render::elements(self, &mut udev.renderer, &output, screen.glass.as_ref(), false));
        let clear = if self.theme.theme.dark { [0.10, 0.11, 0.20, 1.0] } else { [0.90, 0.91, 0.96, 1.0] };
        match screen.drm.render_frame(&mut udev.renderer, &elements, clear, FrameFlags::DEFAULT) {
            Ok(result) if !result.is_empty => match screen.drm.queue_frame(()) {
                Ok(()) => {
                    screen.queued = true;
                    true
                }
                Err(e) => {
                    tracing::warn!("couldn't queue a frame: {e}");
                    false
                }
            },
            Ok(_) => false,
            Err(e) => {
                tracing::warn!("render failed: {e}");
                false
            }
        }
    }

    /// The pointer, front-most: the client's own cursor surface, or the
    /// theme's image for the named cursor.
    fn cursor_elements(&mut self, renderer: &mut GlesRenderer, cursors: &mut Cursors, output: &Output) -> Vec<ForgeElement> {
        let Some(geo) = self.space.output_geometry(output) else { return Vec::new() };
        let pointer = self.seat.get_pointer().unwrap();
        let pos = pointer.current_location();
        if !geo.to_f64().contains(pos) {
            return Vec::new();
        }
        let scale = output.current_scale().fractional_scale();
        let local = pos - geo.loc.to_f64();
        if let CursorImageStatus::Surface(surface) = &self.cursor_status {
            if !surface.alive() {
                self.cursor_status = CursorImageStatus::default_named();
            }
        }
        match &self.cursor_status {
            CursorImageStatus::Hidden => Vec::new(),
            CursorImageStatus::Surface(surface) => {
                let hotspot = with_states(surface, |s| {
                    s.data_map
                        .get::<std::sync::Mutex<smithay::input::pointer::CursorImageAttributes>>()
                        .map(|a| a.lock().unwrap().hotspot)
                        .unwrap_or_default()
                });
                let at = (local - hotspot.to_f64()).to_physical(scale).to_i32_round();
                render_elements_from_surface_tree(renderer, surface, at, scale, 1.0, Kind::Cursor)
                    .into_iter()
                    .map(ForgeElement::Surface)
                    .collect()
            }
            CursorImageStatus::Named(icon) => {
                let mut names = vec![icon.name()];
                names.extend(icon.alt_names());
                let Some((buffer, hotspot)) = cursors.get(&names) else { return Vec::new() };
                let at = (local - Point::from((hotspot.x as f64, hotspot.y as f64))).to_physical(scale);
                MemoryRenderBufferRenderElement::from_buffer(renderer, at, &buffer, None, None, None, Kind::Cursor)
                    .ok()
                    .map(ForgeElement::Bar)
                    .into_iter()
                    .collect()
            }
        }
    }
}
