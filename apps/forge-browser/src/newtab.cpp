#include "newtab.h"

#include <QBuffer>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QPalette>
#include <QStyleHints>
#include <QUrl>
#include <QWebEngineUrlRequestJob>
#include <QWebEngineUrlScheme>

#include "adblock.h"
#include "bookmarks.h"

namespace {

constexpr const char* kWallpaperDir =
    "/usr/share/wallpapers/ForgeGlass/contents/";

QString escaped(const QString& s) { return s.toHtmlEscaped(); }

}  // namespace

ForgeScheme::ForgeScheme(adblock::Blocker* blocker, QObject* parent)
    : QWebEngineUrlSchemeHandler(parent), blocker_(blocker) {}

void ForgeScheme::registerScheme() {
  QWebEngineUrlScheme scheme("forge");
  scheme.setSyntax(QWebEngineUrlScheme::Syntax::Host);
  scheme.setFlags(QWebEngineUrlScheme::SecureScheme |
                  QWebEngineUrlScheme::LocalAccessAllowed |
                  QWebEngineUrlScheme::ContentSecurityPolicyIgnored);
  QWebEngineUrlScheme::registerScheme(scheme);
}

// Dark if the desktop is (the ForgeGlass Dark colour scheme sets a dark
// window colour, which Qt reports as a dark colour scheme).
bool ForgeScheme::darkMode() {
  const auto hint = QGuiApplication::styleHints()->colorScheme();
  if (hint != Qt::ColorScheme::Unknown) return hint == Qt::ColorScheme::Dark;
  return QGuiApplication::palette().color(QPalette::Window).lightness() < 128;
}

void ForgeScheme::requestStarted(QWebEngineUrlRequestJob* job) {
  const QUrl url = job->requestUrl();
  QByteArray body;
  QByteArray type;
  if (url.host() == "newtab") {
    body = newTabPage();
    type = "text/html";
  } else if (url.host() == "wallpaper") {
    body = wallpaper(url.path().mid(1) == "dark" ? "dark" : "light");
    type = "image/jpeg";
  }
  if (body.isEmpty()) {
    job->fail(QWebEngineUrlRequestJob::UrlNotFound);
    return;
  }
  auto* buffer = new QBuffer(job);
  buffer->setData(body);
  job->reply(type, buffer);
}

QByteArray ForgeScheme::newTabPage() const {
  QFile f(":/newtab.html");
  if (!f.open(QIODevice::ReadOnly)) return {};
  QString html = QString::fromUtf8(f.readAll());

  // Bookmarks first, topped up with the sites visited most.
  QList<Entry> tiles = Store::instance()->bookmarks().mid(0, 8);
  if (tiles.size() < 8) {
    for (const auto& e : Store::instance()->topSites(8)) {
      if (tiles.size() >= 8) break;
      if (std::none_of(tiles.begin(), tiles.end(), [&](const Entry& t) {
            return t.url.host() == e.url.host();
          })) {
        tiles.append(e);
      }
    }
  }
  QString cards;
  for (const auto& t : tiles) {
    const QString host = t.url.host();
    QString title = t.title.isEmpty() ? host : t.title;
    if (title.size() > 24) title = host.startsWith("www.") ? host.mid(4) : host;
    // A letter tile rather than a fetched favicon: no request leaves the
    // browser just because a new tab opened.
    const QString bare = host.startsWith("www.") ? host.mid(4) : host;
    cards += QString("<a href=\"%1\"><b>%2</b><span>%3</span></a>")
                 .arg(escaped(t.url.toString()),
                      escaped(bare.left(1).toUpper()), escaped(title));
  }

  QString shield;
  if (blocker_->enabled() && blocker_->ruleCount() > 0) {
    shield = QString("Ad blocker on · %1 rules").arg(blocker_->ruleCount());
  }

  html.replace("{{TILES}}", cards);
  html.replace("{{SHIELD}}", escaped(shield));
  html.replace("{{VARIANT}}", darkMode() ? "dark" : "light");
  return html.toUtf8();
}

// The 4K PNG would be slow to load in every new tab: scale it once.
QByteArray ForgeScheme::wallpaper(const QString& variant) {
  if (wallpapers_.contains(variant)) return wallpapers_[variant];
  const QString dir = QString(kWallpaperDir) +
                      (variant == "dark" ? "images_dark/" : "images/");
  QImage image(dir + "3840x2160.png");
  if (image.isNull()) image.load(QString(kWallpaperDir) + "images/3840x2160.png");
  QByteArray out;
  if (!image.isNull()) {
    QBuffer buffer(&out);
    buffer.open(QIODevice::WriteOnly);
    image.scaledToWidth(1920, Qt::SmoothTransformation)
        .save(&buffer, "JPEG", 88);
  }
  wallpapers_[variant] = out;
  return out;
}
