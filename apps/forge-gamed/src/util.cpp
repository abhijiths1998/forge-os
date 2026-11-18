#include "util.hpp"

#include <fcntl.h>
#include <pwd.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <cctype>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>

namespace fg {

std::vector<std::string> splitArgs(const std::string& s) {
  std::vector<std::string> out;
  std::string cur;
  bool have = false;
  size_t i = 0;
  const size_t n = s.size();
  while (i < n) {
    char c = s[i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      if (have) {
        out.push_back(cur);
        cur.clear();
        have = false;
      }
      ++i;
    } else if (c == '\'') {
      have = true;
      ++i;
      while (i < n && s[i] != '\'') cur += s[i++];
      if (i < n) ++i;
    } else if (c == '"') {
      have = true;
      ++i;
      while (i < n && s[i] != '"') {
        if (s[i] == '\\' && i + 1 < n &&
            (s[i + 1] == '"' || s[i + 1] == '\\' || s[i + 1] == '$' || s[i + 1] == '`')) {
          cur += s[i + 1];
          i += 2;
        } else if (s[i] == '\\' && i + 1 < n && s[i + 1] == '\n') {
          i += 2;
        } else {
          cur += s[i++];
        }
      }
      if (i < n) ++i;
    } else if (c == '\\') {
      have = true;
      if (i + 1 < n) {
        if (s[i + 1] != '\n') cur += s[i + 1];
        i += 2;
      } else {
        ++i;
      }
    } else {
      have = true;
      cur += c;
      ++i;
    }
  }
  if (have) out.push_back(cur);
  return out;
}

std::string home() {
  if (const char* h = std::getenv("HOME"); h && *h) return h;
  if (struct passwd* pw = getpwuid(getuid())) return pw->pw_dir;
  return "/";
}
std::string dataDir() { return home() + "/.local/share/forge-gaming"; }
std::string stateDir() { return home() + "/.local/state/forge-gaming"; }
std::string logDir() { return stateDir() + "/logs"; }
std::string socketPath() {
  const char* r = std::getenv("XDG_RUNTIME_DIR");
  std::string dir = (r && *r) ? r : "/run/user/" + std::to_string(getuid());
  return dir + "/forge-gamed.sock";
}

std::string sanitizeId(const std::string& id) {
  std::string o = id;
  for (char& c : o)
    if (c == ':' || c == '/') c = '_';
  return o;
}
std::string logFileName(const std::string& id) { return sanitizeId(id) + ".log"; }

bool readFile(const std::string& path, std::string& out) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  std::ostringstream ss;
  ss << f.rdbuf();
  out = ss.str();
  return true;
}

bool mkdirs(const std::string& path) {
  std::error_code ec;
  std::filesystem::create_directories(path, ec);
  return !ec || isDir(path);
}

bool writeFileAtomic(const std::string& path, const std::string& data) {
  auto slash = path.rfind('/');
  if (slash != std::string::npos && slash > 0) mkdirs(path.substr(0, slash));
  std::string tmp = path + ".tmp";
  int fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  if (fd < 0) return false;
  size_t off = 0;
  while (off < data.size()) {
    ssize_t w = ::write(fd, data.data() + off, data.size() - off);
    if (w < 0) {
      if (errno == EINTR) continue;
      ::close(fd);
      ::unlink(tmp.c_str());
      return false;
    }
    off += static_cast<size_t>(w);
  }
  ::fsync(fd);
  ::close(fd);
  if (::rename(tmp.c_str(), path.c_str()) != 0) {
    ::unlink(tmp.c_str());
    return false;
  }
  return true;
}

std::string lower(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}
bool endsWith(const std::string& s, const std::string& x) {
  return s.size() >= x.size() && s.compare(s.size() - x.size(), x.size(), x) == 0;
}
bool startsWith(const std::string& s, const std::string& x) {
  return s.size() >= x.size() && s.compare(0, x.size(), x) == 0;
}

int naturalCompare(const std::string& a, const std::string& b) {
  size_t i = 0, j = 0;
  while (i < a.size() && j < b.size()) {
    if (std::isdigit(static_cast<unsigned char>(a[i])) &&
        std::isdigit(static_cast<unsigned char>(b[j]))) {
      size_t si = i, sj = j;
      while (si < a.size() && a[si] == '0') ++si;
      while (sj < b.size() && b[sj] == '0') ++sj;
      size_t ei = si, ej = sj;
      while (ei < a.size() && std::isdigit(static_cast<unsigned char>(a[ei]))) ++ei;
      while (ej < b.size() && std::isdigit(static_cast<unsigned char>(b[ej]))) ++ej;
      if (ei - si != ej - sj) return (ei - si) < (ej - sj) ? -1 : 1;
      int c = a.compare(si, ei - si, b, sj, ej - sj);
      if (c != 0) return c < 0 ? -1 : 1;
      i = ei;
      j = ej;
    } else {
      if (a[i] != b[j]) return static_cast<unsigned char>(a[i]) < static_cast<unsigned char>(b[j]) ? -1 : 1;
      ++i;
      ++j;
    }
  }
  if (i < a.size()) return 1;
  if (j < b.size()) return -1;
  return 0;
}

bool parseJson(const std::string& text, Json::Value& out) {
  Json::CharReaderBuilder b;
  // Nothing we read nests deeply; a low limit keeps hostile input cheap.
  b["stackLimit"] = 128;
  std::unique_ptr<Json::CharReader> r(b.newCharReader());
  std::string errs;
  // jsoncpp throws (rather than failing) past the stack limit and on a few
  // other malformed inputs: every caller treats that as "not JSON".
  try {
    return r->parse(text.data(), text.data() + text.size(), &out, &errs);
  } catch (const std::exception&) {
    out = Json::Value();
    return false;
  }
}

std::string toLine(const Json::Value& v) {
  Json::StreamWriterBuilder b;
  b["indentation"] = "";
  b["emitUTF8"] = true;
  return Json::writeString(b, v);
}

std::string percentEncode(const std::string& s) {
  static const char* hex = "0123456789ABCDEF";
  std::string o;
  for (unsigned char c : s) {
    if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
      o += static_cast<char>(c);
    } else {
      o += '%';
      o += hex[c >> 4];
      o += hex[c & 15];
    }
  }
  return o;
}

int64_t unixNow() {
  return std::chrono::duration_cast<std::chrono::seconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}
int64_t monoMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

bool isDir(const std::string& p) {
  struct stat st;
  return ::stat(p.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}
bool isFile(const std::string& p) {
  struct stat st;
  return ::stat(p.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}
bool isExecutable(const std::string& p) { return isFile(p) && ::access(p.c_str(), X_OK) == 0; }

std::string findInPath(const std::string& name) {
  if (name.find('/') != std::string::npos) return isExecutable(name) ? name : "";
  const char* path = std::getenv("PATH");
  if (!path) return "";
  std::stringstream ss(path);
  std::string dir;
  while (std::getline(ss, dir, ':')) {
    if (dir.empty()) continue;
    std::string full = dir + "/" + name;
    if (isExecutable(full)) return full;
  }
  return "";
}

std::string jstr(const Json::Value& v, const char* key, const std::string& def) {
  if (!v.isObject()) return def;
  const Json::Value& x = v[key];
  return x.isString() ? x.asString() : def;
}
bool jbool(const Json::Value& v, const char* key, bool def) {
  if (!v.isObject()) return def;
  const Json::Value& x = v[key];
  return x.isBool() ? x.asBool() : def;
}
int64_t jint(const Json::Value& v, const char* key, int64_t def) {
  if (!v.isObject()) return def;
  const Json::Value& x = v[key];
  // Out-of-range numbers fall back to the default instead of throwing or
  // overflowing.
  if (x.isInt64()) return x.asInt64();
  if (x.isDouble()) {
    double d = x.asDouble();
    if (std::isfinite(d) && d > -9.0e18 && d < 9.0e18) return static_cast<int64_t>(d);
  }
  return def;
}

}  // namespace fg
