#include "bookmarks.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>

#include <algorithm>

namespace {

constexpr int kMaxHistory = 5000;

QString dataPath(const QString& file) {
  const QString dir =
      QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  QDir().mkpath(dir);
  return dir + "/" + file;
}

}  // namespace

Store* Store::instance() {
  static Store* store = new Store;
  return store;
}

Store::Store() {
  bookmarks_ = load("bookmarks.json");
  history_ = load("history.json");
}

QList<Entry> Store::load(const QString& file) const {
  QList<Entry> out;
  QFile f(dataPath(file));
  if (!f.open(QIODevice::ReadOnly)) return out;
  for (const auto& v : QJsonDocument::fromJson(f.readAll()).array()) {
    const auto o = v.toObject();
    out.append({o["title"].toString(), QUrl(o["url"].toString()),
                o["visits"].toInt(),
                QDateTime::fromString(o["last"].toString(), Qt::ISODate)});
  }
  return out;
}

void Store::save(const QString& file, const QList<Entry>& entries) const {
  QJsonArray a;
  for (const auto& e : entries) {
    a.append(QJsonObject{{"title", e.title},
                         {"url", e.url.toString()},
                         {"visits", e.visits},
                         {"last", e.last.toString(Qt::ISODate)}});
  }
  QSaveFile f(dataPath(file));
  if (f.open(QIODevice::WriteOnly)) {
    f.write(QJsonDocument(a).toJson(QJsonDocument::Compact));
    f.commit();
  }
}

bool Store::isBookmarked(const QUrl& url) const {
  return std::any_of(bookmarks_.begin(), bookmarks_.end(),
                     [&](const Entry& e) { return e.url == url; });
}

void Store::toggleBookmark(const QString& title, const QUrl& url) {
  const auto it = std::find_if(bookmarks_.begin(), bookmarks_.end(),
                               [&](const Entry& e) { return e.url == url; });
  if (it != bookmarks_.end()) {
    bookmarks_.erase(it);
  } else {
    bookmarks_.append({title.isEmpty() ? url.host() : title, url, 0,
                       QDateTime::currentDateTime()});
  }
  save("bookmarks.json", bookmarks_);
  emit bookmarksChanged();
}

void Store::recordVisit(const QString& title, const QUrl& url) {
  if (url.scheme() != "http" && url.scheme() != "https") return;
  const auto it = std::find_if(history_.begin(), history_.end(),
                               [&](const Entry& e) { return e.url == url; });
  if (it != history_.end()) {
    it->visits++;
    it->last = QDateTime::currentDateTime();
    if (!title.isEmpty()) it->title = title;
  } else {
    history_.append({title, url, 1, QDateTime::currentDateTime()});
    if (history_.size() > kMaxHistory) {
      // Drop the oldest.
      std::sort(history_.begin(), history_.end(),
                [](const Entry& a, const Entry& b) { return a.last > b.last; });
      history_.resize(kMaxHistory);
    }
  }
  saveHistorySoon();
}

void Store::saveHistorySoon() {
  if (history_dirty_) return;
  history_dirty_ = true;
  QTimer::singleShot(5000, this, [this] {
    history_dirty_ = false;
    save("history.json", history_);
  });
}

QList<Entry> Store::suggest(const QString& text, int limit) const {
  const QString t = text.trimmed().toLower();
  if (t.isEmpty()) return {};
  QList<std::pair<double, Entry>> scored;
  for (const auto& e : history_ + bookmarks_) {
    const QString url = e.url.toString(QUrl::RemoveScheme).toLower();
    const QString host = e.url.host().toLower();
    double s = 0;
    if (host.startsWith(t) || host.startsWith("www." + t)) {
      s = 3;
    } else if (url.contains(t)) {
      s = 2;
    } else if (e.title.toLower().contains(t)) {
      s = 1;
    }
    if (s > 0) scored.append({s * 10 + std::min(e.visits, 50) / 5.0, e});
  }
  std::stable_sort(scored.begin(), scored.end(),
                   [](const auto& a, const auto& b) { return a.first > b.first; });
  QList<Entry> out;
  for (const auto& [score, e] : scored) {
    if (std::none_of(out.begin(), out.end(),
                     [&](const Entry& o) { return o.url == e.url; })) {
      out.append(e);
    }
    if (out.size() >= limit) break;
  }
  return out;
}

QList<Entry> Store::topSites(int limit) const {
  QList<Entry> sorted = history_;
  std::sort(sorted.begin(), sorted.end(),
            [](const Entry& a, const Entry& b) { return a.visits > b.visits; });
  // One per site; search results pages aren't sites anyone wants a tile for.
  QList<Entry> out;
  for (const auto& e : sorted) {
    if (e.url.host().endsWith("duckduckgo.com")) continue;
    if (std::none_of(out.begin(), out.end(), [&](const Entry& o) {
          return o.url.host() == e.url.host();
        })) {
      out.append({e.title, QUrl(e.url.scheme() + "://" + e.url.host()),
                  e.visits, e.last});
    }
    if (out.size() >= limit) break;
  }
  return out;
}

void Store::clearHistory() {
  history_.clear();
  save("history.json", history_);
}
