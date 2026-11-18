#pragma once
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <json/json.h>

namespace fg {

struct Gamescope {
  bool enabled = false;
  int width = 1920, height = 1080, fps = 0;
  bool fullscreen = true;
};

struct GameSettings {
  std::string kind = "native";  // native | windows
  std::string exe, args;
  std::optional<std::string> workdir, runner, prefix;
  std::map<std::string, std::string> env;
  bool gamemode = false, mangohud = false;
  Gamescope gamescope;
};

struct Game {
  std::string id, source, title;
  std::optional<std::string> cover, hero;
  bool installed = true;
  bool running = false;
  int64_t playtimeMinutes = 0;
  std::optional<int64_t> lastPlayed;
  bool favorite = false, hidden = false;
  std::optional<GameSettings> settings;
};

struct Runner {
  std::string id, name, kind, source, path;
};

struct Pad {
  int index = 0;
  std::string name, type;
};

Json::Value toJson(const GameSettings& s);
Json::Value toJson(const Game& g);
Json::Value toJson(const Runner& r);
Json::Value toJson(const Pad& p);

// Strict parse of a GameSettings object (client input). On failure sets err.
bool settingsFromJson(const Json::Value& v, GameSettings& out, std::string& err);
// Lenient parse for our own persisted data.
GameSettings settingsFromStored(const Json::Value& v);

}  // namespace fg
