# Forge Terminal

Forge OS's terminal, in Flutter on `forge_ui` like the other Forge apps, so
it is part of the desktop's look rather than themed after the fact:

- **The theme, live.** Colours are the Theming Kit's terminal scheme (the
  same `konsoleColours` it writes for Konsole), the cursor and selection are
  the accent, and the background is the theme's terminal opacity over the
  compositor's glass. Changing the theme or switching light/dark restyles
  open windows at once (it watches `~/.config/forge/theme.json` and
  `kdeglobals`). Optionally light colours when the desktop is light.
- **The desktop's font**: kdeglobals' fixed-width font unless one is picked.
- Tabs (drag to reorder, middle-click to close, a dot for new output, a
  flash for the bell), titles from the program or its name and folder.
- Find in the scrollback, Ctrl+click links and paths, Ctrl+Shift+E opens
  the folder in Forge Files, and a confirmation before closing a tab that's
  running something.

| Keys | |
|---|---|
| Ctrl+Shift+T / W / N | new tab / close tab / new window |
| Ctrl+Tab, Ctrl+PgUp/PgDn, Alt+1…9 | switch tab (Ctrl+Shift+PgUp/PgDn moves it) |
| Ctrl+Shift+C / V, Shift+Insert | copy / paste |
| Ctrl+Shift+F | find |
| Ctrl+= / − / 0 | zoom |
| Shift+PgUp/PgDn | scroll |
| Ctrl+Shift+, | settings |

`forge-terminal [--workdir DIR] [--hold] [-e COMMAND ARG...]`; a folder as
the only argument opens there.

How it's built: xterm (pub.dev) emulates the terminal; the pseudo-terminal
is our own. `linux/runner/pty.cc` forks and execs the shell (C, since a fork
of the Dart VM can't run Dart), and `lib/pty.dart` calls it through dart:ffi
from the executable itself (`ENABLE_EXPORTS`), reading each terminal in its
own isolate. Settings: `~/.config/forge/terminal.json`.

Build: `flutter build linux --release --no-tree-shake-icons`; try it with
`utils/dev-install-app.sh forge-terminal`.
