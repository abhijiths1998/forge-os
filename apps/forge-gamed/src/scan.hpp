#pragma once
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "model.hpp"

namespace fg {

// ---- Steam ----
bool isSteamTool(const std::string& appid, const std::string& name);
// Library directories listed in libraryfolders.vdf (old and new format).
std::vector<std::string> parseSteamLibraryFolders(const std::string& vdfText);
// nullopt for tools, uninstalled or malformed manifests. Cover/hero are the
// CDN fallback URLs.
std::optional<Game> parseSteamManifest(const std::string& acfText);
std::string findSteamRoot(const std::string& home);   // "" if none
std::vector<std::string> steamLibraries(const std::string& steamRoot);
std::vector<Game> scanSteam(const std::string& home);

// ---- Heroic ----
struct HeroicArt {
  std::string title, cover, hero;
};
std::vector<std::string> heroicConfigDirs(const std::string& home);
// App names (plus any inline title) of installed games, tolerant of shapes.
std::vector<std::pair<std::string, std::string>> parseHeroicInstalled(const Json::Value& v);
// app name -> install folder (install_path, or path), where present.
std::map<std::string, std::string> parseHeroicInstallPaths(const Json::Value& v);
std::map<std::string, HeroicArt> parseHeroicLibrary(const Json::Value& v);
std::vector<Game> scanHeroic(const std::string& home);

// ---- Lutris ----
std::vector<Game> scanLutris(const std::string& home);

}  // namespace fg
