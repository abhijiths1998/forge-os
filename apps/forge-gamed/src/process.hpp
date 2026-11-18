#pragma once
#include <string>
#include <sys/types.h>

#include "launch.hpp"

namespace fg {

struct SpawnResult {
  bool ok = false;
  pid_t pid = 0;      // 0 for detached spawns
  std::string error;
};

// tracked: single fork, setsid (pid == process group id), stdout/stderr to
// logPath. detached: double fork + setsid so nothing is left to reap.
SpawnResult spawnProcess(const LaunchSpec& spec, const std::string& logPath, bool detached);

}  // namespace fg
