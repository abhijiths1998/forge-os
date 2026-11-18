#include "watch.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cstdlib>

#include "util.hpp"

namespace fg {

std::string normalizeGamePath(const std::string& s) {
  std::string o;
  o.reserve(s.size());
  for (char c : s) o += c == '\\' ? '/' : static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  if (o.size() >= 2 && o[0] == 'z' && o[1] == ':') o.erase(0, 2);
  std::string r;
  for (char c : o) {
    if (c == '/' && !r.empty() && r.back() == '/') continue;
    r += c;
  }
  while (r.size() > 1 && r.back() == '/') r.pop_back();
  return r;
}

static std::string baseName(const std::string& s) {
  auto p = s.find_last_of('/');
  return p == std::string::npos ? s : s.substr(p + 1);
}

static std::string trim(const std::string& s) {
  size_t a = 0, b = s.size();
  while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
  while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
  return s.substr(a, b - a);
}

bool isLauncherProcess(const ProcInfo& p) {
  static const std::set<std::string> names = {"steam", "steamwebhelper", "heroic", "legendary",
                                              "gogdl", "nile",           "lutris"};
  for (size_t i = 0; i < p.argv.size() && i < 2; ++i)
    if (names.count(lower(baseName(trim(p.argv[i]))))) return true;
  return false;
}

static bool steamMatch(const ProcInfo& p, const std::string& appid) {
  // Steam's reaper: `.../reaper SteamLaunch AppId=<n> -- ...`, each its own
  // argument. Matching whole arguments only (and only for reaper itself)
  // keeps a shell or editor whose command line mentions it from counting.
  if (p.argv.empty() || lower(baseName(trim(p.argv[0]))) != "reaper") return false;
  bool launch = false, app = false;
  const std::string want = "AppId=" + appid;
  for (size_t i = 1; i < p.argv.size(); ++i) {
    if (p.argv[i] == "SteamLaunch") launch = true;
    if (p.argv[i] == want) app = true;
  }
  return launch && app;
}

static bool lutrisMatch(const ProcInfo& p, const std::string& name) {
  if (name.empty()) return false;
  const std::string n = lower(trim(name));
  for (size_t i = 0; i < p.argv.size(); ++i) {
    const std::string a = trim(p.argv[i]);
    static const std::string title = "lutris-wrapper:";
    if (lower(a).compare(0, title.size(), title) == 0 && lower(trim(a.substr(title.size()))) == n) return true;
    if (lower(baseName(a)) == "lutris-wrapper" && i + 1 < p.argv.size() && lower(trim(p.argv[i + 1])) == n)
      return true;
  }
  return false;
}

// Folders too shallow to identify a game ("/", "/home/u", a drive root).
static bool usableDir(const std::string& d) {
  if (d.empty() || d[0] != '/') return false;
  return std::count(d.begin(), d.end(), '/') >= 3;
}

static bool insideDir(const ProcInfo& p, const std::string& dir) {
  for (const auto& a : p.argv) {
    if (a.empty()) continue;
    std::string n = normalizeGamePath(a);
    if (n == dir || (n.size() > dir.size() && n.compare(0, dir.size(), dir) == 0 && n[dir.size()] == '/'))
      return true;
  }
  return false;
}

std::set<std::string> matchRunning(const std::vector<ProcInfo>& procs, const std::vector<Game>& games) {
  std::set<std::string> out;
  for (const auto& g : games) {
    if (g.source != "steam" && g.source != "heroic" && g.source != "lutris") continue;
    std::string dir = g.installDir.empty() ? "" : normalizeGamePath(g.installDir);
    bool useDir = (g.source == "heroic" || g.source == "lutris") && usableDir(dir);
    std::string appid = g.source == "steam" ? g.id.substr(g.id.find(':') + 1) : "";
    for (const auto& p : procs) {
      bool hit = false;
      if (g.source == "steam") hit = !appid.empty() && steamMatch(p, appid);
      if (!hit && g.source == "lutris") hit = lutrisMatch(p, g.lutrisName);
      if (!hit && useDir && !isLauncherProcess(p)) hit = insideDir(p, dir);
      if (hit) {
        out.insert(g.id);
        break;
      }
    }
  }
  return out;
}

WatchState::Changes WatchState::update(const std::set<std::string>& found) {
  Changes ch;
  for (const auto& id : found) {
    missing_.erase(id);
    if (running_.insert(id).second) ch.started.push_back(id);
  }
  for (auto it = running_.begin(); it != running_.end();) {
    if (found.count(*it)) {
      ++it;
      continue;
    }
    if (++missing_[*it] >= 2) {
      ch.stopped.push_back(*it);
      missing_.erase(*it);
      it = running_.erase(it);
    } else {
      ++it;
    }
  }
  return ch;
}

std::vector<ProcInfo> readProcessList() {
  std::vector<ProcInfo> out;
  DIR* d = ::opendir("/proc");
  if (!d) return out;
  while (dirent* e = ::readdir(d)) {
    const char* n = e->d_name;
    if (!*n || !std::isdigit(static_cast<unsigned char>(*n))) continue;
    char* end = nullptr;
    long pid = std::strtol(n, &end, 10);
    if (*end || pid <= 0) continue;
    std::string path = std::string("/proc/") + n + "/cmdline";
    int fd = ::open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) continue;
    std::string buf;
    char tmp[4096];
    ssize_t r;
    while (buf.size() < (64u << 10) && (r = ::read(fd, tmp, sizeof tmp)) > 0) buf.append(tmp, static_cast<size_t>(r));
    ::close(fd);
    if (buf.empty()) continue;
    ProcInfo p;
    p.pid = static_cast<int>(pid);
    size_t i = 0;
    while (i < buf.size()) {
      size_t j = buf.find('\0', i);
      if (j == std::string::npos) j = buf.size();
      p.argv.push_back(buf.substr(i, j - i));
      i = j + 1;
    }
    if (!p.argv.empty()) out.push_back(std::move(p));
  }
  ::closedir(d);
  return out;
}

}  // namespace fg
