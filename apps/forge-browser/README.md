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
- **Vertical tabs** (menu, or Ctrl+Shift+,): a tab sidebar on the left
  (`src/tabsidebar.cpp`) that is expanded (icon and title), collapsed
  (icons only; resting the pointer on the strip rolls it open over the page
  Brave-style, until the pointer leaves) or auto-hidden: hidden until the pointer reaches the
  window's left edge, then it slides out over the page and away again when
  the pointer leaves (Ctrl+\ or the eye/pin button). Drag to reorder,
  middle-click or right-click to close. The choice is remembered.
- Tabs restore on restart; bookmarks (Ctrl+D) and history feed the address
  bar's suggestions; searches go to DuckDuckGo.
- One process: `forge-browser URL` from another app opens a tab in the
  running browser.

Data: profile and bookmarks/history in `~/.local/share/forgeos/forge-browser`,
settings in `~/.config/forgeos/forge-browser.conf`.

DRM (Netflix, Spotify web, Prime Video) uses Widevine from
`chromium-widevine` (Chaotic-AUR, on the ISO). Qt WebEngine doesn't search
its `/usr/lib/chromium` path itself, so `main.cpp` passes `--widevine-path`
when the CDM is there. Check it at `chrome://media-internals` or
https://bitmovin.com/demos/drm.

Build: `cmake -S . -B build -G Ninja && ninja -C build`.
