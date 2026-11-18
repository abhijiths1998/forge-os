#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include <json/json.h>

namespace fg {

// Splits like a POSIX shell: whitespace separated, '...' literal, "..." with
// \" \\ \$ \` escapes, backslash outside quotes escapes the next character.
std::vector<std::string> splitArgs(const std::string& s);

std::string home();           // $HOME
std::string dataDir();        // ~/.local/share/forge-gaming
std::string stateDir();       // ~/.local/state/forge-gaming
std::string logDir();         // <stateDir>/logs
std::string socketPath();     // $XDG_RUNTIME_DIR/forge-gamed.sock

// "local:abc" -> "local_abc" (also strips '/').
std::string sanitizeId(const std::string& id);
std::string logFileName(const std::string& id);   // sanitizeId + ".log"

bool readFile(const std::string& path, std::string& out);
// Writes <path>.tmp then rename()s it over <path>. Creates parent dirs.
bool writeFileAtomic(const std::string& path, const std::string& data);
bool mkdirs(const std::string& path);

std::string lower(std::string s);
bool endsWith(const std::string& s, const std::string& suffix);
bool startsWith(const std::string& s, const std::string& prefix);
// Compares digit runs numerically: "GE-Proton9-2" < "GE-Proton10-1".
int naturalCompare(const std::string& a, const std::string& b);

bool parseJson(const std::string& text, Json::Value& out);
std::string toLine(const Json::Value& v);   // compact, no trailing newline
std::string percentEncode(const std::string& s);

int64_t unixNow();
int64_t monoMs();
std::string findInPath(const std::string& name);   // "" if not found
bool isDir(const std::string& p);
bool isFile(const std::string& p);
bool isExecutable(const std::string& p);

// Defensive JSON readers: wrong type or missing -> default, never throw.
std::string jstr(const Json::Value& v, const char* key, const std::string& def = "");
bool jbool(const Json::Value& v, const char* key, bool def = false);
int64_t jint(const Json::Value& v, const char* key, int64_t def = 0);

}  // namespace fg
