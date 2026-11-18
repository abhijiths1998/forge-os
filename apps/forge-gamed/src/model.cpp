#include "model.hpp"

#include "util.hpp"

#include <algorithm>

namespace fg {

static Json::Value optStr(const std::optional<std::string>& s) {
  return s ? Json::Value(*s) : Json::Value(Json::nullValue);
}

Json::Value toJson(const GameSettings& s) {
  Json::Value v(Json::objectValue);
  v["kind"] = s.kind;
  v["exe"] = s.exe;
  v["args"] = s.args;
  v["workdir"] = optStr(s.workdir);
  v["runner"] = optStr(s.runner);
  v["prefix"] = optStr(s.prefix);
  Json::Value env(Json::objectValue);
  for (auto& [k, val] : s.env) env[k] = val;
  v["env"] = env;
  v["gamemode"] = s.gamemode;
  v["mangohud"] = s.mangohud;
  Json::Value gs(Json::objectValue);
  gs["enabled"] = s.gamescope.enabled;
  gs["width"] = s.gamescope.width;
  gs["height"] = s.gamescope.height;
  gs["fps"] = s.gamescope.fps;
  gs["fullscreen"] = s.gamescope.fullscreen;
  v["gamescope"] = gs;
  return v;
}

Json::Value toJson(const Profile& p) {
  Json::Value v(Json::objectValue);
  v["thermal"] = optStr(p.thermal);
  v["quiet"] = p.quiet;
  return v;
}

Profile profileFromStored(const Json::Value& v) {
  Profile p;
  if (v.isObject()) {
    if (v["thermal"].isString() && !v["thermal"].asString().empty()) p.thermal = v["thermal"].asString();
    p.quiet = jbool(v, "quiet");
  }
  return p;
}

Json::Value toJson(const Game& g) {
  Json::Value v(Json::objectValue);
  v["id"] = g.id;
  v["source"] = g.source;
  v["title"] = g.title;
  v["cover"] = optStr(g.cover);
  v["hero"] = optStr(g.hero);
  v["installed"] = g.installed;
  v["running"] = g.running;
  v["playtimeMinutes"] = Json::Int64(g.playtimeMinutes);
  v["lastPlayed"] = g.lastPlayed ? Json::Value(Json::Int64(*g.lastPlayed)) : Json::Value(Json::nullValue);
  v["favorite"] = g.favorite;
  v["hidden"] = g.hidden;
  v["settings"] = g.settings ? toJson(*g.settings) : Json::Value(Json::nullValue);
  v["profile"] = toJson(g.profile);
  v["detected"] = g.detected;
  v["canStop"] = g.canStop;
  return v;
}

Json::Value toJson(const Runner& r) {
  Json::Value v(Json::objectValue);
  v["id"] = r.id;
  v["name"] = r.name;
  v["kind"] = r.kind;
  v["source"] = r.source;
  v["path"] = r.path;
  return v;
}

Json::Value toJson(const Pad& p) {
  Json::Value v(Json::objectValue);
  v["index"] = p.index;
  v["name"] = p.name;
  v["type"] = p.type;
  return v;
}

static GameSettings parseLenient(const Json::Value& v) {
  GameSettings s;
  s.kind = jstr(v, "kind", "native");
  if (s.kind != "native" && s.kind != "windows") s.kind = "native";
  s.exe = jstr(v, "exe");
  s.args = jstr(v, "args");
  if (v["workdir"].isString() && !v["workdir"].asString().empty()) s.workdir = v["workdir"].asString();
  if (v["runner"].isString() && !v["runner"].asString().empty()) s.runner = v["runner"].asString();
  if (v["prefix"].isString() && !v["prefix"].asString().empty()) s.prefix = v["prefix"].asString();
  if (v["env"].isObject()) {
    for (auto& k : v["env"].getMemberNames()) {
      const Json::Value& e = v["env"][k];
      if (e.isString() || e.isIntegral() || e.isDouble()) s.env[k] = e.asString();
    }
  }
  s.gamemode = jbool(v, "gamemode");
  s.mangohud = jbool(v, "mangohud");
  const Json::Value& gs = v["gamescope"];
  if (gs.isObject()) {
    s.gamescope.enabled = jbool(gs, "enabled");
    // Clamped: these become gamescope arguments.
    s.gamescope.width = static_cast<int>(std::clamp<int64_t>(jint(gs, "width", 1920), 0, 16384));
    s.gamescope.height = static_cast<int>(std::clamp<int64_t>(jint(gs, "height", 1080), 0, 16384));
    s.gamescope.fps = static_cast<int>(std::clamp<int64_t>(jint(gs, "fps", 0), 0, 1000));
    s.gamescope.fullscreen = jbool(gs, "fullscreen", true);
  }
  return s;
}

GameSettings settingsFromStored(const Json::Value& v) { return parseLenient(v); }

bool settingsFromJson(const Json::Value& v, GameSettings& out, std::string& err) {
  if (!v.isObject()) { err = "settings must be an object"; return false; }
  std::string kind = jstr(v, "kind");
  if (kind != "native" && kind != "windows") { err = "settings.kind must be native or windows"; return false; }
  if (jstr(v, "exe").empty()) { err = "settings.exe is required"; return false; }
  for (const char* k : {"args", "workdir", "runner", "prefix"}) {
    if (v.isMember(k) && !v[k].isNull() && !v[k].isString()) { err = std::string("settings.") + k + " must be a string or null"; return false; }
  }
  if (v.isMember("env") && !v["env"].isNull()) {
    if (!v["env"].isObject()) { err = "settings.env must be an object"; return false; }
    for (auto& k : v["env"].getMemberNames())
      if (!v["env"][k].isString()) { err = "settings.env values must be strings"; return false; }
  }
  if (v.isMember("gamescope") && !v["gamescope"].isNull() && !v["gamescope"].isObject()) {
    err = "settings.gamescope must be an object";
    return false;
  }
  out = parseLenient(v);
  return true;
}

}  // namespace fg
