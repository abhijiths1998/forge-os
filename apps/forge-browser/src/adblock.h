// Forge Browser's built-in ad blocker.
//
// Network rules (Adblock Plus syntax, as in EasyList/EasyPrivacy) block
// requests in a QWebEngineUrlRequestInterceptor; element-hiding rules become
// CSS injected into pages. Filter lists download on first run and refresh
// weekly into ~/.cache/forge-browser/filters; a small built-in list covers the
// time before the first download.
#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QWebEngineUrlRequestInterceptor>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class QNetworkAccessManager;
class QWebEngineProfile;

namespace adblock {

// Resource types, as a bit mask (0 in a rule means "any").
enum Type : uint32_t {
  Script = 1 << 0,
  Image = 1 << 1,
  Stylesheet = 1 << 2,
  Xhr = 1 << 3,
  Subdocument = 1 << 4,
  Media = 1 << 5,
  Font = 1 << 6,
  Ping = 1 << 7,
  Websocket = 1 << 8,
  Other = 1 << 9,
};

struct Rule {
  std::string pattern;      // lower case, '*' and '^' wildcards
  bool domainAnchor = false;  // ||
  bool startAnchor = false;   // |
  bool endAnchor = false;     // trailing |
  uint32_t types = 0;
  int thirdParty = -1;  // -1 any, 1 third-party only, 0 first-party only
  std::vector<std::string> includeDomains;
  std::vector<std::string> excludeDomains;
};

struct Request {
  std::string url;   // lower case
  std::string host;  // lower case
  std::string pageHost;
  uint32_t type = Other;
  bool thirdParty = false;
};

// One parsed set of lists. Immutable once built, so the interceptor (on
// WebEngine's IO thread) can read it while a new one is being parsed.
class Engine {
 public:
  void addList(const QString& text);
  void finish();  // build the generic CSS once all lists are in

  bool shouldBlock(const Request& r) const;

  // CSS that hides ads on pages of `host`, generic rules included unless
  // the lists exempt the site.
  QString cssFor(const QString& host) const;
  const QString& genericCss() const { return generic_css_; }
  bool genericHideExempt(const QString& host) const;

  size_t networkRuleCount() const { return rule_count_; }

 private:
  void addLine(const std::string& line);
  void addCosmetic(const std::string& domains, const std::string& selector,
                   bool exception);
  bool matchAny(const std::vector<Rule>& rules,
                const std::unordered_map<std::string, std::vector<int>>& index,
                const std::vector<int>& untokenized, const Request& r) const;

  // ||example.com^ with no options: a hash lookup on the host and its
  // parent domains.
  std::unordered_set<std::string> blocked_hosts_;
  std::unordered_set<std::string> allowed_hosts_;
  // Everything else, indexed by a token the URL must contain.
  std::vector<Rule> block_rules_, allow_rules_;
  std::unordered_map<std::string, std::vector<int>> block_index_, allow_index_;
  std::vector<int> block_untokenized_, allow_untokenized_;
  // Sites the lists say to leave alone ($document) or not hide on.
  std::unordered_set<std::string> document_exempt_, generichide_exempt_;

  QStringList generic_selectors_;
  QHash<QString, QStringList> site_selectors_;       // host -> selectors
  QHash<QString, QSet<QString>> site_exceptions_;    // host -> #@# selectors
  QString generic_css_;
  size_t rule_count_ = 0;
};

class Blocker : public QWebEngineUrlRequestInterceptor {
  Q_OBJECT
 public:
  explicit Blocker(QObject* parent = nullptr);

  void install(QWebEngineProfile* profile);
  void interceptRequest(QWebEngineUrlRequestInfo& info) override;

  bool enabled() const { return enabled_; }
  void setEnabled(bool on);

  // Per-site switch (the shield in the toolbar).
  bool allowedOn(const QString& host) const;
  void setAllowedOn(const QString& host, bool allowed);

  // Requests blocked for pages on `host` since it was last reset.
  int blockedCount(const QString& host) const;
  void resetCount(const QString& host);

  QString cssFor(const QString& host) const;
  size_t ruleCount() const;
  QString lastUpdated() const;

  // Download fresh lists now (also done weekly on start).
  void updateLists();

 signals:
  void blocked(const QString& pageHost);
  void listsChanged();

 private:
  void rebuild();
  void refreshGenericScript();

  std::shared_ptr<const Engine> engine() const;

  QWebEngineProfile* profile_ = nullptr;
  QNetworkAccessManager* net_ = nullptr;
  mutable std::mutex mutex_;
  std::shared_ptr<const Engine> engine_;
  std::atomic<bool> enabled_{true};
  QSet<QString> allowed_sites_;  // guarded by mutex_
  QHash<QString, int> counts_;   // guarded by mutex_
  int pending_downloads_ = 0;
};

}  // namespace adblock
