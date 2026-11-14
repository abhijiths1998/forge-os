# Forge Arcade

A launcher for the games in `forge-games`: a grid of cover cards, and for the
chosen game its description, controls, a "Needs a GPU" badge, its high scores
and a big Play button. Flutter on `forge_ui`. The session's Super+G runs
`forge-arcade`.

- Arrow keys move, Enter or Space plays, Esc quits.
- A gamepad does the same: d-pad or left stick moves, A plays, B quits. Flutter
  has no gamepad input on Linux, so `lib/gamepad.dart` reads the kernel's
  `/dev/input/js*` devices. It ignores the pad while the Arcade isn't the
  focused window, so a running game keeps it.
- Play starts the game's `exec` detached. The game outlives the Arcade.
- Hyprland draws no titlebars, so the window has its own strip (drag to move,
  a close button). The runner (`linux/runner/my_application.cc`) does the move
  and close through a method channel, `org.forgeos.arcade/window`; the strip
  goes into `forge_ui` later.

The games come from `/usr/share/forge-games/games.json` (see
`packages/forge-games`). `FORGE_GAMES_JSON` overrides the path:

    FORGE_GAMES_JSON=/path/to/games.json flutter run -d linux

High scores come from the files the games write (`highScoreFile` in
games.json; `~/.local/share` follows `XDG_DATA_HOME`). Port Calder keeps a
save game, not scores, so it shows none. Orbit Golf's best is strokes, so
smaller is better.

    flutter analyze && flutter test
    flutter build linux --release --no-tree-shake-icons

Not tested on hardware: the gamepad reader (only its event parsing is) and the
window drag under Hyprland.
