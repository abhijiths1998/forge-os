#include "pads.hpp"

#include <SDL3/SDL.h>

#include <algorithm>

namespace fg {

struct PadState {
  SDL_Gamepad* pad = nullptr;
  Pad info;
  PadNav nav;
  Trigger lt, rt;
  float lx = 0, ly = 0;
};

static std::string typeName(SDL_GamepadType t) {
  switch (t) {
    case SDL_GAMEPAD_TYPE_XBOX360:
    case SDL_GAMEPAD_TYPE_XBOXONE:
      return "xbox";
    case SDL_GAMEPAD_TYPE_PS3:
    case SDL_GAMEPAD_TYPE_PS4:
    case SDL_GAMEPAD_TYPE_PS5:
      return "playstation";
    case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO:
    case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT:
    case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT:
    case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR:
      return "switch";
    default:
      return "generic";
  }
}

Pads::Pads() = default;
Pads::~Pads() { shutdown(); }

bool Pads::init(std::string& err) {
  SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
  SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI, "0");
  if (!SDL_Init(SDL_INIT_GAMEPAD)) {
    err = SDL_GetError();
    return false;
  }
  inited_ = true;
  return true;
}

void Pads::shutdown() {
  for (auto& [id, p] : pads_)
    if (p->pad) SDL_CloseGamepad(p->pad);
  pads_.clear();
  if (inited_) {
    SDL_Quit();
    inited_ = false;
  }
}

size_t Pads::count() const { return pads_.size(); }

std::vector<Pad> Pads::list() const {
  std::vector<Pad> out;
  for (auto& [id, p] : pads_) out.push_back(p->info);
  return out;
}

void Pads::emit(int idx, const char* button, bool pressed, bool repeat, std::vector<PadEvent>& out) {
  PadEvent e;
  e.kind = PadEvent::Button;
  e.index = idx;
  e.button = button;
  e.pressed = pressed;
  e.repeat = repeat;
  out.push_back(std::move(e));
}

static const char* buttonName(Uint8 b) {
  switch (b) {
    case SDL_GAMEPAD_BUTTON_SOUTH: return "a";
    case SDL_GAMEPAD_BUTTON_EAST: return "b";
    case SDL_GAMEPAD_BUTTON_WEST: return "x";
    case SDL_GAMEPAD_BUTTON_NORTH: return "y";
    case SDL_GAMEPAD_BUTTON_BACK: return "back";
    case SDL_GAMEPAD_BUTTON_GUIDE: return "guide";
    case SDL_GAMEPAD_BUTTON_START: return "start";
    case SDL_GAMEPAD_BUTTON_LEFT_STICK: return "ls";
    case SDL_GAMEPAD_BUTTON_RIGHT_STICK: return "rs";
    case SDL_GAMEPAD_BUTTON_LEFT_SHOULDER: return "lb";
    case SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER: return "rb";
    default: return nullptr;
  }
}

void Pads::poll(int64_t now, std::vector<PadEvent>& out) {
  if (!inited_) return;
  SDL_PumpEvents();
  auto flush = [&](int idx, std::vector<NavEvent>& nav) {
    for (auto& n : nav) emit(idx, dirName(n.dir), n.pressed, n.repeat, out);
    nav.clear();
  };
  std::vector<NavEvent> nav;
  SDL_Event ev;
  while (SDL_PollEvent(&ev)) {
    switch (ev.type) {
      case SDL_EVENT_GAMEPAD_ADDED: {
        int id = static_cast<int>(ev.gdevice.which);
        if (pads_.count(id)) break;
        SDL_Gamepad* g = SDL_OpenGamepad(ev.gdevice.which);
        if (!g) break;
        auto st = std::make_unique<PadState>();
        st->pad = g;
        st->info.index = id;
        const char* nm = SDL_GetGamepadName(g);
        st->info.name = nm ? nm : "Gamepad";
        st->info.type = typeName(SDL_GetGamepadType(g));
        PadEvent e;
        e.kind = PadEvent::Connected;
        e.pad = st->info;
        e.index = id;
        out.push_back(std::move(e));
        pads_[id] = std::move(st);
        break;
      }
      case SDL_EVENT_GAMEPAD_REMOVED: {
        int id = static_cast<int>(ev.gdevice.which);
        auto it = pads_.find(id);
        if (it == pads_.end()) break;
        if (it->second->pad) SDL_CloseGamepad(it->second->pad);
        pads_.erase(it);
        PadEvent e;
        e.kind = PadEvent::Disconnected;
        e.index = id;
        out.push_back(std::move(e));
        break;
      }
      case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
      case SDL_EVENT_GAMEPAD_BUTTON_UP: {
        int id = static_cast<int>(ev.gbutton.which);
        auto it = pads_.find(id);
        if (it == pads_.end()) break;
        bool down = ev.gbutton.down;
        Uint8 b = ev.gbutton.button;
        Dir d;
        bool isDir = true;
        switch (b) {
          case SDL_GAMEPAD_BUTTON_DPAD_UP: d = Dir::Up; break;
          case SDL_GAMEPAD_BUTTON_DPAD_DOWN: d = Dir::Down; break;
          case SDL_GAMEPAD_BUTTON_DPAD_LEFT: d = Dir::Left; break;
          case SDL_GAMEPAD_BUTTON_DPAD_RIGHT: d = Dir::Right; break;
          default: d = Dir::Up; isDir = false; break;
        }
        if (isDir) {
          it->second->nav.dpad(d, down, now, nav);
          flush(id, nav);
        } else if (const char* name = buttonName(b)) {
          emit(id, name, down, false, out);
        }
        break;
      }
      case SDL_EVENT_GAMEPAD_AXIS_MOTION: {
        int id = static_cast<int>(ev.gaxis.which);
        auto it = pads_.find(id);
        if (it == pads_.end()) break;
        PadState& s = *it->second;
        float v = static_cast<float>(ev.gaxis.value) / 32767.0f;
        switch (ev.gaxis.axis) {
          case SDL_GAMEPAD_AXIS_LEFTX: s.lx = v; s.nav.stick(s.lx, s.ly, now, nav); flush(id, nav); break;
          case SDL_GAMEPAD_AXIS_LEFTY: s.ly = v; s.nav.stick(s.lx, s.ly, now, nav); flush(id, nav); break;
          case SDL_GAMEPAD_AXIS_LEFT_TRIGGER: {
            bool before = s.lt.pressed();
            if (s.lt.update(v) != before) emit(id, "lt", !before, false, out);
            break;
          }
          case SDL_GAMEPAD_AXIS_RIGHT_TRIGGER: {
            bool before = s.rt.pressed();
            if (s.rt.update(v) != before) emit(id, "rt", !before, false, out);
            break;
          }
          default: break;
        }
        break;
      }
      default: break;
    }
  }
  for (auto& [id, s] : pads_) {
    s->nav.tick(now, nav);
    flush(id, nav);
  }
}

bool Pads::rumble(float strength, int ms, int index) {
  strength = std::clamp(strength, 0.0f, 1.0f);
  Uint16 amp = static_cast<Uint16>(strength * 65535.0f);
  bool any = false;
  for (auto& [id, p] : pads_) {
    if (index >= 0 && id != index) continue;
    if (SDL_RumbleGamepad(p->pad, amp, amp, static_cast<Uint32>(ms))) any = true;
  }
  return any;
}

}  // namespace fg
