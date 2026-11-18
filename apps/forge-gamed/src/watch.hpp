#pragma once
#include <map>
#include <set>
#include <string>
#include <vector>

#include "model.hpp"

namespace fg {

// One process as seen in /proc: its pid and NUL-separated argv.
struct ProcInfo {
  int pid = 0;
  std::vector<std::string> argv;
};

// "Z:\Games\Foo\X.EXE" -> "/games/foo/x.exe": `\` becomes `/`, a leading
// `z:` is dropped, lower case, doubled and trailing slashes removed.
std::string normalizeGamePath(const std::string& s);

// True for Steam, Heroic and Lutris themselves (not lutris-wrapper): argv[0]
// or the script argument (argv[1]) has a launcher's name.
bool isLauncherProcess(const ProcInfo& p);

// Ids of the games (steam, heroic, lutris) that some process shows to be
// running. Local games are ignored. Pure.
std::set<std::string> matchRunning(const std::vector<ProcInfo>& procs, const std::vector<Game>& games);

// "Missing from two scans in a row" rule: a game is started the first time it
// is seen and stopped after two consecutive scans without it.
class WatchState {
 public:
  struct Changes {
    std::vector<std::string> started, stopped;
  };
  Changes update(const std::set<std::string>& found);
  const std::set<std::string>& running() const { return running_; }
  bool isRunning(const std::string& id) const { return running_.count(id) > 0; }

 private:
  std::set<std::string> running_;
  std::map<std::string, int> missing_;
};

// Reads /proc/<pid>/cmdline of every process (unreadable and empty ones, such
// as kernel threads, are skipped; nothing is followed).
std::vector<ProcInfo> readProcessList();

}  // namespace fg
