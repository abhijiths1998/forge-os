#pragma once
#include <map>
#include <optional>
#include <string>
#include <vector>
#include <json/json.h>

#include "model.hpp"

namespace fg {

// What `forged state` says about the two things profiles touch.
struct ForgedState {
  bool thermalAvailable = false;
  std::vector<std::string> profiles;
  std::optional<std::string> thermalCurrent;
  bool dndAvailable = false;
  bool dndEnabled = false;
};

// Parses `forged state` output; false when it is not a JSON object. Missing
// fields mean "not available".
bool parseForgedState(const std::string& text, ForgedState& out);
// The system.info result.
Json::Value systemInfoJson(const ForgedState& s);

// One `forged <args...>` call.
using ForgedCmd = std::vector<std::string>;

struct HoldPlan {
  std::vector<ForgedCmd> cmds;          // run in order
  std::optional<std::string> writeMarker;  // game id to write to thermal-held-by-game, before cmds
  bool removeMarker = false;            // after cmds
  bool removeFullscreenSaved = false;   // we restore it now, not forge-game
  bool empty() const { return cmds.empty() && !writeMarker && !removeMarker && !removeFullscreenSaved; }
};

// Decides what to set and restore as games start and stop. Only the first
// game to start holds each setting. Pure: no I/O.
class ProfileHolds {
 public:
  // fullscreenSaved: what `forge-game fullscreen-on` saved before it switched
  // to "gaming" (a game that went full screen before we saw it start). It is
  // the profile to restore, as the current one is forge-game's.
  HoldPlan start(const std::string& gameId, const Profile& profile, const ForgedState& state,
                 const std::optional<std::string>& fullscreenSaved = std::nullopt);
  HoldPlan stop(const std::string& gameId);
  HoldPlan stopAll();
  const std::string& thermalHolder() const { return thermalBy_; }
  const std::string& dndHolder() const { return dndBy_; }
  // What is held and what to restore, to survive a crash (holdRecordPath).
  Json::Value toJson() const;

 private:
  std::string thermalBy_, dndBy_;
  std::optional<std::string> thermalRestore_;  // set when the profile differs
  bool dndRestoreOff_ = false;                 // dnd was off before: turn it off again
};

// ---- the parts that touch the system ----
std::string forgedBin();   // $FORGED_BIN or "forged"
// Runs `forged args...` with a timeout (ms); false if it could not run, timed
// out or exited non-zero. Output goes to `out` (stdout only).
bool runForged(const std::vector<std::string>& args, int timeoutMs, std::string& out);
// `forged state`, parsed; unavailable (both false) on any failure.
ForgedState readForgedState(int timeoutMs = 5000);
std::string thermalMarkerPath();   // $XDG_RUNTIME_DIR/forge/thermal-held-by-game
std::string fullscreenSavedPath();  // $XDG_RUNTIME_DIR/forge/thermal-before-game (forge-game's)
std::string holdRecordPath();      // $XDG_RUNTIME_DIR/forge/gamed-holds.json
void execPlan(const HoldPlan& plan);
// Writes the record while anything is held, removes it when nothing is.
void saveHoldRecord(const ProfileHolds& holds);
// What to undo for a record a crashed daemon left behind. Pure.
HoldPlan recoveryPlan(const std::string& recordText);

}  // namespace fg
