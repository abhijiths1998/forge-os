//! Forge Glass in the compositor: frosted panes behind the windows, the
//! title bars, the top bar and the dock, and rounded window corners.
//!
//! The pane is the wallpaper (the shell's bottom layers) blurred: drawn into
//! a texture whenever it changes, then blurred with a dual Kawase filter at
//! a fraction of the size (a few cheap passes give a wide, smooth blur).
//! Each glass surface draws its piece of that with the glass shader:
//! rounded to the theme's corners, tinted toward the window colour, a touch
//! more saturated (vibrancy) and with fine grain, so the glass reads as a
//! material. Windows behind don't show through, only the wallpaper: clean,
//! and one blur per frame at most, not one per window.

use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            Bind, Frame, Offscreen, Renderer, Texture, TextureFilter,
            damage::OutputDamageTracker,
            element::{
                Element, Id, Kind, RenderElement, UnderlyingStorage,
                texture::TextureRenderElement,
            },
            gles::{GlesError, GlesFrame, GlesRenderer, GlesTexProgram, GlesTexture, Uniform, UniformName, UniformType, element::TextureShaderElement},
            utils::{CommitCounter, DamageSet, OpaqueRegions},
        },
    },
    utils::{Buffer, Logical, Physical, Point, Rectangle, Scale, Size, Transform},
};

use std::{cell::RefCell, collections::HashMap};

use smithay::reexports::wayland_server::backend::ObjectId;

use crate::theme::{Rgba, Theme};

/// Each pass halves the size; four give a soft, wide blur.
const PASSES: usize = 4;

const DOWN: &str = r#"#version 100
//_DEFINES_
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform sampler2D tex;
uniform float alpha;
uniform vec2 halfpixel;
varying vec2 v_coords;
void main() {
    vec2 uv = v_coords;
    vec4 sum = texture2D(tex, uv) * 4.0;
    sum += texture2D(tex, uv - halfpixel);
    sum += texture2D(tex, uv + halfpixel);
    sum += texture2D(tex, uv + vec2(halfpixel.x, -halfpixel.y));
    sum += texture2D(tex, uv - vec2(halfpixel.x, -halfpixel.y));
    gl_FragColor = sum / 8.0;
}
"#;

const UP: &str = r#"#version 100
//_DEFINES_
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform sampler2D tex;
uniform float alpha;
uniform vec2 halfpixel;
varying vec2 v_coords;
void main() {
    vec2 uv = v_coords;
    vec4 sum = texture2D(tex, uv + vec2(-halfpixel.x * 2.0, 0.0));
    sum += texture2D(tex, uv + vec2(-halfpixel.x, halfpixel.y)) * 2.0;
    sum += texture2D(tex, uv + vec2(0.0, halfpixel.y * 2.0));
    sum += texture2D(tex, uv + vec2(halfpixel.x, halfpixel.y)) * 2.0;
    sum += texture2D(tex, uv + vec2(halfpixel.x * 2.0, 0.0));
    sum += texture2D(tex, uv + vec2(halfpixel.x, -halfpixel.y)) * 2.0;
    sum += texture2D(tex, uv + vec2(0.0, -halfpixel.y * 2.0));
    sum += texture2D(tex, uv + vec2(-halfpixel.x, -halfpixel.y)) * 2.0;
    gl_FragColor = sum / 12.0;
}
"#;

/// The pane: blurred wallpaper, rounded, tinted, more vivid, grained.
/// `uv_rect` is the pane's part of the texture, so the shader knows where in
/// the pane each pixel is.
const PANE: &str = r#"#version 100
//_DEFINES_
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
uniform sampler2D tex;
uniform float alpha;
uniform vec4 uv_rect;
uniform vec2 size;
uniform vec4 radius;
uniform vec4 tint;
uniform float vibrancy;
uniform float grain;
varying vec2 v_coords;

float rounded(vec2 p, vec2 half_size, float r) {
    vec2 q = abs(p) - half_size + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Grain noise that only ever works with small numbers. The usual
// fract(sin(dot(p, (12.9, 78.2))) * 43758) overflows 16-bit floats (max
// 65504) a few hundred pixels into a pane, gives NaN and paints the rest
// of the pane black: that was the dark wedge in big windows on NVIDIA.
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 local = (v_coords - uv_rect.xy) / uv_rect.zw * size;
    vec2 centred = local - size * 0.5;
    // radius: top-left, top-right, bottom-right, bottom-left
    float r = centred.x < 0.0 ? (centred.y < 0.0 ? radius.x : radius.w)
                              : (centred.y < 0.0 ? radius.y : radius.z);
    float d = rounded(centred, size * 0.5, r);
    float inside = 1.0 - smoothstep(-0.5, 0.5, d);

    vec3 c = texture2D(tex, v_coords).rgb;
    float grey = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(grey), c, vibrancy);
    c = mix(c, tint.rgb, tint.a);
    c += (hash(local) - 0.5) * grain;
    gl_FragColor = vec4(c, 1.0) * inside * alpha;
}
"#;

/// Window content with rounded bottom corners (the title bar rounds the
/// top). Works in screen pixels, as a window is many surfaces.
const CLIP: &str = r#"#version 100
//_DEFINES_
#if defined(EXTERNAL)
#extension GL_OES_EGL_image_external : require
#endif
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#if defined(EXTERNAL)
uniform samplerExternalOES tex;
#else
uniform sampler2D tex;
#endif
uniform float alpha;
uniform vec4 rect;
uniform float radius;
uniform float fb_height;
uniform float flip;
varying vec2 v_coords;

void main() {
    vec4 color = texture2D(tex, v_coords);
#if defined(NO_ALPHA)
    color = vec4(color.rgb, 1.0);
#endif
    vec2 p = vec2(gl_FragCoord.x, flip > 0.5 ? fb_height - gl_FragCoord.y : gl_FragCoord.y);
    vec2 local = p - rect.xy;
    // Only the bottom corners.
    vec2 corner = vec2(local.x < radius ? radius : (local.x > rect.z - radius ? rect.z - radius : local.x),
                       rect.w - radius);
    float d = (local.y > rect.w - radius && (local.x < radius || local.x > rect.z - radius))
        ? length(local - corner) - radius : -1.0;
    float inside = 1.0 - smoothstep(-0.5, 0.5, d);
    gl_FragColor = color * alpha * inside;
}
"#;

pub struct Glass {
    down: GlesTexProgram,
    up: GlesTexProgram,
    pane: GlesTexProgram,
    clip: GlesTexProgram,
    /// The drawn wallpaper, its damage tracker, and whether it holds the
    /// previous frame yet (then only what changed is drawn again).
    background: Option<(GlesTexture, OutputDamageTracker, bool)>,
    chain: Vec<GlesTexture>,
    /// Counts the blurs; a pane whose blur is out of date is redrawn.
    generation: u64,
    /// Each pane's element id (by the surface it sits behind) and the blur
    /// it was made for. Panes need ids of their own: the damage tracker
    /// follows each id's position, so a shared id leaves stale glass
    /// behind when a window moves.
    ids: RefCell<HashMap<ObjectId, (u64, Id)>>,
    size: Size<i32, Physical>,
}

impl Glass {
    pub fn new(renderer: &mut GlesRenderer) -> Result<Self, GlesError> {
        let halfpixel = [UniformName::new("halfpixel", UniformType::_2f)];
        Ok(Glass {
            down: renderer.compile_custom_texture_shader(DOWN, &halfpixel)?,
            up: renderer.compile_custom_texture_shader(UP, &halfpixel)?,
            pane: renderer.compile_custom_texture_shader(
                PANE,
                &[
                    UniformName::new("uv_rect", UniformType::_4f),
                    UniformName::new("size", UniformType::_2f),
                    UniformName::new("radius", UniformType::_4f),
                    UniformName::new("tint", UniformType::_4f),
                    UniformName::new("vibrancy", UniformType::_1f),
                    UniformName::new("grain", UniformType::_1f),
                ],
            )?,
            clip: renderer.compile_custom_texture_shader(
                CLIP,
                &[
                    UniformName::new("rect", UniformType::_4f),
                    UniformName::new("radius", UniformType::_1f),
                    UniformName::new("fb_height", UniformType::_1f),
                    UniformName::new("flip", UniformType::_1f),
                ],
            )?,
            background: None,
            chain: Vec::new(),
            generation: 0,
            ids: RefCell::new(HashMap::new()),
            size: Size::default(),
        })
    }

    /// Draws the wallpaper elements and, if anything changed, blurs them again.
    pub fn update<E: RenderElement<GlesRenderer>>(&mut self, renderer: &mut GlesRenderer, size: Size<i32, Physical>, scale: f64, wallpaper: &[E]) -> Result<(), GlesError> {
        if size != self.size || self.background.is_none() {
            self.size = size;
            let tex: GlesTexture = renderer.create_buffer(Fourcc::Abgr8888, (size.w, size.h).into())?;
            self.background = Some((tex, OutputDamageTracker::new(size, scale, Transform::Normal), false));
            self.chain.clear();
            let mut s = size;
            for _ in 0..PASSES {
                s = ((s.w / 2).max(1), (s.h / 2).max(1)).into();
                self.chain.push(renderer.create_buffer(Fourcc::Abgr8888, (s.w, s.h).into())?);
            }
        }
        let (bg, tracker, drawn) = self.background.as_mut().unwrap();
        // Age 1 once the texture holds the last frame: only changes are
        // drawn and reported, so an unchanged wallpaper isn't blurred again
        // (age 0 redrew and re-blurred everything on every frame).
        let age = if *drawn { 1 } else { 0 };
        *drawn = true;
        let changed = {
            let mut target = renderer.bind(bg)?;
            let result = tracker
                .render_output(renderer, &mut target, age, wallpaper, [0.10, 0.11, 0.20, 1.0])
                .map_err(|e| match e {
                    smithay::backend::renderer::damage::Error::Rendering(e) => e,
                    _ => GlesError::FramebufferBindingError,
                })?;
            result.damage.is_some_and(|d| !d.is_empty())
        };
        if !changed {
            return Ok(());
        }

        renderer.downscale_filter(TextureFilter::Linear)?;
        renderer.upscale_filter(TextureFilter::Linear)?;
        // Down: background → chain[0] → … → chain[last]; then up again to chain[0].
        let bg = bg.clone();
        let mut src = bg;
        for i in 0..PASSES {
            let dst = self.chain[i].clone();
            pass(renderer, &src, &dst, &self.down)?;
            src = dst;
        }
        for i in (0..PASSES - 1).rev() {
            let dst = self.chain[i].clone();
            pass(renderer, &src, &dst, &self.up)?;
            src = dst;
        }
        self.generation += 1;
        Ok(())
    }

    /// Forgets the panes of surfaces that are gone.
    pub fn retain_panes(&self, alive: impl Fn(&ObjectId) -> bool) {
        self.ids.borrow_mut().retain(|k, _| alive(k));
    }

    /// Saves the wallpaper texture and each blur step as PNGs in `dir`
    /// (IPC "glass_dump"), to see what the panes are drawn from.
    pub fn dump(&self, renderer: &mut GlesRenderer, dir: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
        use smithay::backend::renderer::ExportMem;
        std::fs::create_dir_all(dir)?;
        let mut textures: Vec<(String, GlesTexture)> = Vec::new();
        if let Some((bg, _, _)) = &self.background {
            textures.push(("background".into(), bg.clone()));
        }
        for (i, t) in self.chain.iter().enumerate() {
            textures.push((format!("chain{i}"), t.clone()));
        }
        for (name, tex) in textures {
            let size = tex.size();
            let mapping = renderer.copy_texture(&tex, Rectangle::from_size((size.w, size.h).into()), Fourcc::Abgr8888)?;
            let bytes = renderer.map_texture(&mapping)?.to_vec();
            crate::capture::save_png(bytes, size.w as u32, size.h as u32, &dir.join(format!("{name}.png")))?;
        }
        Ok(())
    }

    /// A glass pane over `rect` (output pixels), with per-corner radii
    /// (top-left, top-right, bottom-right, bottom-left), behind the surface
    /// `key`.
    pub fn pane(&self, renderer: &GlesRenderer, key: &ObjectId, rect: Rectangle<i32, Physical>, radii: [f32; 4], theme: &Theme, strength: f32, alpha: f32) -> Option<TextureShaderElement> {
        let tex = self.chain.first()?.clone();
        let tsize = tex.size();
        let (fx, fy) = (tsize.w as f64 / self.size.w as f64, tsize.h as f64 / self.size.h as f64);
        let src: Rectangle<f64, Logical> = Rectangle::new(
            (rect.loc.x as f64 * fx, rect.loc.y as f64 * fy).into(),
            (rect.size.w as f64 * fx, rect.size.h as f64 * fy).into(),
        );
        let uv = [
            (src.loc.x / tsize.w as f64) as f32,
            (src.loc.y / tsize.h as f64) as f32,
            (src.size.w / tsize.w as f64) as f32,
            (src.size.h / tsize.h as f64) as f32,
        ];
        let tint: Rgba = theme.window();
        let id = {
            let mut ids = self.ids.borrow_mut();
            let entry = ids.entry(key.clone()).or_insert_with(|| (self.generation, Id::new()));
            if entry.0 != self.generation {
                *entry = (self.generation, Id::new());
            }
            entry.1.clone()
        };
        let inner = TextureRenderElement::from_static_texture(
            id,
            renderer.context_id(),
            rect.loc.to_f64(),
            tex,
            1,
            Transform::Normal,
            Some(alpha),
            Some(src),
            Some((rect.size.w, rect.size.h).into()),
            None,
            Kind::Unspecified,
        );
        Some(TextureShaderElement::new(
            inner,
            self.pane.clone(),
            vec![
                Uniform::new("uv_rect", uv),
                Uniform::new("size", [rect.size.w as f32, rect.size.h as f32]),
                Uniform::new("radius", radii),
                Uniform::new("tint", [tint.0, tint.1, tint.2, strength]),
                Uniform::new("vibrancy", 1.35f32),
                Uniform::new("grain", 0.018f32),
            ],
        ))
    }

    /// A window surface element with its bottom corners rounded off.
    pub fn clip<E>(&self, inner: E, rect: Rectangle<i32, Physical>, radius: f32, fb_height: i32, flip: bool) -> Rounded<E> {
        Rounded { inner, program: self.clip.clone(), rect, radius, fb_height, flip }
    }
}

/// One blur pass: `src` drawn into all of `dst` through `program`.
fn pass(renderer: &mut GlesRenderer, src: &GlesTexture, dst: &GlesTexture, program: &GlesTexProgram) -> Result<(), GlesError> {
    let mut dst = dst.clone();
    let size = dst.size();
    let dst_rect: Rectangle<i32, Physical> = Rectangle::from_size((size.w, size.h).into());
    let src_size = src.size();
    let halfpixel = [0.5 / src_size.w as f32, 0.5 / src_size.h as f32];
    let mut target = renderer.bind(&mut dst)?;
    let mut frame = renderer.render(&mut target, (size.w, size.h).into(), Transform::Normal)?;
    frame.render_texture_from_to(
        src,
        Rectangle::<f64, Buffer>::from_size((src_size.w as f64, src_size.h as f64).into()),
        dst_rect,
        &[dst_rect],
        &[],
        Transform::Normal,
        1.0,
        Some(program),
        &[Uniform::new("halfpixel", halfpixel)],
    )?;
    let _sync = frame.finish()?;
    Ok(())
}

/// A window's surface drawn through the corner-rounding shader.
#[derive(Debug)]
pub struct Rounded<E> {
    inner: E,
    program: GlesTexProgram,
    rect: Rectangle<i32, Physical>,
    radius: f32,
    fb_height: i32,
    flip: bool,
}

impl<E: Element> Element for Rounded<E> {
    fn id(&self) -> &Id {
        self.inner.id()
    }
    fn current_commit(&self) -> CommitCounter {
        self.inner.current_commit()
    }
    fn src(&self) -> Rectangle<f64, Buffer> {
        self.inner.src()
    }
    fn geometry(&self, scale: Scale<f64>) -> Rectangle<i32, Physical> {
        self.inner.geometry(scale)
    }
    fn location(&self, scale: Scale<f64>) -> Point<i32, Physical> {
        self.inner.location(scale)
    }
    fn transform(&self) -> Transform {
        self.inner.transform()
    }
    fn damage_since(&self, scale: Scale<f64>, commit: Option<CommitCounter>) -> DamageSet<i32, Physical> {
        self.inner.damage_since(scale, commit)
    }
    /// Nothing is opaque any more: the corners are cut away.
    fn opaque_regions(&self, _scale: Scale<f64>) -> OpaqueRegions<i32, Physical> {
        OpaqueRegions::default()
    }
    fn alpha(&self) -> f32 {
        self.inner.alpha()
    }
    fn kind(&self) -> Kind {
        self.inner.kind()
    }
}

impl<E: RenderElement<GlesRenderer>> RenderElement<GlesRenderer> for Rounded<E> {
    fn draw(
        &self,
        frame: &mut GlesFrame<'_, '_>,
        src: Rectangle<f64, Buffer>,
        dst: Rectangle<i32, Physical>,
        damage: &[Rectangle<i32, Physical>],
        opaque_regions: &[Rectangle<i32, Physical>],
    ) -> Result<(), GlesError> {
        frame.override_default_tex_program(
            self.program.clone(),
            vec![
                Uniform::new("rect", [self.rect.loc.x as f32, self.rect.loc.y as f32, self.rect.size.w as f32, self.rect.size.h as f32]),
                Uniform::new("radius", self.radius),
                Uniform::new("fb_height", self.fb_height as f32),
                Uniform::new("flip", if self.flip { 1.0f32 } else { 0.0 }),
            ],
        );
        let result = self.inner.draw(frame, src, dst, damage, opaque_regions);
        frame.clear_tex_program_override();
        result
    }

    fn underlying_storage(&self, _renderer: &mut GlesRenderer) -> Option<UnderlyingStorage<'_>> {
        // Never handed to the display hardware as-is: it needs the shader.
        None
    }
}
