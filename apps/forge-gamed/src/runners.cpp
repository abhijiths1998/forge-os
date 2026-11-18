#include "runners.hpp"

#include <curl/curl.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstdio>
#include <filesystem>
#include <mutex>
#include <vector>

#include "scan.hpp"
#include "util.hpp"

namespace fs = std::filesystem;

namespace fg {

std::string classifyRunnerDir(const std::string& dir) {
  if (isFile(dir + "/proton")) return "proton";
  if (isFile(dir + "/bin/wine")) return "wine";
  return "";
}

static void addDirs(std::vector<Runner>& out, const std::string& parent, const std::string& source,
                    const std::string& prefix, bool onlyProtonNamed) {
  std::error_code ec;
  std::vector<std::string> names;
  for (fs::directory_iterator it(parent, ec), end; !ec && it != end; it.increment(ec)) {
    std::string n = it->path().filename().string();
    if (n.empty() || n[0] == '.') continue;
    if (onlyProtonNamed && !startsWith(n, "Proton")) continue;
    if (!it->is_directory(ec)) continue;
    names.push_back(n);
  }
  std::sort(names.begin(), names.end(), [](const std::string& a, const std::string& b) { return naturalCompare(a, b) < 0; });
  for (auto& n : names) {
    std::string dir = parent + "/" + n;
    std::string kind = classifyRunnerDir(dir);
    if (kind.empty()) continue;
    out.push_back({prefix + ":" + n, n, kind, source, dir});
  }
}

std::vector<Runner> scanRunners(const std::string& home, const std::string& dataDir) {
  std::vector<Runner> out;
  std::string root = findSteamRoot(home);
  if (!root.empty()) {
    addDirs(out, root + "/compatibilitytools.d", "steam", "steam", false);
    for (auto& lib : steamLibraries(root)) addDirs(out, lib + "/steamapps/common", "steam", "steam", true);
  }
  addDirs(out, dataDir + "/runners", "forge", "forge", false);
  addDirs(out, home + "/.local/share/lutris/runners/wine", "lutris", "lutris", false);
  std::string wine = findInPath("wine");
  if (!wine.empty()) out.push_back({"system:wine", "System Wine", "wine", "system", wine});
  // de-duplicate ids (same dir via two Steam library paths)
  std::vector<Runner> uniq;
  for (auto& r : out)
    if (std::none_of(uniq.begin(), uniq.end(), [&](const Runner& u) { return u.id == r.id; })) uniq.push_back(r);
  return uniq;
}

std::string pickDefaultRunner(const std::vector<Runner>& runners) {
  const Runner* best = nullptr;
  auto score = [](const Runner& r) { return startsWith(r.name, "GE-Proton") ? 3 : r.kind == "proton" ? 2 : 1; };
  for (auto& r : runners) {
    if (!best || score(r) > score(*best) ||
        (score(r) == score(*best) && naturalCompare(r.name, best->name) > 0))
      best = &r;
  }
  return best ? best->id : "";
}

bool validRunnerName(const std::string& n) {
  if (n.empty() || n.size() > 128 || n[0] == '.' || n[0] == '-') return false;
  for (char c : n)
    if (!(std::isalnum(static_cast<unsigned char>(c)) || c == '.' || c == '_' || c == '-')) return false;
  return true;
}

std::vector<Release> parseReleases(const std::string& json, size_t max) {
  std::vector<Release> out;
  Json::Value root;
  if (!parseJson(json, root) || !root.isArray()) return out;
  for (auto& r : root) {
    if (!r.isObject() || jbool(r, "draft")) continue;
    std::string name = jstr(r, "tag_name");
    if (name.empty()) name = jstr(r, "name");
    if (!validRunnerName(name)) continue;
    // Newer releases ship aarch64 and x86_64 archives: take x86_64 (or an
    // unsuffixed legacy archive), never the arm one.
    const Json::Value* pick = nullptr;
    for (auto& a : r["assets"]) {
      std::string an = lower(jstr(a, "name"));
      if (!endsWith(an, ".tar.gz") || jstr(a, "browser_download_url").empty()) continue;
      if (an.find("aarch64") != std::string::npos || an.find("arm64") != std::string::npos) continue;
      if (!pick || an.find("x86_64") != std::string::npos) pick = &a;
    }
    if (pick) out.push_back({name, jstr(*pick, "browser_download_url"), jint(*pick, "size")});
    if (out.size() >= max) break;
  }
  return out;
}

// ------------------------------------------------------------------ curl ----

namespace {
struct CurlInit {
  CurlInit() { curl_global_init(CURL_GLOBAL_DEFAULT); }
  ~CurlInit() { curl_global_cleanup(); }
};
void ensureCurl() {
  static CurlInit init;
  (void)init;
}

size_t writeString(char* p, size_t sz, size_t n, void* ud) {
  static_cast<std::string*>(ud)->append(p, sz * n);
  return sz * n;
}
size_t writeFile(char* p, size_t sz, size_t n, void* ud) {
  return std::fwrite(p, sz, n, static_cast<FILE*>(ud)) * sz;
}

struct ProgressCtx {
  const std::function<void(int64_t, int64_t)>* cb;
  const std::atomic<bool>* cancel;
  int64_t lastMs = 0;
};
int xferInfo(void* ud, curl_off_t total, curl_off_t now, curl_off_t, curl_off_t) {
  auto* c = static_cast<ProgressCtx*>(ud);
  if (c->cancel->load()) return 1;
  int64_t t = monoMs();
  if (t - c->lastMs >= 100 || (total > 0 && now >= total)) {
    c->lastMs = t;
    (*c->cb)(now, total);
  }
  return 0;
}
}  // namespace

bool httpGet(const std::string& url, std::string& body, int timeoutSec, std::string& err) {
  ensureCurl();
  CURL* c = curl_easy_init();
  if (!c) { err = "curl init failed"; return false; }
  char ebuf[CURL_ERROR_SIZE] = {0};
  curl_slist* hdr = curl_slist_append(nullptr, "Accept: application/vnd.github+json");
  curl_easy_setopt(c, CURLOPT_URL, url.c_str());
  curl_easy_setopt(c, CURLOPT_USERAGENT, "forge-gamed");
  curl_easy_setopt(c, CURLOPT_HTTPHEADER, hdr);
  curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(c, CURLOPT_TIMEOUT, static_cast<long>(timeoutSec));
  curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT, static_cast<long>(std::min(timeoutSec, 8)));
  curl_easy_setopt(c, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(c, CURLOPT_ERRORBUFFER, ebuf);
  curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, writeString);
  curl_easy_setopt(c, CURLOPT_WRITEDATA, &body);
  CURLcode rc = curl_easy_perform(c);
  long code = 0;
  curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &code);
  curl_slist_free_all(hdr);
  curl_easy_cleanup(c);
  if (rc != CURLE_OK) { err = ebuf[0] ? ebuf : curl_easy_strerror(rc); return false; }
  if (code < 200 || code >= 300) { err = "HTTP " + std::to_string(code); return false; }
  return true;
}

bool downloadFile(const std::string& url, const std::string& dest,
                  const std::function<void(int64_t, int64_t)>& progress,
                  const std::atomic<bool>& cancel, std::string& err) {
  ensureCurl();
  auto slash = dest.rfind('/');
  if (slash != std::string::npos) mkdirs(dest.substr(0, slash));
  FILE* f = std::fopen(dest.c_str(), "wb");
  if (!f) { err = "cannot write " + dest; return false; }
  CURL* c = curl_easy_init();
  if (!c) { std::fclose(f); err = "curl init failed"; return false; }
  char ebuf[CURL_ERROR_SIZE] = {0};
  ProgressCtx ctx{&progress, &cancel, 0};
  curl_easy_setopt(c, CURLOPT_URL, url.c_str());
  curl_easy_setopt(c, CURLOPT_USERAGENT, "forge-gamed");
  curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(c, CURLOPT_FAILONERROR, 1L);
  curl_easy_setopt(c, CURLOPT_CONNECTTIMEOUT, 15L);
  curl_easy_setopt(c, CURLOPT_LOW_SPEED_LIMIT, 1024L);
  curl_easy_setopt(c, CURLOPT_LOW_SPEED_TIME, 60L);
  curl_easy_setopt(c, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(c, CURLOPT_ERRORBUFFER, ebuf);
  curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, writeFile);
  curl_easy_setopt(c, CURLOPT_WRITEDATA, f);
  curl_easy_setopt(c, CURLOPT_NOPROGRESS, 0L);
  curl_easy_setopt(c, CURLOPT_XFERINFOFUNCTION, xferInfo);
  curl_easy_setopt(c, CURLOPT_XFERINFODATA, &ctx);
  CURLcode rc = curl_easy_perform(c);
  curl_easy_cleanup(c);
  bool closed = std::fclose(f) == 0;
  if (rc != CURLE_OK) {
    err = rc == CURLE_ABORTED_BY_CALLBACK ? "cancelled" : (ebuf[0] ? ebuf : curl_easy_strerror(rc));
    ::unlink(dest.c_str());
    return false;
  }
  if (!closed) { err = "write error"; ::unlink(dest.c_str()); return false; }
  return true;
}

// Runs tar into destDir as it is (no staging).
bool extractTarGzRaw(const std::string& file, const std::string& destDir, std::string& err);

bool extractTarGz(const std::string& file, const std::string& destDir, std::string& err) {
  // Unpack into a hidden staging folder (scanRunners skips dot names) and
  // move the result into place only when tar succeeded, so a failed or
  // interrupted install never leaves a half runner that looks complete.
  namespace fs = std::filesystem;
  mkdirs(destDir);
  const std::string stage = destDir + "/.extract-" + std::to_string(::getpid()) + "-" +
                            fs::path(file).stem().string();
  std::error_code ec;
  fs::remove_all(stage, ec);
  mkdirs(stage);
  if (!extractTarGzRaw(file, stage, err)) {
    fs::remove_all(stage, ec);
    return false;
  }
  std::vector<fs::path> made;
  for (const auto& e : fs::directory_iterator(stage, ec)) made.push_back(e.path());
  for (const auto& src : made) {
    fs::path dst = fs::path(destDir) / src.filename();
    if (fs::exists(dst, ec)) {
      err = dst.string() + " already exists";
      fs::remove_all(stage, ec);
      return false;
    }
  }
  for (const auto& src : made) {
    fs::rename(src, fs::path(destDir) / src.filename(), ec);
    if (ec) {
      err = "move into place failed: " + ec.message();
      fs::remove_all(stage, ec);
      return false;
    }
  }
  fs::remove_all(stage, ec);
  return true;
}

bool extractTarGzRaw(const std::string& file, const std::string& destDir, std::string& err) {
  pid_t pid = ::fork();
  if (pid < 0) { err = "fork failed"; return false; }
  if (pid == 0) {
    ::execlp("tar", "tar", "-xzf", file.c_str(), "-C", destDir.c_str(), static_cast<char*>(nullptr));
    ::_exit(127);
  }
  int status = 0;
  while (::waitpid(pid, &status, 0) < 0) {
    if (errno != EINTR) { err = "waitpid failed"; return false; }
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    err = "tar failed (status " + std::to_string(status) + ")";
    return false;
  }
  return true;
}

}  // namespace fg
