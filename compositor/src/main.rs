//! Forge Compositor: the Forge desktop's own compositor. It draws the
//! windows and their Forge title bars, moves and resizes them, and runs the
//! Forge Shell (bar, dock, wallpaper) on top. Smithay supplies the Wayland
//! protocols, rendering and input plumbing; the desktop is ours.
//!
//!   forge-compositor [--startup "cmd" ...]
//!       the desktop, on the screens (from the login screen)
//!   forge-compositor --nested [--startup "cmd" ...]
//!       in a window on the current desktop (to try it); also chosen when
//!       started inside another Wayland or X session

mod anim;
mod capture;
mod deco;
mod glass;
mod grabs;
mod handlers;
mod input;
mod ipc;
mod render;
mod state;
mod theme;
mod udev;
mod cursor;
mod winit;
mod win;
mod wm;
mod xwayland;

use std::time::Duration;

use smithay::reexports::{
    calloop::{EventLoop, timer::{TimeoutAction, Timer}},
    wayland_server::Display,
};

use state::Forge;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    match tracing_subscriber::EnvFilter::try_from_default_env() {
        Ok(filter) => tracing_subscriber::fmt().with_env_filter(filter).init(),
        Err(_) => tracing_subscriber::fmt().with_env_filter("forge_compositor=info,warn").init(),
    }

    let mut startup = Vec::new();
    let mut nested = std::env::var_os("WAYLAND_DISPLAY").is_some() || std::env::var_os("DISPLAY").is_some();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--nested" => nested = true,
            "--startup" => startup.extend(args.next()),
            other => return Err(format!("unknown argument {other}").into()),
        }
    }

    let mut event_loop: EventLoop<'static, Forge> = EventLoop::try_new()?;
    let display: Display<Forge> = Display::new()?;
    let mut state = Forge::new(&mut event_loop, display);

    if nested {
        winit::run(&mut event_loop, &mut state)?;
    } else {
        udev::run(&mut event_loop, &mut state)?;
    }
    tracing::info!(
        "Forge on {} (IPC {})",
        state.socket_name.to_string_lossy(),
        state.ipc.path().display()
    );

    // The theme, followed while running.
    event_loop.handle().insert_source(Timer::from_duration(Duration::from_secs(2)), |_, _, state| {
        if state.theme.reload() {
            tracing::info!("theme changed");
        }
        TimeoutAction::ToDuration(Duration::from_secs(2))
    })?;

    state.start_xwayland();
    // Programs wait a moment for XWayland, so they start with DISPLAY set.
    // On a real screen the first one is the session (forge-session-start):
    // when it ends, so does Forge, as with KWin's --exit-with-session.
    let pending = std::mem::take(&mut startup);
    event_loop.handle().insert_source(Timer::from_duration(Duration::from_millis(600)), move |_, _, state| {
        for (i, cmd) in pending.iter().enumerate() {
            let child = state.spawn_child(cmd);
            if let (0, false, Some(mut child)) = (i, nested, child) {
                let _ = state.loop_handle.insert_source(Timer::from_duration(Duration::from_secs(1)), move |_, _, state| {
                    match child.try_wait() {
                        Ok(None) => TimeoutAction::ToDuration(Duration::from_secs(1)),
                        _ => {
                            tracing::info!("the session ended");
                            state.loop_signal.stop();
                            TimeoutAction::Drop
                        }
                    }
                });
            }
        }
        TimeoutAction::Drop
    })?;
    watchdog(&event_loop)?;
    event_loop.run(None, &mut state, |_| {})?;
    Ok(())
}

/// If the event loop stops turning (a GPU call that never returns, a
/// deadlock), the screen would just freeze with no way out but the power
/// button. A thread watches a heartbeat the loop beats every second; after
/// 12 s without one, the compositor aborts, so the session ends and the
/// login screen comes back (the log says why, in `journalctl -t forge`).
fn watchdog(event_loop: &EventLoop<'static, Forge>) -> Result<(), Box<dyn std::error::Error>> {
    use std::sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    };
    let start = std::time::Instant::now();
    let beat = Arc::new(AtomicU64::new(0));
    let loop_beat = beat.clone();
    event_loop.handle().insert_source(Timer::from_duration(Duration::from_secs(1)), move |_, _, _| {
        loop_beat.store(start.elapsed().as_secs(), Ordering::Relaxed);
        TimeoutAction::ToDuration(Duration::from_secs(1))
    })?;
    if std::env::var_os("FORGE_NO_WATCHDOG").is_some() {
        return Ok(());
    }
    std::thread::Builder::new().name("watchdog".into()).spawn(move || {
        loop {
            std::thread::sleep(Duration::from_secs(2));
            let now = start.elapsed().as_secs();
            let last = beat.load(Ordering::Relaxed);
            if now.saturating_sub(last) > 12 {
                eprintln!("forge-compositor: the event loop has been stuck for {}s, giving up", now - last);
                std::process::abort();
            }
        }
    })?;
    Ok(())
}
