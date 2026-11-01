//! Moving and resizing windows with the pointer: started from a title bar
//! or an edge Forge draws, or by a client that draws its own title bar
//! (xdg move/resize requests). Adapted from Smithay's smallvil example.

use std::cell::RefCell;

use smithay::{
    desktop::Window,
    input::pointer::{
        AxisFrame, ButtonEvent, Focus, GestureHoldBeginEvent, GestureHoldEndEvent, GesturePinchBeginEvent,
        GesturePinchEndEvent, GesturePinchUpdateEvent, GestureSwipeBeginEvent, GestureSwipeEndEvent,
        GestureSwipeUpdateEvent, GrabStartData, MotionEvent, PointerGrab, PointerInnerHandle, RelativeMotionEvent,
    },
    reexports::{wayland_protocols::xdg::shell::server::xdg_toplevel, wayland_server::protocol::wl_surface::WlSurface},
    utils::{Logical, Point, Rectangle, Serial, Size},
    wayland::compositor,
};

use crate::{
    state::{Forge, win_data},
    win,
};

const BTN_LEFT: u32 = 0x110;

/// The pointer-grab methods that just pass events on.
macro_rules! forward_rest {
    () => {
        fn relative_motion(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, focus: Option<(WlSurface, Point<f64, Logical>)>, event: &RelativeMotionEvent) {
            handle.relative_motion(data, focus, event);
        }
        fn axis(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, details: AxisFrame) {
            handle.axis(data, details)
        }
        fn frame(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>) {
            handle.frame(data);
        }
        fn gesture_swipe_begin(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &GestureSwipeBeginEvent) {
            handle.gesture_swipe_begin(data, event)
        }
        fn gesture_swipe_update(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &GestureSwipeUpdateEvent) {
            handle.gesture_swipe_update(data, event)
        }
        fn gesture_swipe_end(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &GestureSwipeEndEvent) {
            handle.gesture_swipe_end(data, event)
        }
        fn gesture_pinch_begin(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &GesturePinchBeginEvent) {
            handle.gesture_pinch_begin(data, event)
        }
        fn gesture_pinch_update(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &GesturePinchUpdateEvent) {
            handle.gesture_pinch_update(data, event)
        }
        fn gesture_pinch_end(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &GesturePinchEndEvent) {
            handle.gesture_pinch_end(data, event)
        }
        fn gesture_hold_begin(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &GestureHoldBeginEvent) {
            handle.gesture_hold_begin(data, event)
        }
        fn gesture_hold_end(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &GestureHoldEndEvent) {
            handle.gesture_hold_end(data, event)
        }
    };
}

bitflags::bitflags! {
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub struct ResizeEdge: u32 {
        const TOP    = 0b0001;
        const BOTTOM = 0b0010;
        const LEFT   = 0b0100;
        const RIGHT  = 0b1000;
    }
}

impl From<xdg_toplevel::ResizeEdge> for ResizeEdge {
    fn from(x: xdg_toplevel::ResizeEdge) -> Self {
        Self::from_bits_truncate(x as u32)
    }
}

fn start_data(state: &Forge) -> GrabStartData<Forge> {
    let pointer = state.seat.get_pointer().unwrap();
    GrabStartData { focus: None, button: BTN_LEFT, location: pointer.current_location() }
}

pub fn start_move(state: &mut Forge, window: &Window, serial: Serial) {
    // A maximised window dragged by its bar comes back to its own size first,
    // under the pointer.
    if win_data(window, |d| d.restore.is_some()) {
        state.toggle_maximize(window);
    }
    let Some(initial) = state.space.element_location(window) else { return };
    win_data(window, |d| d.moving = true);
    let grab = MoveGrab { start: start_data(state), window: window.clone(), initial };
    let pointer = state.seat.get_pointer().unwrap();
    pointer.set_grab(state, grab, serial, Focus::Clear);
}

pub fn start_resize(state: &mut Forge, window: &Window, edges: ResizeEdge, serial: Serial) {
    if edges.is_empty() {
        return;
    }
    let Some(loc) = state.space.element_location(window) else { return };
    let initial = Rectangle::new(loc, window.geometry().size);
    win::set_state(window, win::State::Resizing, true);
    win::send(window);
    if let Some(t) = window.toplevel() {
        ResizeState::with(t.wl_surface(), |s| *s = ResizeState::Resizing { edges, initial });
    }
    let grab = ResizeGrab { start: start_data(state), window: window.clone(), edges, initial, last_size: initial.size };
    let pointer = state.seat.get_pointer().unwrap();
    pointer.set_grab(state, grab, serial, Focus::Clear);
}

// --- Move -----------------------------------------------------------------------------

pub struct MoveGrab {
    start: GrabStartData<Forge>,
    window: Window,
    initial: Point<i32, Logical>,
}

impl PointerGrab<Forge> for MoveGrab {
    fn motion(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, _focus: Option<(WlSurface, Point<f64, Logical>)>, event: &MotionEvent) {
        handle.motion(data, None, event);
        let delta = event.location - self.start.location;
        let mut loc: Point<i32, Logical> = (self.initial.to_f64() + delta).to_i32_round();
        // Keep the title bar below the top of the free area, so it can't be
        // lost under the top bar.
        let zone = data.usable_area();
        let bar = if data.has_bar(&self.window) { crate::deco::BAR_HEIGHT } else { 0 };
        loc.y = loc.y.max(zone.loc.y + bar);
        data.move_window(&self.window, loc, true);
    }

    fn button(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &ButtonEvent) {
        handle.button(data, event);
        if !handle.current_pressed().contains(&BTN_LEFT) {
            handle.unset_grab(self, data, event.serial, event.time, true);
        }
    }

    fn start_data(&self) -> &GrabStartData<Forge> {
        &self.start
    }

    fn unset(&mut self, _data: &mut Forge) {
        win_data(&self.window, |d| d.moving = false);
    }

    forward_rest!();
}

// --- Resize -----------------------------------------------------------------------------

pub struct ResizeGrab {
    start: GrabStartData<Forge>,
    window: Window,
    edges: ResizeEdge,
    initial: Rectangle<i32, Logical>,
    last_size: Size<i32, Logical>,
}

impl PointerGrab<Forge> for ResizeGrab {
    fn motion(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, _focus: Option<(WlSurface, Point<f64, Logical>)>, event: &MotionEvent) {
        handle.motion(data, None, event);
        let mut delta = event.location - self.start.location;
        let (mut w, mut h) = (self.initial.size.w, self.initial.size.h);
        if self.edges.intersects(ResizeEdge::LEFT | ResizeEdge::RIGHT) {
            if self.edges.contains(ResizeEdge::LEFT) {
                delta.x = -delta.x;
            }
            w = (self.initial.size.w as f64 + delta.x) as i32;
        }
        if self.edges.intersects(ResizeEdge::TOP | ResizeEdge::BOTTOM) {
            if self.edges.contains(ResizeEdge::TOP) {
                delta.y = -delta.y;
            }
            h = (self.initial.size.h as f64 + delta.y) as i32;
        }
        let (min, max) = win::size_limits(&self.window);
        let max_w = if max.w == 0 { i32::MAX } else { max.w };
        let max_h = if max.h == 0 { i32::MAX } else { max.h };
        self.last_size = Size::from((w.max(min.w.max(120)).min(max_w), h.max(min.h.max(60)).min(max_h)));
        // Wayland windows move once they've taken the size (resize_commit);
        // X11 windows are told their place and size together.
        let mut loc = self.initial.loc;
        if self.window.x11_surface().is_some() {
            if self.edges.contains(ResizeEdge::LEFT) {
                loc.x += self.initial.size.w - self.last_size.w;
            }
            if self.edges.contains(ResizeEdge::TOP) {
                loc.y += self.initial.size.h - self.last_size.h;
            }
            data.space.map_element(self.window.clone(), loc, true);
        }
        win::configure(&self.window, loc, Some(self.last_size));
    }

    fn button(&mut self, data: &mut Forge, handle: &mut PointerInnerHandle<'_, Forge>, event: &ButtonEvent) {
        handle.button(data, event);
        if !handle.current_pressed().contains(&BTN_LEFT) {
            handle.unset_grab(self, data, event.serial, event.time, true);
            win::set_state(&self.window, win::State::Resizing, false);
            let loc = data.space.element_location(&self.window).unwrap_or(self.initial.loc);
            win::configure(&self.window, loc, Some(self.last_size));
            if let Some(t) = self.window.toplevel() {
                ResizeState::with(t.wl_surface(), |s| {
                    *s = ResizeState::WaitingForLastCommit { edges: self.edges, initial: self.initial }
                });
            }
        }
    }

    fn start_data(&self) -> &GrabStartData<Forge> {
        &self.start
    }

    fn unset(&mut self, _data: &mut Forge) {}

    forward_rest!();
}

/// Where a resize is, kept on the surface: resizing from the top or left
/// moves the window as the client takes on its new size.
#[derive(Debug, Clone, Copy, Default)]
enum ResizeState {
    #[default]
    Idle,
    Resizing { edges: ResizeEdge, initial: Rectangle<i32, Logical> },
    WaitingForLastCommit { edges: ResizeEdge, initial: Rectangle<i32, Logical> },
}

impl ResizeState {
    fn with<T>(surface: &WlSurface, f: impl FnOnce(&mut Self) -> T) -> T {
        compositor::with_states(surface, |states| {
            states.data_map.insert_if_missing(RefCell::<Self>::default);
            f(&mut states.data_map.get::<RefCell<Self>>().unwrap().borrow_mut())
        })
    }
}

/// On a window's commit during a resize: keep its bottom-right corner put
/// when its top or left edge is the one being dragged.
pub fn resize_commit(state: &mut Forge, surface: &WlSurface) {
    let Some(window) = state.window_for(surface) else { return };
    let Some(mut loc) = state.space.element_location(&window) else { return };
    let size = window.geometry().size;
    let moved = ResizeState::with(surface, |s| {
        let (edges, initial) = match *s {
            ResizeState::Resizing { edges, initial } => (edges, initial),
            ResizeState::WaitingForLastCommit { edges, initial } => {
                *s = ResizeState::Idle;
                (edges, initial)
            }
            ResizeState::Idle => return false,
        };
        if edges.contains(ResizeEdge::LEFT) {
            loc.x = initial.loc.x + (initial.size.w - size.w);
        }
        if edges.contains(ResizeEdge::TOP) {
            loc.y = initial.loc.y + (initial.size.h - size.h);
        }
        edges.intersects(ResizeEdge::LEFT | ResizeEdge::TOP)
    });
    if moved {
        state.space.map_element(window, loc, false);
    }
}

