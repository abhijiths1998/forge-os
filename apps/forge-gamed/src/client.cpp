#include "client.hpp"

#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <iostream>

#include "util.hpp"

namespace fg {

static int connectDaemon() {
  std::string path = socketPath();
  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (path.size() >= sizeof(addr.sun_path)) return -1;
  std::strcpy(addr.sun_path, path.c_str());
  int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) return -1;
  if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof addr) != 0) {
    std::cerr << "forge-gamed: cannot connect to " << path << ": " << std::strerror(errno) << "\n";
    ::close(fd);
    return -1;
  }
  return fd;
}

static bool sendAll(int fd, const std::string& s) {
  size_t off = 0;
  while (off < s.size()) {
    ssize_t n = ::send(fd, s.data() + off, s.size() - off, MSG_NOSIGNAL);
    if (n < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    off += static_cast<size_t>(n);
  }
  return true;
}

// Reads lines until `onLine` returns false, EOF or timeout (ms, <0 = none).
template <class F>
static bool readLines(int fd, std::string& buf, int timeoutMs, F onLine) {
  for (;;) {
    size_t pos;
    while ((pos = buf.find('\n')) != std::string::npos) {
      std::string line = buf.substr(0, pos);
      buf.erase(0, pos + 1);
      if (!onLine(line)) return true;
    }
    pollfd p{fd, POLLIN, 0};
    int rc = ::poll(&p, 1, timeoutMs);
    if (rc < 0 && errno == EINTR) continue;
    if (rc <= 0) return false;
    char tmp[65536];
    ssize_t n = ::recv(fd, tmp, sizeof tmp, 0);
    if (n <= 0) return false;
    buf.append(tmp, static_cast<size_t>(n));
  }
}

int cmdCall(const std::string& method, const std::string& paramsJson) {
  Json::Value params(Json::objectValue);
  if (!paramsJson.empty() && !parseJson(paramsJson, params)) {
    std::cerr << "forge-gamed: params are not valid JSON\n";
    return 2;
  }
  int fd = connectDaemon();
  if (fd < 0) return 1;
  Json::Value req(Json::objectValue);
  req["id"] = 1;
  req["method"] = method;
  req["params"] = params;
  if (!sendAll(fd, toLine(req) + "\n")) { ::close(fd); return 1; }
  std::string buf;
  int rc = 1;
  bool got = false;
  readLines(fd, buf, 30000, [&](const std::string& line) {
    Json::Value v;
    if (!parseJson(line, v) || !v.isObject() || !v.isMember("id")) return true;  // an event
    std::cout << line << std::endl;
    rc = v.isMember("error") ? 1 : 0;
    got = true;
    return false;
  });
  ::close(fd);
  if (!got) std::cerr << "forge-gamed: no response\n";
  return rc;
}

int cmdWatch() {
  int fd = connectDaemon();
  if (fd < 0) return 1;
  Json::Value req(Json::objectValue);
  req["id"] = 1;
  req["method"] = "pads.list";
  if (!sendAll(fd, toLine(req) + "\n")) { ::close(fd); return 1; }
  std::string buf;
  readLines(fd, buf, -1, [&](const std::string& line) {
    Json::Value v;
    if (parseJson(line, v) && v.isObject() && v.isMember("id")) {
      for (auto& pad : v["result"]["pads"]) {
        Json::Value ev(Json::objectValue);
        Json::Value d(Json::objectValue);
        d["pad"] = pad;
        ev["event"] = "pad.connected";
        ev["data"] = d;
        std::cout << toLine(ev) << std::endl;
      }
    } else {
      std::cout << line << std::endl;
    }
    return true;
  });
  ::close(fd);
  return 0;
}

}  // namespace fg
