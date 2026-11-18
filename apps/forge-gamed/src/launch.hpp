#pragma once
#include <map>
#include <string>
#include <vector>

#include "model.hpp"

namespace fg {

// Everything needed to start a process, as plain data.
struct LaunchSpec {
  std::vector<std::string> argv;
  std::map<std::string, std::string> env;  // additions/overrides to the environment
  std::string workdir;                     // "" = inherit
  std::vector<std::string> mkdirs;         // directories to create first (prefixes)
  bool tracked = false;
};

struct LaunchContext {
  std::string dataDir;           // ~/.local/share/forge-gaming
  std::string steamRoot;         // "" if none
  bool umuRun = false;           // umu-run is on PATH
  std::vector<Runner> runners;
  std::string defaultRunner;     // effective default runner id (may be empty)
};

// Builds the command for any source. Returns false and sets err when it
// cannot (missing runner, malformed id, ...).
bool buildLaunch(const Game& game, const LaunchContext& ctx, LaunchSpec& out, std::string& err);

}  // namespace fg
