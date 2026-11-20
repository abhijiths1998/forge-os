#pragma once
#include <atomic>
#include <condition_variable>
#include <deque>
#include <cstdint>
#include <functional>
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "launch.hpp"
#include "model.hpp"
#include "pads.hpp"
#include "profile.hpp"
#include "runners.hpp"
#include "store.hpp"
#include "watch.hpp"

namespace fg {

struct RpcError {
  std::string code, message;
};

class Daemon {
 public:
  Daemon();
  ~Daemon();
  // Runs until SIGTERM/SIGINT. Returns the process exit code.
  int run();

 private:
  struct Client {
    int fd = -1;
    uint64_t serial = 0;
    std::string in, out;
    bool isUI = false;
    bool dead = false;
  };
  struct Running {
    std::string gameId;
    int64_t startMono = 0;
    int64_t killAt = 0;  // 0 = none
    bool stopRequested = false;
  };

  // setup / loop
  bool bindSocket(bool& alreadyRunning);
  void acceptClients();
  void readClient(Client& c);
  void flushClient(Client& c);
  void dropDead();
  void handleSignals();
  void drainMainQueue();

  // IPC
  void handleLine(Client& c, const std::string& line);
  bool dispatch(Client& c, const std::string& method, const Json::Value& params, Json::Value& result);
  void sendLine(Client& c, const Json::Value& v);
  void reply(Client& c, const Json::Value& id, const Json::Value& result);
  void replyError(Client& c, const Json::Value& id, const std::string& code, const std::string& msg);
  void broadcast(const std::string& event, const Json::Value& data);
  Client* clientBySerial(uint64_t serial);
  void postMain(std::function<void()> fn);
  void startWorker(std::function<void()> fn);

  // library
  void rescan();
  std::vector<Game> allGames() const;
  std::optional<Game> findGame(const std::string& id) const;
  Json::Value gamesJson() const;
  LaunchContext launchContext() const;
  std::string effectiveDefaultRunner() const;

  // methods
  void methodGameAdd(const Json::Value& p, Json::Value& r);
  void methodGameUpdate(const Json::Value& p, Json::Value& r);
  void methodGameRemove(const Json::Value& p);
  void methodGameLaunch(const Json::Value& p);
  void methodGameStop(const Json::Value& p);
  void methodGameLog(const Json::Value& p, Json::Value& r);
  void methodRunnersInstall(const Json::Value& p);
  void methodRunnersRemove(const Json::Value& p);
  void methodRumble(const Json::Value& p);
  void methodAvailable(Client& c, const Json::Value& id);
  void methodSystemInfo(Client& c, const Json::Value& id);

  // profiles (forged) and the watcher
  void enqueueForged(std::function<void()> fn);
  void stopForgedWorker();
  void applyProfile(const std::string& gameId);
  void recoverHolds();
  void releaseProfile(const std::string& gameId);
  void watchTick();
  void onDetectedStart(const std::string& id);
  void onDetectedStop(const std::string& id);

  // processes
  void reapChildren();
  void checkKillTimers();
  void onGameExit(pid_t pid, int status);

  // pads
  void pumpPads();
  void spawnUi();

  Store store_;
  Pads pads_;
  std::vector<Game> scanned_;
  std::vector<Runner> runners_;

  int listenFd_ = -1, sigFd_ = -1, evFd_ = -1;
  std::string sockPath_;
  std::map<int, Client> clients_;
  uint64_t nextSerial_ = 1;
  std::map<pid_t, Running> running_;
  bool padsOk_ = false;
  int64_t lastUiSpawn_ = 0;
  bool quit_ = false;

  std::mutex qmu_;
  std::vector<std::function<void()>> queue_;
  // Workers by id; each one is joined on the main thread once it finishes.
  std::map<uint64_t, std::thread> threads_;
  uint64_t nextWorker_ = 0;
  std::atomic<bool> cancel_{false};
  std::set<std::string> installing_;
  std::vector<Release> releases_;  // last fetched (main thread only)

  // watcher (main thread only)
  WatchState watch_;
  std::map<std::string, int64_t> detectedStart_;
  int64_t nextWatch_ = 0;

  // forged: one FIFO worker so starts, stops and state reads never race
  std::thread forgedThread_;
  std::mutex fmu_;
  std::condition_variable fcv_;
  std::deque<std::function<void()>> fq_;
  bool fstop_ = false;
  ProfileHolds holds_;  // forged worker only
  ForgedState sysState_;  // main thread only
  bool haveSysState_ = false;
  int64_t sysInfoAt_ = 0;
  bool sysInfoPending_ = false;
  std::vector<std::pair<uint64_t, Json::Value>> sysInfoWaiters_;
};

std::string sanitizeUtf8(const std::string& s);

}  // namespace fg
