#include "store.hpp"

#include "util.hpp"

namespace fg {

void Store::load() {
  locals.clear();
  meta.clear();
  defaultRunner.clear();
  std::string text;
  Json::Value root;
  if (readFile(dir_ + "/library.json", text) && parseJson(text, root) && root.isObject()) {
    for (const auto& g : root["local"]) {
      if (!g.isObject() || jstr(g, "id").empty()) continue;
      LocalGame lg;
      lg.id = jstr(g, "id");
      lg.title = jstr(g, "title", lg.id);
      if (g["cover"].isString() && !g["cover"].asString().empty()) lg.cover = g["cover"].asString();
      lg.settings = settingsFromStored(g["settings"]);
      locals.push_back(std::move(lg));
    }
    const Json::Value& m = root["meta"];
    if (m.isObject()) {
      for (auto& id : m.getMemberNames()) {
        Meta mm;
        mm.favorite = jbool(m[id], "favorite");
        mm.hidden = jbool(m[id], "hidden");
        mm.playedSeconds = jint(m[id], "playedSeconds");
        if (m[id]["lastPlayed"].isIntegral()) mm.lastPlayed = m[id]["lastPlayed"].asInt64();
        meta[id] = mm;
      }
    }
  }
  text.clear();
  root = Json::Value();
  if (readFile(dir_ + "/settings.json", text) && parseJson(text, root))
    defaultRunner = jstr(root, "defaultRunner");
}

bool Store::saveLibrary() const {
  Json::Value root(Json::objectValue);
  root["version"] = 1;
  Json::Value arr(Json::arrayValue);
  for (auto& g : locals) {
    Json::Value o(Json::objectValue);
    o["id"] = g.id;
    o["title"] = g.title;
    o["cover"] = g.cover ? Json::Value(*g.cover) : Json::Value(Json::nullValue);
    o["settings"] = toJson(g.settings);
    arr.append(o);
  }
  root["local"] = arr;
  Json::Value m(Json::objectValue);
  for (auto& [id, mm] : meta) {
    Json::Value o(Json::objectValue);
    o["favorite"] = mm.favorite;
    o["hidden"] = mm.hidden;
    o["playedSeconds"] = Json::Int64(mm.playedSeconds);
    o["lastPlayed"] = mm.lastPlayed ? Json::Value(Json::Int64(*mm.lastPlayed)) : Json::Value(Json::nullValue);
    m[id] = o;
  }
  root["meta"] = m;
  Json::StreamWriterBuilder b;
  b["indentation"] = "  ";
  b["emitUTF8"] = true;
  return writeFileAtomic(dir_ + "/library.json", Json::writeString(b, root) + "\n");
}

bool Store::saveSettings() const {
  Json::Value root(Json::objectValue);
  root["defaultRunner"] = defaultRunner.empty() ? Json::Value(Json::nullValue) : Json::Value(defaultRunner);
  Json::StreamWriterBuilder b;
  b["indentation"] = "  ";
  return writeFileAtomic(dir_ + "/settings.json", Json::writeString(b, root) + "\n");
}

LocalGame* Store::findLocal(const std::string& id) {
  for (auto& g : locals)
    if (g.id == id) return &g;
  return nullptr;
}

std::string newLocalId() {
  std::string u;
  if (readFile("/proc/sys/kernel/random/uuid", u)) {
    while (!u.empty() && (u.back() == '\n' || u.back() == ' ')) u.pop_back();
    if (u.size() >= 32) return "local:" + u;
  }
  return "local:" + std::to_string(unixNow()) + "-" + std::to_string(monoMs());
}

}  // namespace fg
