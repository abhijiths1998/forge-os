#include "scan.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <set>

#include "util.hpp"
#include "vdf.hpp"

namespace fs = std::filesystem;

namespace fg {

// ---------------------------------------------------------------- Steam ----

bool isSteamTool(const std::string& appid, const std::string& name) {
  static const std::set<std::string> toolIds = {"228980", "1070560", "1391110",
                                                "1628350", "1493710", "2180100"};
  if (toolIds.count(appid)) return true;
  if (startsWith(name, "Proton") || startsWith(name, "Steam Linux Runtime") ||
      startsWith(name, "Steamworks Common Redistributables"))
    return true;
  return false;
}

std::vector<std::string> parseSteamLibraryFolders(const std::string& text) {
  std::vector<std::string> out;
  auto root = parseVdf(text);
  if (!root) return out;
  const VdfNode* lf = root->find("libraryfolders");
  if (!lf) return out;
  for (auto& [key, node] : lf->kids) {
    if (key.empty() || !std::isdigit(static_cast<unsigned char>(key[0]))) continue;
    std::string path = node.isObject ? node.str("path") : node.value;
    if (!path.empty()) out.push_back(path);
  }
  return out;
}

std::optional<Game> parseSteamManifest(const std::string& text) {
  auto root = parseVdf(text);
  if (!root) return std::nullopt;
  const VdfNode* st = root->find("AppState");
  if (!st) return std::nullopt;
  std::string appid = st->str("appid");
  std::string name = st->str("name");
  if (appid.empty() || name.empty()) return std::nullopt;
  for (char c : appid)
    if (!std::isdigit(static_cast<unsigned char>(c))) return std::nullopt;
  if (isSteamTool(appid, name)) return std::nullopt;
  long flags = std::strtol(st->str("StateFlags", "0").c_str(), nullptr, 10);
  if (!(flags & 4)) return std::nullopt;  // not fully installed
  Game g;
  g.id = "steam:" + appid;
  g.source = "steam";
  g.title = name;
  g.cover = "https://shared.steamstatic.com/store_item_assets/steam/apps/" + appid + "/library_600x900.jpg";
  g.hero = "https://shared.steamstatic.com/store_item_assets/steam/apps/" + appid + "/library_hero.jpg";
  long long lp = std::strtoll(st->str("LastPlayed", "0").c_str(), nullptr, 10);
  if (lp > 0) g.lastPlayed = lp;
  g.installDir = st->str("installdir");  // relative; scanSteam makes it absolute
  return g;
}

std::string findSteamRoot(const std::string& home) {
  for (const char* rel : {"/.local/share/Steam", "/.steam/steam"}) {
    std::string p = home + rel;
    if (isDir(p + "/steamapps") || isDir(p)) return p;
  }
  return "";
}

std::vector<std::string> steamLibraries(const std::string& root) {
  std::vector<std::string> libs;
  if (root.empty()) return libs;
  libs.push_back(root);
  std::string text;
  if (readFile(root + "/steamapps/libraryfolders.vdf", text))
    for (auto& p : parseSteamLibraryFolders(text))
      if (std::find(libs.begin(), libs.end(), p) == libs.end()) libs.push_back(p);
  return libs;
}

static std::optional<std::string> findCachedArt(const std::string& dir, const std::string& prefix) {
  std::error_code ec;
  if (!fs::is_directory(dir, ec)) return std::nullopt;
  std::vector<std::string> hits;
  for (fs::recursive_directory_iterator it(dir, fs::directory_options::skip_permission_denied, ec), end;
       !ec && it != end; it.increment(ec)) {
    if (!it->is_regular_file(ec)) continue;
    std::string n = it->path().filename().string();
    if (startsWith(n, prefix) && endsWith(n, ".jpg")) hits.push_back(it->path().string());
  }
  if (hits.empty()) return std::nullopt;
  std::sort(hits.begin(), hits.end(), [](const std::string& a, const std::string& b) {
    if (a.size() != b.size()) return a.size() < b.size();
    return a < b;
  });
  return hits.front();
}

std::vector<Game> scanSteam(const std::string& home) {
  std::vector<Game> out;
  std::string root = findSteamRoot(home);
  std::set<std::string> seen;
  for (auto& lib : steamLibraries(root)) {
    std::error_code ec;
    std::string apps = lib + "/steamapps";
    for (fs::directory_iterator it(apps, ec), end; !ec && it != end; it.increment(ec)) {
      std::string n = it->path().filename().string();
      if (!startsWith(n, "appmanifest_") || !endsWith(n, ".acf")) continue;
      std::string text;
      if (!readFile(it->path().string(), text)) continue;
      auto g = parseSteamManifest(text);
      if (!g || !seen.insert(g->id).second) continue;
      std::string appid = g->id.substr(6);
      std::string cache = root + "/appcache/librarycache/" + appid;
      if (auto c = findCachedArt(cache, "library_600x900")) g->cover = *c;
      if (auto h = findCachedArt(cache, "library_hero")) g->hero = *h;
      if (!g->installDir.empty() && g->installDir.find("..") == std::string::npos && g->installDir[0] != '/')
        g->installDir = lib + "/steamapps/common/" + g->installDir;
      else
        g->installDir.clear();
      out.push_back(std::move(*g));
    }
  }
  return out;
}

// --------------------------------------------------------------- Heroic ----

std::vector<std::string> heroicConfigDirs(const std::string& home) {
  std::vector<std::string> dirs;
  for (std::string d : {home + "/.config/heroic",
                        home + "/.var/app/com.heroicgameslauncher.hgl/config/heroic"})
    if (isDir(d)) dirs.push_back(d);
  return dirs;
}

static std::string appNameOf(const Json::Value& o) {
  std::string n = jstr(o, "app_name");
  if (n.empty()) n = jstr(o, "appName");
  return n;
}

std::vector<std::pair<std::string, std::string>> parseHeroicInstalled(const Json::Value& v) {
  std::vector<std::pair<std::string, std::string>> out;
  auto take = [&](const Json::Value& o, const std::string& key) {
    if (!o.isObject()) return;
    std::string app = appNameOf(o);
    if (app.empty()) app = key;
    if (app.empty()) return;
    std::string title = jstr(o, "title");
    out.emplace_back(app, title);
  };
  if (v.isArray()) {
    for (auto& e : v) take(e, "");
  } else if (v.isObject()) {
    if (v["installed"].isArray()) {
      for (auto& e : v["installed"]) take(e, "");
    } else {
      for (auto& k : v.getMemberNames()) take(v[k], k);
    }
  }
  return out;
}

std::map<std::string, std::string> parseHeroicInstallPaths(const Json::Value& v) {
  std::map<std::string, std::string> out;
  auto take = [&](const Json::Value& o, const std::string& key) {
    if (!o.isObject()) return;
    std::string app = appNameOf(o);
    if (app.empty()) app = key;
    std::string p = jstr(o, "install_path");
    if (p.empty()) p = jstr(o, "path");
    if (!app.empty() && !p.empty()) out[app] = p;
  };
  if (v.isArray()) {
    for (auto& e : v) take(e, "");
  } else if (v.isObject()) {
    if (v["installed"].isArray()) {
      for (auto& e : v["installed"]) take(e, "");
    } else {
      for (auto& k : v.getMemberNames()) take(v[k], k);
    }
  }
  return out;
}

static void collectLibrary(const Json::Value& v, int depth, std::map<std::string, HeroicArt>& out) {
  if (depth > 3) return;
  if (v.isArray()) {
    for (auto& e : v) collectLibrary(e, depth + 1, out);
  } else if (v.isObject()) {
    std::string app = appNameOf(v);
    if (!app.empty()) {
      HeroicArt a;
      a.title = jstr(v, "title");
      std::string square = jstr(v, "art_square");
      std::string cover = jstr(v, "art_cover");
      a.cover = !square.empty() ? square : cover;
      a.hero = !cover.empty() ? cover : square;
      out[app] = a;
    } else {
      for (auto& k : v.getMemberNames()) collectLibrary(v[k], depth + 1, out);
    }
  }
}

std::map<std::string, HeroicArt> parseHeroicLibrary(const Json::Value& v) {
  std::map<std::string, HeroicArt> out;
  collectLibrary(v, 0, out);
  return out;
}

static bool loadJsonFile(const std::string& path, Json::Value& v) {
  std::string t;
  return readFile(path, t) && parseJson(t, v);
}

std::vector<Game> scanHeroic(const std::string& home) {
  std::vector<Game> out;
  struct Src { const char* runner; const char* installed; const char* library; };
  const Src srcs[] = {
      {"legendary", "legendaryConfig/legendary/installed.json", "store_cache/legendary_library.json"},
      {"gog", "gog_store/installed.json", "store_cache/gog_library.json"},
      {"nile", "nile_config/nile/installed.json", "store_cache/nile_library.json"},
  };
  std::set<std::string> seen;
  for (auto& dir : heroicConfigDirs(home)) {
    for (auto& s : srcs) {
      Json::Value inst;
      if (!loadJsonFile(dir + "/" + s.installed, inst)) continue;
      std::map<std::string, HeroicArt> art;
      Json::Value lib;
      if (loadJsonFile(dir + "/" + s.library, lib)) art = parseHeroicLibrary(lib);
      auto paths = parseHeroicInstallPaths(inst);
      for (auto& [app, inlineTitle] : parseHeroicInstalled(inst)) {
        std::string id = std::string("heroic:") + s.runner + ":" + app;
        if (!seen.insert(id).second) continue;
        Game g;
        g.id = id;
        g.source = "heroic";
        g.title = app;
        if (auto pit = paths.find(app); pit != paths.end()) g.installDir = pit->second;
        if (!inlineTitle.empty()) g.title = inlineTitle;
        auto it = art.find(app);
        if (it != art.end()) {
          if (!it->second.title.empty()) g.title = it->second.title;
          if (!it->second.cover.empty()) g.cover = it->second.cover;
          if (!it->second.hero.empty()) g.hero = it->second.hero;
        }
        out.push_back(std::move(g));
      }
    }
  }
  return out;
}

// --------------------------------------------------------------- Lutris ----

std::vector<Game> scanLutris(const std::string& home) {
  std::vector<Game> out;
  std::string base = home + "/.local/share/lutris";
  std::string db = base + "/pga.db";
  if (!isFile(db)) return out;
  sqlite3* h = nullptr;
  if (sqlite3_open_v2(db.c_str(), &h, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK) {
    if (h) sqlite3_close(h);
    return out;
  }
  sqlite3_busy_timeout(h, 500);
  sqlite3_stmt* st = nullptr;
  const char* sql = "SELECT id, name, slug, runner, installed, playtime, lastplayed, directory FROM games WHERE installed = 1";
  // Very old databases have no `directory` column.
  bool prepared = sqlite3_prepare_v2(h, sql, -1, &st, nullptr) == SQLITE_OK;
  if (!prepared) {
    sqlite3_finalize(st);
    st = nullptr;
    prepared = sqlite3_prepare_v2(h,
        "SELECT id, name, slug, runner, installed, playtime, lastplayed, NULL FROM games WHERE installed = 1",
        -1, &st, nullptr) == SQLITE_OK;
  }
  if (prepared) {
    while (sqlite3_step(st) == SQLITE_ROW) {
      Game g;
      long long id = sqlite3_column_int64(st, 0);
      auto col = [&](int i) {
        const unsigned char* t = sqlite3_column_text(st, i);
        return t ? std::string(reinterpret_cast<const char*>(t)) : std::string();
      };
      g.id = "lutris:" + std::to_string(id);
      g.source = "lutris";
      g.title = col(1);
      if (g.title.empty()) g.title = g.id;
      std::string slug = col(2);
      g.lutrisName = col(1);
      g.installDir = col(7);
      g.playtimeMinutes = static_cast<int64_t>(sqlite3_column_double(st, 5) * 60.0 + 0.5);
      if (sqlite3_column_type(st, 6) != SQLITE_NULL) {
        long long lp = sqlite3_column_int64(st, 6);
        if (lp > 0) g.lastPlayed = lp;
      }
      if (!slug.empty() && slug.find('/') == std::string::npos) {
        for (const char* ext : {".jpg", ".png"})
          if (!g.cover && isFile(base + "/coverart/" + slug + ext)) g.cover = base + "/coverart/" + slug + ext;
        if (isFile(base + "/banners/" + slug + ".jpg")) g.hero = base + "/banners/" + slug + ".jpg";
      }
      out.push_back(std::move(g));
    }
  }
  sqlite3_finalize(st);
  sqlite3_close(h);
  return out;
}

}  // namespace fg
