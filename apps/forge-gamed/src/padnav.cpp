#include "padnav.hpp"

#include <cmath>

namespace fg {

const char* dirName(Dir d) {
  switch (d) {
    case Dir::Up: return "up";
    case Dir::Down: return "down";
    case Dir::Left: return "left";
    case Dir::Right: return "right";
  }
  return "up";
}

int StickDirection::update(float x, float y) {
  float ax = std::fabs(x), ay = std::fabs(y);
  if (cur_ >= 0) {
    Dir d = static_cast<Dir>(cur_);
    float own = (d == Dir::Up) ? -y : (d == Dir::Down) ? y : (d == Dir::Left) ? -x : x;
    float other = (d == Dir::Up || d == Dir::Down) ? ax : ay;
    bool otherTakesOver = other >= kPress && other > own;
    if (own > kRelease && !otherTakesOver) return cur_;
  }
  if (ax >= kPress || ay >= kPress) {
    if (ax >= ay)
      cur_ = static_cast<int>(x < 0 ? Dir::Left : Dir::Right);
    else
      cur_ = static_cast<int>(y < 0 ? Dir::Up : Dir::Down);
  } else {
    cur_ = -1;
  }
  return cur_;
}

bool Trigger::update(float v) {
  if (!on_ && v >= 0.5f) on_ = true;
  else if (on_ && v < 0.3f) on_ = false;
  return on_;
}

void PadNav::recompute(int64_t now, std::vector<NavEvent>& out) {
  for (int i = 0; i < 4; ++i) {  // releases first
    bool want = dpad_[i] || stickDir_ == i;
    if (!want && held_[i]) {
      held_[i] = false;
      out.push_back({static_cast<Dir>(i), false, false});
    }
  }
  for (int i = 0; i < 4; ++i) {
    bool want = dpad_[i] || stickDir_ == i;
    if (want && !held_[i]) {
      held_[i] = true;
      next_[i] = now + kRepeatDelayMs;
      out.push_back({static_cast<Dir>(i), true, false});
    }
  }
}

void PadNav::dpad(Dir d, bool down, int64_t now, std::vector<NavEvent>& out) {
  dpad_[static_cast<int>(d)] = down;
  recompute(now, out);
}

void PadNav::stick(float x, float y, int64_t now, std::vector<NavEvent>& out) {
  stickDir_ = stick_.update(x, y);
  recompute(now, out);
}

void PadNav::tick(int64_t now, std::vector<NavEvent>& out) {
  for (int i = 0; i < 4; ++i) {
    if (held_[i] && now >= next_[i]) {
      out.push_back({static_cast<Dir>(i), true, true});
      next_[i] += kRepeatIntervalMs;
      if (next_[i] <= now) next_[i] = now + kRepeatIntervalMs;  // fell behind: don't burst
    }
  }
}

bool PadNav::anyHeld() const {
  for (bool h : held_)
    if (h) return true;
  return false;
}

}  // namespace fg
