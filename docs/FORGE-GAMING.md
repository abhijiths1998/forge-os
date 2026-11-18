# Forge Gaming

Forge OS's game library and launcher, the Lutris-like piece of the "Game Hub"
idea. Two programs:

| Program | Language | Path | Job |
|---|---|---|---|
| `forge-gamed` | C++20 (CMake) | `apps/forge-gamed/` | Daemon: scans libraries, launches and tracks games, manages Proton/Wine runners, reads controllers |
| `forge-gaming` | Flutter on `forge_ui` | `apps/forge-gaming/` | The glass UI: desktop window + full-screen couch mode, fully controller-driven |

The UI never touches game files or devices itself; everything goes through the
daemon's socket. The daemon keeps running when the UI is closed, so the
controller's Guide button can open the UI at any time, including mid-game.

## Milestone 1 scope (library and launcher)

- Library: Steam, Heroic (Epic/GOG/Amazon) and Lutris games are imported;
  your own games are added by hand (native Linux executables, or Windows
  `.exe` run with Proton or Wine).
- Per-game settings for your own games: runner, prefix, arguments, working
  directory, environment, GameMode, MangoHud, gamescope.
- Favourites, hidden games, play time and last played for every game.
- Runners: lists Proton/Wine found on the system; downloads GE-Proton.
- Controllers through SDL3 (its mapping database covers DirectInput pads too),
  with hotplug, rumble and the Guide button.
- Later milestones: Lutris install scripts, winetricks/DXVK switching, cloud
  saves, per-game controller layouts.

## Files

| Path | Contents |
|---|---|
| `$XDG_RUNTIME_DIR/forge-gamed.sock` | the daemon's socket |
| `~/.local/share/forge-gaming/library.json` | your own games, plus favourite/hidden/play time for imported ones |
| `~/.local/share/forge-gaming/settings.json` | default runner |
| `~/.local/share/forge-gaming/runners/` | runners Forge Gaming downloaded |
| `~/.local/share/forge-gaming/prefixes/<id>/` | default Wine/Proton prefixes |
| `~/.local/state/forge-gaming/logs/<id>.log` | output of the last run of each game (ids with `:`→`_`) |

## Protocol

A Unix stream socket at `$XDG_RUNTIME_DIR/forge-gamed.sock` carrying
newline-delimited JSON, one UTF-8 object per line, both directions.

```jsonc
// client → daemon
{"id": 7, "method": "game.launch", "params": {"id": "lutris:2"}}
// daemon → client, exactly one per request
{"id": 7, "result": {}}
{"id": 7, "error": {"code": "not_found", "message": "no game lutris:9"}}
// daemon → every client, any time
{"event": "game.started", "data": {"id": "lutris:2", "tracked": true}}
```

`params` may be omitted when a method takes none. Error codes: `bad_request`,
`not_found`, `not_local`, `already_running`, `launch_failed`, `io`,
`network`, `internal`.

### Objects

**Game**

```jsonc
{
  "id": "steam:1046930",          // steam:<appid> | heroic:<runner>:<appName> | lutris:<id> | local:<uuid>
  "source": "steam",              // steam | heroic | lutris | local
  "title": "Dota Underlords",
  "cover": "/home/u/.../library_600x900.jpg", // portrait art: absolute path, https URL or null
  "hero": "https://.../library_hero.jpg",      // wide art: absolute path, https URL or null
  "installed": true,
  "running": false,               // only for launches the daemon can track
  "playtimeMinutes": 754,         // Lutris's own play time + time tracked by forge-gamed
  "lastPlayed": 1763400000,       // unix seconds or null
  "favorite": false,
  "hidden": false,
  "settings": null                // GameSettings for local games, null otherwise
}
```

**GameSettings** (local games only)

```jsonc
{
  "kind": "windows",              // native | windows
  "exe": "/games/Foo/Foo.exe",
  "args": "-dx11 --skip-intro",   // split like a shell would (quotes respected)
  "workdir": null,                // null → the exe's directory
  "runner": null,                 // Runner id; null → the default runner (windows only)
  "prefix": null,                 // null → ~/.local/share/forge-gaming/prefixes/<id>
  "env": {"DXVK_HUD": "fps"},
  "gamemode": true,
  "mangohud": false,
  "gamescope": {"enabled": false, "width": 1920, "height": 1080, "fps": 0, "fullscreen": true}
}
```

**Runner**

```jsonc
{
  "id": "steam:GE-Proton11-12",   // <source>:<directory name>; system wine is "system:wine"
  "name": "GE-Proton11-12",
  "kind": "proton",               // proton | wine
  "source": "steam",              // steam (compatibilitytools.d or steamapps/common/Proton*) | forge | lutris | system
  "path": "/home/u/.local/share/Steam/compatibilitytools.d/GE-Proton11-12"
}
```

**Pad**

```jsonc
{"index": 3, "name": "Bteam Specter", "type": "xbox"} // type: xbox | playstation | switch | generic
```

### Methods

| Method | Params | Result |
|---|---|---|
| `hello` | — | `{"protocol": 1, "daemon": "forge-gamed 0.1.0"}` |
| `ui.register` | — | `{}`; marks this connection as a UI (see Guide button) |
| `library.list` | — | `{"games": [Game]}` |
| `library.refresh` | — | `{"games": [Game]}`, rescans everything, then emits `library.changed` |
| `game.add` | `{"title", "cover"?, "settings": GameSettings}` | `{"game": Game}` |
| `game.update` | `{"id", "title"?, "cover"?, "favorite"?, "hidden"?, "settings"?}` | `{"game": Game}`; title, cover and settings only for local games |
| `game.remove` | `{"id"}` | `{}`; local games only (`not_local` otherwise) |
| `game.launch` | `{"id"}` | `{}` once the process is started; `already_running` if it is |
| `game.stop` | `{"id"}` | `{}`; SIGTERM to the process group, SIGKILL after 5 s |
| `game.log` | `{"id"}` | `{"text": "..."}`, the last 64 KiB of the last run's output |
| `runners.list` | — | `{"runners": [Runner], "default": "<id>" or null}` |
| `runners.setDefault` | `{"id"}` | `{}` |
| `runners.available` | — | `{"releases": [{"name", "url", "size", "installed"}]}`, the latest 10 GE-Proton releases |
| `runners.install` | `{"name"}` | `{}` at once; progress comes as events |
| `runners.remove` | `{"id"}` | `{}`; only `forge:` runners |
| `pads.list` | — | `{"pads": [Pad]}` |
| `pad.rumble` | `{"strength": 0.0–1.0, "ms": 1–2000, "index"?}` | `{}`; all pads unless `index` |

### Events

| Event | Data |
|---|---|
| `library.changed` | `{}`, a client should call `library.list` |
| `game.started` | `{"id", "tracked"}`; `tracked` is false for Steam, Heroic and Lutris hand-offs |
| `game.stopped` | `{"id", "exitCode", "playedSeconds"}` |
| `game.failed` | `{"id", "message"}` |
| `runner.progress` | `{"name", "received", "total"}` (bytes; at most ~10 per second) |
| `runner.installed` | `{"name", "runner": Runner}` |
| `runner.failed` | `{"name", "message"}` |
| `pad.connected` | `{"pad": Pad}` |
| `pad.disconnected` | `{"index"}` |
| `pad.button` | `{"pad", "button", "pressed", "repeat"}` |

`button` is one of `a b x y lb rb lt rt back start guide ls rs up down left right`,
in the Xbox layout (`a` is the bottom face button on every pad). The daemon
turns the left stick and the d-pad into `up/down/left/right` (stick
threshold 0.5 with hysteresis) and the triggers into `lt/rt`. A held
direction repeats: a first `repeat: true` press after 400 ms, then every 90 ms.

### Launching

| Source | Command | Tracked |
|---|---|---|
| steam | `steam steam://rungameid/<appid>` | no |
| heroic | `xdg-open heroic://launch?appName=<app>&runner=<runner>` | no |
| lutris | `lutris lutris:rungameid/<id>` | no (an open Lutris takes the game over and the command exits; Lutris counts play time itself) |
| local native | `[gamescope -W w -H h [-r fps] [-f] --] [gamemoderun] [mangohud] <exe> <args>` | yes |
| local windows, proton runner | `umu-run <exe> <args>` with `PROTONPATH=<runner> WINEPREFIX=<prefix> GAMEID=umu-default` when `umu-run` is on PATH; else `<runner>/proton waitforexitandrun <exe> <args>` with `STEAM_COMPAT_DATA_PATH=<prefix>` and `STEAM_COMPAT_CLIENT_INSTALL_PATH=<steam root>`; wrappers as for native | yes |
| local windows, wine runner | `<runner>/bin/wine <exe> <args>` (system: `wine`) with `WINEPREFIX=<prefix>`; wrappers as for native | yes |

Tracked games run in their own session (`setsid`), with stdout and stderr in
their log file. `game.stop` signals the whole process group.

### Guide button

Every Guide press is sent to clients as a `pad.button` event. If no
connection has called `ui.register`, the daemon also starts
`forge-gaming --couch` (`$FORGE_GAMING_BIN` overrides the command).
The UI ignores every other pad event while its window is not focused or a
tracked game is running, so the controller does not drive the UI behind a game.

### Starting the daemon

`forge-gamed` runs as a systemd user service (`forge-gamed.service`). The UI
starts it itself (detached) when the socket is missing. Only one daemon runs:
a second one that finds a live socket exits with code 0.

`forge-gamed --call <method> [json-params]` sends one request to the running
daemon and prints the response; `forge-gamed --watch` prints events.

## Milestone 2: the Game Hub

The roadmap's Game Hub: one library for every source, and a profile per game
that is applied when the game starts and undone when it stops, whichever
launcher started it.

### Seeing games run

Steam, Heroic and Lutris launches are hand-offs, so forge-gamed watches for
the games themselves: every 2 s it reads `/proc/*/cmdline` and marks a game
running when it finds

| Source | Sign |
|---|---|
| steam | a process whose arguments contain `SteamLaunch` and `AppId=<appid>` (Steam's reaper) |
| lutris | a process titled `lutris-wrapper: <name>` (or the `lutris-wrapper` script with `<name>` as its first argument), `<name>` being the game's Lutris name |
| heroic, lutris | otherwise, a process with an argument inside the game's install folder (Windows paths normalised: `\`→`/`, a leading `Z:` dropped, case-insensitive), not counting Steam, Heroic or Lutris themselves |

A game counts as stopped once it has been missing from two scans in a row.
Found games send the same `game.started` / `game.stopped` events as launched
ones, with `"detected": true`. Play time is added for Steam and Heroic games;
Lutris counts its own (forge-gamed reads it from `pga.db`).

### Profiles

Every game has a profile, applied when it starts (launched or found) and
undone when it stops:

| Field | Effect |
|---|---|
| `thermal` | a Forge Thermal profile (`forged set thermal <name>`), or null to leave cooling to the desktop's own rule (the `gaming` profile while a game is full screen) |
| `quiet` | do not disturb while playing (`forged set dnd on`) |

The setting in force before the game is remembered and put back. While a
game's thermal profile is held, `$XDG_RUNTIME_DIR/forge/thermal-held-by-game`
holds its id and the desktop's full-screen rule (`forge-game
fullscreen-on`) leaves cooling alone. Only the first game to start holds a
setting; `forged` missing means profiles do nothing (no error). Mangohud,
GameMode, gamescope and the runner stay per-game settings of your own games:
Steam, Heroic and Lutris keep those in their own launch options.

### Protocol additions

Game gains:

```jsonc
{
  "profile": {"thermal": "performance", "quiet": true}, // thermal null = automatic
  "detected": false,  // running, found by the watcher rather than launched here
  "canStop": false    // forge-gamed launched it and can stop it
}
```

| Method | Params | Result |
|---|---|---|
| `game.update` | also `"profile": {"thermal"?, "quiet"?}` (merged; `"thermal": null` = automatic) | `{"game": Game}` |
| `system.info` | — | `{"thermal": {"available": bool, "profiles": [name], "current": name or null}, "quiet": {"available": bool}}` from `forged state` |

`game.started` data gains `"detected"` (bool).
