#include "webpage.h"

#include <QMessageBox>
#include <QWebEngineProfile>
#include <QWebEngineScript>
#include <QWebEngineScriptCollection>
#include <QWebEngineView>

#include "adblock.h"

namespace {

constexpr const char* kSiteScript = "forge-adblock-site";

QString describe(QWebEnginePermission::PermissionType type) {
  using T = QWebEnginePermission::PermissionType;
  switch (type) {
    case T::MediaAudioCapture: return "use your microphone";
    case T::MediaVideoCapture: return "use your camera";
    case T::MediaAudioVideoCapture: return "use your camera and microphone";
    case T::DesktopVideoCapture:
    case T::DesktopAudioVideoCapture: return "share your screen";
    case T::Geolocation: return "know your location";
    case T::Notifications: return "show notifications";
    case T::ClipboardReadWrite: return "read your clipboard";
    case T::LocalFontsAccess: return "see your installed fonts";
    case T::MouseLock: return "lock your mouse pointer";
    default: return "use a device feature";
  }
}

}  // namespace

WebPage::WebPage(QWebEngineProfile* profile, adblock::Blocker* blocker,
                 QObject* parent)
    : QWebEnginePage(profile, parent), blocker_(blocker) {
  connect(this, &QWebEnginePage::permissionRequested, this,
          &WebPage::askPermission);
}

void WebPage::askPermission(QWebEnginePermission permission) {
  const QString site = permission.origin().host();
  const auto answer = QMessageBox::question(
      QWebEngineView::forPage(this) ? QWebEngineView::forPage(this)->window()
                                    : nullptr,
      "Permission",
      QString("Allow %1 to %2?").arg(site, describe(permission.permissionType())),
      QMessageBox::Yes | QMessageBox::No, QMessageBox::No);
  if (answer == QMessageBox::Yes) {
    permission.grant();
  } else {
    permission.deny();
  }
}

// Each new site gets its own element-hiding CSS, injected as the document
// is created (the generic rules are a profile-wide script, see adblock.cpp).
void WebPage::refreshSiteCss(const QUrl& url) {
  for (const auto& s : scripts().find(kSiteScript)) scripts().remove(s);
  const QString css = blocker_->cssFor(url.host().toLower());
  if (css.isEmpty()) return;
  QString quoted = css;
  quoted.replace('\\', "\\\\").replace('`', "\\`").replace("${", "\\${");
  QWebEngineScript script;
  script.setName(kSiteScript);
  script.setInjectionPoint(QWebEngineScript::DocumentCreation);
  script.setWorldId(QWebEngineScript::ApplicationWorld);
  script.setRunsOnSubFrames(false);
  script.setSourceCode(QStringLiteral(
                           "(() => { const add = () => {"
                           "const s = document.createElement('style');"
                           "s.textContent = `%1`;"
                           "(document.head || document.documentElement).appendChild(s); };"
                           "if (document.documentElement) add();"
                           "else document.addEventListener('readystatechange', add, {once: true});"
                           "})();")
                           .arg(quoted));
  scripts().insert(script);
}

bool WebPage::acceptNavigationRequest(const QUrl& url, NavigationType type,
                                      bool isMainFrame) {
  if (isMainFrame && (url.scheme() == "http" || url.scheme() == "https")) {
    refreshSiteCss(url);
  }
  return QWebEnginePage::acceptNavigationRequest(url, type, isMainFrame);
}

QWebEnginePage* WebPage::createWindow(WebWindowType type) {
  auto* page = new WebPage(profile(), blocker_);
  emit newPageRequested(page, type == WebBrowserBackgroundTab,
                        type == WebBrowserWindow || type == WebDialog);
  return page;
}
