// Bookmarks and history, kept as JSON in ~/.local/share/forge-browser.
#pragma once

#include <QDateTime>
#include <QList>
#include <QObject>
#include <QString>
#include <QUrl>

struct Entry {
  QString title;
  QUrl url;
  int visits = 0;
  QDateTime last;
};

class Store : public QObject {
  Q_OBJECT
 public:
  static Store* instance();

  const QList<Entry>& bookmarks() const { return bookmarks_; }
  bool isBookmarked(const QUrl& url) const;
  void toggleBookmark(const QString& title, const QUrl& url);

  void recordVisit(const QString& title, const QUrl& url);
  // Best history matches for the address bar.
  QList<Entry> suggest(const QString& text, int limit = 8) const;
  // Most visited, for the new tab page when there are few bookmarks.
  QList<Entry> topSites(int limit) const;
  void clearHistory();

 signals:
  void bookmarksChanged();

 private:
  Store();
  void save(const QString& file, const QList<Entry>& entries) const;
  QList<Entry> load(const QString& file) const;
  void saveHistorySoon();

  QList<Entry> bookmarks_;
  QList<Entry> history_;
  bool history_dirty_ = false;
};
