// Forge Browser: Forge OS's web browser. Qt WebEngine (Chromium) with
// built-in ad and tracker blocking; Qt Widgets, so Darkly and the ForgeGlass
// colours make its toolbar and tabs translucent glass like the rest of the
// desktop.
//
// One process per user: `forge-browser URL...` from another app (or the
// launcher) hands its URLs to the running browser over a local socket and
// exits, and they open as tabs.
#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QLocalServer>
#include <QLocalSocket>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QWebEngineDownloadRequest>
#include <QWebEngineProfile>
#include <QWebEngineSettings>

#include <unistd.h>

#include "adblock.h"
#include "browserwindow.h"
#include "newtab.h"

namespace {

QString socketName() {
  return QString("forge-browser-%1").arg(getuid());
}

// Already running? Pass it the URLs (or "" for a new window) and stop.
bool forwardToRunning(const QStringList& urls) {
  QLocalSocket socket;
  socket.connectToServer(socketName());
  if (!socket.waitForConnected(300)) return false;
  socket.write((urls.isEmpty() ? QStringList{""} : urls).join('\n').toUtf8());
  socket.waitForBytesWritten(1000);
  socket.disconnectFromServer();
  return true;
}

BrowserWindow* activeWindow() {
  if (auto* w = qobject_cast<BrowserWindow*>(QApplication::activeWindow())) {
    return w;
  }
  for (QWidget* w : QApplication::topLevelWidgets()) {
    if (auto* b = qobject_cast<BrowserWindow*>(w); b && b->isVisible()) return b;
  }
  return nullptr;
}

}  // namespace

int main(int argc, char* argv[]) {
  ForgeScheme::registerScheme();
  QApplication::setOrganizationName("forgeos");
  QApplication::setApplicationName("forge-browser");
  QApplication::setApplicationDisplayName("Forge Browser");
  QApplication::setDesktopFileName("org.forgeos.browser");
  QApplication app(argc, argv);

  QCommandLineParser cli;
  cli.setApplicationDescription("Forge OS web browser");
  cli.addHelpOption();
  cli.addPositionalArgument("urls", "Pages to open", "[url...]");
  cli.process(app);
  QStringList urls;
  for (const QString& arg : cli.positionalArguments()) {
    urls << BrowserWindow::fromUserInput(arg).toString();
  }
  if (forwardToRunning(urls)) return 0;

  // Persistent profile: cookies, cache, logins and site permissions survive
  // restarts (in ~/.local/share/forgeos/forge-browser).
  auto* profile = new QWebEngineProfile("default", &app);
  profile->setPersistentCookiesPolicy(QWebEngineProfile::ForcePersistentCookies);
  // Sites like Google serve degraded pages to "QtWebEngine" user agents;
  // present as the Chromium it is.
  QString agent = profile->httpUserAgent();
  agent.remove(QRegularExpression(" QtWebEngine/[^ ]+"));
  profile->setHttpUserAgent(agent);
  auto* s = profile->settings();
  s->setAttribute(QWebEngineSettings::FullScreenSupportEnabled, true);
  s->setAttribute(QWebEngineSettings::ScrollAnimatorEnabled, true);
  s->setAttribute(QWebEngineSettings::ScreenCaptureEnabled, true);
  s->setAttribute(QWebEngineSettings::DnsPrefetchEnabled, true);
  s->setAttribute(QWebEngineSettings::PdfViewerEnabled, true);

  auto* blocker = new adblock::Blocker(&app);
  blocker->install(profile);
  profile->installUrlSchemeHandler("forge", new ForgeScheme(blocker, &app));

  QObject::connect(profile, &QWebEngineProfile::downloadRequested,
                   [](QWebEngineDownloadRequest* download) {
                     download->setDownloadDirectory(QStandardPaths::writableLocation(
                         QStandardPaths::DownloadLocation));
                     download->accept();
                     if (auto* w = activeWindow()) w->trackDownload(download);
                   });

  auto openWindow = [profile, blocker](const QStringList& pages) {
    auto* w = new BrowserWindow(profile, blocker);
    if (pages.isEmpty()) {
      w->addTab();
    } else {
      w->addTab(QUrl(pages.first()));
      for (const QString& u : pages.mid(1)) w->addTab(QUrl(u), true);
    }
    w->show();
    return w;
  };

  // Later invocations: their URLs become tabs here.
  QLocalServer::removeServer(socketName());
  auto* server = new QLocalServer(&app);
  server->setSocketOptions(QLocalServer::UserAccessOption);
  server->listen(socketName());
  QObject::connect(server, &QLocalServer::newConnection, [server, openWindow] {
    QLocalSocket* socket = server->nextPendingConnection();
    QObject::connect(socket, &QLocalSocket::disconnected, socket,
                     &QObject::deleteLater);
    QObject::connect(socket, &QLocalSocket::readyRead, [socket, openWindow] {
      const QStringList got =
          QString::fromUtf8(socket->readAll()).split('\n', Qt::SkipEmptyParts);
      BrowserWindow* w = activeWindow();
      if (w == nullptr || got.isEmpty()) {
        w = openWindow(got);
      } else {
        for (const QString& u : got) w->addTab(QUrl(u));
      }
      w->raise();
      w->activateWindow();
    });
  });

  // First window: the URLs asked for, else the tabs from last time.
  QStringList pages = urls;
  if (pages.isEmpty()) pages = QSettings().value("session/tabs").toStringList();
  openWindow(pages);
  return app.exec();
}
