# Forge Store

Forge OS's software store, in place of the Pamac GUI: Discover (AppStream's
featured apps), categories, search across the repos, Chaotic-AUR and (when
`EnableAUR` is on in `/etc/pamac.conf`) the AUR, installed packages, and
updates. Flutter UI in Forge Glass colours; the window is translucent and
KWin's Glass effect frosts it.

- **Queries** go straight to libpamac (`linux/runner/pamac_channel.cc`).
- **Transactions** run the `pamac` CLI (`install`, `build`, `remove`,
  `upgrade`, with `--no-confirm`), so authentication is the same polkit
  prompt as `forge install`. They queue and run one at a time; the activity
  bar shows pamac's output.
- Repo packages only update together (**Update all**, `pamac upgrade`):
  updating one on its own would be a partial upgrade. AUR packages can
  update one at a time.

```sh
forge-store                     # Discover
forge-store --search obs        # open on a search (the launcher uses this)
forge-store --page updates      # or installed
forge-store --details vlc       # one package
```

Build: `flutter build linux --release` (needs libpamac's headers, from the
`pamac` package).
