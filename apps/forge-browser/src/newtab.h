// forge:// pages: forge://newtab (clock, search, bookmarks or top sites
// over the Forge Glass wallpaper) and forge://wallpaper/{light,dark}.
#pragma once

#include <QByteArray>
#include <QHash>
#include <QWebEngineUrlSchemeHandler>

namespace adblock {
class Blocker;
}

class ForgeScheme : public QWebEngineUrlSchemeHandler {
  Q_OBJECT
 public:
  explicit ForgeScheme(adblock::Blocker* blocker, QObject* parent = nullptr);

  // Must run before the QApplication exists.
  static void registerScheme();
  static bool darkMode();

  void requestStarted(QWebEngineUrlRequestJob* job) override;

 private:
  QByteArray newTabPage() const;
  QByteArray wallpaper(const QString& variant);

  adblock::Blocker* blocker_;
  QHash<QString, QByteArray> wallpapers_;  // scaled JPEGs, made once
};
