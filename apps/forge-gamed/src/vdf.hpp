#pragma once
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace fg {

// Valve KeyValues (VDF / ACF). Keys are matched case-insensitively.
struct VdfNode {
  std::string value;
  bool isObject = false;
  std::vector<std::pair<std::string, VdfNode>> kids;

  const VdfNode* find(const std::string& key) const;
  std::string str(const std::string& key, const std::string& def = "") const;
};

// Returns the implicit root object holding the top-level pairs; nullopt on
// malformed input.
std::optional<VdfNode> parseVdf(const std::string& text);

}  // namespace fg
