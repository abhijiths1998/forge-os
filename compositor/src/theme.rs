//! The desktop's look, from the Forge theme (~/.config/forge/theme.json,
//! written by the Theming Kit): light or dark, the accent, corners and how
//! see-through the glass is. Re-read every couple of seconds, so a theme
//! change reaches the title bars without a restart.

use std::{path::PathBuf, time::SystemTime};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgba(pub f32, pub f32, pub f32, pub f32);

impl Rgba {
    fn hex(s: &str, a: f32) -> Option<Self> {
        let h = s.trim_start_matches('#');
        let n = u32::from_str_radix(h.get(0..6)?, 16).ok()?;
        Some(Rgba(
            ((n >> 16) & 0xff) as f32 / 255.0,
            ((n >> 8) & 0xff) as f32 / 255.0,
            (n & 0xff) as f32 / 255.0,
            a,
        ))
    }

    pub fn with_alpha(self, a: f32) -> Self {
        Rgba(self.0, self.1, self.2, a)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Theme {
    pub dark: bool,
    pub accent: Rgba,
    pub corner_radius: f32,
    /// The window glass's opacity, 0-1 (the Theming Kit's windowOpacity).
    pub glass: f32,
    /// How fast windows animate: 1 normal, 0 off (theme.json `animations`,
    /// a number or true/false; Forge Settings sets it).
    pub animations: f32,
}

impl Default for Theme {
    /// Forge Glass, dark.
    fn default() -> Self {
        Theme {
            dark: true,
            accent: Rgba::hex("#7F8EF5", 1.0).unwrap(),
            corner_radius: 14.0,
            glass: 0.41,
            animations: 1.0,
        }
    }
}

impl Theme {
    /// colors.py's window colour for the mode.
    pub fn window(&self) -> Rgba {
        if self.dark {
            Rgba::hex("#1A1C33", 1.0).unwrap()
        } else {
            Rgba::hex("#F3F2FA", 1.0).unwrap()
        }
    }

    pub fn text(&self) -> Rgba {
        if self.dark {
            Rgba::hex("#E4E6F4", 1.0).unwrap()
        } else {
            Rgba::hex("#1E2140", 1.0).unwrap()
        }
    }

    pub fn dim_text(&self) -> Rgba {
        if self.dark {
            Rgba::hex("#9296B5", 1.0).unwrap()
        } else {
            Rgba::hex("#6E7391", 1.0).unwrap()
        }
    }

    /// Close, maximise, minimise: forge_ui's negative, positive and neutral.
    pub fn buttons(&self) -> [Rgba; 3] {
        let c = |h| Rgba::hex(h, 1.0).unwrap();
        if self.dark {
            [c("#F28B9B"), c("#8FD3A8"), c("#F6CFA8")]
        } else {
            [c("#D9576E"), c("#3E9E6C"), c("#D98A3E")]
        }
    }
}

fn theme_file() -> PathBuf {
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"));
    config.join("forge/theme.json")
}

/// Keeps the theme in step with theme.json.
pub struct ThemeWatch {
    pub theme: Theme,
    seen: Option<SystemTime>,
}

impl ThemeWatch {
    pub fn new() -> Self {
        let mut watch = ThemeWatch { theme: Theme::default(), seen: None };
        watch.reload();
        watch
    }

    /// Re-reads theme.json if it changed; true if the theme did.
    pub fn reload(&mut self) -> bool {
        let path = theme_file();
        let modified = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
        if modified.is_some() && modified == self.seen {
            return false;
        }
        self.seen = modified;
        let Some(json) = std::fs::read_to_string(&path)
            .ok()
            .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
        else {
            return false;
        };
        let d = Theme::default();
        let theme = Theme {
            dark: json["dark"].as_bool().unwrap_or(d.dark),
            accent: json["accent"].as_str().and_then(|s| Rgba::hex(s, 1.0)).unwrap_or(d.accent),
            corner_radius: json["cornerRadius"].as_f64().map(|v| v as f32).unwrap_or(d.corner_radius),
            glass: json["windowOpacity"].as_f64().map(|v| v as f32 / 100.0).unwrap_or(d.glass),
            animations: match &json["animations"] {
                serde_json::Value::Bool(on) => if *on { 1.0 } else { 0.0 },
                v => v.as_f64().map(|v| v.clamp(0.0, 4.0) as f32).unwrap_or(d.animations),
            },
        };
        let changed = theme != self.theme;
        self.theme = theme;
        changed
    }
}
