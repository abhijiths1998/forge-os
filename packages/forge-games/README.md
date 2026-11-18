# forge-games

The ten games from github.com/abhijiths1998/games (commit `2a19cdc`), built
from source for Forge Arcade (`apps/forge-arcade`): Port Calder, Hardlight,
Bramble Bound, Orbit Golf, Prism Smash, Lumen Drift, Relic Runner, Ember
Isle, Nova Lancer and Deep Delve. Depends on `sdl2`, and `mesa` for the two
OpenGL games.

## What it installs

| Path | What |
|---|---|
| `/usr/lib/forge-games/<name>` | the game binary |
| `/usr/bin/<name>` | a wrapper that sets the window class (below) and execs the binary |
| `/usr/share/applications/<name>.desktop` | from the game's own `.desktop.in`, `Exec=/usr/bin/<name>` |
| `/usr/share/forge-games/games.json` | what the Arcade lists |
| `/usr/share/forge-games/covers/<name>.png` | 640x400 cover art |

The games have no `DESTDIR` or top-level install, and `make PREFIX=$pkgdir/usr
install` would write the build path into `Exec=`. So `build()` runs `make -C`
per game, and `package()` installs the binary itself and runs the `sed` on
`@BIN@` with `/usr/bin/<name>`. The games repo is unchanged. They load no
data files (everything is generated in code), so no wrapper needs a working
directory.

## Desktop files

`Categories=Game;ArcadeGame;` replaces the game's own category, and each file
gets `StartupWMClass=<name>` and `X-Forge-Arcade=true`. Port Calder and
Hardlight also get `X-Forge-Needs-GPU=true` (OpenGL 3.3); the other eight are
software SDL2.

## Window class

The session's game rules (`rules.lua`) match the class names `port-calder`,
`hardlight`, `bramble-bound`, `orbit-golf`, `prism-smash`, `lumen-drift`,
`relic-runner`, `ember-isle`, `nova-lancer` and `deep-delve`. The games call
`SDL_CreateWindow` with a title and set no class, and Arch's `sdl2` is
sdl2-compat on SDL 3, which would otherwise pick its own default. So each
`/usr/bin/<name>` wrapper exports `SDL_APP_ID`, `SDL_VIDEO_WAYLAND_WMCLASS` and
`SDL_VIDEO_X11_WMCLASS` as the game's name. Verified: the wrappers and desktop
files in the container. Not verified: the class under a live Hyprland
(`hyprctl clients`); check that after the first ISO boot.

## Cover art

Every game has `--selftest DIR`, which runs it headless and writes BMP
screenshots of real frames from its own renderer. `build()` runs that with
`SDL_VIDEODRIVER=offscreen`, `SDL_AUDIODRIVER=dummy` and Mesa's llvmpipe
(`LIBGL_ALWAYS_SOFTWARE=1`), in a throwaway `XDG_DATA_HOME`, and ImageMagick
turns one frame per game (named in `_games` in the PKGBUILD) into a 640x400
PNG. The 320x200 games are scaled with a point filter so the pixels stay
square. No network and no GPU after the clone. If a self-test fails, the cover is a plain gradient and the
build says so, rather than failing the ISO.

## games.json

Hand-written (`games.json`, here): the controls come from each README, and
parsing Markdown tables in `build()` would be more fragile than a file the
build checks with `jq`. Fields: `id, name, description, controls [[keys,
action]], needsGpu, exec, cover, highScoreFile` (null when none), plus
`highScoreFormat` (`int` or `table`) and `lowerIsBetter`.

## High scores

| Game | File (under `~/.local/share`, or `XDG_DATA_HOME`) |
|---|---|
| Hardlight | `doomedl/hardlight/best.txt` (first number) |
| Bramble Bound, Orbit Golf, Prism Smash | `doomedl/<name>/best` |
| Lumen Drift | `lumen-drift/best` (no organisation in the path) |
| Relic Runner, Ember Isle, Nova Lancer, Deep Delve | `doomedl/<name>/scores.txt` (`NAME score level`, 8 lines) |
| Port Calder | none: `doomedl/port-calder/save.txt` is a save game |

Orbit Golf's best round is strokes, so the lowest wins.

## Build

    makepkg --nodeps

needs `sdl2`, `mesa`, `git`, `gcc`, `make`, `pkgconf`, `imagemagick` and `jq`
installed (the ISO's `apps/build-packages.sh` uses `--nodeps`, so the build
container must have them). The sources are `git+https://github.com/abhijiths1998/games.git`
pinned to the commit, so the clone needs the network.
