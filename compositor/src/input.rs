//! Keyboard and pointer: Forge's own shortcuts, clicks on the title bars and
//! window edges it draws, and everything else passed on to the client under
//! the pointer or with the keyboard.

use std::time::{Duration, Instant};

use smithay::{
    backend::input::{
        AbsolutePositionEvent, Axis, AxisSource, ButtonState, Event, InputBackend, InputEvent, KeyState,
        KeyboardKeyEvent, PointerAxisEvent, PointerButtonEvent, PointerMotionEvent,
    },
    desktop::{WindowSurfaceType, layer_map_for_output},
    input::{
        keyboard::{FilterResult, Keysym, ModifiersState},
        pointer::{AxisFrame, ButtonEvent, MotionEvent},
    },
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::{Logical, Point, SERIAL_COUNTER},
    wayland::{compositor::get_parent, shell::wlr_layer::KeyboardInteractivity},
};

use crate::{
    deco::Button,
    grabs,
    state::Forge,
    wm::Hit,
};

const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const DOUBLE_CLICK: Duration = Duration::from_millis(400);

/// What a shortcut does.
enum Action {
    Close,
    ToggleMaximize,
    Minimize,
    Spawn(&'static str),
    Quit,
    Vt(i32),
}

fn shortcut(mods: &ModifiersState, sym: Keysym) -> Option<Action> {
    if mods.ctrl && mods.alt && sym == Keysym::BackSpace {
        return Some(Action::Quit);
    }
    let raw = sym.raw();
    if (Keysym::XF86_Switch_VT_1.raw()..=Keysym::XF86_Switch_VT_12.raw()).contains(&raw) {
        return Some(Action::Vt((raw - Keysym::XF86_Switch_VT_1.raw() + 1) as i32));
    }
    if mods.alt && sym == Keysym::F4 {
        return Some(Action::Close);
    }
    if mods.alt && sym == Keysym::space {
        return Some(Action::Spawn("forge-launcher"));
    }
    // Screenshots, sound, brightness and media, with or without modifiers.
    let spawn = |cmd| Some(Action::Spawn(cmd));
    match sym {
        Keysym::Print if mods.shift => return spawn("forge-shot region || grim -g \"$(slurp)\" - | wl-copy"),
        Keysym::Print => return spawn("forge-shot full || grim - | wl-copy"),
        Keysym::XF86_AudioRaiseVolume => return spawn("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"),
        Keysym::XF86_AudioLowerVolume => return spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
        Keysym::XF86_AudioMute => return spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
        Keysym::XF86_AudioMicMute => return spawn("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
        Keysym::XF86_MonBrightnessUp => return spawn("brightnessctl set 5%+"),
        Keysym::XF86_MonBrightnessDown => return spawn("brightnessctl set 5%-"),
        Keysym::XF86_AudioPlay | Keysym::XF86_AudioPause => return spawn("playerctl play-pause"),
        Keysym::XF86_AudioNext => return spawn("playerctl next"),
        Keysym::XF86_AudioPrev => return spawn("playerctl previous"),
        _ => {}
    }
    if !mods.logo {
        return None;
    }
    Some(match sym {
        Keysym::q | Keysym::Q => Action::Close,
        Keysym::Up => Action::ToggleMaximize,
        Keysym::Down | Keysym::m | Keysym::M => Action::Minimize,
        Keysym::space => Action::Spawn("forge-launcher"),
        Keysym::a | Keysym::A => Action::Spawn("forge-control"),
        Keysym::Return | Keysym::t | Keysym::T => Action::Spawn("forge-terminal"),
        Keysym::e | Keysym::E => Action::Spawn("forge-files"),
        Keysym::i | Keysym::I => Action::Spawn("forge-settings"),
        Keysym::s | Keysym::S if mods.shift => Action::Spawn("forge-shot region || grim -g \"$(slurp)\" - | wl-copy"),
        Keysym::l | Keysym::L => Action::Spawn("loginctl lock-session"),
        _ => return None,
    })
}

impl Forge {
    pub fn process_input_event<I: InputBackend>(&mut self, event: InputEvent<I>) {
        match event {
            InputEvent::Keyboard { event } => self.on_key(event.key_code(), event.state(), event.time_msec()),
            InputEvent::PointerMotionAbsolute { event } => {
                let Some(output) = self.output.as_ref() else { return };
                let geo = self.space.output_geometry(output).unwrap_or_default();
                let pos = event.position_transformed(geo.size) + geo.loc.to_f64();
                self.pointer_to(pos, event.time_msec());
            }
            InputEvent::PointerMotion { event } => {
                let pointer = self.seat.get_pointer().unwrap();
                let mut pos = pointer.current_location() + event.delta();
                if let Some(output) = self.output.as_ref() {
                    let geo = self.space.output_geometry(output).unwrap_or_default().to_f64();
                    pos.x = pos.x.clamp(geo.loc.x, geo.loc.x + geo.size.w - 1.0);
                    pos.y = pos.y.clamp(geo.loc.y, geo.loc.y + geo.size.h - 1.0);
                }
                self.pointer_to(pos, event.time_msec());
            }
            InputEvent::PointerButton { event } => self.on_button(event.button_code(), event.state(), event.time_msec()),
            InputEvent::PointerAxis { event } => {
                let source = event.source();
                let amount = |axis| {
                    event.amount(axis).unwrap_or_else(|| event.amount_v120(axis).unwrap_or(0.0) * 15.0 / 120.0)
                };
                let mut frame = AxisFrame::new(event.time_msec()).source(source);
                for axis in [Axis::Horizontal, Axis::Vertical] {
                    let value = amount(axis);
                    if value != 0.0 {
                        frame = frame.value(axis, value);
                        if let Some(v120) = event.amount_v120(axis) {
                            frame = frame.v120(axis, v120 as i32);
                        }
                    }
                    if source == AxisSource::Finger && event.amount(axis) == Some(0.0) {
                        frame = frame.stop(axis);
                    }
                }
                let pointer = self.seat.get_pointer().unwrap();
                pointer.axis(self, frame);
                pointer.frame(self);
            }
            _ => {}
        }
    }

    fn on_key(&mut self, code: smithay::backend::input::Keycode, state: KeyState, time: u32) {
        let serial = SERIAL_COUNTER.next_serial();
        let keyboard = self.seat.get_keyboard().unwrap();
        let mut start_menu = false;
        let action = keyboard.input(self, code, state, serial, time, |forge, mods, handle| {
            // A tap on Super alone: the start menu, once it's let go (the
            // release still goes to the app, so Super never sticks there).
            let sym = handle.modified_sym();
            let is_super = matches!(sym, Keysym::Super_L | Keysym::Super_R);
            match state {
                KeyState::Pressed => forge.super_alone = is_super,
                KeyState::Released if is_super => {
                    start_menu = std::mem::take(&mut forge.super_alone);
                }
                KeyState::Released => {}
            }
            if state == KeyState::Pressed {
                if let Some(action) = shortcut(mods, handle.modified_sym()) {
                    return FilterResult::Intercept(action);
                }
            }
            FilterResult::Forward
        });
        if start_menu {
            self.spawn("forge-dialog start-menu");
        }
        let Some(action) = action else { return };
        match action {
            Action::Close => {
                if let Some(w) = self.focused_window() {
                    self.close(&w);
                }
            }
            Action::ToggleMaximize => {
                if let Some(w) = self.focused_window() {
                    self.toggle_maximize(&w);
                }
            }
            Action::Minimize => {
                if let Some(w) = self.focused_window() {
                    self.minimize(&w);
                }
            }
            Action::Spawn(cmd) => self.spawn(cmd),
            Action::Quit => self.loop_signal.stop(),
            Action::Vt(vt) => self.change_vt(vt),
        }
    }

    /// Test input (IPC, FORGE_TEST_INPUT=1): as if the mouse did it.
    pub fn test_pointer(&mut self, pos: Point<f64, Logical>) {
        let time = self.start_time.elapsed().as_millis() as u32;
        self.pointer_to(pos, time);
    }

    pub fn test_key(&mut self, evdev: u32) {
        let time = self.start_time.elapsed().as_millis() as u32;
        // xkb keycodes are evdev's plus 8.
        let code = smithay::backend::input::Keycode::new(evdev + 8);
        self.on_key(code, KeyState::Pressed, time);
        self.on_key(code, KeyState::Released, time + 1);
    }

    pub fn test_button(&mut self, press: bool, right: bool) {
        let time = self.start_time.elapsed().as_millis() as u32;
        let state = if press { ButtonState::Pressed } else { ButtonState::Released };
        self.on_button(if right { BTN_RIGHT } else { BTN_LEFT }, state, time);
    }

    fn pointer_to(&mut self, pos: Point<f64, Logical>, time: u32) {
        let pointer = self.seat.get_pointer().unwrap();
        let hit = self.under(pos);
        let hover = match &hit {
            Hit::Bar(w, Some(b)) => Some((w.clone(), *b)),
            _ => None,
        };
        self.hover = hover;
        let focus = match hit {
            Hit::Surface(surface, origin) => Some((surface, origin)),
            _ => None,
        };
        pointer.motion(self, focus, &MotionEvent { location: pos, serial: SERIAL_COUNTER.next_serial(), time });
        pointer.frame(self);
    }

    fn on_button(&mut self, button: u32, state: ButtonState, time: u32) {
        let pointer = self.seat.get_pointer().unwrap();
        let serial = SERIAL_COUNTER.next_serial();
        let pressed = state == ButtonState::Pressed;
        // Super+drag moves a window; it's not a tap on Super.
        self.super_alone = false;
        let mut start: Option<Box<dyn FnOnce(&mut Forge)>> = None;

        if pressed && !pointer.is_grabbed() {
            match self.under(pointer.current_location()) {
                Hit::Surface(surface, _) => self.focus_surface(&surface),
                Hit::Bar(window, Some(b)) => {
                    match b {
                        Button::Close => self.close(&window),
                        Button::Maximize => self.toggle_maximize(&window),
                        Button::Minimize => self.minimize(&window),
                    }
                    self.hover = None;
                }
                Hit::Bar(window, None) if button == BTN_LEFT => {
                    self.click_focus(&window);
                    let now = Instant::now();
                    let double = self
                        .last_bar_click
                        .take()
                        .is_some_and(|(t, w)| w == window && now - t < DOUBLE_CLICK);
                    if double {
                        self.toggle_maximize(&window);
                    } else {
                        self.last_bar_click = Some((now, window.clone()));
                        start = Some(Box::new(move |s| grabs::start_move(s, &window, serial)));
                    }
                }
                Hit::Bar(window, None) => self.click_focus(&window),
                Hit::Edge(window, edges) if button == BTN_LEFT => {
                    self.focus_window(&window);
                    start = Some(Box::new(move |s| grabs::start_resize(s, &window, edges, serial)));
                }
                Hit::Edge(window, _) => self.focus_window(&window),
                Hit::Nothing => self.unfocus(),
            }
        }

        pointer.button(self, &ButtonEvent { button, state, serial, time });
        pointer.frame(self);
        if let Some(start) = start {
            start(self);
        }
    }

    /// A click on a client surface: raise and focus its window, or give a
    /// shell surface (the Control Center) the keyboard if it takes it.
    fn focus_surface(&mut self, surface: &WlSurface) {
        let mut root = surface.clone();
        while let Some(parent) = get_parent(&root) {
            root = parent;
        }
        if let Some(window) = self.window_for(&root) {
            self.click_focus(&window);
            return;
        }
        let Some(output) = self.output.clone() else { return };
        let takes_keyboard = {
            let map = layer_map_for_output(&output);
            map.layer_for_surface(&root, WindowSurfaceType::ALL)
                .is_some_and(|l| l.cached_state().keyboard_interactivity != KeyboardInteractivity::None)
        };
        if takes_keyboard {
            let keyboard = self.seat.get_keyboard().unwrap();
            keyboard.set_focus(self, Some(root), SERIAL_COUNTER.next_serial());
        }
    }
}
