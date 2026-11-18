#pragma once
#include <cstdint>
#include <vector>

namespace fg {

// Pure controller navigation logic (no SDL), driven by timestamps in ms.

enum class Dir { Up = 0, Down = 1, Left = 2, Right = 3 };
const char* dirName(Dir d);

// Stick -> direction with hysteresis. x right-positive, y DOWN-positive,
// both in -1..1. A direction engages at |v| >= kPress on the dominant axis and
// holds until it falls below kRelease (or the other axis clearly takes over).
class StickDirection {
 public:
  static constexpr float kPress = 0.5f;
  static constexpr float kRelease = 0.3f;
  // Returns -1 for none, else static_cast<int>(Dir).
  int update(float x, float y);
  int current() const { return cur_; }

 private:
  int cur_ = -1;
};

// Schmitt trigger for analog triggers.
class Trigger {
 public:
  bool update(float v);  // returns the new pressed state
  bool pressed() const { return on_; }

 private:
  bool on_ = false;
};

struct NavEvent {
  Dir dir;
  bool pressed;
  bool repeat;
  bool operator==(const NavEvent& o) const { return dir == o.dir && pressed == o.pressed && repeat == o.repeat; }
};

// Merges d-pad and left stick into up/down/left/right with key repeat: the
// first repeat comes kRepeatDelayMs after the press, then every
// kRepeatIntervalMs.
class PadNav {
 public:
  static constexpr int64_t kRepeatDelayMs = 400;
  static constexpr int64_t kRepeatIntervalMs = 90;

  void dpad(Dir d, bool down, int64_t nowMs, std::vector<NavEvent>& out);
  void stick(float x, float y, int64_t nowMs, std::vector<NavEvent>& out);
  void tick(int64_t nowMs, std::vector<NavEvent>& out);
  bool anyHeld() const;

 private:
  void recompute(int64_t nowMs, std::vector<NavEvent>& out);
  bool dpad_[4] = {false, false, false, false};
  int stickDir_ = -1;
  StickDirection stick_;
  bool held_[4] = {false, false, false, false};
  int64_t next_[4] = {0, 0, 0, 0};
};

}  // namespace fg
