//! Forge's IPC: how Forge Shell (the dock, the bar) sees the windows and
//! acts on them. A Unix socket ($FORGE_COMPOSITOR_SOCKET); one JSON request
//! per line, one JSON reply per line:
//!
//!   {"get":"windows"}        → {"windows":[{"id":1,"app_id":"…","title":"…",
//!                               "focused":true,"minimized":false,
//!                               "maximized":false,"fullscreen":false}]}
//!   {"activate":1}           bring back if minimised, raise and focus
//!   {"minimize":1} {"maximize":1} {"close":1}
//!   {"spawn":"konsole"}
//!   {"screenshot":"/path.png"}  the next frame, saved as a PNG
//!   {"glass_dump":"/dir"}    the glass's wallpaper texture and blur steps,
//!                            saved as PNGs (background.png, chain0.png…)
//!   {"subscribe":true}       then a {"event":"windows","windows":[…]} line
//!                            whenever the windows change
//!
//! With FORGE_TEST_INPUT=1 in the compositor's environment, for testing
//! without a hand on the mouse:
//!   {"pointer":[x,y]}        move the pointer there
//!   {"button":"press"}       left button down (or "release")
//!   {"button":"press","right":true}  the right button
//!   {"key":30}               a key pressed and released (evdev code: 30 is A)
//!
//! Anything else gets {"error":"…"}.

use std::{
    io::{ErrorKind, Read, Write},
    os::unix::net::{UnixListener, UnixStream},
    path::{Path, PathBuf},
};

use serde_json::{Value, json};
use smithay::{
    desktop::Window,
    reexports::calloop::{Interest, LoopHandle, Mode, PostAction, generic::Generic},
};

use crate::state::{Forge, win_data};

pub struct Ipc {
    path: PathBuf,
    subscribers: Vec<UnixStream>,
    dirty: bool,
}

impl Ipc {
    pub fn new(handle: &LoopHandle<'static, Forge>, wayland_socket: &std::ffi::OsStr) -> Self {
        let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
        let path = runtime.join(format!("forge-{}.sock", wayland_socket.to_string_lossy()));
        let _ = std::fs::remove_file(&path);
        match UnixListener::bind(&path) {
            Ok(listener) => {
                listener.set_nonblocking(true).ok();
                let source = Generic::new(listener, Interest::READ, Mode::Level);
                let inserted = handle.insert_source(source, |_, listener, state| {
                    while let Ok((stream, _)) = listener.accept() {
                        state.ipc_client(stream);
                    }
                    Ok(PostAction::Continue)
                });
                if let Err(e) = inserted {
                    tracing::warn!("IPC socket not watched: {e}");
                }
            }
            Err(e) => tracing::warn!("no IPC socket at {}: {e}", path.display()),
        }
        Ipc { path, subscribers: Vec::new(), dirty: false }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for Ipc {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

impl Forge {
    fn ipc_client(&mut self, stream: UnixStream) {
        stream.set_nonblocking(true).ok();
        let Ok(mut writer) = stream.try_clone() else { return };
        let mut pending = Vec::new();
        let source = Generic::new(stream, Interest::READ, Mode::Level);
        let inserted = self.loop_handle.insert_source(source, move |_, stream, state| {
            let mut reader: &UnixStream = stream;
            let mut chunk = [0u8; 4096];
            loop {
                match reader.read(&mut chunk) {
                    Ok(0) => return Ok(PostAction::Remove),
                    Ok(n) => pending.extend_from_slice(&chunk[..n]),
                    Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                    Err(_) => return Ok(PostAction::Remove),
                }
            }
            while let Some(end) = pending.iter().position(|&b| b == b'\n') {
                let line: Vec<u8> = pending.drain(..=end).collect();
                let line = String::from_utf8_lossy(&line);
                if line.trim().is_empty() {
                    continue;
                }
                let (reply, subscribe) = state.ipc_request(line.trim());
                if writer.write_all((reply.to_string() + "\n").as_bytes()).is_err() {
                    return Ok(PostAction::Remove);
                }
                if subscribe {
                    if let Ok(w) = writer.try_clone() {
                        state.ipc.subscribers.push(w);
                    }
                }
            }
            Ok(PostAction::Continue)
        });
        if let Err(e) = inserted {
            tracing::warn!("IPC client not watched: {e}");
        }
    }

    /// Something about the windows changed; subscribers hear after this frame.
    pub fn ipc_changed(&mut self) {
        self.ipc.dirty = true;
    }

    pub fn ipc_flush(&mut self) {
        if !self.ipc.dirty || self.ipc.subscribers.is_empty() {
            self.ipc.dirty = false;
            return;
        }
        self.ipc.dirty = false;
        let line = json!({"event": "windows", "windows": self.window_list()}).to_string() + "\n";
        self.ipc.subscribers.retain_mut(|s| match s.write_all(line.as_bytes()) {
            Ok(()) => true,
            Err(e) => e.kind() == ErrorKind::WouldBlock,
        });
    }

    fn window_list(&self) -> Value {
        let focused = self.focused_window();
        let info = |w: &Window, minimized: bool| {
            let (title, app_id) = (crate::win::title(w), crate::win::app_id(w));
            let (id, maximized, fullscreen) = win_data(w, |d| (d.id, d.restore.is_some(), d.fullscreen));
            json!({
                "id": id, "app_id": app_id, "title": title,
                "focused": !minimized && focused.as_ref() == Some(w),
                "minimized": minimized, "maximized": maximized, "fullscreen": fullscreen,
            })
        };
        Value::Array(
            self.space
                .elements()
                .rev()
                .filter(|w| !crate::win::is_override_redirect(w))
                .map(|w| info(w, false))
                .chain(self.minimized.iter().map(|w| info(w, true)))
                .collect(),
        )
    }

    fn window_by_id(&self, id: u64) -> Option<Window> {
        self.space.elements().chain(self.minimized.iter()).find(|w| win_data(w, |d| d.id) == id).cloned()
    }

    /// One request; the reply, and whether the client now subscribes.
    fn ipc_request(&mut self, line: &str) -> (Value, bool) {
        let Ok(req) = serde_json::from_str::<Value>(line) else {
            return (json!({"error": "not JSON"}), false);
        };
        let id = |key: &str| req[key].as_u64();
        if req["get"] == "windows" {
            return (json!({"windows": self.window_list()}), false);
        }
        if req["subscribe"] == true {
            return (json!({"windows": self.window_list()}), true);
        }
        if std::env::var_os("FORGE_TEST_INPUT").is_some() {
            if let Some([x, y]) = req["pointer"].as_array().map(|a| [a[0].as_f64(), a[1].as_f64()]) {
                self.test_pointer((x.unwrap_or(0.0), y.unwrap_or(0.0)).into());
                return (json!({"ok": true}), false);
            }
            if let Some(code) = req["key"].as_u64() {
                self.test_key(code as u32);
                return (json!({"ok": true}), false);
            }
            if let Some(b) = req["button"].as_str() {
                self.test_button(b == "press", req["right"].as_bool() == Some(true));
                return (json!({"ok": true}), false);
            }
        }
        if let Some(path) = req["screenshot"].as_str() {
            self.screenshot = Some(path.into());
            return (json!({"ok": true}), false);
        }
        if let Some(dir) = req["glass_dump"].as_str() {
            self.glass_dump = Some(dir.into());
            return (json!({"ok": true}), false);
        }
        if let Some(cmd) = req["spawn"].as_str() {
            self.spawn(cmd);
            return (json!({"ok": true}), false);
        }
        for (key, act) in [
            ("activate", Forge::activate as fn(&mut Forge, &Window)),
            ("minimize", Forge::minimize),
            ("maximize", Forge::toggle_maximize),
            ("close", Forge::close),
        ] {
            if let Some(id) = id(key) {
                return match self.window_by_id(id) {
                    Some(w) => {
                        act(self, &w);
                        (json!({"ok": true}), false)
                    }
                    None => (json!({"error": "no such window"}), false),
                };
            }
        }
        (json!({"error": "unknown request"}), false)
    }
}
