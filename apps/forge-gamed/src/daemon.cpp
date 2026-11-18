#include "daemon.hpp"

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/eventfd.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <iostream>

#include "launch.hpp"
#include "process.hpp"
#include "scan.hpp"
#include "util.hpp"

namespace fs = std::filesystem;

namespace fg {

static Json::Value emptyObj() { return Json::Value(Json::objectValue); }

std::string sanitizeUtf8(const std::string& s) {
  std::string o;
  size_t i = 0, n = s.size();
  while (i < n) {
    unsigned char c = static_cast<unsigned char>(s[i]);
    size_t len = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 0;
    bool ok = len > 0 && i + len <= n;
    for (size_t k = 1; ok && k < len; ++k)
      if ((static_cast<unsigned char>(s[i + k]) & 0xC0) != 0x80) ok = false;
    if (ok && len == 2 && c < 0xC2) ok = false;
    if (ok) {
      o.append(s, i, len);
      i += len;
    } else {
      o += "\xEF\xBF\xBD";
      ++i;
    }
  }
  return o;
}

Daemon::Daemon() : store_(dataDir()) {}
Daemon::~Daemon() {
  cancel_ = true;
  stopForgedWorker();
  for (auto& t : threads_)
    if (t.joinable()) t.join();
}

// ---------------------------------------------------------------- setup ----

bool Daemon::bindSocket(bool& alreadyRunning) {
  alreadyRunning = false;
  sockPath_ = socketPath();
  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (sockPath_.size() >= sizeof(addr.sun_path)) {
    std::cerr << "forge-gamed: socket path too long\n";
    return false;
  }
  std::strcpy(addr.sun_path, sockPath_.c_str());
  if (fs::exists(sockPath_)) {
    int probe = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    bool live = probe >= 0 && ::connect(probe, reinterpret_cast<sockaddr*>(&addr), sizeof addr) == 0;
    if (probe >= 0) ::close(probe);
    if (live) {
      alreadyRunning = true;
      return false;
    }
    ::unlink(sockPath_.c_str());
  }
  listenFd_ = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
  if (listenFd_ < 0) return false;
  mode_t old = ::umask(0177);
  int rc = ::bind(listenFd_, reinterpret_cast<sockaddr*>(&addr), sizeof addr);
  ::umask(old);
  if (rc != 0 || ::listen(listenFd_, 16) != 0) {
    std::cerr << "forge-gamed: cannot bind " << sockPath_ << ": " << std::strerror(errno) << "\n";
    return false;
  }
  return true;
}

int Daemon::run() {
  bool already = false;
  if (!bindSocket(already)) {
    if (already) {
      std::cout << "forge-gamed is already running (" << socketPath() << ")\n";
      return 0;
    }
    return 1;
  }

  sigset_t mask;
  sigemptyset(&mask);
  sigaddset(&mask, SIGCHLD);
  sigaddset(&mask, SIGTERM);
  sigaddset(&mask, SIGINT);
  sigprocmask(SIG_BLOCK, &mask, nullptr);  // before any thread exists
  signal(SIGPIPE, SIG_IGN);
  sigFd_ = ::signalfd(-1, &mask, SFD_CLOEXEC | SFD_NONBLOCK);
  evFd_ = ::eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
  if (sigFd_ < 0 || evFd_ < 0) {
    std::cerr << "forge-gamed: signalfd/eventfd failed\n";
    return 1;
  }

  store_.load();
  rescan();
  nextWatch_ = monoMs() + 2000;
  std::string perr;
  padsOk_ = pads_.init(perr);
  if (!padsOk_) std::cerr << "forge-gamed: controllers disabled: " << perr << "\n";
  std::cerr << "forge-gamed " << FORGE_GAMED_VERSION << " listening on " << sockPath_ << "\n";

  while (!quit_) {
    std::vector<pollfd> fds;
    fds.push_back({listenFd_, POLLIN, 0});
    fds.push_back({sigFd_, POLLIN, 0});
    fds.push_back({evFd_, POLLIN, 0});
    for (auto& [fd, c] : clients_) fds.push_back({fd, static_cast<short>(POLLIN | (c.out.empty() ? 0 : POLLOUT)), 0});

    int timeout = pads_.count() > 0 ? 16 : 250;
    int64_t now = monoMs();
    for (auto& [pid, r] : running_)
      if (r.killAt > 0) timeout = static_cast<int>(std::clamp<int64_t>(r.killAt - now, 0, timeout));
    timeout = static_cast<int>(std::clamp<int64_t>(nextWatch_ - now, 0, timeout));
    int n = ::poll(fds.data(), fds.size(), timeout);
    if (n < 0 && errno != EINTR) break;

    if (n > 0) {
      if (fds[1].revents & POLLIN) handleSignals();
      if (fds[2].revents & POLLIN) drainMainQueue();
      if (fds[0].revents & POLLIN) acceptClients();
      for (size_t i = 3; i < fds.size(); ++i) {
        auto it = clients_.find(fds[i].fd);
        if (it == clients_.end()) continue;
        Client& c = it->second;
        if (fds[i].revents & (POLLERR | POLLNVAL)) c.dead = true;
        if (fds[i].revents & POLLOUT) flushClient(c);
        if (!c.dead && (fds[i].revents & (POLLIN | POLLHUP))) readClient(c);
      }
      dropDead();
    }
    checkKillTimers();
    if (monoMs() >= nextWatch_) watchTick();
    pumpPads();
  }

  // shutdown
  cancel_ = true;
  // Give back whatever a game still holds (cooling, do not disturb).
  stopForgedWorker();
  for (auto& t : threads_)
    if (t.joinable()) t.join();
  threads_.clear();
  store_.saveLibrary();
  for (auto& [fd, c] : clients_) ::close(fd);
  clients_.clear();
  pads_.shutdown();
  ::close(listenFd_);
  ::unlink(sockPath_.c_str());
  return 0;
}

void Daemon::handleSignals() {
  signalfd_siginfo si;
  while (::read(sigFd_, &si, sizeof si) == static_cast<ssize_t>(sizeof si)) {
    if (si.ssi_signo == SIGCHLD) reapChildren();
    else quit_ = true;
  }
}

void Daemon::drainMainQueue() {
  uint64_t v;
  if (::read(evFd_, &v, sizeof v) < 0) { /* nothing */ }
  std::vector<std::function<void()>> q;
  {
    std::lock_guard<std::mutex> lk(qmu_);
    q.swap(queue_);
  }
  for (auto& f : q) f();
}

void Daemon::postMain(std::function<void()> fn) {
  {
    std::lock_guard<std::mutex> lk(qmu_);
    queue_.push_back(std::move(fn));
  }
  uint64_t one = 1;
  if (::write(evFd_, &one, sizeof one) < 0) { /* eventfd full: main will wake anyway */ }
}

void Daemon::startWorker(std::function<void()> fn) { threads_.emplace_back(std::move(fn)); }

// ------------------------------------------------------------- clients ----

void Daemon::acceptClients() {
  for (;;) {
    int fd = ::accept4(listenFd_, nullptr, nullptr, SOCK_CLOEXEC | SOCK_NONBLOCK);
    if (fd < 0) return;
    Client c;
    c.fd = fd;
    c.serial = nextSerial_++;
    clients_[fd] = std::move(c);
  }
}

void Daemon::readClient(Client& c) {
  char buf[65536];
  for (;;) {
    ssize_t n = ::recv(c.fd, buf, sizeof buf, 0);
    if (n > 0) {
      c.in.append(buf, static_cast<size_t>(n));
      if (c.in.size() > (4u << 20) && c.in.find('\n') == std::string::npos) { c.dead = true; return; }
      continue;
    }
    if (n == 0) { c.dead = true; break; }
    if (errno == EINTR) continue;
    if (errno != EAGAIN && errno != EWOULDBLOCK) c.dead = true;
    break;
  }
  size_t pos;
  while ((pos = c.in.find('\n')) != std::string::npos) {
    std::string line = c.in.substr(0, pos);
    c.in.erase(0, pos + 1);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.empty()) continue;
    handleLine(c, line);
  }
}

void Daemon::flushClient(Client& c) {
  while (!c.out.empty()) {
    ssize_t n = ::send(c.fd, c.out.data(), c.out.size(), MSG_NOSIGNAL | MSG_DONTWAIT);
    if (n > 0) { c.out.erase(0, static_cast<size_t>(n)); continue; }
    if (n < 0 && errno == EINTR) continue;
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
    c.dead = true;
    return;
  }
}

void Daemon::dropDead() {
  for (auto it = clients_.begin(); it != clients_.end();) {
    if (it->second.dead) {
      ::close(it->first);
      it = clients_.erase(it);
    } else {
      ++it;
    }
  }
}

void Daemon::sendLine(Client& c, const Json::Value& v) {
  if (c.dead) return;
  c.out += toLine(v);
  c.out += '\n';
  if (c.out.size() > (16u << 20)) { c.dead = true; return; }
  flushClient(c);
}

void Daemon::reply(Client& c, const Json::Value& id, const Json::Value& result) {
  Json::Value v(Json::objectValue);
  v["id"] = id;
  v["result"] = result;
  sendLine(c, v);
}

void Daemon::replyError(Client& c, const Json::Value& id, const std::string& code, const std::string& msg) {
  Json::Value v(Json::objectValue);
  v["id"] = id;
  Json::Value e(Json::objectValue);
  e["code"] = code;
  e["message"] = msg;
  v["error"] = e;
  sendLine(c, v);
}

void Daemon::broadcast(const std::string& event, const Json::Value& data) {
  Json::Value v(Json::objectValue);
  v["event"] = event;
  v["data"] = data;
  for (auto& [fd, c] : clients_) sendLine(c, v);
}

Daemon::Client* Daemon::clientBySerial(uint64_t serial) {
  for (auto& [fd, c] : clients_)
    if (c.serial == serial && !c.dead) return &c;
  return nullptr;
}

// ------------------------------------------------------------- library ----

void Daemon::rescan() {
  scanned_.clear();
  std::string h = home();
  for (auto&& g : scanSteam(h)) scanned_.push_back(std::move(g));
  for (auto&& g : scanHeroic(h)) scanned_.push_back(std::move(g));
  for (auto&& g : scanLutris(h)) scanned_.push_back(std::move(g));
  runners_ = scanRunners(h, dataDir());
}

std::vector<Game> Daemon::allGames() const {
  std::vector<Game> out = scanned_;
  for (auto& l : store_.locals) {
    Game g;
    g.id = l.id;
    g.source = "local";
    g.title = l.title;
    g.cover = l.cover;
    g.settings = l.settings;
    out.push_back(std::move(g));
  }
  for (auto& g : out) {
    auto it = store_.meta.find(g.id);
    if (it != store_.meta.end()) {
      g.favorite = it->second.favorite;
      g.hidden = it->second.hidden;
      g.playtimeMinutes += it->second.playedSeconds / 60;
      if (it->second.lastPlayed && (!g.lastPlayed || *it->second.lastPlayed > *g.lastPlayed))
        g.lastPlayed = it->second.lastPlayed;
    }
    g.profile = it != store_.meta.end() ? it->second.profile : Profile();
    if (watch_.isRunning(g.id)) {
      g.running = true;
      g.detected = true;
    }
    for (auto& [pid, r] : running_)
      if (r.gameId == g.id) {
        g.running = true;
        g.canStop = true;
      }
  }
  std::stable_sort(out.begin(), out.end(), [](const Game& a, const Game& b) { return lower(a.title) < lower(b.title); });
  return out;
}

std::optional<Game> Daemon::findGame(const std::string& id) const {
  for (auto& g : allGames())
    if (g.id == id) return g;
  return std::nullopt;
}

Json::Value Daemon::gamesJson() const {
  Json::Value arr(Json::arrayValue);
  for (auto& g : allGames()) arr.append(toJson(g));
  Json::Value r(Json::objectValue);
  r["games"] = arr;
  return r;
}

std::string Daemon::effectiveDefaultRunner() const {
  if (!store_.defaultRunner.empty())
    for (auto& r : runners_)
      if (r.id == store_.defaultRunner) return r.id;
  return pickDefaultRunner(runners_);
}

LaunchContext Daemon::launchContext() const {
  LaunchContext c;
  c.dataDir = dataDir();
  c.steamRoot = findSteamRoot(home());
  c.umuRun = !findInPath("umu-run").empty();
  c.runners = runners_;
  c.defaultRunner = effectiveDefaultRunner();
  return c;
}

// ------------------------------------------------------------ dispatch ----

static std::string reqString(const Json::Value& p, const char* key) {
  if (!p.isObject() || !p[key].isString() || p[key].asString().empty())
    throw RpcError{"bad_request", std::string("missing string param '") + key + "'"};
  return p[key].asString();
}

void Daemon::handleLine(Client& c, const std::string& line) {
  Json::Value req;
  if (!parseJson(line, req) || !req.isObject()) {
    replyError(c, Json::Value(Json::nullValue), "bad_request", "invalid JSON");
    return;
  }
  Json::Value id = req.isMember("id") ? req["id"] : Json::Value(Json::nullValue);
  if (!req["method"].isString()) {
    replyError(c, id, "bad_request", "missing method");
    return;
  }
  Json::Value params = req.isMember("params") ? req["params"] : emptyObj();
  if (params.isNull()) params = emptyObj();
  if (!params.isObject()) {
    replyError(c, id, "bad_request", "params must be an object");
    return;
  }
  try {
    Json::Value result = emptyObj();
    const std::string method = req["method"].asString();
    if (method == "runners.available") {
      methodAvailable(c, id);
      return;
    }
    if (method == "system.info") {
      methodSystemInfo(c, id);
      return;
    }
    if (!dispatch(c, method, params, result)) {
      replyError(c, id, "bad_request", "unknown method " + method);
      return;
    }
    reply(c, id, result);
  } catch (const RpcError& e) {
    replyError(c, id, e.code, e.message);
  } catch (const std::exception& e) {
    replyError(c, id, "internal", e.what());
  }
}

bool Daemon::dispatch(Client& c, const std::string& m, const Json::Value& p, Json::Value& r) {
  if (m == "hello") {
    r["protocol"] = 1;
    r["daemon"] = std::string("forge-gamed ") + FORGE_GAMED_VERSION;
  } else if (m == "ui.register") {
    c.isUI = true;
  } else if (m == "library.list") {
    r = gamesJson();
  } else if (m == "library.refresh") {
    rescan();
    r = gamesJson();
    broadcast("library.changed", emptyObj());
  } else if (m == "game.add") {
    methodGameAdd(p, r);
  } else if (m == "game.update") {
    methodGameUpdate(p, r);
  } else if (m == "game.remove") {
    methodGameRemove(p);
  } else if (m == "game.launch") {
    methodGameLaunch(p);
  } else if (m == "game.stop") {
    methodGameStop(p);
  } else if (m == "game.log") {
    methodGameLog(p, r);
  } else if (m == "runners.list") {
    runners_ = scanRunners(home(), dataDir());
    Json::Value arr(Json::arrayValue);
    for (auto& x : runners_) arr.append(toJson(x));
    r["runners"] = arr;
    std::string d = effectiveDefaultRunner();
    r["default"] = d.empty() ? Json::Value(Json::nullValue) : Json::Value(d);
  } else if (m == "runners.setDefault") {
    std::string id = reqString(p, "id");
    runners_ = scanRunners(home(), dataDir());
    if (std::none_of(runners_.begin(), runners_.end(), [&](const Runner& x) { return x.id == id; }))
      throw RpcError{"not_found", "no runner " + id};
    store_.defaultRunner = id;
    if (!store_.saveSettings()) throw RpcError{"io", "cannot write settings.json"};
  } else if (m == "runners.install") {
    methodRunnersInstall(p);
  } else if (m == "runners.remove") {
    methodRunnersRemove(p);
  } else if (m == "pads.list") {
    Json::Value arr(Json::arrayValue);
    for (auto& x : pads_.list()) arr.append(toJson(x));
    r["pads"] = arr;
  } else if (m == "pad.rumble") {
    methodRumble(p);
  } else {
    return false;
  }
  return true;
}

// --------------------------------------------------------- game methods ----

void Daemon::methodGameAdd(const Json::Value& p, Json::Value& r) {
  std::string title = reqString(p, "title");
  GameSettings s;
  std::string err;
  if (!settingsFromJson(p["settings"], s, err)) throw RpcError{"bad_request", err};
  LocalGame g;
  g.id = newLocalId();
  g.title = title;
  if (p["cover"].isString() && !p["cover"].asString().empty()) g.cover = p["cover"].asString();
  else if (!p["cover"].isNull() && p.isMember("cover")) throw RpcError{"bad_request", "cover must be a string or null"};
  g.settings = s;
  store_.locals.push_back(g);
  if (!store_.saveLibrary()) {
    store_.locals.pop_back();
    throw RpcError{"io", "cannot write library.json"};
  }
  r["game"] = toJson(*findGame(g.id));
  broadcast("library.changed", emptyObj());
}

void Daemon::methodGameUpdate(const Json::Value& p, Json::Value& r) {
  std::string id = reqString(p, "id");
  auto game = findGame(id);
  if (!game) throw RpcError{"not_found", "no game " + id};
  bool local = game->source == "local";
  bool localOnly = p.isMember("title") || p.isMember("cover") || p.isMember("settings");
  if (localOnly && !local) throw RpcError{"not_local", "title, cover and settings can only be changed on local games"};
  Store backup = store_;
  if (local) {
    LocalGame* lg = store_.findLocal(id);
    if (p.isMember("title")) {
      if (!p["title"].isString() || p["title"].asString().empty()) throw RpcError{"bad_request", "title must be a non-empty string"};
      lg->title = p["title"].asString();
    }
    if (p.isMember("cover")) {
      if (p["cover"].isNull() || (p["cover"].isString() && p["cover"].asString().empty())) lg->cover.reset();
      else if (p["cover"].isString()) lg->cover = p["cover"].asString();
      else throw RpcError{"bad_request", "cover must be a string or null"};
    }
    if (p.isMember("settings")) {
      std::string err;
      GameSettings s;
      if (!settingsFromJson(p["settings"], s, err)) throw RpcError{"bad_request", err};
      lg->settings = s;
    }
  }
  if (p.isMember("favorite")) {
    if (!p["favorite"].isBool()) throw RpcError{"bad_request", "favorite must be a boolean"};
    store_.meta[id].favorite = p["favorite"].asBool();
  }
  if (p.isMember("hidden")) {
    if (!p["hidden"].isBool()) throw RpcError{"bad_request", "hidden must be a boolean"};
    store_.meta[id].hidden = p["hidden"].asBool();
  }
  if (p.isMember("profile")) {
    const Json::Value& pr = p["profile"];
    if (!pr.isObject()) throw RpcError{"bad_request", "profile must be an object"};
    Profile cur = store_.meta[id].profile;
    if (pr.isMember("thermal")) {
      const Json::Value& t = pr["thermal"];
      if (t.isNull() || (t.isString() && t.asString().empty())) {
        cur.thermal.reset();
      } else if (t.isString()) {
        // Checked against forged's list when we know it; otherwise any name passes.
        if (haveSysState_ && sysState_.thermalAvailable && !sysState_.profiles.empty() &&
            std::find(sysState_.profiles.begin(), sysState_.profiles.end(), t.asString()) == sysState_.profiles.end())
          throw RpcError{"bad_request", "unknown thermal profile " + t.asString()};
        cur.thermal = t.asString();
      } else {
        throw RpcError{"bad_request", "profile.thermal must be a string or null"};
      }
    }
    if (pr.isMember("quiet")) {
      if (!pr["quiet"].isBool()) throw RpcError{"bad_request", "profile.quiet must be a boolean"};
      cur.quiet = pr["quiet"].asBool();
    }
    store_.meta[id].profile = cur;
  }
  if (!store_.saveLibrary()) {
    store_ = backup;
    throw RpcError{"io", "cannot write library.json"};
  }
  r["game"] = toJson(*findGame(id));
  broadcast("library.changed", emptyObj());
}

void Daemon::methodGameRemove(const Json::Value& p) {
  std::string id = reqString(p, "id");
  auto game = findGame(id);
  if (!game) throw RpcError{"not_found", "no game " + id};
  if (game->source != "local") throw RpcError{"not_local", "only local games can be removed"};
  if (game->running) throw RpcError{"already_running", "stop the game first"};
  auto& v = store_.locals;
  v.erase(std::remove_if(v.begin(), v.end(), [&](const LocalGame& g) { return g.id == id; }), v.end());
  store_.meta.erase(id);
  if (!store_.saveLibrary()) throw RpcError{"io", "cannot write library.json"};
  broadcast("library.changed", emptyObj());
}

void Daemon::methodGameLaunch(const Json::Value& p) {
  std::string id = reqString(p, "id");
  auto game = findGame(id);
  if (!game) throw RpcError{"not_found", "no game " + id};
  if (game->running) throw RpcError{"already_running", id + " is already running"};
  LaunchSpec spec;
  std::string err;
  // A launch that fails here is answered with the error; game.failed is for
  // games that die after starting.
  if (!buildLaunch(*game, launchContext(), spec, err)) {
    throw RpcError{"launch_failed", err};
  }
  std::string logPath = logDir() + "/" + logFileName(id);
  SpawnResult sr = spawnProcess(spec, logPath, !spec.tracked);
  if (!sr.ok) {
    throw RpcError{"launch_failed", sr.error};
  }
  store_.meta[id].lastPlayed = unixNow();
  store_.saveLibrary();
  if (spec.tracked) {
    Running run;
    run.gameId = id;
    run.startMono = monoMs();
    running_[sr.pid] = run;
  }
  Json::Value d = emptyObj();
  d["id"] = id;
  d["tracked"] = spec.tracked;
  d["detected"] = false;
  broadcast("game.started", d);
  if (spec.tracked) applyProfile(id);
}

void Daemon::methodGameStop(const Json::Value& p) {
  std::string id = reqString(p, "id");
  for (auto& [pid, r] : running_) {
    if (r.gameId != id) continue;
    r.stopRequested = true;
    if (r.killAt == 0) r.killAt = monoMs() + 5000;
    ::killpg(pid, SIGTERM);
    return;
  }
  if (!findGame(id)) throw RpcError{"not_found", "no game " + id};
  throw RpcError{"not_found", id + " is not running"};
}

void Daemon::methodGameLog(const Json::Value& p, Json::Value& r) {
  std::string id = reqString(p, "id");
  if (!findGame(id)) throw RpcError{"not_found", "no game " + id};
  std::string text;
  readFile(logDir() + "/" + logFileName(id), text);
  constexpr size_t kMax = 64 * 1024;
  if (text.size() > kMax) text = text.substr(text.size() - kMax);
  r["text"] = sanitizeUtf8(text);
}

// ------------------------------------------------------------ processes ----

void Daemon::reapChildren() {
  std::vector<pid_t> pids;
  for (auto& [pid, r] : running_) pids.push_back(pid);
  for (pid_t pid : pids) {
    int status = 0;
    pid_t w = ::waitpid(pid, &status, WNOHANG);
    if (w == pid) onGameExit(pid, status);
    else if (w < 0 && errno == ECHILD) onGameExit(pid, 0);
  }
}

void Daemon::onGameExit(pid_t pid, int status) {
  auto it = running_.find(pid);
  if (it == running_.end()) return;
  Running r = it->second;
  running_.erase(it);
  // The leader is gone, but members that ignored SIGTERM (wineserver, a
  // launcher script's children) may not be: finish the stop now rather than
  // forgetting them with the timer.
  if (r.stopRequested) ::killpg(pid, SIGKILL);
  int64_t played = std::max<int64_t>(0, (monoMs() - r.startMono + 500) / 1000);
  int code = WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : 0;
  Meta& m = store_.meta[r.gameId];
  m.playedSeconds += played;
  m.lastPlayed = unixNow();
  store_.saveLibrary();
  Json::Value d = emptyObj();
  d["id"] = r.gameId;
  d["exitCode"] = code;
  d["playedSeconds"] = Json::Int64(played);
  broadcast("game.stopped", d);
  if (code != 0 && !r.stopRequested && played < 3) {
    Json::Value f = emptyObj();
    f["id"] = r.gameId;
    f["message"] = "exited with code " + std::to_string(code) + " after " + std::to_string(played) + " s";
    broadcast("game.failed", f);
  }
  broadcast("library.changed", emptyObj());
  releaseProfile(r.gameId);
}

void Daemon::checkKillTimers() {
  int64_t now = monoMs();
  for (auto& [pid, r] : running_) {
    if (r.killAt > 0 && now >= r.killAt) {
      ::killpg(pid, SIGKILL);
      r.killAt = 0;
    }
  }
}

// ----------------------------------------------------------------- pads ----

void Daemon::spawnUi() {
  int64_t now = monoMs();
  if (lastUiSpawn_ != 0 && now - lastUiSpawn_ < 3000) return;
  lastUiSpawn_ = now;
  LaunchSpec spec;
  const char* bin = std::getenv("FORGE_GAMING_BIN");
  spec.argv = splitArgs(bin && *bin ? bin : "forge-gaming");
  if (spec.argv.empty()) spec.argv = {"forge-gaming"};
  spec.argv.push_back("--couch");
  SpawnResult sr = spawnProcess(spec, "", true);
  if (!sr.ok) std::cerr << "forge-gamed: cannot start the UI: " << sr.error << "\n";
}

void Daemon::pumpPads() {
  if (!padsOk_) return;
  std::vector<PadEvent> evs;
  pads_.poll(monoMs(), evs);
  for (auto& e : evs) {
    Json::Value d = emptyObj();
    switch (e.kind) {
      case PadEvent::Connected:
        d["pad"] = toJson(e.pad);
        broadcast("pad.connected", d);
        break;
      case PadEvent::Disconnected:
        d["index"] = e.index;
        broadcast("pad.disconnected", d);
        break;
      case PadEvent::Button:
        d["pad"] = e.index;
        d["button"] = e.button;
        d["pressed"] = e.pressed;
        d["repeat"] = e.repeat;
        broadcast("pad.button", d);
        if (e.button == "guide" && e.pressed && !e.repeat) {
          bool ui = std::any_of(clients_.begin(), clients_.end(), [](auto& kv) { return kv.second.isUI && !kv.second.dead; });
          if (!ui) spawnUi();
        }
        break;
    }
  }
}

void Daemon::methodRumble(const Json::Value& p) {
  if (!p["strength"].isNumeric()) throw RpcError{"bad_request", "strength must be a number"};
  if (!p["ms"].isNumeric()) throw RpcError{"bad_request", "ms must be a number"};
  double s = p["strength"].asDouble();
  double ms = p["ms"].asDouble();
  if (s < 0 || s > 1 || ms < 1 || ms > 2000) throw RpcError{"bad_request", "strength 0..1 and ms 1..2000 required"};
  int index = -1;
  if (p.isMember("index") && !p["index"].isNull()) {
    if (!p["index"].isInt()) throw RpcError{"bad_request", "index must be an integer"};
    index = p["index"].asInt();
  }
  pads_.rumble(static_cast<float>(s), static_cast<int>(ms), index);
}

// -------------------------------------------------------------- runners ----

void Daemon::methodAvailable(Client& c, const Json::Value& id) {
  uint64_t serial = c.serial;
  startWorker([this, serial, id]() {
    std::string body, err;
    bool ok = httpGet(kReleasesUrl, body, 10, err);
    std::vector<Release> rel;
    if (ok) rel = parseReleases(body, 10);
    postMain([this, serial, id, ok, err, rel]() {
      Client* cl = clientBySerial(serial);
      if (ok) releases_ = rel;
      if (!cl) return;
      if (!ok) {
        replyError(*cl, id, "network", "cannot fetch GE-Proton releases: " + err);
        return;
      }
      runners_ = scanRunners(home(), dataDir());
      Json::Value arr(Json::arrayValue);
      for (auto& r : rel) {
        Json::Value o = emptyObj();
        o["name"] = r.name;
        o["url"] = r.url;
        o["size"] = Json::Int64(r.size);
        o["installed"] = std::any_of(runners_.begin(), runners_.end(), [&](const Runner& x) {
          return x.source == "forge" && (x.name == r.name || startsWith(x.name, r.name + "-"));
        });
        arr.append(o);
      }
      Json::Value res = emptyObj();
      res["releases"] = arr;
      reply(*cl, id, res);
    });
  });
}

void Daemon::methodRunnersInstall(const Json::Value& p) {
  std::string name = reqString(p, "name");
  if (!validRunnerName(name)) throw RpcError{"bad_request", "invalid runner name"};
  if (installing_.count(name)) throw RpcError{"already_running", name + " is already being installed"};
  runners_ = scanRunners(home(), dataDir());
  for (auto& r : runners_)
    if (r.source == "forge" && r.name == name) {
      Json::Value d = emptyObj();
      d["name"] = name;
      d["runner"] = toJson(r);
      broadcast("runner.installed", d);
      return;
    }
  installing_.insert(name);
  std::vector<Release> cached = releases_;
  startWorker([this, name, cached]() {
    auto fail = [&](const std::string& msg) {
      postMain([this, name, msg]() {
        installing_.erase(name);
        Json::Value d = emptyObj();
        d["name"] = name;
        d["message"] = msg;
        broadcast("runner.failed", d);
      });
    };
    std::string url;
    int64_t size = 0;
    for (auto& r : cached)
      if (r.name == name) { url = r.url; size = r.size; }
    if (url.empty()) {
      std::string body, err;
      if (!httpGet(kReleasesUrl, body, 10, err)) return fail("cannot fetch release list: " + err);
      for (auto& r : parseReleases(body, 10))
        if (r.name == name) { url = r.url; size = r.size; }
    }
    if (url.empty()) return fail("no GE-Proton release named " + name);
    std::string rdir = dataDir() + "/runners";
    std::string tmp = rdir + "/.download/" + name + ".tar.gz";
    std::string err;
    bool ok = downloadFile(url, tmp, [&](int64_t got, int64_t total) {
      postMain([this, name, got, total, size]() {
        Json::Value d = emptyObj();
        d["name"] = name;
        d["received"] = Json::Int64(got);
        d["total"] = Json::Int64(total > 0 ? total : size);
        broadcast("runner.progress", d);
      });
    }, cancel_, err);
    if (!ok) return fail("download failed: " + err);
    if (!extractTarGz(tmp, rdir, err)) {
      ::unlink(tmp.c_str());
      return fail("extract failed: " + err);
    }
    ::unlink(tmp.c_str());
    postMain([this, name]() {
      installing_.erase(name);
      runners_ = scanRunners(home(), dataDir());
      for (auto& r : runners_)
        if (r.source == "forge" && (r.name == name || startsWith(r.name, name + "-"))) {
          Json::Value d = emptyObj();
          d["name"] = name;
          d["runner"] = toJson(r);
          broadcast("runner.installed", d);
          return;
        }
      Json::Value d = emptyObj();
      d["name"] = name;
      d["message"] = "archive extracted but no runner was found in it";
      broadcast("runner.failed", d);
    });
  });
}

void Daemon::methodRunnersRemove(const Json::Value& p) {
  std::string id = reqString(p, "id");
  if (!startsWith(id, "forge:")) throw RpcError{"bad_request", "only forge: runners can be removed"};
  runners_ = scanRunners(home(), dataDir());
  for (auto& r : runners_) {
    if (r.id != id) continue;
    std::error_code ec;
    fs::path rp = fs::weakly_canonical(r.path, ec);
    fs::path base = fs::weakly_canonical(dataDir() + "/runners", ec);
    if (ec || rp.parent_path() != base) throw RpcError{"internal", "refusing to remove " + r.path};
    fs::remove_all(rp, ec);
    if (ec) throw RpcError{"io", "cannot remove " + r.path + ": " + ec.message()};
    if (store_.defaultRunner == id) {
      store_.defaultRunner.clear();
      store_.saveSettings();
    }
    runners_ = scanRunners(home(), dataDir());
    return;
  }
  throw RpcError{"not_found", "no runner " + id};
}

}  // namespace fg

namespace fg {

// ------------------------------------------------- forged: profiles, info ----

void Daemon::enqueueForged(std::function<void()> fn) {
  {
    std::lock_guard<std::mutex> lk(fmu_);
    if (fstop_) return;
    fq_.push_back(std::move(fn));
    if (!forgedThread_.joinable()) {
      forgedThread_ = std::thread([this]() {
        for (;;) {
          std::function<void()> job;
          {
            std::unique_lock<std::mutex> lk(fmu_);
            fcv_.wait(lk, [&] { return !fq_.empty() || fstop_; });
            if (fq_.empty()) return;  // stopped and drained
            job = std::move(fq_.front());
            fq_.pop_front();
          }
          job();
        }
      });
    }
  }
  fcv_.notify_one();
}

// Restores anything still held, then ends the worker (queued jobs run first).
void Daemon::stopForgedWorker() {
  {
    std::lock_guard<std::mutex> lk(fmu_);
    if (fstop_) return;
    // Runs on the worker, after every queued start/stop.
    fq_.push_back([this]() { execPlan(holds_.stopAll()); });
    fstop_ = true;
    if (!forgedThread_.joinable()) {
      // Nothing was ever queued: nothing can be held.
      fq_.clear();
      return;
    }
  }
  fcv_.notify_all();
  forgedThread_.join();
}

void Daemon::applyProfile(const std::string& id) {
  auto it = store_.meta.find(id);
  if (it == store_.meta.end()) return;
  Profile p = it->second.profile;
  if (!p.thermal && !p.quiet) return;
  enqueueForged([this, id, p]() {
    ForgedState st = readForgedState();
    execPlan(holds_.start(id, p, st));
    postMain([this]() { sysInfoAt_ = 0; });
  });
}

void Daemon::releaseProfile(const std::string& id) {
  enqueueForged([this, id]() {
    HoldPlan plan = holds_.stop(id);
    if (plan.empty()) return;
    execPlan(plan);
    postMain([this]() { sysInfoAt_ = 0; });
  });
}

void Daemon::methodSystemInfo(Client& c, const Json::Value& id) {
  if (sysInfoAt_ != 0 && monoMs() - sysInfoAt_ < 10000) {
    reply(c, id, systemInfoJson(sysState_));
    return;
  }
  sysInfoWaiters_.emplace_back(c.serial, id);
  if (sysInfoPending_) return;
  sysInfoPending_ = true;
  enqueueForged([this]() {
    ForgedState st = readForgedState();
    postMain([this, st]() {
      sysState_ = st;
      haveSysState_ = true;
      sysInfoAt_ = monoMs();
      sysInfoPending_ = false;
      auto waiters = std::move(sysInfoWaiters_);
      sysInfoWaiters_.clear();
      for (auto& [serial, rid] : waiters)
        if (Client* cl = clientBySerial(serial)) reply(*cl, rid, systemInfoJson(st));
    });
  });
}

// ------------------------------------------------------------- watcher ----

void Daemon::watchTick() {
  nextWatch_ = monoMs() + 2000;
  std::vector<Game> cand;
  for (auto& g : scanned_) cand.push_back(g);
  if (cand.empty() && watch_.running().empty()) return;
  std::set<std::string> found = matchRunning(readProcessList(), cand);
  // Games launched here are tracked by pid already.
  for (auto& [pid, r] : running_) found.erase(r.gameId);
  auto ch = watch_.update(found);
  for (auto& id : ch.started) onDetectedStart(id);
  for (auto& id : ch.stopped) onDetectedStop(id);
}

void Daemon::onDetectedStart(const std::string& id) {
  detectedStart_[id] = monoMs();
  if (!startsWith(id, "lutris:")) {
    store_.meta[id].lastPlayed = unixNow();
    store_.saveLibrary();
  }
  Json::Value d = emptyObj();
  d["id"] = id;
  d["tracked"] = true;
  d["detected"] = true;
  broadcast("game.started", d);
  broadcast("library.changed", emptyObj());
  applyProfile(id);
}

void Daemon::onDetectedStop(const std::string& id) {
  int64_t played = 0;
  auto it = detectedStart_.find(id);
  if (it != detectedStart_.end()) {
    played = std::max<int64_t>(0, (monoMs() - it->second + 500) / 1000);
    detectedStart_.erase(it);
  }
  if (startsWith(id, "lutris:")) {
    rescan();  // Lutris counts its own play time; read it back from pga.db
  } else {
    Meta& m = store_.meta[id];
    m.playedSeconds += played;
    m.lastPlayed = unixNow();
    store_.saveLibrary();
  }
  Json::Value d = emptyObj();
  d["id"] = id;
  d["exitCode"] = 0;
  d["playedSeconds"] = Json::Int64(played);
  broadcast("game.stopped", d);
  broadcast("library.changed", emptyObj());
  releaseProfile(id);
}

}  // namespace fg
