#pragma once
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "model.hpp"

namespace fg {

struct Meta {
  bool favorite = false, hidden = false;
  int64_t playedSeconds = 0;  // tracked by forge-gamed
  std::optional<int64_t> lastPlayed;
};

struct LocalGame {
  std::string id, title;
  std::optional<std::string> cover;
  GameSettings settings;
};

// library.json + settings.json under dataDir.
class Store {
 public:
  explicit Store(std::string dataDir) : dir_(std::move(dataDir)) {}
  void load();
  bool saveLibrary() const;
  bool saveSettings() const;

  std::vector<LocalGame> locals;
  std::map<std::string, Meta> meta;
  std::string defaultRunner;

  LocalGame* findLocal(const std::string& id);

 private:
  std::string dir_;
};

std::string newLocalId();

}  // namespace fg
