#pragma once
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "model.hpp"
#include "padnav.hpp"

namespace fg {

struct PadEvent {
  enum Kind { Connected, Disconnected, Button } kind = Button;
  Pad pad;             // Connected
  int index = 0;       // Disconnected / Button
  std::string button;  // Button
  bool pressed = false, repeat = false;
};

struct PadState;

// SDL3 gamepads (evdev only: HIDAPI off, so we never grab pads from games).
class Pads {
 public:
  Pads();
  ~Pads();
  bool init(std::string& err);
  void shutdown();
  // Pumps SDL and advances repeat timers.
  void poll(int64_t nowMs, std::vector<PadEvent>& out);
  std::vector<Pad> list() const;
  bool rumble(float strength, int ms, int index /* -1 = all */);
  size_t count() const;

 private:
  bool inited_ = false;
  std::map<int, std::unique_ptr<PadState>> pads_;
  void emit(int idx, const char* button, bool pressed, bool repeat, std::vector<PadEvent>& out);
};

}  // namespace fg
