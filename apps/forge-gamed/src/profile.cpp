#include "profile.hpp"

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <vector>

#include "util.hpp"

extern char** environ;

namespace fg {

bool parseForgedState(const std::string& text, ForgedState& out) {
  out = ForgedState();
  Json::Value v;
  if (!parseJson(text, v) || !v.isObject()) return false;
  const Json::Value& t = v["thermal"];
  if (t.isObject()) {
    out.thermalAvailable = jbool(t, "available");
    if (t["profiles"].isArray())
      for (auto& p : t["profiles"])
        if (p.isString() && !p.asString().empty()) out.profiles.push_back(p.asString());
    if (t["profile"].isString() && !t["profile"].asString().empty()) out.thermalCurrent = t["profile"].asString();
  }
  const Json::Value& d = v["dnd"];
  if (d.isObject()) {
    out.dndAvailable = jbool(d, "available");
    out.dndEnabled = jbool(d, "enabled");
  }
  return true;
}

Json::Value systemInfoJson(const ForgedState& s) {
  Json::Value r(Json::objectValue);
  Json::Value t(Json::objectValue);
  t["available"] = s.thermalAvailable;
  Json::Value arr(Json::arrayValue);
  for (auto& p : s.profiles) arr.append(p);
  t["profiles"] = arr;
  t["current"] = s.thermalCurrent ? Json::Value(*s.thermalCurrent) : Json::Value(Json::nullValue);
  r["thermal"] = t;
  Json::Value q(Json::objectValue);
  q["available"] = s.dndAvailable;
  r["quiet"] = q;
  return r;
}

HoldPlan ProfileHolds::start(const std::string& id, const Profile& profile, const ForgedState& st,
                             const std::optional<std::string>& fullscreenSaved) {
  HoldPlan plan;
  if (profile.thermal && st.thermalAvailable && thermalBy_.empty()) {
    thermalBy_ = id;
    thermalRestore_.reset();
    std::optional<std::string> before = st.thermalCurrent;
    if (fullscreenSaved && !fullscreenSaved->empty()) {
      before = fullscreenSaved;
      plan.removeFullscreenSaved = true;
    }
    if (before && *before != *profile.thermal) thermalRestore_ = *before;
    plan.writeMarker = id;
    plan.cmds.push_back({"set", "thermal", *profile.thermal});
  }
  if (profile.quiet && st.dndAvailable && dndBy_.empty()) {
    dndBy_ = id;
    dndRestoreOff_ = !st.dndEnabled;
    if (!st.dndEnabled) plan.cmds.push_back({"set", "dnd", "on"});
  }
  return plan;
}

HoldPlan ProfileHolds::stop(const std::string& id) {
  HoldPlan plan;
  if (!thermalBy_.empty() && thermalBy_ == id) {
    if (thermalRestore_) plan.cmds.push_back({"set", "thermal", *thermalRestore_});
    plan.removeMarker = true;
    thermalBy_.clear();
    thermalRestore_.reset();
  }
  if (!dndBy_.empty() && dndBy_ == id) {
    if (dndRestoreOff_) plan.cmds.push_back({"set", "dnd", "off"});
    dndBy_.clear();
    dndRestoreOff_ = false;
  }
  return plan;
}

Json::Value ProfileHolds::toJson() const {
  Json::Value v(Json::objectValue);
  if (!thermalBy_.empty()) {
    v["thermalBy"] = thermalBy_;
    if (thermalRestore_) v["thermalRestore"] = *thermalRestore_;
  }
  if (!dndBy_.empty()) {
    v["dndBy"] = dndBy_;
    v["dndRestoreOff"] = dndRestoreOff_;
  }
  return v;
}

HoldPlan recoveryPlan(const std::string& text) {
  HoldPlan plan;
  plan.removeMarker = true;  // whoever wrote it is gone
  Json::Value v;
  if (!parseJson(text, v) || !v.isObject()) return plan;
  if (v["thermalBy"].isString() && v["thermalRestore"].isString() && !v["thermalRestore"].asString().empty())
    plan.cmds.push_back({"set", "thermal", v["thermalRestore"].asString()});
  if (v["dndBy"].isString() && jbool(v, "dndRestoreOff")) plan.cmds.push_back({"set", "dnd", "off"});
  return plan;
}

HoldPlan ProfileHolds::stopAll() {
  HoldPlan plan;
  std::string a = thermalBy_, b = dndBy_;
  if (!a.empty()) plan = stop(a);
  if (!b.empty()) {
    HoldPlan p2 = stop(b);
    plan.cmds.insert(plan.cmds.end(), p2.cmds.begin(), p2.cmds.end());
  }
  return plan;
}

// ---------------------------------------------------------------- system ----

std::string forgedBin() {
  const char* e = std::getenv("FORGED_BIN");
  return e && *e ? e : "forged";
}

bool runForged(const std::vector<std::string>& args, int timeoutMs, std::string& out) {
  out.clear();
  int pfd[2];
  if (::pipe2(pfd, O_CLOEXEC) != 0) return false;
  posix_spawn_file_actions_t fa;
  posix_spawnattr_t at;
  posix_spawn_file_actions_init(&fa);
  posix_spawnattr_init(&at);
  posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
  posix_spawn_file_actions_adddup2(&fa, pfd[1], 1);
  posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
  sigset_t none;
  sigemptyset(&none);  // the daemon blocks SIGCHLD/SIGTERM/SIGINT
  posix_spawnattr_setsigmask(&at, &none);
  posix_spawnattr_setflags(&at, POSIX_SPAWN_SETSIGMASK);
  std::string bin = forgedBin();
  std::vector<char*> argv;
  argv.push_back(const_cast<char*>(bin.c_str()));
  for (auto& a : args) argv.push_back(const_cast<char*>(a.c_str()));
  argv.push_back(nullptr);
  pid_t pid = 0;
  int rc = ::posix_spawnp(&pid, bin.c_str(), &fa, &at, argv.data(), environ);
  posix_spawn_file_actions_destroy(&fa);
  posix_spawnattr_destroy(&at);
  ::close(pfd[1]);
  if (rc != 0) {
    ::close(pfd[0]);
    return false;
  }
  int64_t deadline = monoMs() + timeoutMs;
  bool timedOut = false;
  for (;;) {
    int64_t left = deadline - monoMs();
    if (left <= 0) { timedOut = true; break; }
    pollfd p{pfd[0], POLLIN, 0};
    int n = ::poll(&p, 1, static_cast<int>(left));
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) { timedOut = n == 0; break; }
    char buf[4096];
    ssize_t r = ::read(pfd[0], buf, sizeof buf);
    if (r > 0) {
      if (out.size() < (1u << 20)) out.append(buf, static_cast<size_t>(r));
      continue;
    }
    if (r < 0 && errno == EINTR) continue;
    break;  // EOF
  }
  ::close(pfd[0]);
  if (timedOut) ::kill(pid, SIGKILL);
  int status = 0;
  while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
  return !timedOut && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

ForgedState readForgedState(int timeoutMs) {
  ForgedState st;
  std::string out;
  if (!runForged({"state"}, timeoutMs, out) || !parseForgedState(out, st)) return ForgedState();
  return st;
}

std::string thermalMarkerPath() {
  const char* r = std::getenv("XDG_RUNTIME_DIR");
  std::string base = r && *r ? r : "/tmp";
  return base + "/forge/thermal-held-by-game";
}

static std::string forgeRunDir() {
  const char* r = std::getenv("XDG_RUNTIME_DIR");
  std::string base = r && *r ? r : "/tmp";
  return base + "/forge";
}

std::string fullscreenSavedPath() { return forgeRunDir() + "/thermal-before-game"; }
std::string holdRecordPath() { return forgeRunDir() + "/gamed-holds.json"; }

void saveHoldRecord(const ProfileHolds& holds) {
  Json::Value v = holds.toJson();
  if (v.empty()) {
    ::unlink(holdRecordPath().c_str());
    return;
  }
  writeFileAtomic(holdRecordPath(), toLine(v) + "\n");
}

void execPlan(const HoldPlan& plan) {
  if (plan.writeMarker) writeFileAtomic(thermalMarkerPath(), *plan.writeMarker);
  // Before the marker exists forge-game may still save this; after, it won't.
  if (plan.removeFullscreenSaved) ::unlink(fullscreenSavedPath().c_str());
  for (auto& c : plan.cmds) {
    std::string out;
    runForged(c, 5000, out);
  }
  if (plan.removeMarker) ::unlink(thermalMarkerPath().c_str());
}

}  // namespace fg
