// Plain assert-style tests (no framework). Exit code 0 = all passed.
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

#include "daemon.hpp"
#include "launch.hpp"
#include "padnav.hpp"
#include "profile.hpp"
#include "watch.hpp"
#include "process.hpp"
#include <sys/wait.h>
#include "runners.hpp"
#include "scan.hpp"
#include "store.hpp"
#include "util.hpp"
#include "vdf.hpp"

static int g_fail = 0, g_checks = 0;
#define CHECK(cond)                                                              \
  do {                                                                           \
    ++g_checks;                                                                  \
    if (!(cond)) {                                                               \
      ++g_fail;                                                                  \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
    }                                                                            \
  } while (0)
#define CHECK_EQ(a, b)                                                           \
  do {                                                                           \
    ++g_checks;                                                                  \
    if (!((a) == (b))) {                                                         \
      ++g_fail;                                                                  \
      std::fprintf(stderr, "%s:%d: CHECK_EQ failed: %s == %s\n", __FILE__, __LINE__, #a, #b); \
    }                                                                            \
  } while (0)

using namespace fg;
using V = std::vector<std::string>;

static void testVdf() {
  const char* acf = R"("AppState"
{
	"appid"		"1046930"
	"Universe"		"1"
	"name"		"Dota \"Underlords\""
	"StateFlags"		"4"
	"LastPlayed"		"1763400000"
	// comment
	"UserConfig"
	{
		"language"		"english"
	}
})";
  auto root = parseVdf(acf);
  CHECK(root.has_value());
  const VdfNode* st = root->find("appstate");  // case-insensitive
  CHECK(st != nullptr);
  CHECK_EQ(st->str("appid"), "1046930");
  CHECK_EQ(st->str("name"), "Dota \"Underlords\"");
  CHECK(st->find("UserConfig") && st->find("UserConfig")->isObject);
  CHECK_EQ(st->find("UserConfig")->str("language"), "english");
  CHECK_EQ(st->str("missing", "dflt"), "dflt");
  CHECK(!parseVdf("\"a\" { \"b\" \"c\"").has_value());   // unterminated
  CHECK(!parseVdf("\"a\" \"b").has_value());             // unterminated string
  CHECK(parseVdf("").has_value());
  auto win = parseVdf("\"p\" \"C:\\\\Games\\\\x\"");
  CHECK(win && win->str("p") == "C:\\Games\\x");

  // libraryfolders: new format and old format
  const char* lf = R"("libraryfolders"
{
	"0" { "path" "/home/u/.local/share/Steam" "label" "" "apps" { "228980" "1" } }
	"1" { "path" "/mnt/games/SteamLibrary" }
})";
  auto libs = parseSteamLibraryFolders(lf);
  CHECK_EQ(libs.size(), 2u);
  CHECK_EQ(libs[1], "/mnt/games/SteamLibrary");
  auto old = parseSteamLibraryFolders("\"LibraryFolders\" { \"TimeNextStatsReport\" \"123\" \"1\" \"/mnt/old\" }");
  CHECK_EQ(old.size(), 1u);
  CHECK_EQ(old[0], "/mnt/old");

  auto g = parseSteamManifest(acf);
  CHECK(g.has_value());
  CHECK_EQ(g->id, "steam:1046930");
  CHECK_EQ(g->source, "steam");
  CHECK(g->lastPlayed && *g->lastPlayed == 1763400000);
  CHECK(g->cover && g->cover->find("1046930/library_600x900.jpg") != std::string::npos);
  CHECK(g->hero && g->hero->find("library_hero.jpg") != std::string::npos);
  // not fully installed
  CHECK(!parseSteamManifest("\"AppState\" { \"appid\" \"5\" \"name\" \"X\" \"StateFlags\" \"1026\" }"));
}

static void testSteamTools() {
  CHECK(isSteamTool("228980", "Steamworks Common Redistributables"));
  for (const char* id : {"1070560", "1391110", "1628350", "1493710", "2180100"}) CHECK(isSteamTool(id, "Whatever"));
  CHECK(isSteamTool("123", "Proton 9.0"));
  CHECK(isSteamTool("123", "Proton Experimental"));
  CHECK(isSteamTool("123", "Steam Linux Runtime 3.0 (sniper)"));
  CHECK(!isSteamTool("1046930", "Dota Underlords"));
  CHECK(!isSteamTool("620", "Portal 2"));
  CHECK(!parseSteamManifest("\"AppState\" { \"appid\" \"1493710\" \"name\" \"Proton Experimental\" \"StateFlags\" \"4\" }"));
  CHECK(!parseSteamManifest("\"AppState\" { \"appid\" \"1\" \"name\" \"Steam Linux Runtime 3.0 (sniper)\" \"StateFlags\" \"4\" }"));
  CHECK(!parseSteamManifest("\"AppState\" { \"appid\" \"228980\" \"name\" \"Steamworks Common Redistributables\" \"StateFlags\" \"4\" }"));
}

static void testSplitArgs() {
  CHECK_EQ(splitArgs(""), V{});
  CHECK_EQ(splitArgs("   "), V{});
  CHECK_EQ(splitArgs("-dx11 --skip-intro"), (V{"-dx11", "--skip-intro"}));
  CHECK_EQ(splitArgs("a  b\tc"), (V{"a", "b", "c"}));
  CHECK_EQ(splitArgs("--name \"John Smith\" x"), (V{"--name", "John Smith", "x"}));
  CHECK_EQ(splitArgs("'a b' \"c d\""), (V{"a b", "c d"}));
  CHECK_EQ(splitArgs("a\\ b"), (V{"a b"}));
  CHECK_EQ(splitArgs("\"say \\\"hi\\\"\""), (V{"say \"hi\""}));
  CHECK_EQ(splitArgs("'it'\\''s'"), (V{"it's"}));
  CHECK_EQ(splitArgs("pre\"mid dle\"post"), (V{"premid dlepost"}));
  CHECK_EQ(splitArgs("\"\" x"), (V{"", "x"}));
  CHECK_EQ(splitArgs("\"C:\\Games\\x\""), (V{"C:\\Games\\x"}));   // backslash kept in dquotes
  CHECK_EQ(splitArgs("'a\\b'"), (V{"a\\b"}));                     // literal in squotes
  CHECK_EQ(splitArgs("\"unterminated arg"), (V{"unterminated arg"}));
  CHECK_EQ(splitArgs("trailing\\"), (V{"trailing"}));
}

static void testIds() {
  CHECK_EQ(logFileName("lutris:2"), "lutris_2.log");
  CHECK_EQ(logFileName("local:1b4e-28ba"), "local_1b4e-28ba.log");
  CHECK_EQ(logFileName("heroic:legendary:Fortnite"), "heroic_legendary_Fortnite.log");
  CHECK_EQ(logFileName("steam:1046930"), "steam_1046930.log");
  CHECK_EQ(sanitizeId("a/b:c"), "a_b_c");
  CHECK(naturalCompare("GE-Proton9-2", "GE-Proton10-1") < 0);
  CHECK(naturalCompare("GE-Proton11-12", "GE-Proton11-9") > 0);
  CHECK_EQ(naturalCompare("a1", "a1"), 0);
  CHECK_EQ(percentEncode("a b&c"), "a%20b%26c");
  CHECK_EQ(sanitizeUtf8("ok\xff" "x"), "ok\xEF\xBF\xBD" "x");
  CHECK_EQ(sanitizeUtf8("h\xC3\xA9"), "h\xC3\xA9");
}

static Game localGame(GameSettings s) {
  Game g;
  g.id = "local:abc";
  g.source = "local";
  g.title = "T";
  g.settings = s;
  return g;
}

static LaunchContext ctx(bool umu) {
  LaunchContext c;
  c.dataDir = "/data/forge-gaming";
  c.steamRoot = "/steam";
  c.umuRun = umu;
  c.runners = {{"steam:GE-Proton11-12", "GE-Proton11-12", "proton", "steam", "/steam/compatibilitytools.d/GE-Proton11-12"},
               {"lutris:wine-9", "wine-9", "wine", "lutris", "/lutris/wine-9"},
               {"system:wine", "System Wine", "wine", "system", "/usr/bin/wine"}};
  c.defaultRunner = "steam:GE-Proton11-12";
  return c;
}

static void testLaunch() {
  LaunchSpec sp;
  std::string err;
  {  // steam
    Game g; g.id = "steam:1046930"; g.source = "steam";
    CHECK(buildLaunch(g, ctx(false), sp, err));
    CHECK_EQ(sp.argv, (V{"steam", "steam://rungameid/1046930"}));
    CHECK(!sp.tracked);
  }
  {  // heroic
    Game g; g.id = "heroic:legendary:Fortnite"; g.source = "heroic";
    CHECK(buildLaunch(g, ctx(false), sp, err));
    CHECK_EQ(sp.argv, (V{"xdg-open", "heroic://launch?appName=Fortnite&runner=legendary"}));
    CHECK(!sp.tracked);
    Game bad; bad.id = "heroic:oops"; bad.source = "heroic";
    CHECK(!buildLaunch(bad, ctx(false), sp, err));
  }
  {  // lutris
    Game g; g.id = "lutris:2"; g.source = "lutris";
    CHECK(buildLaunch(g, ctx(false), sp, err));
    CHECK_EQ(sp.argv, (V{"lutris", "lutris:rungameid/2"}));
    CHECK(!sp.tracked);
  }
  {  // local native, plain, with args and env
    GameSettings s; s.exe = "/games/foo/foo.sh"; s.args = "-a \"b c\""; s.env["X"] = "1";
    CHECK(buildLaunch(localGame(s), ctx(false), sp, err));
    CHECK_EQ(sp.argv, (V{"/games/foo/foo.sh", "-a", "b c"}));
    CHECK_EQ(sp.env.at("X"), "1");
    CHECK_EQ(sp.workdir, "/games/foo");
    CHECK(sp.tracked);
    s.workdir = "/elsewhere";
    CHECK(buildLaunch(localGame(s), ctx(false), sp, err));
    CHECK_EQ(sp.workdir, "/elsewhere");
  }
  {  // native with every wrapper, in order
    GameSettings s; s.exe = "/g/x"; s.gamemode = true; s.mangohud = true;
    s.gamescope.enabled = true; s.gamescope.width = 1280; s.gamescope.height = 720; s.gamescope.fps = 60; s.gamescope.fullscreen = true;
    CHECK(buildLaunch(localGame(s), ctx(false), sp, err));
    CHECK_EQ(sp.argv, (V{"gamescope", "-W", "1280", "-H", "720", "-r", "60", "-f", "--", "gamemoderun", "mangohud", "/g/x"}));
    s.gamescope.fps = 0; s.gamescope.fullscreen = false;
    CHECK(buildLaunch(localGame(s), ctx(false), sp, err));
    CHECK_EQ(sp.argv, (V{"gamescope", "-W", "1280", "-H", "720", "--", "gamemoderun", "mangohud", "/g/x"}));
  }
  {  // windows + proton + umu-run
    GameSettings s; s.kind = "windows"; s.exe = "/g/Foo/Foo.exe"; s.args = "-dx11"; s.gamemode = true;
    CHECK(buildLaunch(localGame(s), ctx(true), sp, err));
    CHECK_EQ(sp.argv, (V{"gamemoderun", "umu-run", "/g/Foo/Foo.exe", "-dx11"}));
    CHECK_EQ(sp.env.at("PROTONPATH"), "/steam/compatibilitytools.d/GE-Proton11-12");
    CHECK_EQ(sp.env.at("WINEPREFIX"), "/data/forge-gaming/prefixes/local_abc");
    CHECK_EQ(sp.env.at("GAMEID"), "umu-default");
    CHECK_EQ(sp.mkdirs, V{"/data/forge-gaming/prefixes/local_abc"});
  }
  {  // windows + proton without umu-run
    GameSettings s; s.kind = "windows"; s.exe = "/g/Foo/Foo.exe"; s.prefix = "/pfx"; s.mangohud = true;
    CHECK(buildLaunch(localGame(s), ctx(false), sp, err));
    CHECK_EQ(sp.argv, (V{"mangohud", "/steam/compatibilitytools.d/GE-Proton11-12/proton", "waitforexitandrun", "/g/Foo/Foo.exe"}));
    CHECK_EQ(sp.env.at("STEAM_COMPAT_DATA_PATH"), "/pfx");
    CHECK_EQ(sp.env.at("STEAM_COMPAT_CLIENT_INSTALL_PATH"), "/steam");
    CHECK(sp.env.count("PROTONPATH") == 0);
  }
  {  // windows + wine runner (lutris) and system wine
    GameSettings s; s.kind = "windows"; s.exe = "/g/Foo.exe"; s.runner = "lutris:wine-9";
    CHECK(buildLaunch(localGame(s), ctx(true), sp, err));
    CHECK_EQ(sp.argv, (V{"/lutris/wine-9/bin/wine", "/g/Foo.exe"}));
    CHECK_EQ(sp.env.at("WINEPREFIX"), "/data/forge-gaming/prefixes/local_abc");
    s.runner = "system:wine";
    CHECK(buildLaunch(localGame(s), ctx(false), sp, err));
    CHECK_EQ(sp.argv, (V{"wine", "/g/Foo.exe"}));
  }
  {  // windows errors
    GameSettings s; s.kind = "windows"; s.exe = "/g/Foo.exe"; s.runner = "forge:nope";
    CHECK(!buildLaunch(localGame(s), ctx(false), sp, err));
    s.runner.reset();
    LaunchContext c = ctx(false); c.defaultRunner.clear();
    CHECK(!buildLaunch(localGame(s), c, sp, err));
    GameSettings e; e.exe = "";
    CHECK(!buildLaunch(localGame(e), ctx(false), sp, err));
  }
}

static void testPadNav() {
  StickDirection sd;
  CHECK_EQ(sd.update(0.0f, 0.0f), -1);
  CHECK_EQ(sd.update(0.49f, 0.0f), -1);
  CHECK_EQ(sd.update(0.5f, 0.0f), static_cast<int>(Dir::Right));
  CHECK_EQ(sd.update(0.4f, 0.0f), static_cast<int>(Dir::Right));   // hysteresis: still held
  CHECK_EQ(sd.update(0.31f, 0.0f), static_cast<int>(Dir::Right));
  CHECK_EQ(sd.update(0.29f, 0.0f), -1);                            // released below 0.3
  CHECK_EQ(sd.update(0.4f, 0.0f), -1);                             // must cross 0.5 again
  CHECK_EQ(sd.update(0.0f, -0.9f), static_cast<int>(Dir::Up));     // y negative = up
  CHECK_EQ(sd.update(0.0f, 0.9f), static_cast<int>(Dir::Down));
  CHECK_EQ(sd.update(-0.9f, 0.1f), static_cast<int>(Dir::Left));
  CHECK_EQ(sd.update(-0.6f, 0.55f), static_cast<int>(Dir::Left));  // diagonal: keeps current
  CHECK_EQ(sd.update(-0.4f, 0.8f), static_cast<int>(Dir::Down));   // other axis takes over
  StickDirection diag;
  CHECK_EQ(diag.update(0.7f, 0.6f), static_cast<int>(Dir::Right)); // dominant axis wins

  Trigger t;
  CHECK(!t.update(0.4f));
  CHECK(t.update(0.5f));
  CHECK(t.update(0.4f));
  CHECK(!t.update(0.29f));

  // press, repeat timing: 400 ms then every 90 ms
  PadNav nav;
  std::vector<NavEvent> ev;
  nav.stick(0.0f, 0.9f, 1000, ev);   // down
  CHECK_EQ(ev.size(), 1u);
  CHECK(ev[0] == (NavEvent{Dir::Down, true, false}));
  ev.clear();
  nav.tick(1399, ev);
  CHECK(ev.empty());
  nav.tick(1400, ev);
  CHECK_EQ(ev.size(), 1u);
  CHECK(ev[0] == (NavEvent{Dir::Down, true, true}));
  ev.clear();
  nav.tick(1489, ev);
  CHECK(ev.empty());
  nav.tick(1490, ev);
  CHECK_EQ(ev.size(), 1u);
  ev.clear();
  nav.tick(1580, ev);
  CHECK_EQ(ev.size(), 1u);
  ev.clear();
  nav.tick(1581, ev);   // not due yet (next 1670)
  CHECK(ev.empty());
  nav.tick(5000, ev);   // fell far behind: one event, no burst
  CHECK_EQ(ev.size(), 1u);
  ev.clear();
  nav.tick(5001, ev);
  CHECK(ev.empty());
  nav.stick(0.0f, 0.0f, 5002, ev);   // release
  CHECK_EQ(ev.size(), 1u);
  CHECK(ev[0] == (NavEvent{Dir::Down, false, false}));
  CHECK(!nav.anyHeld());
  ev.clear();
  nav.tick(9000, ev);
  CHECK(ev.empty());

  // d-pad and stick share one logical direction
  PadNav n2;
  ev.clear();
  n2.dpad(Dir::Left, true, 0, ev);
  n2.stick(-0.9f, 0.0f, 10, ev);     // stick joins: no second press
  CHECK_EQ(ev.size(), 1u);
  n2.dpad(Dir::Left, false, 20, ev); // stick still holds it: no release
  CHECK_EQ(ev.size(), 1u);
  n2.stick(0.0f, 0.0f, 30, ev);
  CHECK_EQ(ev.size(), 2u);
  CHECK(ev[1] == (NavEvent{Dir::Left, false, false}));

  // stick moving from right to up releases right and presses up
  PadNav n3;
  ev.clear();
  n3.stick(0.9f, 0.0f, 0, ev);
  n3.stick(0.0f, -0.9f, 5, ev);
  CHECK_EQ(ev.size(), 3u);
  CHECK(ev[1] == (NavEvent{Dir::Right, false, false}));
  CHECK(ev[2] == (NavEvent{Dir::Up, true, false}));
  CHECK_EQ(std::string(dirName(Dir::Up)), "up");
}

static void testHeroic() {
  Json::Value v;
  CHECK(parseJson(R"({"Fortnite":{"app_name":"Fortnite","title":"Fortnite","install_path":"/x"},"9ab":{"install_path":"/y"}})", v));
  auto a = parseHeroicInstalled(v);
  CHECK_EQ(a.size(), 2u);
  CHECK(parseJson(R"({"installed":[{"appName":"1207658930","install_path":"/z"}]})", v));
  auto b = parseHeroicInstalled(v);
  CHECK_EQ(b.size(), 1u);
  CHECK_EQ(b[0].first, "1207658930");
  CHECK(parseJson(R"([{"app_name":"A"},{"app_name":"B"},5,null])", v));
  CHECK_EQ(parseHeroicInstalled(v).size(), 2u);
  CHECK(parseJson("42", v));
  CHECK(parseHeroicInstalled(v).empty());

  CHECK(parseJson(R"({"library":[{"app_name":"Fortnite","title":"Fortnite!","art_cover":"https://c","art_square":"https://s"}]})", v));
  auto lib = parseHeroicLibrary(v);
  CHECK_EQ(lib.size(), 1u);
  CHECK_EQ(lib["Fortnite"].title, "Fortnite!");
  CHECK_EQ(lib["Fortnite"].cover, "https://s");
  CHECK_EQ(lib["Fortnite"].hero, "https://c");
  CHECK(parseJson(R"({"games":[{"app_name":"1","title":"G","art_cover":"https://c"}]})", v));
  CHECK_EQ(parseHeroicLibrary(v)["1"].cover, "https://c");
}

static void testRunnersAndModel() {
  std::string json = R"([
    {"tag_name":"GE-Proton11-12","draft":false,"assets":[{"name":"GE-Proton11-12.sha512sum","browser_download_url":"https://x/s","size":1},
      {"name":"GE-Proton11-12.tar.gz","browser_download_url":"https://x/a.tar.gz","size":500}]},
    {"tag_name":"GE-Proton11-11","assets":[{"name":"only.txt","browser_download_url":"https://x/t","size":1}]},
    {"tag_name":"../evil","assets":[{"name":"e.tar.gz","browser_download_url":"https://x/e","size":1}]},
    {"tag_name":"GE-Proton11-10","assets":[{"name":"GE-Proton11-10-aarch64.tar.gz","browser_download_url":"https://x/arm.tar.gz","size":9},{"name":"GE-Proton11-10-x86_64.tar.gz","browser_download_url":"https://x/b.tar.gz","size":7}]}])";
  auto r = parseReleases(json, 10);
  CHECK_EQ(r.size(), 2u);
  CHECK_EQ(r[0].name, "GE-Proton11-12");
  CHECK_EQ(r[0].url, "https://x/a.tar.gz");
  CHECK_EQ(r[0].size, 500);
  CHECK_EQ(r[1].url, "https://x/b.tar.gz");   // x86_64 over aarch64
  CHECK_EQ(parseReleases(json, 1).size(), 1u);
  CHECK(parseReleases("garbage", 10).empty());
  CHECK(validRunnerName("GE-Proton11-12"));
  CHECK(!validRunnerName("../x"));
  CHECK(!validRunnerName(""));

  std::vector<Runner> rs = {{"steam:GE-Proton9-2", "GE-Proton9-2", "proton", "steam", "/a"},
                            {"steam:GE-Proton11-12", "GE-Proton11-12", "proton", "steam", "/b"},
                            {"system:wine", "System Wine", "wine", "system", "/usr/bin/wine"}};
  CHECK_EQ(pickDefaultRunner(rs), "steam:GE-Proton11-12");
  CHECK_EQ(pickDefaultRunner({}), "");

  GameSettings s;
  std::string err;
  Json::Value j;
  CHECK(parseJson(R"({"kind":"windows","exe":"/g/F.exe","args":"-x","workdir":null,"env":{"A":"1"},"gamescope":{"enabled":true,"width":800,"height":600,"fps":30,"fullscreen":false}})", j));
  CHECK(settingsFromJson(j, s, err));
  CHECK_EQ(s.kind, "windows");
  CHECK(!s.workdir.has_value());
  CHECK_EQ(s.env["A"], "1");
  CHECK(s.gamescope.enabled && s.gamescope.width == 800 && !s.gamescope.fullscreen);
  Json::Value back = toJson(s);
  CHECK(back["workdir"].isNull());
  CHECK_EQ(back["gamescope"]["fps"].asInt(), 30);
  CHECK(parseJson(R"({"kind":"dos","exe":"x"})", j));
  CHECK(!settingsFromJson(j, s, err));
  CHECK(parseJson(R"({"kind":"native"})", j));
  CHECK(!settingsFromJson(j, s, err));
}

static void testSpawn() {
  LaunchSpec s;
  s.argv = {"/bin/true"};
  auto r = spawnProcess(s, "", true);
  CHECK(r.ok);
  s.argv = {"/nonexistent/binary"};
  r = spawnProcess(s, "", true);
  CHECK(!r.ok);
  r = spawnProcess(s, "/dev/null", false);
  CHECK(!r.ok);
  s.argv = {"/bin/sh", "-c", "echo $FOO"};
  s.env["FOO"] = "bar";
  r = spawnProcess(s, "/dev/null", false);
  CHECK(r.ok && r.pid > 0);
  int st = 0;
  waitpid(r.pid, &st, 0);
  CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 0);
}

// Review findings (2026-11-19): hostile JSON, out-of-range numbers, and an
// install that must not leave a half-extracted runner behind.
static void testHardening() {
  Json::Value v;
  CHECK(!parseJson(std::string(100000, '['), v));
  CHECK(!parseJson("{\"id\":1,\"params\":" + std::string(5000, '['), v));
  CHECK(parseJson("{\"a\":[[1]]}", v));

  Json::Value o;
  CHECK(parseJson("{\"big\":18446744073709551615,\"huge\":1e30,\"ok\":7,\"f\":2.9}", o));
  CHECK_EQ(jint(o, "big", -1), -1);
  CHECK_EQ(jint(o, "huge", -1), -1);
  CHECK_EQ(jint(o, "ok", -1), 7);
  CHECK_EQ(jint(o, "f", -1), 2);

  Json::Value s;
  CHECK(parseJson("{\"kind\":\"native\",\"exe\":\"/bin/true\",\"gamescope\":{\"enabled\":true,"
                  "\"width\":99999999,\"height\":-5,\"fps\":1e30}}", s));
  GameSettings gs = settingsFromStored(s);
  CHECK_EQ(gs.gamescope.width, 16384);
  CHECK_EQ(gs.gamescope.height, 0);
  CHECK_EQ(gs.gamescope.fps, 0);

  // extractTarGz: all or nothing.
  char tmpl[] = "/tmp/fg-tar-XXXXXX";
  std::string dir = ::mkdtemp(tmpl);
  std::string src = dir + "/src", dest = dir + "/runners";
  CHECK(std::system(("mkdir -p " + src + "/GE-Test && echo x > " + src + "/GE-Test/proton && tar -czf " +
                     dir + "/good.tar.gz -C " + src + " GE-Test && head -c 60 " + dir +
                     "/good.tar.gz > " + dir + "/bad.tar.gz").c_str()) == 0);
  std::string err;
  CHECK(!extractTarGz(dir + "/bad.tar.gz", dest, err));
  CHECK(!std::filesystem::exists(dest + "/GE-Test"));
  CHECK(extractTarGz(dir + "/good.tar.gz", dest, err));
  CHECK(std::filesystem::exists(dest + "/GE-Test/proton"));
  int dots = 0;
  for (const auto& e : std::filesystem::directory_iterator(dest))
    if (e.path().filename().string()[0] == '.') ++dots;
  CHECK_EQ(dots, 0);
  CHECK(!extractTarGz(dir + "/good.tar.gz", dest, err));  // already there
  std::filesystem::remove_all(dir);
}

static Game mk(const std::string& id, const std::string& source, const std::string& dir = "", const std::string& lname = "") {
  Game g;
  g.id = id;
  g.source = source;
  g.title = id;
  g.installDir = dir;
  g.lutrisName = lname;
  return g;
}

static void testWatchMatcher() {
  std::vector<Game> games = {mk("steam:4242", "steam"), mk("lutris:1", "lutris", "/home/u/Games/Foo", "Foo Quest"),
                             mk("heroic:legendary:abc", "heroic", "/home/u/Games/Heroic/Bar"),
                             mk("local:x", "local", "/home/u/Games/Loc")};
  auto run = [&](std::vector<ProcInfo> p) { return matchRunning(p, games); };
  // Steam reaper
  auto s = run({{10, {"/home/u/.steam/ubuntu12_32/reaper", "SteamLaunch", "AppId=4242", "--", "x"}}});
  CHECK_EQ(s.size(), 1u);
  CHECK(s.count("steam:4242"));
  CHECK(run({{10, {"reaper", "SteamLaunch", "AppId=42420", "--"}}}).empty());   // not a prefix match
  CHECK(run({{10, {"reaper", "AppId=4242"}}}).empty());                       // needs SteamLaunch too
  CHECK(run({{10, {"reaper SteamLaunch AppId=4242 -- x"}}}).empty());  // one argument: a shell line, not reaper
  CHECK(run({{10, {"/bin/bash", "-c", "reaper SteamLaunch AppId=4242"}}}).empty());
  CHECK(run({{10, {"grep", "SteamLaunch", "AppId=4242"}}}).empty());   // only reaper itself counts
  // Lutris wrapper: title form and script form
  CHECK(run({{11, {"lutris-wrapper: Foo Quest"}}}).count("lutris:1") == 1);
  CHECK(run({{11, {"lutris-wrapper: Other Game"}}}).empty());
  CHECK(run({{11, {"/usr/bin/python3", "/usr/lib/lutris/lutris-wrapper", "Foo Quest", "0", "1"}}}).count("lutris:1") == 1);
  CHECK(run({{11, {"/usr/bin/python3", "/usr/lib/lutris/lutris-wrapper", "Other", "0"}}}).empty());
  // Install folder: native, Windows path, case
  CHECK(run({{12, {"/home/u/Games/Heroic/Bar/bin/bar"}}}).count("heroic:legendary:abc") == 1);
  CHECK(run({{12, {"C:\\windows\\system32\\start.exe", "Z:\\HOME\\U\\Games\\Heroic\\BAR\\Bar.exe"}}}).count("heroic:legendary:abc") == 1);
  CHECK(run({{12, {"wine", "z:/home/u/games/heroic/bar/"}}}).count("heroic:legendary:abc") == 1);
  CHECK(run({{12, {"/home/u/Games/Heroic/Bar"}}}).count("heroic:legendary:abc") == 1);
  CHECK(run({{12, {"/home/u/Games/Heroic/Barista/x"}}}).empty());         // sibling with the same prefix
  CHECK(run({{12, {"/home/u/Games/Heroic"}}}).empty());
  CHECK(run({{13, {"/home/u/Games/Foo/foo.sh"}}}).count("lutris:1") == 1);
  // Launchers are not games
  CHECK(run({{14, {"/usr/bin/heroic", "/home/u/Games/Heroic/Bar/x"}}}).empty());
  CHECK(run({{14, {"/usr/lib/steam/steamwebhelper", "--dir=x", "/home/u/Games/Heroic/Bar"}}}).empty());
  CHECK(run({{14, {"/usr/bin/gogdl", "/home/u/Games/Heroic/Bar"}}}).empty());
  CHECK(run({{14, {"/usr/bin/python3", "/usr/bin/lutris", "/home/u/Games/Foo"}}}).empty());
  CHECK(isLauncherProcess({14, {"/usr/bin/legendary", "launch"}}));
  CHECK(isLauncherProcess({1, {"/usr/bin/nile"}}));
  CHECK(!isLauncherProcess({1, {"lutris-wrapper: Foo"}}));
  // Local games are never detected; unrelated processes match nothing
  CHECK(run({{15, {"/home/u/Games/Loc/run"}}}).empty());
  CHECK(run({{16, {"bash", "-lc", "ls"}}, {17, {"firefox"}}}).empty());
  CHECK(run({}).empty());
  // A shallow install folder is never used (would match anything)
  std::vector<Game> shallow = {mk("heroic:gog:z", "heroic", "/home/u")};
  CHECK(matchRunning({{18, {"/home/u/anything"}}}, shallow).empty());
  CHECK_EQ(normalizeGamePath("Z:\\Games\\Foo\\"), "/games/foo");
  CHECK_EQ(normalizeGamePath("/A//B/"), "/a/b");
}

static void testWatchState() {
  WatchState w;
  auto c = w.update({"a"});
  CHECK(c.started == V{"a"} && c.stopped.empty());
  c = w.update({"a"});
  CHECK(c.started.empty() && c.stopped.empty());
  c = w.update({});  // missing once: still running
  CHECK(c.started.empty() && c.stopped.empty() && w.isRunning("a"));
  c = w.update({"a"});  // back: counter resets
  CHECK(c.started.empty() && c.stopped.empty());
  c = w.update({});
  CHECK(c.stopped.empty());
  c = w.update({});  // second miss in a row
  CHECK(c.stopped == V{"a"} && !w.isRunning("a"));
  c = w.update({"a", "b"});
  CHECK_EQ(c.started.size(), 2u);
}

static void testProfileHolds() {
  ForgedState st;
  st.thermalAvailable = true;
  st.profiles = {"balanced", "performance"};
  st.thermalCurrent = "balanced";
  st.dndAvailable = true;
  st.dndEnabled = false;
  Profile perf;
  perf.thermal = "performance";
  perf.quiet = true;
  ProfileHolds h;
  auto p1 = h.start("g1", perf, st);
  CHECK(p1.writeMarker && *p1.writeMarker == "g1");
  CHECK_EQ(p1.cmds.size(), 2u);
  CHECK((p1.cmds[0] == ForgedCmd{"set", "thermal", "performance"}));
  CHECK((p1.cmds[1] == ForgedCmd{"set", "dnd", "on"}));
  // Second game while the first holds: state now shows the changed values, nothing is taken over.
  ForgedState st2 = st;
  st2.thermalCurrent = "performance";
  st2.dndEnabled = true;
  Profile cool;
  cool.thermal = "cool";
  cool.quiet = true;
  CHECK(h.start("g2", cool, st2).empty());
  CHECK_EQ(h.thermalHolder(), "g1");
  CHECK(h.stop("g2").empty());                  // the non-holder stopping changes nothing
  auto p2 = h.stop("g1");
  CHECK_EQ(p2.cmds.size(), 2u);
  CHECK((p2.cmds[0] == ForgedCmd{"set", "thermal", "balanced"}));
  CHECK((p2.cmds[1] == ForgedCmd{"set", "dnd", "off"}));
  CHECK(p2.removeMarker);
  CHECK(h.thermalHolder().empty() && h.dndHolder().empty());
  // Once free, a later game can hold
  CHECK(!h.start("g2", cool, st).empty());
  // already quiet: held, but nothing to undo
  ProfileHolds h2;
  ForgedState quiet = st;
  quiet.dndEnabled = true;
  Profile q;
  q.quiet = true;
  CHECK(h2.start("a", q, quiet).empty());
  CHECK(h2.dndHolder() == "a" && h2.stop("a").empty());
  // no thermal in profile: no marker; forged unavailable: nothing
  ProfileHolds h3;
  CHECK(h3.start("a", Profile(), st).empty());
  CHECK(h3.start("a", perf, ForgedState()).empty());
  // stopAll gives back everything
  ProfileHolds h4;
  h4.start("a", perf, st);
  auto all = h4.stopAll();
  CHECK_EQ(all.cmds.size(), 2u);
  CHECK(all.removeMarker);
  CHECK(h4.stopAll().empty());
}

static void testForgedStateAndProfileJson() {
  const char* real = R"({"dnd":{"available":true,"enabled":false,"ours":false},"thermal":{"available":true,"profile":"balanced","profiles":["balanced","cool","custom","performance","silent"],"x":1}})";
  ForgedState st;
  CHECK(parseForgedState(real, st));
  CHECK(st.thermalAvailable && st.dndAvailable && !st.dndEnabled);
  CHECK_EQ(st.profiles.size(), 5u);
  CHECK(st.thermalCurrent && *st.thermalCurrent == "balanced");
  Json::Value info = systemInfoJson(st);
  CHECK(info["thermal"]["available"].asBool());
  CHECK_EQ(info["thermal"]["current"].asString(), "balanced");
  CHECK(info["quiet"]["available"].asBool());
  CHECK(parseForgedState("{}", st));
  CHECK(!st.thermalAvailable && !st.dndAvailable);
  CHECK(systemInfoJson(st)["thermal"]["current"].isNull());
  CHECK(!parseForgedState("not json", st));
  CHECK(!st.thermalAvailable);

  // Profile round trip through library.json; an old file without it
  std::string dir = std::filesystem::temp_directory_path().string() + "/fg-profile-test";
  std::filesystem::remove_all(dir);
  Store s(dir);
  s.meta["steam:1"].profile.thermal = "silent";
  s.meta["steam:1"].profile.quiet = true;
  s.meta["steam:2"].favorite = true;
  CHECK(s.saveLibrary());
  Store t(dir);
  t.load();
  CHECK(t.meta["steam:1"].profile.thermal && *t.meta["steam:1"].profile.thermal == "silent");
  CHECK(t.meta["steam:1"].profile.quiet);
  CHECK(!t.meta["steam:2"].profile.thermal && !t.meta["steam:2"].profile.quiet);
  CHECK(writeFileAtomic(dir + "/library.json", "{\"version\":1,\"local\":[],\"meta\":{\"steam:9\":{\"favorite\":true,\"hidden\":false,\"playedSeconds\":60,\"lastPlayed\":null}}}"));
  Store u(dir);
  u.load();
  CHECK(u.meta["steam:9"].favorite && u.meta["steam:9"].playedSeconds == 60);
  CHECK(!u.meta["steam:9"].profile.thermal && !u.meta["steam:9"].profile.quiet);
  Game g = mk("steam:9", "steam");
  Json::Value j = toJson(g);
  CHECK(j["profile"]["thermal"].isNull() && j["profile"]["quiet"] == false);
  CHECK(j["detected"] == false && j["canStop"] == false);
  CHECK(!j.isMember("installDir"));
  std::filesystem::remove_all(dir);

  // Scanner folders
  auto acf = parseSteamManifest("\"AppState\" { \"appid\" \"7\" \"name\" \"G\" \"StateFlags\" \"4\" \"installdir\" \"GDir\" }");
  CHECK(acf && acf->installDir == "GDir");
  Json::Value hv;
  CHECK(parseJson("{\"abc\":{\"install_path\":\"/g/abc\"}}", hv));
  CHECK_EQ(parseHeroicInstallPaths(hv)["abc"], "/g/abc");
}

int main() {
  testWatchMatcher();
  testWatchState();
  testProfileHolds();
  testForgedStateAndProfileJson();
  testHardening();
  testSpawn();
  testVdf();
  testSteamTools();
  testSplitArgs();
  testIds();
  testLaunch();
  testPadNav();
  testHeroic();
  testRunnersAndModel();
  std::printf("%d checks, %d failed\n", g_checks, g_fail);
  return g_fail ? 1 : 0;
}
