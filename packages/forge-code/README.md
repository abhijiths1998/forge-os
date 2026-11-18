# Forge Code

Forge OS's code editor: Neovim with a ready-made configuration, run as
`forge-code` (or "Forge Code" in the launcher). It works offline from the
ISO and has no connection to your own Neovim setup.

## What is in it

- lazy.nvim, with every plugin pinned in `nvim/lazy-lock.json`
- LSP through Neovim 0.12's `vim.lsp.config` / `vim.lsp.enable`, with
  nvim-lspconfig for the server defaults; blink.cmp for completion
- nvim-lint, and conform.nvim (formats on save)
- nvim-treesitter, parsers compiled when the package is built: python sql
  bash c cpp rust dart qmljs lua json yaml toml markdown markdown_inline vim
  vimdoc query regex
- Telescope (with fzf-native), which-key, nvim-tree, gitsigns, toggleterm,
  lualine, mini.icons (needs the Nerd Font Forge OS ships)
- the Forge colourscheme, built at startup from `~/.config/forge/theme.json`
  (`dark`, `accent`, `tintHue`; without the file, Forge Glass dark). The
  background is transparent so a translucent terminal shows through;
  `:ForgeTransparent` toggles it, or set `vim.g.forge_transparent = false`.

No Mason: language servers and tools are Arch packages, listed as optional
dependencies. A server is switched on only when its program is installed.
Python (pyright, ruff), Bash, C/C++ (clangd), Rust, Lua, JSON, YAML, TOML,
Markdown, QML (`qmlls` from qt6-declarative) and Dart (`dart language-server`
from the SDK) are covered; SQL gets treesitter and, with `sqlfluff`, lint and
format. basedpyright and sqls are not in the repos and are skipped (basedpyright
is used if installed and pyright is not).

## Keys

Leader is Space; press it and wait for the which-key menu.

| Keys | Does |
|---|---|
| `Space f f` / `f g` / `f b` / `f r` | files / search text / buffers / recent |
| `Space e` | file explorer |
| `Space g ...` | git: hunks (`p` `s` `r` `b`), `g` changed files, `c` commits |
| `Space l ...` | LSP: `a` action, `r` rename, `d` diagnostics, `s` symbols, `f` format |
| `Space t t` / `t h` / `t v` | terminal: float / below / beside (`Ctrl+\` too) |
| `Space c f` | format now; saving formats too |
| `Space h t` | the first-run tutorial again (`:ForgeTutorial`) |

The tutorial opens once, on the first launch with no file, and keeps a marker
in `~/.local/state/forge-code/`.

## Staying apart from ~/.config/nvim

`/usr/bin/forge-code` sets `NVIM_APPNAME=forge-code` and starts
`nvim -u /usr/share/forge/nvim/init.lua`. Neovim then never reads
`~/.config/nvim`; data, state and cache go to `~/.local/share/forge-code`,
`~/.local/state/forge-code` and `~/.cache/forge-code`. Nothing is written
to `~/.config`.

`forge-code --gui` runs the same in Neovide, if it is installed (translucent,
`neovide_opacity = 0.85`). The desktop entry has an "Open in Neovide" action.

## How it works offline

The PKGBUILD clones each plugin at its pinned commit, compiles
telescope-fzf-native and the treesitter parsers in `build()`, and installs
plugins to `/usr/share/forge/nvim/lazy` and parsers to
`/usr/share/forge/nvim/parsers`. lazy is told never to install, check or watch
(`install.missing = false`, `checker.enabled = false`,
`change_detection.enabled = false`), and blink.cmp uses its Lua fuzzy matcher
so it needs no binary download.

## Updating the pins

1. Pick the new commit (`git ls-remote <repo> refs/tags/<tag>`).
2. Change it in `nvim/lazy-lock.json` and in the matching `source=` line of
   the PKGBUILD. They must agree.
3. Bump `pkgrel` or `pkgver`, build, and run the checks below.

Treesitter parser versions follow the pinned nvim-treesitter.

## Check

Build the package in the `forge-os-check` container, install it, then run
`forge-code --headless` with a few `lua` commands: no `vim.v.errmsg`, every
plugin loaded from `/usr/share/forge/nvim/lazy`, the parsers present,
`:checkhealth lazy nvim-treesitter` free of ERROR, and no `~/.config/nvim`.
