//! The pointer on a real screen: the cursor theme's images (Breeze, as the
//! rest of Forge), by the name a client or the compositor asks for
//! ("default", "text", "pointer", "ew-resize"...), cached.

use std::collections::HashMap;

use smithay::{
    backend::{allocator::Fourcc, renderer::element::memory::MemoryRenderBuffer},
    utils::{Logical, Point, Transform},
};
use xcursor::{CursorTheme, parser::parse_xcursor};

pub struct Cursors {
    theme: CursorTheme,
    size: u32,
    cache: HashMap<String, Option<(MemoryRenderBuffer, Point<i32, Logical>)>>,
}

impl Cursors {
    pub fn new() -> Self {
        let name = std::env::var("XCURSOR_THEME").unwrap_or_else(|_| "breeze_cursors".into());
        let size = std::env::var("XCURSOR_SIZE").ok().and_then(|s| s.parse().ok()).unwrap_or(24);
        Cursors { theme: CursorTheme::load(&name), size, cache: HashMap::new() }
    }

    /// The image and its hotspot for a cursor name, trying the theme's
    /// other spellings and falling back to the arrow.
    pub fn get(&mut self, names: &[&str]) -> Option<(MemoryRenderBuffer, Point<i32, Logical>)> {
        for name in names.iter().chain(["default", "left_ptr"].iter()) {
            if let Some(found) = self.load(name) {
                return Some(found);
            }
        }
        None
    }

    fn load(&mut self, name: &str) -> Option<(MemoryRenderBuffer, Point<i32, Logical>)> {
        if let Some(cached) = self.cache.get(name) {
            return cached.clone();
        }
        let loaded = (|| {
            let path = self.theme.load_icon(name)?;
            let data = std::fs::read(path).ok()?;
            let images = parse_xcursor(&data)?;
            let image = images.iter().min_by_key(|i| (i.size as i32 - self.size as i32).abs())?;
            let buffer = MemoryRenderBuffer::from_slice(
                &image.pixels_rgba,
                Fourcc::Abgr8888,
                (image.width as i32, image.height as i32),
                1,
                Transform::Normal,
                None,
            );
            Some((buffer, Point::from((image.xhot as i32, image.yhot as i32))))
        })();
        self.cache.insert(name.to_string(), loaded.clone());
        loaded
    }
}
