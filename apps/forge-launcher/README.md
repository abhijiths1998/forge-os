# Forge Launcher

The Meta+Space command bar: a Forge Glass card (Flutter UI, GTK runner) that
finds apps, files (Baloo), Forge actions (theme, tiling, thermal profiles,
updates) and power actions, does quick maths, and runs commands.

| Type | Does |
|---|---|
| an app name, generic name or keyword | launch it |
| `2*(3+4)`, `sqrt(2)`, `pi/4` | maths; Enter copies the result |
| `dark`, `tiling`, `cool`, `update` | Forge actions |
| `lock`, `sleep`, `restart` | power actions |
| `install <pkg>` | find it in Forge Store (or `forge install` without it) |
| `> command` | run it in Konsole |
| `? words`, or any URL | web search / open the page |

It starts hidden at login (`forge-launcher --background`) and stays running,
so Meta+Space only shows the window. Running `forge-launcher` again toggles
it. The window is translucent; KWin's Glass effect frosts it, and a KWin rule
(`/etc/skel/.config/kwinrulesrc`) takes the border off and centres it.

Build: `flutter build linux --release` (the bundle is in
`build/linux/x64/release/bundle/`). `FORGE_LAUNCHER_QUERY=text` pre-fills the
search on start, for testing.
