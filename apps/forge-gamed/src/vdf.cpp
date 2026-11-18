#include "vdf.hpp"

#include "util.hpp"

namespace fg {

const VdfNode* VdfNode::find(const std::string& key) const {
  std::string k = lower(key);
  for (auto& [name, node] : kids)
    if (lower(name) == k) return &node;
  return nullptr;
}

std::string VdfNode::str(const std::string& key, const std::string& def) const {
  const VdfNode* n = find(key);
  return (n && !n->isObject) ? n->value : def;
}

namespace {

struct Parser {
  const std::string& s;
  size_t i = 0;
  explicit Parser(const std::string& text) : s(text) {}

  void skipWs() {
    for (;;) {
      while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')) ++i;
      if (i + 1 < s.size() && s[i] == '/' && s[i + 1] == '/') {
        while (i < s.size() && s[i] != '\n') ++i;
      } else {
        break;
      }
    }
  }

  // Token kinds: 0 end, 1 string, 2 '{', 3 '}', -1 error
  int next(std::string& out) {
    skipWs();
    if (i >= s.size()) return 0;
    char c = s[i];
    if (c == '{') { ++i; return 2; }
    if (c == '}') { ++i; return 3; }
    out.clear();
    if (c == '"') {
      ++i;
      while (i < s.size() && s[i] != '"') {
        if (s[i] == '\\' && i + 1 < s.size()) {
          char e = s[i + 1];
          switch (e) {
            case 'n': out += '\n'; break;
            case 't': out += '\t'; break;
            case '\\': out += '\\'; break;
            case '"': out += '"'; break;
            default: out += '\\'; out += e; break;
          }
          i += 2;
        } else {
          out += s[i++];
        }
      }
      if (i >= s.size()) return -1;
      ++i;
      return 1;
    }
    // bare token
    while (i < s.size() && s[i] != ' ' && s[i] != '\t' && s[i] != '\r' && s[i] != '\n' &&
           s[i] != '{' && s[i] != '}' && s[i] != '"')
      out += s[i++];
    return out.empty() ? -1 : 1;
  }

  bool parseObject(VdfNode& obj, int depth, bool top) {
    if (depth > 64) return false;
    obj.isObject = true;
    for (;;) {
      std::string key;
      int t = next(key);
      if (t == 0) return top;
      if (t == 3) return !top;
      if (t != 1) return false;
      std::string val;
      int v = next(val);
      if (v == 1) {
        VdfNode n;
        n.value = val;
        obj.kids.emplace_back(key, std::move(n));
      } else if (v == 2) {
        VdfNode n;
        if (!parseObject(n, depth + 1, false)) return false;
        obj.kids.emplace_back(key, std::move(n));
      } else {
        return false;
      }
    }
  }
};

}  // namespace

std::optional<VdfNode> parseVdf(const std::string& text) {
  Parser p(text);
  VdfNode root;
  if (!p.parseObject(root, 0, true)) return std::nullopt;
  return root;
}

}  // namespace fg
