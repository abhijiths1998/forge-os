#pragma once
#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "model.hpp"

namespace fg {

// "proton" if the directory has a `proton` script, "wine" if bin/wine, else "".
std::string classifyRunnerDir(const std::string& dir);
std::vector<Runner> scanRunners(const std::string& home, const std::string& dataDir);
// Newest GE-Proton (natural order), else newest proton, else first wine, else "".
std::string pickDefaultRunner(const std::vector<Runner>& runners);

struct Release {
  std::string name, url;
  int64_t size = 0;
};
// GitHub releases JSON -> releases that have a .tar.gz asset (newest first).
std::vector<Release> parseReleases(const std::string& json, size_t max);
bool validRunnerName(const std::string& name);

// libcurl helpers (blocking; call from a worker thread).
bool httpGet(const std::string& url, std::string& body, int timeoutSec, std::string& err);
bool downloadFile(const std::string& url, const std::string& dest,
                  const std::function<void(int64_t received, int64_t total)>& progress,
                  const std::atomic<bool>& cancel, std::string& err);
bool extractTarGz(const std::string& file, const std::string& destDir, std::string& err);

constexpr const char* kReleasesUrl =
    "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=10";

}  // namespace fg
