//! Capturing the screen: Forge's own wlr-screencopy (what grim, Forge Shot,
//! OBS and xdg-desktop-portal-wlr's screen sharing use), and the IPC
//! screenshot. Both draw the output again into an offscreen texture and
//! read it back, so they never disturb what's on screen.
//!
//! Copies go into the client's shm buffer as XRGB8888, which every
//! client takes. A copy is done at the output's next frame.

use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{Bind, ExportMem, Offscreen, TextureMapping, damage::OutputDamageTracker, gles::{GlesRenderer, GlesTexture}},
    },
    output::Output,
    reexports::{
        wayland_protocols_wlr::screencopy::v1::server::{
            zwlr_screencopy_frame_v1::{self, Flags, ZwlrScreencopyFrameV1},
            zwlr_screencopy_manager_v1::{self, ZwlrScreencopyManagerV1},
        },
        wayland_server::{
            Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
            protocol::{wl_buffer::WlBuffer, wl_shm},
        },
    },
    utils::{Physical, Rectangle, Transform},
    wayland::shm::with_buffer_contents_mut,
};

use crate::{glass::Glass, render, state::Forge};

/// Draws `output` offscreen and returns `region` of it as RGBA rows, top
/// row first.
pub fn capture(state: &mut Forge, renderer: &mut GlesRenderer, output: &Output, glass: Option<&Glass>, region: Rectangle<i32, Physical>) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let size = output.current_mode().map(|m| m.size).ok_or("no mode")?;
    let mut texture: GlesTexture = renderer.create_buffer(Fourcc::Abgr8888, (size.w, size.h).into())?;
    let elements = render::elements(state, renderer, output, glass, false);
    let scale = output.current_scale().fractional_scale();
    let mut tracker = OutputDamageTracker::new(size, scale, Transform::Normal);
    let mut target = renderer.bind(&mut texture)?;
    let clear = if state.theme.theme.dark { [0.10, 0.11, 0.20, 1.0] } else { [0.90, 0.91, 0.96, 1.0] };
    tracker.render_output(renderer, &mut target, 0, &elements, clear).map_err(|e| format!("{e:?}"))?;
    let (w, h) = (size.w as usize, size.h as usize);
    let mapping = renderer.copy_framebuffer(&target, Rectangle::from_size((size.w, size.h).into()), Fourcc::Abgr8888)?;
    let flipped = mapping.flipped();
    let bytes = renderer.map_texture(&mapping)?;
    let r = region.intersection(Rectangle::from_size(size)).ok_or("region off screen")?;
    let mut out = Vec::with_capacity(r.size.w as usize * r.size.h as usize * 4);
    for y in r.loc.y as usize..(r.loc.y + r.size.h) as usize {
        // A texture we drew into reads back the other way up from a window
        // surface's convention.
        let row = if flipped { y } else { h - 1 - y };
        let start = (row * w + r.loc.x as usize) * 4;
        out.extend_from_slice(&bytes[start..start + r.size.w as usize * 4]);
    }
    for px in out.chunks_mut(4) {
        px[3] = 255;
    }
    Ok(out)
}

pub fn save_png(rgba: Vec<u8>, w: u32, h: u32, path: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let size = tiny_skia::IntSize::from_wh(w, h).ok_or("empty")?;
    tiny_skia::Pixmap::from_vec(rgba, size).ok_or("bad image")?.save_png(path)?;
    Ok(())
}

// --- wlr-screencopy ---------------------------------------------------------------

pub struct ScreencopyState;

impl ScreencopyState {
    pub fn new(dh: &DisplayHandle) -> Self {
        dh.create_global::<Forge, ZwlrScreencopyManagerV1, ()>(3, ());
        ScreencopyState
    }
}

/// A frame waiting for its output's next draw.
pub struct PendingCopy {
    frame: ZwlrScreencopyFrameV1,
    output: Output,
    region: Rectangle<i32, Physical>,
    buffer: WlBuffer,
    with_damage: bool,
}

/// What a frame object knows before the client hands it a buffer.
pub struct FrameData {
    output: Output,
    region: Rectangle<i32, Physical>,
}

impl GlobalDispatch<ZwlrScreencopyManagerV1, ()> for Forge {
    fn bind(_state: &mut Self, _dh: &DisplayHandle, _client: &Client, resource: New<ZwlrScreencopyManagerV1>, _data: &(), init: &mut DataInit<'_, Self>) {
        init.init(resource, ());
    }
}

impl Dispatch<ZwlrScreencopyManagerV1, ()> for Forge {
    fn request(state: &mut Self, _client: &Client, _manager: &ZwlrScreencopyManagerV1, request: zwlr_screencopy_manager_v1::Request, _data: &(), _dh: &DisplayHandle, init: &mut DataInit<'_, Self>) {
        let (frame, output, region) = match request {
            zwlr_screencopy_manager_v1::Request::CaptureOutput { frame, output, .. } => {
                let Some(output) = Output::from_resource(&output) else { return };
                let size = output.current_mode().map(|m| m.size).unwrap_or_default();
                (frame, output, Rectangle::from_size(size))
            }
            zwlr_screencopy_manager_v1::Request::CaptureOutputRegion { frame, output, x, y, width, height, .. } => {
                let Some(output) = Output::from_resource(&output) else { return };
                let scale = output.current_scale().fractional_scale();
                let r = Rectangle::<i32, smithay::utils::Logical>::new((x, y).into(), (width, height).into()).to_physical_precise_round(scale);
                (frame, output, r)
            }
            zwlr_screencopy_manager_v1::Request::Destroy => return,
            _ => return,
        };
        let _ = state;
        let frame = init.init(frame, FrameData { output, region });
        let FrameData { region, .. } = frame.data::<FrameData>().unwrap();
        let (w, h) = (region.size.w.max(1) as u32, region.size.h.max(1) as u32);
        frame.buffer(wl_shm::Format::Xrgb8888, w, h, w * 4);
        if frame.version() >= 3 {
            frame.buffer_done();
        }
    }
}

impl Dispatch<ZwlrScreencopyFrameV1, FrameData> for Forge {
    fn request(state: &mut Self, _client: &Client, frame: &ZwlrScreencopyFrameV1, request: zwlr_screencopy_frame_v1::Request, data: &FrameData, _dh: &DisplayHandle, _init: &mut DataInit<'_, Self>) {
        let (buffer, with_damage) = match request {
            zwlr_screencopy_frame_v1::Request::Copy { buffer } => (buffer, false),
            zwlr_screencopy_frame_v1::Request::CopyWithDamage { buffer } => (buffer, true),
            _ => return,
        };
        state.screencopies.push(PendingCopy { frame: frame.clone(), output: data.output.clone(), region: data.region, buffer, with_damage });
    }
}

impl Forge {
    /// Answers the copies waiting on `output`. Called by the backends after
    /// a frame, with the renderer free.
    pub fn fulfil_screencopies(&mut self, renderer: &mut GlesRenderer, output: &Output, glass: Option<&Glass>) {
        let (mine, rest): (Vec<_>, Vec<_>) = std::mem::take(&mut self.screencopies).into_iter().partition(|c| &c.output == output);
        self.screencopies = rest;
        for copy in mine {
            if !copy.frame.is_alive() {
                continue;
            }
            let pixels = match capture(self, renderer, output, glass, copy.region) {
                Ok(p) => p,
                Err(e) => {
                    tracing::warn!("screencopy: {e}");
                    copy.frame.failed();
                    continue;
                }
            };
            let (w, h) = (copy.region.size.w as usize, copy.region.size.h as usize);
            // Clients apply the output's transform to what they get; the
            // nested window's output is vertically flipped, so send it that way.
            let flip = output.current_transform() == Transform::Flipped180;
            let written = with_buffer_contents_mut(&copy.buffer, |ptr, len, d| {
                if d.width as usize != w || d.height as usize != h || !matches!(d.format, wl_shm::Format::Xrgb8888 | wl_shm::Format::Argb8888) {
                    return false;
                }
                let dst = unsafe { std::slice::from_raw_parts_mut(ptr.add(d.offset as usize), len - d.offset as usize) };
                for y in 0..h {
                    let sy = if flip { h - 1 - y } else { y };
                    for x in 0..w {
                        let s = (sy * w + x) * 4;
                        let o = y * d.stride as usize + x * 4;
                        // RGBA → XRGB8888 (B, G, R, X in memory).
                        dst[o] = pixels[s + 2];
                        dst[o + 1] = pixels[s + 1];
                        dst[o + 2] = pixels[s];
                        dst[o + 3] = 255;
                    }
                }
                true
            });
            if !matches!(written, Ok(true)) {
                copy.frame.failed();
                continue;
            }
            copy.frame.flags(Flags::empty());
            if copy.with_damage {
                copy.frame.damage(0, 0, w as u32, h as u32);
            }
            let now = rustix_now();
            copy.frame.ready((now.0 >> 32) as u32, now.0 as u32, now.1);
        }
    }
}

fn rustix_now() -> (u64, u32) {
    let t = smithay::reexports::rustix::time::clock_gettime(smithay::reexports::rustix::time::ClockId::Monotonic);
    (t.tv_sec as u64, t.tv_nsec as u32)
}
