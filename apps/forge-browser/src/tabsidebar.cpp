#include "tabsidebar.h"

#include <QApplication>
#include <QBoxLayout>
#include <QEnterEvent>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QListWidget>
#include <QMenu>
#include <QMouseEvent>
#include <QPainter>
#include <QPropertyAnimation>
#include <QResizeEvent>
#include <QVariantAnimation>

#include <algorithm>
#include <cstdlib>
#include <QTabBar>
#include <QTimer>
#include <QScrollBar>
#include <QToolButton>

namespace {

constexpr int kExpandedWidth = 240;
constexpr int kCollapsedWidth = 52;
constexpr int kRowHeight = 36;
constexpr int kEdgeWidth = 6;
constexpr int kRollMs = 220;  // full collapsed <-> expanded roll

QIcon themed(const char* name, const char* fallback) {
  return QIcon::fromTheme(name, QIcon::fromTheme(fallback));
}

QToolButton* headerButton(const QIcon& icon, const QString& tip) {
  auto* b = new QToolButton;
  b->setIcon(icon);
  b->setToolTip(tip);
  b->setAutoRaise(true);
  b->setIconSize(QSize(16, 16));
  return b;
}

// A title that elides instead of clipping at whatever width the row has.
class ElidedLabel : public QWidget {
 public:
  explicit ElidedLabel(const QString& text) : text_(text) {
    setSizePolicy(QSizePolicy::Ignored, QSizePolicy::Preferred);
    setMinimumHeight(fontMetrics().height());
  }

 protected:
  void paintEvent(QPaintEvent*) override {
    QPainter p(this);
    p.setPen(palette().color(QPalette::WindowText));
    p.drawText(rect(), Qt::AlignVCenter | Qt::AlignLeft,
               fontMetrics().elidedText(text_, Qt::ElideRight, width()));
  }

 private:
  QString text_;
};

// One tab: favicon, title, and a close button that shows on hover (and on
// the current tab).
class TabRow : public QWidget {
 public:
  TabRow(const QIcon& icon, const QString& title, bool collapsed, bool current,
         std::function<void()> onClose)
      : current_(current) {
    auto* row = new QHBoxLayout(this);
    row->setContentsMargins(collapsed ? 0 : 8, 0, collapsed ? 0 : 2, 0);
    // On the row itself: it covers the list item, whose tooltip it would
    // otherwise swallow.
    setToolTip(title);
    row->setSpacing(8);
    auto* iconLabel = new QLabel;
    iconLabel->setPixmap(
        (icon.isNull() ? QIcon::fromTheme("text-html") : icon).pixmap(16, 16));
    iconLabel->setFixedSize(16, 16);
    if (collapsed) {
      row->addStretch();
      row->addWidget(iconLabel);
      row->addStretch();
      return;
    }
    row->addWidget(iconLabel);
    row->addWidget(new ElidedLabel(title), 1);
    close_ = new QToolButton;
    close_->setIcon(QIcon::fromTheme("window-close"));
    close_->setIconSize(QSize(12, 12));
    close_->setAutoRaise(true);
    close_->setToolTip("Close tab (Ctrl+W)");
    close_->setVisible(current);
    QObject::connect(close_, &QToolButton::clicked, close_, onClose);
    row->addWidget(close_);
  }

 protected:
  void enterEvent(QEnterEvent*) override {
    if (close_) close_->show();
  }
  void leaveEvent(QEvent*) override {
    if (close_ && !current_) close_->hide();
  }

 private:
  QToolButton* close_ = nullptr;
  bool current_;
};

// The hot zone: an invisible strip at the window's left edge.
class EdgeZone : public QWidget {
 public:
  explicit EdgeZone(QWidget* parent, std::function<void()> onEnter)
      : QWidget(parent), onEnter_(std::move(onEnter)) {
    setMouseTracking(true);
    setCursor(Qt::ArrowCursor);
  }

 protected:
  void enterEvent(QEnterEvent*) override { onEnter_(); }

 private:
  std::function<void()> onEnter_;
};

}  // namespace

TabSidebar::TabSidebar(QTabBar* tabs, QWidget* host, QHBoxLayout* dock)
    : QWidget(host), tabs_(tabs), host_(host), dock_(dock) {
  body_ = new QWidget(this);
  auto* layout = new QVBoxLayout(body_);
  layout->setContentsMargins(6, 6, 6, 6);
  layout->setSpacing(4);

  newTab_ = headerButton(QIcon::fromTheme("tab-new"), "New tab (Ctrl+T)");
  newTab_->setText("New tab");
  collapse_ = headerButton(QIcon(), QString());
  pin_ = headerButton(QIcon(), QString());
  header_ = new QBoxLayout(QBoxLayout::LeftToRight);
  header_->setSpacing(2);
  header_->addWidget(newTab_);
  header_->addStretch();
  header_->addWidget(collapse_);
  header_->addWidget(pin_);
  layout->addLayout(header_);

  list_ = new QListWidget;
  list_->setFrameShape(QFrame::NoFrame);
  list_->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
  list_->setDragDropMode(QAbstractItemView::InternalMove);
  list_->setDefaultDropAction(Qt::MoveAction);
  list_->setContextMenuPolicy(Qt::CustomContextMenu);
  list_->viewport()->installEventFilter(this);
  // Transparent, so the glass behind shows through like the rest.
  list_->setAttribute(Qt::WA_TranslucentBackground);
  list_->viewport()->setAutoFillBackground(false);
  layout->addWidget(list_, 1);

  edge_ = new EdgeZone(host, [this] { reveal(); });
  edge_->hide();
  host_->installEventFilter(this);

  roll_ = new QVariantAnimation(this);
  roll_->setEasingCurve(QEasingCurve::OutCubic);
  connect(roll_, &QVariantAnimation::valueChanged, this,
          [this](const QVariant& w) { setFixedWidth(w.toInt()); });

  slide_ = new QPropertyAnimation(this, "pos", this);
  slide_->setDuration(140);
  slide_->setEasingCurve(QEasingCurve::OutCubic);
  hideTimer_ = new QTimer(this);
  hideTimer_->setSingleShot(true);
  hideTimer_->setInterval(350);
  connect(hideTimer_, &QTimer::timeout, this, [this] {
    // Not while the pointer is back over it, or a menu from it is open.
    if (underMouse() || QApplication::activePopupWidget() != nullptr) return;
    if (peeking_) {
      unpeek();
    } else {
      slideAway();
    }
  });
  peekTimer_ = new QTimer(this);
  peekTimer_->setSingleShot(true);
  peekTimer_->setInterval(250);  // a pass-by doesn't open it
  connect(peekTimer_, &QTimer::timeout, this, [this] {
    if (underMouse()) peek();
  });
  spacer_ = new QWidget(host);
  spacer_->setFixedWidth(kCollapsedWidth);
  spacer_->hide();
  refreshTimer_ = new QTimer(this);
  refreshTimer_->setSingleShot(true);
  refreshTimer_->setInterval(0);
  connect(refreshTimer_, &QTimer::timeout, this, &TabSidebar::rebuild);

  connect(newTab_, &QToolButton::clicked, this, &TabSidebar::newTabRequested);
  connect(collapse_, &QToolButton::clicked, this, [this] {
    if (peeking_ || mode_ == AutoHide) {
      setMode(mode_ == Collapsed ? Expanded : Collapsed);
    } else if (mode_ == Expanded) {
      // Roll the titles away, then settle into the strip.
      rolling_ = true;
      syncBody();
      rollTo(kCollapsedWidth, [this] { setMode(Collapsed); });
    } else {
      setMode(Expanded);
      rolling_ = true;
      syncBody();
      setFixedWidth(kCollapsedWidth);
      rollTo(kExpandedWidth, [this] {
        rolling_ = false;
        syncBody();
      });
    }
  });
  connect(pin_, &QToolButton::clicked, this, &TabSidebar::toggleAutoHide);
  connect(list_, &QListWidget::currentRowChanged, this, [this](int row) {
    if (row >= 0 && row != tabs_->currentIndex()) tabs_->setCurrentIndex(row);
  });
  // A drag in the list moves the tab; the tab bar's tabMoved keeps the
  // pages in step, and the rows are rebuilt from it.
  connect(list_->model(), &QAbstractItemModel::rowsMoved, this,
          [this](const QModelIndex&, int start, int, const QModelIndex&, int row) {
            const int to = row > start ? row - 1 : row;
            if (to != start) tabs_->moveTab(start, to);
            refresh();
          });
  connect(list_, &QListWidget::customContextMenuRequested, this,
          [this](const QPoint& pos) {
            const int row = list_->indexAt(pos).row();
            if (row < 0) return;
            QMenu menu;
            menu.addAction(QIcon::fromTheme("window-close"), "Close tab", this,
                           [this, row] { emit closeRequested(row); });
            menu.addAction("Close other tabs", this, [this, row] {
              for (int i = tabs_->count() - 1; i >= 0; i--) {
                if (i != row) emit closeRequested(i);
              }
            });
            menu.addAction("Close tabs below", this, [this, row] {
              for (int i = tabs_->count() - 1; i > row; i--) emit closeRequested(i);
            });
            menu.exec(list_->viewport()->mapToGlobal(pos));
          });

  updateButtons();
}

void TabSidebar::refresh() { refreshTimer_->start(); }

void TabSidebar::rebuild() {
  const bool collapsed = showCollapsed();
  const int current = tabs_->currentIndex();
  const int scroll = list_->verticalScrollBar()->value();
  list_->blockSignals(true);
  list_->clear();
  for (int i = 0; i < tabs_->count(); i++) {
    auto* item = new QListWidgetItem;
    item->setSizeHint(QSize(0, kRowHeight));
    item->setToolTip(tabs_->tabToolTip(i).isEmpty() ? tabs_->tabText(i)
                                                    : tabs_->tabToolTip(i));
    list_->addItem(item);
    list_->setItemWidget(
        item, new TabRow(tabs_->tabIcon(i), tabs_->tabText(i), collapsed,
                         i == current, [this, i] { emit closeRequested(i); }));
  }
  list_->setCurrentRow(current);
  list_->blockSignals(false);
  list_->verticalScrollBar()->setValue(scroll);
  if (current >= 0) list_->scrollToItem(list_->item(current));
}

void TabSidebar::setMode(Mode mode) {
  if (mode != AutoHide) docked_ = mode;
  mode_ = mode;
  place();
  updateButtons();
  rebuild();
  emit modeChanged(mode);
}

void TabSidebar::toggleAutoHide() {
  setMode(mode_ == AutoHide ? docked_ : AutoHide);
}

void TabSidebar::setActive(bool active) {
  active_ = active;
  place();
}

// Docked modes sit in the layout left of the pages; auto-hide takes the
// sidebar out of the layout and floats it over them.
void TabSidebar::place() {
  slide_->stop();
  roll_->stop();
  hideTimer_->stop();
  peekTimer_->stop();
  revealed_ = false;
  peeking_ = false;
  rolling_ = false;
  closing_ = false;
  const bool floating = mode_ == AutoHide;
  dock_->removeWidget(this);
  dock_->removeWidget(spacer_);
  spacer_->hide();
  setAutoFillBackground(floating);
  // Floating pins the height to the page area; docked, the layout sets it.
  setMinimumHeight(0);
  setMaximumHeight(QWIDGETSIZE_MAX);
  if (!active_) {
    hide();
    edge_->hide();
    return;
  }
  if (floating) {
    floatOverPage(kExpandedWidth);
    hide();
    edge_->show();
    positionOverlay();
    edge_->raise();
  } else {
    setPalette(QApplication::palette());
    setFixedWidth(mode_ == Collapsed ? kCollapsedWidth : kExpandedWidth);
    dock_->insertWidget(0, this);
    edge_->hide();
    show();
  }
  syncBody();
}

// Over the page the sidebar needs a solid enough background to read.
void TabSidebar::floatOverPage(int width) {
  QPalette p = palette();
  QColor bg = QApplication::palette().color(QPalette::Window);
  bg.setAlpha(240);
  p.setColor(QPalette::Window, bg);
  setPalette(p);
  setAutoFillBackground(true);
  setFixedWidth(width);
  setFixedHeight(host_->height());
}

void TabSidebar::positionOverlay() {
  setFixedHeight(host_->height());
  if (peeking_) return;
  edge_->setGeometry(0, 0, kEdgeWidth, host_->height());
  if (!revealed_) move(-width(), 0);
}

void TabSidebar::peek() {
  if (mode_ != Collapsed || peeking_ || !active_) return;
  peeking_ = true;
  hideTimer_->stop();
  dock_->removeWidget(this);
  dock_->insertWidget(0, spacer_);
  spacer_->show();
  // Starts as wide as the strip, with the full-width rows behind it, and
  // rolls open over the page.
  floatOverPage(kCollapsedWidth);
  rolling_ = true;
  syncBody();
  move(0, 0);
  raise();
  show();
  updateButtons();
  rebuild();
  rollTo(kExpandedWidth, [this] {
    rolling_ = false;
    syncBody();
  });
}

void TabSidebar::unpeek() {
  if (!peeking_ || closing_) return;
  closing_ = true;
  rolling_ = true;
  syncBody();
  rollTo(kCollapsedWidth, [this] {
    place();  // back into the layout, collapsed
    updateButtons();
    rebuild();
  });
}

void TabSidebar::rollTo(int target, std::function<void()> done) {
  roll_->stop();
  disconnect(roll_, &QVariantAnimation::finished, this, nullptr);
  const int from = width();
  // A partial roll (reversed halfway) takes proportionally less time.
  const int span = kExpandedWidth - kCollapsedWidth;
  roll_->setDuration(std::max(60, kRollMs * std::abs(target - from) / span));
  roll_->setStartValue(from);
  roll_->setEndValue(target);
  connect(roll_, &QVariantAnimation::finished, this, std::move(done),
          Qt::SingleShotConnection);
  roll_->start();
}

// The content: as wide as the sidebar, except mid-roll, when it stays at
// full width and the sidebar's own edge clips it.
void TabSidebar::syncBody() {
  body_->setGeometry(0, 0, rolling_ ? kExpandedWidth : maximumWidth(),
                     height());
}

void TabSidebar::resizeEvent(QResizeEvent* event) {
  syncBody();
  QWidget::resizeEvent(event);
}

void TabSidebar::reveal() {
  if (mode_ != AutoHide || revealed_) return;
  revealed_ = true;
  hideTimer_->stop();
  rebuild();
  show();
  raise();
  slide_->stop();
  slide_->setStartValue(QPoint(-width(), 0));
  slide_->setEndValue(QPoint(0, 0));
  slide_->start();
}

void TabSidebar::slideAway() {
  if (mode_ != AutoHide || !revealed_) return;
  revealed_ = false;
  slide_->stop();
  slide_->setStartValue(pos());
  slide_->setEndValue(QPoint(-width(), 0));
  connect(slide_, &QPropertyAnimation::finished, this, [this] {
    if (!revealed_ && mode_ == AutoHide) hide();
  }, Qt::SingleShotConnection);
  slide_->start();
  edge_->raise();
}

void TabSidebar::updateButtons() {
  const bool collapsed = showCollapsed();
  // Collapsed: the header stacks vertically in the narrow strip.
  header_->setDirection(collapsed ? QBoxLayout::TopToBottom
                                  : QBoxLayout::LeftToRight);
  newTab_->setToolButtonStyle(collapsed ? Qt::ToolButtonIconOnly
                                        : Qt::ToolButtonTextBesideIcon);
  collapse_->setVisible(mode_ != AutoHide);
  // By the setting, not the peek: while peeking it offers to keep it open.
  const bool narrow = mode_ == Collapsed;
  collapse_->setIcon(narrow ? themed("sidebar-expand-left", "go-next")
                            : themed("sidebar-collapse-left", "go-previous"));
  collapse_->setToolTip(narrow ? "Keep tab titles shown" : "Show icons only");
  pin_->setIcon(mode_ == AutoHide ? themed("window-pin", "pin")
                                  : themed("view-hidden", "visibility"));
  pin_->setToolTip(mode_ == AutoHide ? "Keep the tab sidebar open (Ctrl+\\)"
                                     : "Hide the tab sidebar until the pointer "
                                       "reaches the left edge (Ctrl+\\)");
  pin_->setVisible(!collapsed);
}

void TabSidebar::enterEvent(QEnterEvent* event) {
  hideTimer_->stop();
  if (closing_) {
    // Back before it finished rolling shut: roll open again from here.
    closing_ = false;
    rollTo(kExpandedWidth, [this] {
      rolling_ = false;
      syncBody();
    });
  }
  if (mode_ == Collapsed && !peeking_) peekTimer_->start();
  QWidget::enterEvent(event);
}

void TabSidebar::leaveEvent(QEvent* event) {
  peekTimer_->stop();
  if ((mode_ == AutoHide && revealed_) || peeking_) hideTimer_->start();
  QWidget::leaveEvent(event);
}

bool TabSidebar::eventFilter(QObject* watched, QEvent* event) {
  if (watched == host_ && event->type() == QEvent::Resize &&
      (mode_ == AutoHide || peeking_)) {
    positionOverlay();
  }
  // Middle click closes, as on the tab bar.
  if (watched == list_->viewport() &&
      event->type() == QEvent::MouseButtonRelease) {
    auto* me = static_cast<QMouseEvent*>(event);
    if (me->button() == Qt::MiddleButton) {
      const int row = list_->indexAt(me->position().toPoint()).row();
      if (row >= 0) emit closeRequested(row);
      return true;
    }
  }
  return QWidget::eventFilter(watched, event);
}
