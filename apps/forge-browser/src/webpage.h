// One tab's page: site-specific ad hiding, popups as tabs, permission
// prompts.
#pragma once

#include <QWebEnginePage>
#include <QWebEnginePermission>

namespace adblock {
class Blocker;
}

class WebPage : public QWebEnginePage {
  Q_OBJECT
 public:
  WebPage(QWebEngineProfile* profile, adblock::Blocker* blocker,
          QObject* parent = nullptr);

  // Re-applies the ad blocker's CSS for the current site (after the shield
  // is toggled).
  void refreshSiteCss(const QUrl& url);

 signals:
  // A link asked for a new tab or window (target=_blank, middle click...).
  void newPageRequested(WebPage* page, bool background, bool window);

 protected:
  bool acceptNavigationRequest(const QUrl& url, NavigationType type,
                               bool isMainFrame) override;
  QWebEnginePage* createWindow(WebWindowType type) override;
  void javaScriptConsoleMessage(JavaScriptConsoleMessageLevel, const QString&,
                                int, const QString&) override {}

 private:
  void askPermission(QWebEnginePermission permission);

  adblock::Blocker* blocker_;
};
