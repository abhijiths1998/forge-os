#include "browserwindow.h"

#include <QAction>
#include <QApplication>
#include <QCloseEvent>
#include <QCompleter>
#include <QDesktopServices>
#include <QDir>
#include <QFileDialog>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QLineEdit>
#include <QMenu>
#include <QMessageBox>
#include <QProcess>
#include <QSettings>
#include <QShortcut>
#include <QStackedWidget>
#include <QStandardPaths>
#include <QStringListModel>
#include <QTabBar>
#include <QToolButton>
#include <QVBoxLayout>
#include <QWebEngineCookieStore>
#include <QWebEngineDownloadRequest>
#include <QWebEngineFindTextResult>
#include <QWebEngineFullScreenRequest>
#include <QWebEngineHistory>
#include <QWebEngineProfile>
#include <QWebEngineView>

#include "adblock.h"
#include "bookmarks.h"
#include "tabsidebar.h"
#include "webpage.h"

namespace {

constexpr int kMaxTitle = 28;
const QList<double> kZoomLevels = {0.5, 0.67, 0.75, 0.8, 0.9, 1.0,
                                   1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0};

QToolButton* toolButton(const QString& icon, const QString& tip) {
  auto* b = new QToolButton;
  b->setIcon(QIcon::fromTheme(icon));
  b->setToolTip(tip);
  b->setAutoRaise(true);
  b->setIconSize(QSize(18, 18));
  return b;
}

QString elided(const QString& title) {
  return title.size() > kMaxTitle ? title.left(kMaxTitle - 1) + "…" : title;
}

}  // namespace

QUrl BrowserWindow::fromUserInput(const QString& input) {
  const QString text = input.trimmed();
  if (text.isEmpty()) return newTabUrl();
  const bool hasScheme = text.contains("://") || text.startsWith("about:") ||
                         text.startsWith("file:") || text.startsWith("forge:");
  const bool looksLikeHost =
      !text.contains(' ') &&
      (text.contains('.') || text.startsWith("localhost") || text.contains(':'));
  if (hasScheme || looksLikeHost) {
    const QUrl url = QUrl::fromUserInput(text);
    if (url.isValid()) return url;
  }
  QUrl search("https://duckduckgo.com/");
  search.setQuery("q=" + QUrl::toPercentEncoding(text));
  return search;
}

BrowserWindow::BrowserWindow(QWebEngineProfile* profile,
                             adblock::Blocker* blocker)
    : profile_(profile), blocker_(blocker) {
  setAttribute(Qt::WA_DeleteOnClose);
  setWindowIcon(QIcon::fromTheme("internet-web-browser"));
  resize(1280, 820);

  // --- Tab strip.
  tabs_ = new QTabBar;
  tabs_->setDocumentMode(true);
  tabs_->setTabsClosable(true);
  tabs_->setMovable(true);
  tabs_->setExpanding(false);
  tabs_->setUsesScrollButtons(true);
  tabs_->setElideMode(Qt::ElideRight);
  tabs_->setSelectionBehaviorOnRemove(QTabBar::SelectPreviousTab);
  auto* newTab = toolButton("tab-new", "New tab (Ctrl+T)");
  connect(newTab, &QToolButton::clicked, this, [this] { addTab(); });

  tabStrip_ = new QWidget;
  auto* tabRow = new QHBoxLayout(tabStrip_);
  tabRow->setContentsMargins(6, 4, 6, 0);
  tabRow->setSpacing(4);
  tabRow->addWidget(tabs_, 1);
  tabRow->addWidget(newTab);

  // --- Toolbar.
  back_ = toolButton("go-previous", "Back (Alt+Left)");
  forward_ = toolButton("go-next", "Forward (Alt+Right)");
  reload_ = toolButton("view-refresh", "Reload (F5)");
  address_ = new QLineEdit;
  address_->setPlaceholderText("Search or enter address");
  address_->setClearButtonEnabled(true);
  address_->setMinimumHeight(32);
  suggestions_ = new QStringListModel(this);
  completer_ = new QCompleter(suggestions_, this);
  completer_->setCompletionMode(QCompleter::UnfilteredPopupCompletion);
  completer_->setCaseSensitivity(Qt::CaseInsensitive);
  address_->setCompleter(completer_);
  shield_ = toolButton("security-high", "Ad blocker");
  shield_->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
  shield_->setPopupMode(QToolButton::InstantPopup);
  star_ = toolButton("bookmark-new", "Bookmark this page (Ctrl+D)");
  menu_ = toolButton("application-menu", "Menu");
  menu_->setPopupMode(QToolButton::InstantPopup);
  downloads_ = toolButton("folder-download", "Downloads");
  downloads_->setPopupMode(QToolButton::InstantPopup);
  downloads_->setMenu(new QMenu(this));
  downloads_->hide();

  auto* toolRow = new QHBoxLayout;
  toolRow->setContentsMargins(8, 4, 8, 6);
  toolRow->setSpacing(4);
  for (QWidget* w : {static_cast<QWidget*>(back_), static_cast<QWidget*>(forward_),
                     static_cast<QWidget*>(reload_)}) {
    toolRow->addWidget(w);
  }
  toolRow->addSpacing(4);
  toolRow->addWidget(address_, 1);
  toolRow->addSpacing(4);
  toolRow->addWidget(shield_);
  toolRow->addWidget(downloads_);
  toolRow->addWidget(star_);
  toolRow->addWidget(menu_);

  chrome_ = new QWidget;
  auto* chromeLayout = new QVBoxLayout(chrome_);
  chromeLayout->setContentsMargins(0, 0, 0, 0);
  chromeLayout->setSpacing(0);
  chromeLayout->addWidget(tabStrip_);
  chromeLayout->addLayout(toolRow);

  // --- Find bar.
  findBar_ = new QWidget;
  auto* findRow = new QHBoxLayout(findBar_);
  findRow->setContentsMargins(8, 4, 8, 4);
  findText_ = new QLineEdit;
  findText_->setPlaceholderText("Find in page");
  findText_->setMaximumWidth(320);
  auto* findPrev = toolButton("go-up", "Previous (Shift+Enter)");
  auto* findNext = toolButton("go-down", "Next (Enter)");
  auto* findClose = toolButton("window-close", "Close (Esc)");
  findRow->addWidget(findText_);
  findRow->addWidget(findPrev);
  findRow->addWidget(findNext);
  findRow->addStretch();
  findRow->addWidget(findClose);
  findBar_->hide();
  connect(findText_, &QLineEdit::textEdited, this, [this] { find(); });
  connect(findText_, &QLineEdit::returnPressed, this, [this] {
    find(QApplication::keyboardModifiers() & Qt::ShiftModifier);
  });
  connect(findPrev, &QToolButton::clicked, this, [this] { find(true); });
  connect(findNext, &QToolButton::clicked, this, [this] { find(); });
  connect(findClose, &QToolButton::clicked, this, [this] {
    findBar_->hide();
    if (current()) current()->findText(QString());
  });

  // --- Pages.
  stack_ = new QStackedWidget;
  hoverLink_ = new QLabel(stack_);
  hoverLink_->setAutoFillBackground(true);
  hoverLink_->setContentsMargins(8, 3, 8, 3);
  hoverLink_->hide();

  // Pages, with the vertical tab sidebar docked to their left (or floating
  // over them when it auto-hides).
  auto* content = new QWidget;
  auto* contentLayout = new QHBoxLayout(content);
  contentLayout->setContentsMargins(0, 0, 0, 0);
  contentLayout->setSpacing(0);
  contentLayout->addWidget(stack_, 1);
  sidebar_ = new TabSidebar(tabs_, content, contentLayout);

  auto* central = new QWidget;
  auto* layout = new QVBoxLayout(central);
  layout->setContentsMargins(0, 0, 0, 0);
  layout->setSpacing(0);
  layout->addWidget(chrome_);
  layout->addWidget(findBar_);
  layout->addWidget(content, 1);
  setCentralWidget(central);

  connect(tabs_, &QTabBar::currentChanged, this, &BrowserWindow::currentChanged);
  connect(tabs_, &QTabBar::tabCloseRequested, this, &BrowserWindow::closeTab);
  connect(tabs_, &QTabBar::tabMoved, this, [this](int from, int to) {
    QWidget* w = stack_->widget(from);
    stack_->removeWidget(w);
    stack_->insertWidget(to, w);
    stack_->setCurrentIndex(tabs_->currentIndex());
    sidebar_->refresh();
  });
  connect(sidebar_, &TabSidebar::newTabRequested, this, [this] { addTab(); });
  connect(sidebar_, &TabSidebar::closeRequested, this, &BrowserWindow::closeTab);
  connect(sidebar_, &TabSidebar::modeChanged, this, [](TabSidebar::Mode mode) {
    QSettings().setValue("tabs/sidebarMode", static_cast<int>(mode));
  });
  connect(back_, &QToolButton::clicked, this, [this] { current()->back(); });
  connect(forward_, &QToolButton::clicked, this, [this] { current()->forward(); });
  connect(reload_, &QToolButton::clicked, this, [this] {
    auto* v = current();
    if (v->page()->isLoading()) {
      v->stop();
    } else {
      v->reload();
    }
  });
  connect(address_, &QLineEdit::returnPressed, this, &BrowserWindow::navigate);
  connect(address_, &QLineEdit::textEdited, this, &BrowserWindow::suggest);
  connect(completer_, qOverload<const QString&>(&QCompleter::activated), this,
          [this](const QString& text) {
            address_->setText(text.section("  —  ", -1));
            navigate();
          });
  connect(star_, &QToolButton::clicked, this, &BrowserWindow::toggleBookmark);
  connect(blocker_, &adblock::Blocker::blocked, this, [this](const QString& host) {
    if (current() && current()->url().host().toLower() == host) updateShield();
  });

  buildMenu();
  buildShieldMenu();
  addShortcuts();

  QSettings settings;
  sidebar_->setMode(static_cast<TabSidebar::Mode>(
      settings.value("tabs/sidebarMode", TabSidebar::Expanded).toInt()));
  setVerticalTabs(settings.value("tabs/vertical", false).toBool());
}

QWebEngineView* BrowserWindow::current() const {
  return qobject_cast<QWebEngineView*>(stack_->currentWidget());
}

QWebEngineView* BrowserWindow::viewAt(int index) const {
  return qobject_cast<QWebEngineView*>(stack_->widget(index));
}

int BrowserWindow::indexOf(QWebEngineView* view) const {
  return stack_->indexOf(view);
}

QList<QUrl> BrowserWindow::tabUrls() const {
  QList<QUrl> urls;
  for (int i = 0; i < stack_->count(); i++) urls.append(viewAt(i)->url());
  return urls;
}

QWebEngineView* BrowserWindow::addTab(const QUrl& url, bool background,
                                      WebPage* page) {
  auto* view = new QWebEngineView;
  if (page == nullptr) page = new WebPage(profile_, blocker_);
  page->setParent(view);
  view->setPage(page);

  // Foreground tabs open next to the current one; background ones (restored
  // tabs, middle-clicked links) queue at the end, in order.
  const int index = background ? tabs_->count() : tabs_->currentIndex() + 1;
  stack_->insertWidget(index, view);
  tabs_->insertTab(index, "New Tab");
  sidebar_->refresh();

  connect(view, &QWebEngineView::titleChanged, this, [this, view](const QString& t) {
    const int i = indexOf(view);
    if (i < 0) return;
    tabs_->setTabText(i, elided(t.isEmpty() ? "New Tab" : t));
    tabs_->setTabToolTip(i, t);
    sidebar_->refresh();
    if (view == current()) setWindowTitle(t + " — Forge Browser");
  });
  connect(view, &QWebEngineView::iconChanged, this, [this, view](const QIcon& icon) {
    if (int i = indexOf(view); i >= 0) {
      tabs_->setTabIcon(i, icon);
      sidebar_->refresh();
    }
  });
  connect(view, &QWebEngineView::urlChanged, this, [this, view](const QUrl&) {
    if (view == current()) updateChrome();
  });
  connect(view, &QWebEngineView::loadStarted, this, [this, view] {
    blocker_->resetCount(view->url().host().toLower());
    if (view == current()) updateChrome();
  });
  connect(view, &QWebEngineView::loadFinished, this, [this, view](bool) {
    Store::instance()->recordVisit(view->title(), view->url());
    if (view == current()) updateChrome();
  });
  connect(page, &QWebEnginePage::linkHovered, this, [this, view](const QString& link) {
    if (view != current()) return;
    hoverLink_->setText(link);
    hoverLink_->adjustSize();
    hoverLink_->move(0, stack_->height() - hoverLink_->height());
    hoverLink_->setVisible(!link.isEmpty());
    hoverLink_->raise();
  });
  connect(page, &QWebEnginePage::windowCloseRequested, this, [this, view] {
    closeTab(indexOf(view));
  });
  connect(page, &QWebEnginePage::fullScreenRequested, this,
          &BrowserWindow::fullScreen);
  connect(page, &WebPage::newPageRequested, this,
          [this](WebPage* p, bool bg, bool window) {
            if (window) {
              auto* w = new BrowserWindow(profile_, blocker_);
              w->addTab(QUrl(), false, p);
              w->show();
            } else {
              addTab(QUrl(), bg, p);
            }
          });

  if (!url.isEmpty()) {
    view->load(url);
  } else if (page->url().isEmpty() && page->requestedUrl().isEmpty()) {
    // A plain new tab; pages opened by links load themselves.
    view->load(newTabUrl());
  }
  if (!background) {
    tabs_->setCurrentIndex(index);
    if (url.isEmpty() || isNewTab(url)) address_->setFocus();
  }
  return view;
}

void BrowserWindow::closeTab(int index) {
  QWebEngineView* view = viewAt(index);
  if (view == nullptr) return;
  if (!isNewTab(view->url())) closed_.append(view->url());
  tabs_->removeTab(index);
  sidebar_->refresh();
  stack_->removeWidget(view);
  view->deleteLater();
  if (tabs_->count() == 0) close();
}

void BrowserWindow::currentChanged(int index) {
  if (index < 0) return;
  stack_->setCurrentIndex(index);
  hoverLink_->hide();
  sidebar_->refresh();
  updateChrome();
}

void BrowserWindow::updateChrome() {
  QWebEngineView* v = current();
  if (v == nullptr) return;
  const QUrl url = v->url();
  if (!address_->hasFocus() || address_->text().isEmpty()) {
    address_->setText(isNewTab(url) ? QString() : url.toDisplayString());
    address_->setCursorPosition(0);
  }
  back_->setEnabled(v->history()->canGoBack());
  forward_->setEnabled(v->history()->canGoForward());
  const bool loading = v->page()->isLoading();
  reload_->setIcon(QIcon::fromTheme(loading ? "process-stop" : "view-refresh"));
  reload_->setToolTip(loading ? "Stop (Esc)" : "Reload (F5)");
  const bool web = url.scheme() == "http" || url.scheme() == "https";
  star_->setEnabled(web);
  star_->setIcon(QIcon::fromTheme(Store::instance()->isBookmarked(url)
                                      ? "starred-symbolic"
                                      : "non-starred-symbolic"));
  setWindowTitle((v->title().isEmpty() ? "New Tab" : v->title()) +
                 " — Forge Browser");
  updateShield();
}

void BrowserWindow::updateShield() {
  QWebEngineView* v = current();
  if (v == nullptr) return;
  const QString host = v->url().host().toLower();
  const bool web = !host.isEmpty();
  const bool on = blocker_->enabled() && !(web && blocker_->allowedOn(host));
  const int count = web ? blocker_->blockedCount(host) : 0;
  shield_->setIcon(QIcon::fromTheme(on ? "security-high" : "security-low"));
  shield_->setText(on && count > 0 ? QString::number(count) : QString());
  shield_->setToolTip(on ? QString("Ad blocker: %1 blocked on this page").arg(count)
                         : "Ad blocker is off for this site");
}

void BrowserWindow::navigate() {
  const QUrl url = fromUserInput(address_->text());
  current()->load(url);
  current()->setFocus();
}

void BrowserWindow::suggest(const QString& text) {
  QStringList items;
  for (const auto& e : Store::instance()->suggest(text)) {
    const QString url = e.url.toDisplayString();
    items << (e.title.isEmpty() ? url : e.title.left(60) + "  —  " + url);
  }
  suggestions_->setStringList(items);
}

void BrowserWindow::toggleBookmark() {
  QWebEngineView* v = current();
  Store::instance()->toggleBookmark(v->title(), v->url());
  updateChrome();
}

void BrowserWindow::showFind() {
  findBar_->show();
  findText_->setFocus();
  findText_->selectAll();
}

void BrowserWindow::find(bool backwards) {
  QWebEnginePage::FindFlags flags;
  if (backwards) flags |= QWebEnginePage::FindBackward;
  current()->findText(findText_->text(), flags);
}

void BrowserWindow::zoom(int step) {
  QWebEngineView* v = current();
  if (step == 0) {
    v->setZoomFactor(1.0);
    return;
  }
  const double z = v->zoomFactor();
  if (step > 0) {
    for (double level : kZoomLevels) {
      if (level > z + 0.01) {
        v->setZoomFactor(level);
        return;
      }
    }
  } else {
    for (auto it = kZoomLevels.rbegin(); it != kZoomLevels.rend(); ++it) {
      if (*it < z - 0.01) {
        v->setZoomFactor(*it);
        return;
      }
    }
  }
}

void BrowserWindow::openDevTools() {
  auto* tools = new QWebEngineView;
  tools->setAttribute(Qt::WA_DeleteOnClose);
  tools->setWindowTitle("Developer Tools — " + current()->title());
  tools->resize(1000, 700);
  current()->page()->setDevToolsPage(tools->page());
  tools->show();
}

void BrowserWindow::fullScreen(QWebEngineFullScreenRequest request) {
  request.accept();
  if (request.toggleOn()) {
    wasMaximized_ = isMaximized();
    chrome_->hide();
    findBar_->hide();
    sidebar_->setActive(false);
    showFullScreen();
  } else {
    chrome_->show();
    sidebar_->setActive(vertical_);
    if (wasMaximized_) {
      showMaximized();
    } else {
      showNormal();
    }
  }
}

void BrowserWindow::buildMenu() {
  auto* m = new QMenu(this);
  m->addAction(QIcon::fromTheme("tab-new"), "New tab", QKeySequence::AddTab,
               this, [this] { addTab(); });
  m->addAction(QIcon::fromTheme("window-new"), "New window", QKeySequence::New,
               this, [this] {
                 auto* w = new BrowserWindow(profile_, blocker_);
                 w->addTab();
                 w->show();
               });
  m->addAction(QIcon::fromTheme("edit-undo"), "Reopen closed tab",
               QKeySequence("Ctrl+Shift+T"), this, [this] {
                 if (!closed_.isEmpty()) addTab(closed_.takeLast());
               });
  verticalAction_ = m->addAction(QIcon::fromTheme("view-split-left-right"),
                                 "Vertical tabs", QKeySequence("Ctrl+Shift+,"),
                                 this, [this](bool on) { setVerticalTabs(on); });
  verticalAction_->setCheckable(true);
  m->addAction(QIcon::fromTheme("view-hidden"), "Auto-hide tab sidebar",
               QKeySequence("Ctrl+\\"), this, [this] {
                 if (!vertical_) {
                   setVerticalTabs(true);
                   if (sidebar_->mode() == TabSidebar::AutoHide) return;
                 }
                 sidebar_->toggleAutoHide();
               });
  m->addSeparator();

  auto* bookmarks = m->addMenu(QIcon::fromTheme("bookmarks"), "Bookmarks");
  connect(bookmarks, &QMenu::aboutToShow, this, [this, bookmarks] {
    bookmarks->clear();
    const auto& list = Store::instance()->bookmarks();
    if (list.isEmpty()) bookmarks->addAction("No bookmarks yet")->setEnabled(false);
    for (const auto& e : list) {
      const QUrl url = e.url;
      bookmarks->addAction(e.title.left(60), this, [this, url] { current()->load(url); });
    }
  });
  m->addAction(QIcon::fromTheme("folder-download"), "Downloads folder", this, [] {
    QDesktopServices::openUrl(QUrl::fromLocalFile(
        QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)));
  });
  m->addAction(QIcon::fromTheme("edit-clear-history"), "Clear history and cookies",
               this, [this] {
                 if (QMessageBox::question(this, "Clear history",
                                           "Clear browsing history, cookies and cache?") !=
                     QMessageBox::Yes) {
                   return;
                 }
                 Store::instance()->clearHistory();
                 profile_->clearHttpCache();
                 profile_->cookieStore()->deleteAllCookies();
                 for (int i = 0; i < stack_->count(); i++) viewAt(i)->history()->clear();
               });
  m->addSeparator();
  m->addAction(QIcon::fromTheme("edit-find"), "Find in page", QKeySequence::Find,
               this, &BrowserWindow::showFind);
  m->addAction(QIcon::fromTheme("zoom-in"), "Zoom in", this, [this] { zoom(1); })
      ->setShortcuts({QKeySequence("Ctrl++"), QKeySequence("Ctrl+=")});
  m->addAction(QIcon::fromTheme("zoom-out"), "Zoom out", QKeySequence::ZoomOut,
               this, [this] { zoom(-1); });
  m->addAction(QIcon::fromTheme("zoom-original"), "Actual size",
               QKeySequence("Ctrl+0"), this, [this] { zoom(0); });
  m->addAction(QIcon::fromTheme("document-save-as"), "Save page as PDF…",
               QKeySequence::Print, this, [this] {
                 const QString path = QFileDialog::getSaveFileName(
                     this, "Save as PDF",
                     QStandardPaths::writableLocation(QStandardPaths::DownloadLocation) +
                         "/" + current()->title() + ".pdf",
                     "PDF (*.pdf)");
                 if (!path.isEmpty()) current()->printToPdf(path);
               });
  m->addAction(QIcon::fromTheme("code-context"), "Developer tools",
               QKeySequence("F12"), this, &BrowserWindow::openDevTools);
  m->addSeparator();
  m->addAction(QIcon::fromTheme("internet-web-browser"), "Make default browser",
               this, [this] {
                 const bool ok = QProcess::execute(
                                     "xdg-settings",
                                     {"set", "default-web-browser",
                                      "org.forgeos.browser.desktop"}) == 0;
                 QMessageBox::information(
                     this, "Default browser",
                     ok ? "Forge Browser is now your default browser."
                        : "Couldn't set the default browser (xdg-settings failed).");
               });
  m->addAction(QIcon::fromTheme("help-about"), "About Forge Browser", this, [this] {
    QMessageBox::about(
        this, "Forge Browser",
        QString("<b>Forge Browser</b><br>Forge OS's web browser, on Qt WebEngine "
                "(Chromium %1).<br><br>Built-in ad and tracker blocking with "
                "EasyList, EasyPrivacy and Peter Lowe's list: %2 rules.")
            .arg(qWebEngineChromiumVersion())
            .arg(blocker_->ruleCount()));
  });
  menu_->setMenu(m);
  // A QMenu is a window of its own: its shortcuts only fire while it's open
  // unless the window has the actions too.
  addActions(m->actions());
}

void BrowserWindow::buildShieldMenu() {
  auto* m = new QMenu(this);
  connect(m, &QMenu::aboutToShow, this, [this, m] {
    m->clear();
    const QString host = current()->url().host().toLower();
    if (!host.isEmpty()) {
      auto* site = m->addAction(QString("Block ads on %1").arg(host));
      site->setCheckable(true);
      site->setChecked(!blocker_->allowedOn(host));
      site->setEnabled(blocker_->enabled());
      connect(site, &QAction::toggled, this, [this, host](bool block) {
        blocker_->setAllowedOn(host, !block);
        if (auto* p = qobject_cast<WebPage*>(current()->page())) {
          p->refreshSiteCss(current()->url());
        }
        current()->reload();
      });
      m->addAction(QString("%1 requests blocked on this page")
                       .arg(blocker_->blockedCount(host)))
          ->setEnabled(false);
      m->addSeparator();
    }
    auto* all = m->addAction("Ad blocker on");
    all->setCheckable(true);
    all->setChecked(blocker_->enabled());
    connect(all, &QAction::toggled, this, [this](bool on) {
      blocker_->setEnabled(on);
      updateShield();
      current()->reload();
    });
    const QString when = blocker_->lastUpdated();
    m->addAction(QString("Update filter lists%1")
                     .arg(when.isEmpty() ? QString() : " (last: " + when + ")"),
                 blocker_, &adblock::Blocker::updateLists);
    m->addAction(QString("%1 rules from EasyList, EasyPrivacy, Peter Lowe")
                     .arg(blocker_->ruleCount()))
        ->setEnabled(false);
  });
  shield_->setMenu(m);
}

void BrowserWindow::addShortcuts() {
  auto key = [this](const QKeySequence& seq, auto fn) {
    auto* s = new QShortcut(seq, this);
    connect(s, &QShortcut::activated, this, fn);
  };
  key(QKeySequence("Ctrl+L"), [this] {
    address_->setFocus();
    address_->selectAll();
  });
  key(QKeySequence("Alt+D"), [this] {
    address_->setFocus();
    address_->selectAll();
  });
  key(QKeySequence("Ctrl+W"), [this] { closeTab(tabs_->currentIndex()); });
  key(QKeySequence("Ctrl+Tab"), [this] {
    tabs_->setCurrentIndex((tabs_->currentIndex() + 1) % tabs_->count());
  });
  key(QKeySequence("Ctrl+Shift+Tab"), [this] {
    tabs_->setCurrentIndex((tabs_->currentIndex() + tabs_->count() - 1) %
                           tabs_->count());
  });
  for (int i = 1; i <= 9; i++) {
    key(QKeySequence(QString("Ctrl+%1").arg(i)), [this, i] {
      tabs_->setCurrentIndex(i == 9 ? tabs_->count() - 1 : i - 1);
    });
  }
  key(QKeySequence("F5"), [this] { current()->reload(); });
  key(QKeySequence("Ctrl+R"), [this] { current()->reload(); });
  key(QKeySequence("Ctrl+Shift+R"), [this] {
    current()->triggerPageAction(QWebEnginePage::ReloadAndBypassCache);
  });
  key(QKeySequence("Alt+Left"), [this] { current()->back(); });
  key(QKeySequence("Alt+Right"), [this] { current()->forward(); });
  key(QKeySequence("Ctrl+D"), [this] { toggleBookmark(); });
  key(QKeySequence("F11"), [this] {
    if (isFullScreen()) {
      chrome_->show();
      wasMaximized_ ? showMaximized() : showNormal();
    } else {
      wasMaximized_ = isMaximized();
      showFullScreen();
    }
  });
  key(QKeySequence("Esc"), [this] {
    if (findBar_->isVisible()) {
      findBar_->hide();
      current()->findText(QString());
    } else if (current()->page()->isLoading()) {
      current()->stop();
    } else if (isFullScreen()) {
      current()->triggerPageAction(QWebEnginePage::ExitFullScreen);
    }
  });
}

void BrowserWindow::closeEvent(QCloseEvent* event) {
  // The last window closed: remember its tabs for next time.
  int windows = 0;
  for (QWidget* w : QApplication::topLevelWidgets()) {
    if (qobject_cast<BrowserWindow*>(w) && w->isVisible()) windows++;
  }
  if (windows <= 1) {
    QStringList urls;
    for (const QUrl& u : tabUrls()) {
      if (!isNewTab(u) && !u.isEmpty()) urls << u.toString();
    }
    QSettings().setValue("session/tabs", urls);
  }
  event->accept();
}

void BrowserWindow::trackDownload(QWebEngineDownloadRequest* download) {
  downloadList_.append(download);
  downloads_->show();
  connect(download, &QObject::destroyed, this,
          [this, download] { downloadList_.removeAll(download); });

  // The menu is rebuilt each time it opens, so progress is current.
  QMenu* m = downloads_->menu();
  disconnect(m, &QMenu::aboutToShow, nullptr, nullptr);
  connect(m, &QMenu::aboutToShow, this, [this, m] {
    m->clear();
    for (QWebEngineDownloadRequest* d : downloadList_) {
      const QString name = d->downloadFileName();
      QString state;
      switch (d->state()) {
        case QWebEngineDownloadRequest::DownloadInProgress:
          state = d->totalBytes() > 0
                      ? QString("%1%").arg(100 * d->receivedBytes() / d->totalBytes())
                      : QLocale().formattedDataSize(d->receivedBytes());
          break;
        case QWebEngineDownloadRequest::DownloadCompleted: state = "done"; break;
        case QWebEngineDownloadRequest::DownloadCancelled: state = "cancelled"; break;
        case QWebEngineDownloadRequest::DownloadInterrupted: state = "failed"; break;
        default: state = "waiting"; break;
      }
      const QString path = d->downloadDirectory() + "/" + name;
      auto* a = m->addAction(QIcon::fromTheme("document-save"),
                             QString("%1 — %2").arg(name, state));
      if (d->state() == QWebEngineDownloadRequest::DownloadCompleted) {
        connect(a, &QAction::triggered, this, [path] {
          QDesktopServices::openUrl(QUrl::fromLocalFile(path));
        });
      } else if (d->state() == QWebEngineDownloadRequest::DownloadInProgress) {
        connect(a, &QAction::triggered, d, &QWebEngineDownloadRequest::cancel);
        a->setToolTip("Click to cancel");
      }
    }
    m->addSeparator();
    m->addAction(QIcon::fromTheme("folder-download"), "Open Downloads folder", [] {
      QDesktopServices::openUrl(QUrl::fromLocalFile(
          QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)));
    });
  });

  // Highlight the button while anything is still downloading.
  auto refresh = [this] {
    int active = 0;
    for (auto* d : downloadList_) {
      if (d->state() == QWebEngineDownloadRequest::DownloadInProgress) active++;
    }
    downloads_->setToolButtonStyle(active ? Qt::ToolButtonTextBesideIcon
                                          : Qt::ToolButtonIconOnly);
    downloads_->setText(active ? QString::number(active) : QString());
  };
  connect(download, &QWebEngineDownloadRequest::stateChanged, this, refresh);
  refresh();
}

void BrowserWindow::setVerticalTabs(bool vertical) {
  vertical_ = vertical;
  tabStrip_->setVisible(!vertical);
  sidebar_->setActive(vertical && !(isFullScreen() && chrome_->isHidden()));
  sidebar_->refresh();
  verticalAction_->setChecked(vertical);
  QSettings().setValue("tabs/vertical", vertical);
}
