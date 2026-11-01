//! Running inside another desktop, as a window (`forge-compositor
//! --nested`): for trying Forge without logging out. One output the size
//! of the window; input comes from that window.

use std::time::Duration;

use smithay::{
    backend::{
        renderer::{damage::OutputDamageTracker, gles::GlesRenderer},
        winit::{self, WinitEvent},
    },
    desktop::layer_map_for_output,
    output::{Mode, Output, PhysicalProperties, Subpixel},
    reexports::calloop::EventLoop,
    utils::{Rectangle, Transform},
};

use crate::{render, state::Forge};

pub fn run(event_loop: &mut EventLoop<'static, Forge>, state: &mut Forge) -> Result<(), Box<dyn std::error::Error>> {
    let (mut backend, winit) = winit::init::<GlesRenderer>()?;
    backend.window().set_title("Forge");

    let mode = Mode { size: backend.window_size(), refresh: 60_000 };
    let output = Output::new(
        "nested".to_string(),
        PhysicalProperties { size: (0, 0).into(), subpixel: Subpixel::Unknown, make: "Forge".into(), model: "Nested".into() },
    );
    let _global = output.create_global::<Forge>(&state.display_handle);
    output.change_current_state(Some(mode), Some(Transform::Flipped180), None, Some((0, 0).into()));
    output.set_preferred(mode);
    state.space.map_output(&output, (0, 0));
    state.output = Some(output.clone());

    let mut damage_tracker = OutputDamageTracker::from_output(&output);
    state.render_ctx = Some(smithay::backend::renderer::Renderer::context_id(backend.renderer()));
    let mut glass = match crate::glass::Glass::new(backend.renderer()) {
        Ok(g) => Some(g),
        Err(e) => {
            tracing::warn!("no glass (shaders didn't compile): {e}");
            None
        }
    };
    // The nested window's framebuffer runs bottom-up (Flipped180 output).
    let flip = std::env::var_os("FORGE_FLIP").map(|v| v != "0").unwrap_or(true);

    event_loop.handle().insert_source(winit, move |event, _, state| match event {
        WinitEvent::Resized { size, .. } => {
            output.change_current_state(Some(Mode { size, refresh: 60_000 }), None, None, None);
            layer_map_for_output(&output).arrange();
        }
        WinitEvent::Input(event) => state.process_input_event(event),
        WinitEvent::Redraw => {
            if let Some(g) = glass.as_mut() {
                render::update_glass(state, backend.renderer(), &output, g);
            }
            let age = backend.buffer_age().unwrap_or(0);
            let damage = {
                let Ok((renderer, mut framebuffer)) = backend.bind() else { return };
                let elements = render::elements(state, renderer, &output, glass.as_ref(), flip);
                let clear = if state.theme.theme.dark { [0.10, 0.11, 0.20, 1.0] } else { [0.90, 0.91, 0.96, 1.0] };
                let damage = match damage_tracker.render_output(renderer, &mut framebuffer, age, &elements, clear) {
                    Ok(result) => result.damage.cloned(),
                    Err(e) => {
                        tracing::warn!("render failed: {e:?}");
                        None
                    }
                };
                damage
            };
            if let Err(e) = backend.submit(damage.as_deref()) {
                tracing::warn!("submit failed: {e}");
            }
            if let Some(path) = state.screenshot.take() {
                if let Err(e) = screenshot(state, backend.renderer(), &output, glass.as_ref(), &path) {
                    tracing::warn!("screenshot failed: {e}");
                }
            }
            if !state.screencopies.is_empty() {
                state.fulfil_screencopies(backend.renderer(), &output, glass.as_ref());
            }
            state.after_frame(&output);
            backend.window().request_redraw();
        }
        WinitEvent::CloseRequested => state.loop_signal.stop(),
        _ => {}
    })?;
    Ok(())
}

/// The IPC screenshot: the whole output, as a PNG.
pub fn screenshot(state: &mut Forge, renderer: &mut GlesRenderer, output: &Output, glass: Option<&crate::glass::Glass>, path: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let size = output.current_mode().map(|m| m.size).ok_or("no mode")?;
    let rgba = crate::capture::capture(state, renderer, output, glass, Rectangle::from_size(size))?;
    crate::capture::save_png(rgba, size.w as u32, size.h as u32, path)
}

impl Forge {
    /// After a frame is shown: tell clients to draw their next one, tidy up,
    /// and send what's waiting.
    pub fn after_frame(&mut self, output: &Output) {
        let time = self.start_time.elapsed();
        let throttle = Some(Duration::from_secs(1));
        for window in self.space.elements() {
            window.send_frame(output, time, throttle, |_, _| Some(output.clone()));
        }
        for layer in layer_map_for_output(output).layers() {
            layer.send_frame(output, time, throttle, |_, _| Some(output.clone()));
        }
        self.space.refresh();
        self.popups.cleanup();
        layer_map_for_output(output).cleanup();
        self.ipc_flush();
        let _ = self.display_handle.flush_clients();
    }
}
