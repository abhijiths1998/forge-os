#include "launch.hpp"

#include <algorithm>

#include "util.hpp"

namespace fg {

static void addWrappers(std::vector<std::string>& argv, const GameSettings& s) {
  if (s.gamescope.enabled) {
    argv.push_back("gamescope");
    argv.push_back("-W");
    argv.push_back(std::to_string(s.gamescope.width));
    argv.push_back("-H");
    argv.push_back(std::to_string(s.gamescope.height));
    if (s.gamescope.fps > 0) {
      argv.push_back("-r");
      argv.push_back(std::to_string(s.gamescope.fps));
    }
    if (s.gamescope.fullscreen) argv.push_back("-f");
    argv.push_back("--");
  }
  if (s.gamemode) argv.push_back("gamemoderun");
  if (s.mangohud) argv.push_back("mangohud");
}

static std::string dirName(const std::string& path) {
  auto slash = path.rfind('/');
  if (slash == std::string::npos) return "";
  if (slash == 0) return "/";
  return path.substr(0, slash);
}

bool buildLaunch(const Game& g, const LaunchContext& ctx, LaunchSpec& out, std::string& err) {
  out = LaunchSpec();
  if (g.source == "steam") {
    std::string app = g.id.substr(std::min<size_t>(6, g.id.size()));
    if (app.empty()) { err = "bad steam id"; return false; }
    out.argv = {"steam", "steam://rungameid/" + app};
    out.tracked = false;
    return true;
  }
  if (g.source == "heroic") {
    // heroic:<runner>:<appName>
    std::string rest = g.id.substr(std::min<size_t>(7, g.id.size()));
    auto colon = rest.find(':');
    if (colon == std::string::npos || colon == 0 || colon + 1 >= rest.size()) {
      err = "bad heroic id";
      return false;
    }
    out.argv = {"xdg-open", "heroic://launch?appName=" + percentEncode(rest.substr(colon + 1)) +
                                "&runner=" + percentEncode(rest.substr(0, colon))};
    out.tracked = false;
    return true;
  }
  if (g.source == "lutris") {
    std::string n = g.id.substr(std::min<size_t>(7, g.id.size()));
    if (n.empty()) { err = "bad lutris id"; return false; }
    out.argv = {"lutris", "lutris:rungameid/" + n};
    // A hand-off: with Lutris already open this process passes the game to
    // it and exits at once, so its lifetime says nothing about the game.
    // Lutris counts the play time itself (pga.db).
    out.tracked = false;
    return true;
  }
  if (g.source != "local" || !g.settings) {
    err = "unknown game source";
    return false;
  }
  const GameSettings& s = *g.settings;
  if (s.exe.empty()) { err = "no executable set"; return false; }
  out.tracked = true;
  out.workdir = s.workdir ? *s.workdir : dirName(s.exe);
  out.env = s.env;
  std::vector<std::string> args = splitArgs(s.args);

  if (s.kind == "native") {
    addWrappers(out.argv, s);
    out.argv.push_back(s.exe);
    out.argv.insert(out.argv.end(), args.begin(), args.end());
    return true;
  }

  // windows
  std::string rid = s.runner ? *s.runner : ctx.defaultRunner;
  if (rid.empty()) { err = "no runner selected and none available (install GE-Proton)"; return false; }
  auto it = std::find_if(ctx.runners.begin(), ctx.runners.end(), [&](const Runner& r) { return r.id == rid; });
  if (it == ctx.runners.end()) { err = "runner " + rid + " not found"; return false; }
  const Runner& r = *it;
  std::string prefix = s.prefix ? *s.prefix : ctx.dataDir + "/prefixes/" + sanitizeId(g.id);
  out.mkdirs.push_back(prefix);
  addWrappers(out.argv, s);
  if (r.kind == "proton") {
    if (ctx.umuRun) {
      out.env["PROTONPATH"] = r.path;
      out.env["WINEPREFIX"] = prefix;
      out.env["GAMEID"] = "umu-default";
      out.argv.push_back("umu-run");
    } else {
      out.env["STEAM_COMPAT_DATA_PATH"] = prefix;
      out.env["STEAM_COMPAT_CLIENT_INSTALL_PATH"] =
          ctx.steamRoot.empty() ? home() + "/.local/share/Steam" : ctx.steamRoot;
      out.argv.push_back(r.path + "/proton");
      out.argv.push_back("waitforexitandrun");
    }
  } else {
    out.env["WINEPREFIX"] = prefix;
    out.argv.push_back(r.id == "system:wine" ? "wine" : r.path + "/bin/wine");
  }
  // user env wins over our defaults only for keys they set explicitly
  for (auto& [k, v] : s.env) out.env[k] = v;
  out.argv.push_back(s.exe);
  out.argv.insert(out.argv.end(), args.begin(), args.end());
  return true;
}

}  // namespace fg
