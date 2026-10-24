// Vertical tabs: a sidebar that mirrors the window's QTabBar (which stays
// the source of truth, just hidden) and can be expanded (icon + title),
// collapsed (icons only) or auto-hidden (slides out over the page when the
// pointer reaches the window's left edge).
#pragma once

#include <QWidget>

#include <functional>

class QBoxLayout;
class QHBoxLayout;
class QListWidget;
class QPropertyAnimation;
class QTabBar;
class QTimer;
class QVariantAnimation;
class QToolButton;

class TabSidebar : public QWidget {
  Q_OBJECT
 public:
  enum Mode { Expanded, Collapsed, AutoHide };

  // `dock` is the layout the sidebar sits in (left of the pages) when it's
  // expanded or collapsed; `host` is the widget that layout belongs to,
  // which it floats over when auto-hidden.
  TabSidebar(QTabBar* tabs, QWidget* host, QHBoxLayout* dock);

  Mode mode() const { return mode_; }
  void setMode(Mode mode);
  // Auto-hide on/off, back to the last docked mode.
  void toggleAutoHide();

  // Shown at all (vertical tabs on, not in full screen).
  void setActive(bool active);

  // Rebuild the rows from the tab bar (batched to the next event loop turn).
  void refresh();

 signals:
  void newTabRequested();
  void closeRequested(int index);
  void modeChanged(Mode mode);

 protected:
  bool eventFilter(QObject* watched, QEvent* event) override;
  void enterEvent(QEnterEvent* event) override;
  void leaveEvent(QEvent* event) override;
  void resizeEvent(QResizeEvent* event) override;

 private:
  void rebuild();
  void place();
  void reveal();
  void slideAway();
  void positionOverlay();
  void updateButtons();
  // Collapsed strip only: open out to full width over the page on hover
  // (a placeholder keeps the page from moving), and back on leave.
  void peek();
  void unpeek();
  void floatOverPage(int width);
  // Animate the visible width (the "roll", as in Brave): the content keeps
  // its full width meanwhile and is uncovered or covered, not re-laid out.
  void rollTo(int width, std::function<void()> done);
  void syncBody();
  bool showCollapsed() const { return mode_ == Collapsed && !peeking_; }

  QTabBar* tabs_;
  QWidget* host_;
  QHBoxLayout* dock_;
  QBoxLayout* header_;
  QListWidget* list_;
  QToolButton* newTab_;
  QToolButton* collapse_;
  QToolButton* pin_;
  QWidget* edge_;  // the hot zone at the window's left edge (auto-hide)
  QWidget* spacer_;  // holds the collapsed strip's place while it peeks
  QWidget* body_;    // everything inside; wider than the sidebar mid-roll
  QVariantAnimation* roll_;
  QPropertyAnimation* slide_;
  QTimer* hideTimer_;
  QTimer* peekTimer_;
  QTimer* refreshTimer_;
  Mode mode_ = Expanded;
  Mode docked_ = Expanded;  // where toggleAutoHide returns to
  bool active_ = false;
  bool revealed_ = false;
  bool peeking_ = false;
  bool rolling_ = false;  // content laid out at full width, clipped
  bool closing_ = false;  // rolling back to the collapsed strip
};
