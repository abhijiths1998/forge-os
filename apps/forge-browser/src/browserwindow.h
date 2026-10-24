// A Forge Browser window: tabs, toolbar, address bar, find bar.
#pragma once

#include <QList>
#include <QMainWindow>
#include <QUrl>

class QCompleter;
class QLabel;
class QLineEdit;
class QStackedWidget;
class QStringListModel;
class QTabBar;
class QToolButton;
class QWebEngineDownloadRequest;
class QWebEngineFullScreenRequest;
class QWebEngineProfile;
class QWebEngineView;
class QWidget;
class WebPage;

namespace adblock {
class Blocker;
}

class BrowserWindow : public QMainWindow {
  Q_OBJECT
 public:
  BrowserWindow(QWebEngineProfile* profile, adblock::Blocker* blocker);

  QWebEngineView* addTab(const QUrl& url = QUrl(), bool background = false,
                         WebPage* page = nullptr);
  QList<QUrl> tabUrls() const;

  // Show a download in this window's downloads button.
  void trackDownload(QWebEngineDownloadRequest* download);

  static QUrl newTabUrl() { return QUrl("forge://newtab"); }
  static bool isNewTab(const QUrl& url) {
    return url.scheme() == "forge" && url.host() == "newtab";
  }
  // Text from the address bar as a URL, or a web search.
  static QUrl fromUserInput(const QString& text);

 protected:
  void closeEvent(QCloseEvent* event) override;

 private:
  QWebEngineView* current() const;
  QWebEngineView* viewAt(int index) const;
  int indexOf(QWebEngineView* view) const;
  void closeTab(int index);
  void currentChanged(int index);
  void updateChrome();
  void updateShield();
  void navigate();
  void suggest(const QString& text);
  void toggleBookmark();
  void showFind();
  void find(bool backwards = false);
  void zoom(int step);  // 0 resets
  void openDevTools();
  void fullScreen(QWebEngineFullScreenRequest request);
  void buildMenu();
  void buildShieldMenu();
  void addShortcuts();

  QWebEngineProfile* profile_;
  adblock::Blocker* blocker_;
  QTabBar* tabs_;
  QStackedWidget* stack_;
  QWidget* chrome_;  // tab bar + toolbar, hidden in full screen
  QToolButton* back_;
  QToolButton* forward_;
  QToolButton* reload_;
  QLineEdit* address_;
  QStringListModel* suggestions_;
  QCompleter* completer_;
  QToolButton* shield_;
  QToolButton* star_;
  QToolButton* menu_;
  QToolButton* downloads_;
  QList<QWebEngineDownloadRequest*> downloadList_;
  QWidget* findBar_;
  QLineEdit* findText_;
  QLabel* hoverLink_;
  QList<QUrl> closed_;  // for Ctrl+Shift+T
  bool wasMaximized_ = false;
};
