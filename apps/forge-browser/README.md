# Forge Browser

Forge OS's web browser: Qt WebEngine (Chromium) in a Qt Widgets window, so
Darkly and the ForgeGlass colours give it the same translucent glass
toolbar and tabs as the rest of the desktop.

- **Ad and tracker blocking, built in** (`src/adblock.cpp`): EasyList,
  EasyPrivacy and Peter Lowe's list, downloaded on first run and refreshed
  weekly into `~/.cache/forgeos/forge-browser/filters` (a small built-in list
  covers the time before). Network rules block requests in a
  `QWebEngineUrlRequestInterceptor` — plain `||domain^` rules by hash lookup,
  the rest indexed by a token the URL must contain — and element-hiding rules
  become CSS. The shield in the toolbar shows what was blocked and turns
  blocking off per site. Not supported: scriptlets and procedural cosmetic
  filters (uBlock Origin's `+js()`, `:has-text()`...), so YouTube's own
  video ads can still get through.
- **New tab page** (`forge://newtab`): clock, search and your bookmarks or
  most visited sites over the Forge Glass wallpaper. Tiles are letters, not
  favicons fetched from a third party.
- Tabs restore on restart; bookmarks (Ctrl+D) and history feed the address
  bar's suggestions; searches go to DuckDuckGo.
- One process: `forge-browser URL` from another app opens a tab in the
  running browser.

Data: profile and bookmarks/history in `~/.local/share/forgeos/forge-browser`,
settings in `~/.config/forgeos/forge-browser.conf`.

No Widevine DRM out of the box (Netflix, Spotify web): Qt WebEngine picks up
a Widevine CDM if one is installed where Chrome keeps it.

Build: `cmake -S . -B build -G Ninja && ninja -C build`.
