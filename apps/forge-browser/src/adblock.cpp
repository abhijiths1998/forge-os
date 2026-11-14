#include "adblock.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>
#include <QWebEngineProfile>
#include <QWebEngineScript>
#include <QWebEngineScriptCollection>

#include <algorithm>
#include <thread>

namespace adblock {

namespace {

struct List {
  const char* file;
  const char* url;
};

// EasyList (ads), EasyPrivacy (trackers) and Peter Lowe's ad/tracking
// server list: the core of what uBlock Origin and Brave ship by default.
constexpr List kLists[] = {
    {"easylist.txt", "https://easylist.to/easylist/easylist.txt"},
    {"easyprivacy.txt", "https://easylist.to/easylist/easyprivacy.txt"},
    {"peterlowe.txt",
     "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus"
     "&showintro=0&mimetype=plaintext"},
};
constexpr qint64 kRefreshSecs = 7 * 24 * 3600;

QString filterDir() {
  return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) +
         "/filters";
}

bool isTokenChar(char c) {
  return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '%';
}

// '^' in a pattern: anything but a letter, digit or _-.% (or the end).
bool isSeparator(char c) {
  return !(isTokenChar(c) || c == '_' || c == '-' || c == '.');
}

// Does `p` (with '*' and '^') match `s` starting at `si`? Without
// `to_end` only a prefix of s[si..] has to match.
bool globMatch(const std::string& p, const std::string& s, size_t si,
               bool to_end) {
  size_t pi = 0;
  size_t star_p = std::string::npos, star_s = 0;
  while (true) {
    if (pi == p.size()) {
      if (!to_end || si == s.size()) return true;
    } else if (p[pi] == '*') {
      star_p = pi++;
      star_s = si;
      continue;
    } else if (si < s.size() &&
               (p[pi] == '^' ? isSeparator(s[si]) : p[pi] == s[si])) {
      pi++;
      si++;
      continue;
    } else if (p[pi] == '^' && si == s.size()) {
      pi++;
      continue;
    }
    if (star_p == std::string::npos || star_s >= s.size()) return false;
    pi = star_p + 1;
    si = ++star_s;
  }
}

bool hostMatches(const std::string& host, const std::string& domain) {
  return host == domain ||
         (host.size() > domain.size() &&
          host.compare(host.size() - domain.size(), domain.size(), domain) ==
              0 &&
          host[host.size() - domain.size() - 1] == '.');
}

// Is `host`, or a domain it belongs to, in `set`?
bool inSet(const std::unordered_set<std::string>& set, std::string host) {
  while (!host.empty()) {
    if (set.count(host)) return true;
    const size_t dot = host.find('.');
    if (dot == std::string::npos) break;
    host.erase(0, dot + 1);
  }
  return false;
}

// "Registrable" domain, roughly: the last two labels, or three under a
// two-letter country code with a generic second level (example.co.uk).
std::string baseDomain(const std::string& host) {
  std::vector<size_t> dots;
  for (size_t i = 0; i < host.size(); i++) {
    if (host[i] == '.') dots.push_back(i);
  }
  if (dots.size() < 1) return host;
  size_t labels = 2;
  const std::string tld = host.substr(dots.back() + 1);
  if (tld.size() == 2 && dots.size() >= 2) {
    const std::string sld =
        host.substr(dots[dots.size() - 2] + 1, dots.back() - dots[dots.size() - 2] - 1);
    static const std::unordered_set<std::string> generic = {
        "co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go"};
    if (generic.count(sld)) labels = 3;
  }
  if (dots.size() < labels) return host;
  return host.substr(dots[dots.size() - labels] + 1);
}

// The longest run of token characters not touching a wildcard; the
// request URL must contain it, so rules are only tried for URLs that do.
std::string pickToken(const std::string& p) {
  std::string best;
  size_t i = 0;
  while (i < p.size()) {
    if (!isTokenChar(p[i])) {
      i++;
      continue;
    }
    size_t j = i;
    while (j < p.size() && isTokenChar(p[j])) j++;
    const bool before_star = i > 0 && p[i - 1] == '*';
    const bool after_star = j < p.size() && p[j] == '*';
    if (!before_star && !after_star && j - i > best.size()) {
      best = p.substr(i, j - i);
    }
    i = j;
  }
  return best.size() >= 2 ? best : std::string();
}

uint32_t typeFromOption(const std::string& o) {
  static const std::unordered_map<std::string, uint32_t> types = {
      {"script", Script},           {"image", Image},
      {"stylesheet", Stylesheet},   {"css", Stylesheet},
      {"xmlhttprequest", Xhr},      {"xhr", Xhr},
      {"subdocument", Subdocument}, {"frame", Subdocument},
      {"media", Media},             {"font", Font},
      {"ping", Ping},               {"websocket", Websocket},
      {"other", Other},             {"object", Other},
  };
  auto it = types.find(o);
  return it == types.end() ? 0 : it->second;
}

// Options that change what a rule does rather than what it matches (CSP
// injection, redirects, parameter removal...): rules using them are left out.
bool unsupportedOption(const std::string& o) {
  static const char* const prefixes[] = {
      "popup", "csp", "redirect", "removeparam", "rewrite", "badfilter",
      "header", "permissions", "genericblock", "all", "cname",
      "inline-script", "inline-font", "empty", "mp4", "replace",
      "urltransform", "denyallow", "to=", "from=", "method=", "strict"};
  for (const char* p : prefixes) {
    if (o.rfind(p, 0) == 0) return true;
  }
  return false;
}

void splitDomains(const std::string& list, char sep, Rule& rule) {
  size_t start = 0;
  while (start <= list.size()) {
    size_t end = list.find(sep, start);
    if (end == std::string::npos) end = list.size();
    std::string d = list.substr(start, end - start);
    if (!d.empty()) {
      if (d[0] == '~') {
        rule.excludeDomains.push_back(d.substr(1));
      } else {
        rule.includeDomains.push_back(d);
      }
    }
    start = end + 1;
  }
}

constexpr const char* kBuiltin =
#include "builtin_filters.inc"
    ;

}  // namespace

// --- Engine: parsing -----------------------------------------------------------

void Engine::addList(const QString& text) {
  const QByteArray utf8 = text.toUtf8();
  size_t start = 0;
  const std::string all(utf8.constData(), utf8.size());
  while (start < all.size()) {
    size_t end = all.find('\n', start);
    if (end == std::string::npos) end = all.size();
    std::string line = all.substr(start, end - start);
    while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) {
      line.pop_back();
    }
    if (!line.empty()) addLine(line);
    start = end + 1;
  }
}

void Engine::addLine(const std::string& line) {
  if (line[0] == '!' || line[0] == '[') return;

  // Element hiding: "domains##selector" / "domains#@#selector". Extended
  // syntaxes (#?#, #$#, #%#, scriptlets) need a content script engine.
  if (size_t at = line.find("#@#"); at != std::string::npos) {
    addCosmetic(line.substr(0, at), line.substr(at + 3), true);
    return;
  }
  if (size_t at = line.find("##"); at != std::string::npos) {
    addCosmetic(line.substr(0, at), line.substr(at + 2), false);
    return;
  }
  if (line.find("#?#") != std::string::npos ||
      line.find("#$#") != std::string::npos ||
      line.find("#%#") != std::string::npos) {
    return;
  }

  std::string text = line;
  const bool exception = text.rfind("@@", 0) == 0;
  if (exception) text.erase(0, 2);
  if (text.size() > 1 && text.front() == '/' && text.back() == '/') return;

  Rule rule;
  bool document = false, generichide = false;
  if (size_t dollar = text.rfind('$');
      dollar != std::string::npos && dollar + 1 < text.size()) {
    std::string options = text.substr(dollar + 1);
    text.erase(dollar);
    std::transform(options.begin(), options.end(), options.begin(), ::tolower);
    uint32_t include = 0, exclude = 0;
    size_t s = 0;
    while (s <= options.size()) {
      size_t e = options.find(',', s);
      if (e == std::string::npos) e = options.size();
      const std::string o = options.substr(s, e - s);
      s = e + 1;
      if (o.empty() || o == "match-case" || o == "important") continue;
      if (o == "third-party" || o == "3p") {
        rule.thirdParty = 1;
      } else if (o == "~third-party" || o == "first-party" || o == "1p" ||
                 o == "~3p") {
        rule.thirdParty = 0;
      } else if (o.rfind("domain=", 0) == 0) {
        splitDomains(o.substr(7), '|', rule);
      } else if (o == "document" || o == "doc") {
        document = true;
      } else if (o == "elemhide" || o == "ehide" || o == "generichide" ||
                 o == "ghide") {
        generichide = true;
      } else if (o[0] == '~' && typeFromOption(o.substr(1))) {
        exclude |= typeFromOption(o.substr(1));
      } else if (typeFromOption(o)) {
        include |= typeFromOption(o);
      } else if (unsupportedOption(o)) {
        return;
      } else {
        return;  // unknown option: don't guess
      }
    }
    if (exclude) include = (include ? include : 0x3ff) & ~exclude;
    rule.types = include;
  }

  if (text.rfind("||", 0) == 0) {
    rule.domainAnchor = true;
    text.erase(0, 2);
  } else if (!text.empty() && text[0] == '|') {
    rule.startAnchor = true;
    text.erase(0, 1);
  }
  if (!text.empty() && text.back() == '|') {
    rule.endAnchor = true;
    text.pop_back();
  }
  std::transform(text.begin(), text.end(), text.begin(), ::tolower);
  while (!rule.domainAnchor && !rule.startAnchor && !text.empty() &&
         text.front() == '*') {
    text.erase(0, 1);
  }
  while (!rule.endAnchor && !text.empty() && text.back() == '*') {
    text.pop_back();
  }

  // Page-level exemptions: @@||site^$document / $elemhide.
  if (exception && (document || generichide)) {
    std::string host = text;
    if (!host.empty() && host.back() == '^') host.pop_back();
    if (rule.domainAnchor && !host.empty() &&
        host.find_first_of("/*^") == std::string::npos) {
      (document ? document_exempt_ : generichide_exempt_).insert(host);
    }
    return;
  }
  if (document || generichide) return;
  if (text.empty()) return;

  // ||host^ with no options: the fast path.
  const bool plain_host =
      rule.domainAnchor && !rule.endAnchor && rule.types == 0 &&
      rule.thirdParty == -1 && rule.includeDomains.empty() &&
      rule.excludeDomains.empty() && text.back() == '^' &&
      text.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789.-") ==
          text.size() - 1;
  rule_count_++;
  if (plain_host) {
    (exception ? allowed_hosts_ : blocked_hosts_)
        .insert(text.substr(0, text.size() - 1));
    return;
  }

  rule.pattern = text;
  auto& rules = exception ? allow_rules_ : block_rules_;
  auto& index = exception ? allow_index_ : block_index_;
  auto& untokenized = exception ? allow_untokenized_ : block_untokenized_;
  const int id = static_cast<int>(rules.size());
  const std::string token = pickToken(text);
  rules.push_back(std::move(rule));
  if (token.empty()) {
    untokenized.push_back(id);
  } else {
    index[token].push_back(id);
  }
}

void Engine::addCosmetic(const std::string& domains,
                         const std::string& selector, bool exception) {
  // Procedural/extended selectors only work with a script engine.
  static const char* const extended[] = {":-abp-", ":has-text", ":xpath",
                                         ":matches-css", ":upward",
                                         ":remove(", ":style(", "+js(",
                                         ":min-text-length", ":watch-attr",
                                         ":matches-path", ":others("};
  if (selector.empty() || selector.find_first_of("{}") != std::string::npos) {
    return;
  }
  for (const char* e : extended) {
    if (selector.find(e) != std::string::npos) return;
  }
  const QString sel = QString::fromStdString(selector);
  if (domains.empty()) {
    if (!exception) generic_selectors_.append(sel);
    return;
  }
  size_t start = 0;
  while (start <= domains.size()) {
    size_t end = domains.find(',', start);
    if (end == std::string::npos) end = domains.size();
    std::string d = domains.substr(start, end - start);
    start = end + 1;
    if (d.empty() || d[0] == '~') continue;
    std::transform(d.begin(), d.end(), d.begin(), ::tolower);
    const QString host = QString::fromStdString(d);
    if (exception) {
      site_exceptions_[host].insert(sel);
    } else {
      site_selectors_[host].append(sel);
    }
  }
}

namespace {

// Selectors in small groups: one invalid selector only voids its group.
QString cssFrom(const QStringList& selectors) {
  QString css;
  for (qsizetype i = 0; i < selectors.size(); i += 30) {
    css += selectors.mid(i, 30).join(',');
    css += "{display:none!important}\n";
  }
  return css;
}

}  // namespace

void Engine::finish() {
  generic_selectors_.removeDuplicates();
  generic_css_ = cssFrom(generic_selectors_);
  generic_selectors_.clear();
}

// --- Engine: matching ----------------------------------------------------------

namespace {

bool ruleMatches(const Rule& rule, const Request& r) {
  if (rule.types && !(rule.types & r.type)) return false;
  if (rule.thirdParty != -1 && rule.thirdParty != (r.thirdParty ? 1 : 0)) {
    return false;
  }
  if (!rule.includeDomains.empty() &&
      std::none_of(rule.includeDomains.begin(), rule.includeDomains.end(),
                   [&](const std::string& d) {
                     return hostMatches(r.pageHost, d);
                   })) {
    return false;
  }
  for (const auto& d : rule.excludeDomains) {
    if (hostMatches(r.pageHost, d)) return false;
  }
  const std::string& p = rule.pattern;
  if (rule.startAnchor) return globMatch(p, r.url, 0, rule.endAnchor);
  if (rule.domainAnchor) {
    // At the start of the host or of any of its labels.
    const size_t host_at = r.url.find("://");
    if (host_at == std::string::npos) return false;
    const size_t begin = host_at + 3;
    const size_t host_end = begin + r.host.size();
    for (size_t i = begin; i < host_end; i++) {
      if ((i == begin || r.url[i - 1] == '.') &&
          globMatch(p, r.url, i, rule.endAnchor)) {
        return true;
      }
    }
    return false;
  }
  for (size_t i = 0; i < r.url.size(); i++) {
    if ((p[0] == '*' || p[0] == '^' || r.url[i] == p[0]) &&
        globMatch(p, r.url, i, rule.endAnchor)) {
      return true;
    }
  }
  return false;
}

}  // namespace

bool Engine::matchAny(
    const std::vector<Rule>& rules,
    const std::unordered_map<std::string, std::vector<int>>& index,
    const std::vector<int>& untokenized, const Request& r) const {
  // Every token in the URL picks the rules filed under it.
  size_t i = 0;
  const std::string& u = r.url;
  while (i < u.size()) {
    if (!isTokenChar(u[i])) {
      i++;
      continue;
    }
    size_t j = i;
    while (j < u.size() && isTokenChar(u[j])) j++;
    auto it = index.find(u.substr(i, j - i));
    if (it != index.end()) {
      for (int id : it->second) {
        if (ruleMatches(rules[id], r)) return true;
      }
    }
    i = j;
  }
  for (int id : untokenized) {
    if (ruleMatches(rules[id], r)) return true;
  }
  return false;
}

bool Engine::shouldBlock(const Request& r) const {
  if (inSet(document_exempt_, r.pageHost)) return false;
  const bool hit =
      inSet(blocked_hosts_, r.host) ||
      matchAny(block_rules_, block_index_, block_untokenized_, r);
  if (!hit) return false;
  return !inSet(allowed_hosts_, r.host) &&
         !matchAny(allow_rules_, allow_index_, allow_untokenized_, r);
}

bool Engine::genericHideExempt(const QString& host) const {
  const std::string h = host.toStdString();
  return inSet(generichide_exempt_, h) || inSet(document_exempt_, h);
}

QString Engine::cssFor(const QString& host) const {
  QStringList selectors;
  QSet<QString> exceptions;
  QString h = host;
  while (!h.isEmpty()) {
    selectors += site_selectors_.value(h);
    exceptions += site_exceptions_.value(h);
    const qsizetype dot = h.indexOf('.');
    if (dot < 0) break;
    h = h.mid(dot + 1);
  }
  selectors.removeIf([&](const QString& s) { return exceptions.contains(s); });
  return cssFrom(selectors);
}

// --- Blocker ---------------------------------------------------------------------

Blocker::Blocker(QObject* parent)
    : QWebEngineUrlRequestInterceptor(parent),
      net_(new QNetworkAccessManager(this)) {
  QSettings s;
  enabled_ = s.value("adblock/enabled", true).toBool();
  const auto sites = s.value("adblock/allowedSites").toStringList();
  allowed_sites_ = QSet<QString>(sites.begin(), sites.end());
  rebuild();

  // Refresh weekly; on first run this is the first download.
  QFileInfo stamp(filterDir() + "/" + kLists[0].file);
  if (!stamp.exists() ||
      stamp.lastModified().secsTo(QDateTime::currentDateTime()) > kRefreshSecs) {
    QTimer::singleShot(3000, this, &Blocker::updateLists);
  }
}

void Blocker::install(QWebEngineProfile* profile) {
  profile_ = profile;
  profile->setUrlRequestInterceptor(this);
  refreshGenericScript();
}

std::shared_ptr<const Engine> Blocker::engine() const {
  std::lock_guard lock(mutex_);
  return engine_;
}

// Parse the cached lists (or the built-in one) on a worker thread and swap
// the result in.
void Blocker::rebuild() {
  QPointer<Blocker> self(this);
  std::thread([self] {
    auto engine = std::make_shared<Engine>();
    bool any = false;
    for (const auto& list : kLists) {
      QFile f(filterDir() + "/" + list.file);
      if (f.open(QIODevice::ReadOnly)) {
        engine->addList(QString::fromUtf8(f.readAll()));
        any = true;
      }
    }
    if (!any) engine->addList(QString::fromUtf8(kBuiltin));
    engine->finish();
    QMetaObject::invokeMethod(
        QCoreApplication::instance(),
        [self, engine] {
          if (!self) return;
          {
            std::lock_guard lock(self->mutex_);
            self->engine_ = engine;
          }
          self->refreshGenericScript();
          emit self->listsChanged();
        },
        Qt::QueuedConnection);
  }).detach();
}

// Generic hiding CSS goes to every page through one profile-wide script;
// sites exempt from it are listed in the script itself.
void Blocker::refreshGenericScript() {
  if (profile_ == nullptr) return;
  auto* scripts = profile_->scripts();
  for (const auto& s : scripts->find("forge-adblock-generic")) {
    scripts->remove(s);
  }
  const auto e = engine();
  if (!enabled_ || !e || e->genericCss().isEmpty()) return;

  QStringList exempt;
  {
    std::lock_guard lock(mutex_);
    exempt = QStringList(allowed_sites_.begin(), allowed_sites_.end());
  }
  QString js = QStringLiteral(
      "(() => {"
      "const h = location.hostname, off = %1;"
      "if (off.some(d => h === d || h.endsWith('.' + d))) return;"
      "const add = () => {"
      "  const s = document.createElement('style');"
      "  s.textContent = %2;"
      "  (document.head || document.documentElement).appendChild(s);"
      "};"
      "if (document.documentElement) add();"
      "else document.addEventListener('readystatechange', add, {once: true});"
      "})();");
  auto quote = [](const QString& s) {
    QString out = s;
    out.replace('\\', "\\\\").replace('`', "\\`").replace("${", "\\${");
    return "`" + out + "`";
  };
  QString list = "[";
  for (const auto& d : exempt) list += quote(d) + ",";
  list += "]";
  QWebEngineScript script;
  script.setName("forge-adblock-generic");
  script.setInjectionPoint(QWebEngineScript::DocumentCreation);
  script.setRunsOnSubFrames(true);
  script.setWorldId(QWebEngineScript::ApplicationWorld);
  script.setSourceCode(js.arg(list, quote(e->genericCss())));
  scripts->insert(script);
}

QString Blocker::cssFor(const QString& host) const {
  const auto e = engine();
  if (!enabled_ || !e || allowedOn(host)) return {};
  return e->cssFor(host);
}

size_t Blocker::ruleCount() const {
  const auto e = engine();
  return e ? e->networkRuleCount() : 0;
}

QString Blocker::lastUpdated() const {
  QFileInfo f(filterDir() + "/" + kLists[0].file);
  return f.exists() ? QLocale().toString(f.lastModified(), QLocale::ShortFormat)
                    : QString();
}

void Blocker::setEnabled(bool on) {
  enabled_ = on;
  QSettings().setValue("adblock/enabled", on);
  refreshGenericScript();
}

bool Blocker::allowedOn(const QString& host) const {
  std::lock_guard lock(mutex_);
  QString h = host;
  while (!h.isEmpty()) {
    if (allowed_sites_.contains(h)) return true;
    const qsizetype dot = h.indexOf('.');
    if (dot < 0) break;
    h = h.mid(dot + 1);
  }
  return false;
}

void Blocker::setAllowedOn(const QString& host, bool allowed) {
  {
    std::lock_guard lock(mutex_);
    if (allowed) {
      allowed_sites_.insert(host);
    } else {
      allowed_sites_.remove(host);
    }
    QSettings().setValue(
        "adblock/allowedSites",
        QStringList(allowed_sites_.begin(), allowed_sites_.end()));
  }
  refreshGenericScript();
}

int Blocker::blockedCount(const QString& host) const {
  std::lock_guard lock(mutex_);
  return counts_.value(host);
}

void Blocker::resetCount(const QString& host) {
  std::lock_guard lock(mutex_);
  counts_.remove(host);
}

void Blocker::interceptRequest(QWebEngineUrlRequestInfo& info) {
  if (!enabled_) return;
  using RT = QWebEngineUrlRequestInfo::ResourceType;
  const RT rt = info.resourceType();
  if (rt == RT::ResourceTypeMainFrame) return;
  const QUrl url = info.requestUrl();
  if (url.scheme() != "http" && url.scheme() != "https" &&
      url.scheme() != "ws" && url.scheme() != "wss") {
    return;
  }
  const QString page_host = info.firstPartyUrl().host().toLower();
  if (allowedOn(page_host)) return;
  const auto e = engine();
  if (!e) return;

  Request r;
  r.url = url.toString(QUrl::FullyEncoded).toLower().toStdString();
  r.host = url.host().toLower().toStdString();
  r.pageHost = page_host.toStdString();
  r.thirdParty = r.pageHost.empty() || baseDomain(r.host) != baseDomain(r.pageHost);
  switch (rt) {
    case RT::ResourceTypeSubFrame: r.type = Subdocument; break;
    case RT::ResourceTypeStylesheet: r.type = Stylesheet; break;
    case RT::ResourceTypeScript:
    case RT::ResourceTypeWorker:
    case RT::ResourceTypeSharedWorker:
    case RT::ResourceTypeServiceWorker: r.type = Script; break;
    case RT::ResourceTypeImage:
    case RT::ResourceTypeFavicon: r.type = Image; break;
    case RT::ResourceTypeFontResource: r.type = Font; break;
    case RT::ResourceTypeMedia: r.type = Media; break;
    case RT::ResourceTypeXhr:
    case RT::ResourceTypeJson: r.type = Xhr; break;
    case RT::ResourceTypePing:
    case RT::ResourceTypeCspReport: r.type = Ping; break;
    case RT::ResourceTypeWebSocket: r.type = Websocket; break;
    default: r.type = Other; break;
  }
  if (e->shouldBlock(r)) {
    info.block(true);
    {
      std::lock_guard lock(mutex_);
      counts_[page_host]++;
    }
    emit blocked(page_host);
  }
}

void Blocker::updateLists() {
  if (pending_downloads_ > 0) return;
  QDir().mkpath(filterDir());
  for (const auto& list : kLists) {
    pending_downloads_++;
    QNetworkRequest req{QUrl(QString::fromLatin1(list.url))};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setTransferTimeout(30000);
    QNetworkReply* reply = net_->get(req);
    const QString path = filterDir() + "/" + list.file;
    connect(reply, &QNetworkReply::finished, this, [this, reply, path] {
      reply->deleteLater();
      const QByteArray body = reply->readAll();
      // Keep the old copy unless this looks like a real list.
      if (reply->error() == QNetworkReply::NoError && body.size() > 1024) {
        QFile f(path + ".new");
        if (f.open(QIODevice::WriteOnly) && f.write(body) == body.size()) {
          f.close();
          QFile::remove(path);
          QFile::rename(path + ".new", path);
        }
      }
      if (--pending_downloads_ == 0) rebuild();
    });
  }
}

}  // namespace adblock
