# utils

Scripts for working on Forge OS on a real machine: trying changes without an
ISO, and chasing problems (game freezes, heat) on the hardware. Not shipped
in the ISO. Each script's header says exactly what it does; `sudo` ones change
the system.

## Trying changes

| Script | What it does |
|---|---|
| `dev-install-app.sh <app>...` | Builds `apps/<app>` and installs it to `~/.local` (bundle, command, desktop files), restarting it if it was running |
| `sudo install-thermal.sh` | Installs this checkout's `forge-thermal`, its profiles, service, resume hook and polkit action, then re-applies the saved profile |

## Games and freezes

| Script | What it does |
|---|---|
| `gaming-check.sh` | Read-only check: kernel, NVIDIA driver and pin, freeze catching, GameMode/MangoHud, power, memory, indexing. Says what to fix |
| `sudo freeze-debug-setup.sh` | Gets ready for the next freeze: `linux-lts` as a second kernel, journal synced every 5 s, SysRq on |
| `freeze-report.sh [-N \| --list]` | After a freeze: how the boot ended, kernel, driver, GPU errors, warnings, the game, the last log lines and temperatures. Saves `~/forge-freeze-<date>.txt` |
| `grub-default-kernel.sh [lts\|zen\|linux]` | Lists kernels, or (with sudo) makes one GRUB's default; refuses one without an NVIDIA module |
| `nvidia-pin.sh [pin\|unpin]` | Holds the NVIDIA driver at its version through `pacman -Syu`, or lets it update |
| `forge-crashlog` + `forge-crashlog.service` | Temperatures, clocks and power to disk every 2 s, so the last readings survive a hard power-off; `forge-crashlog last` shows them |

Installing the crash logger:

    install -m755 utils/forge-crashlog ~/.local/bin/
    install -m644 utils/forge-crashlog.service ~/.config/systemd/user/
    systemctl --user enable --now forge-crashlog

## On a freeze

1. Don't hold the power button. Hold **Alt+PrtSc** and type **R E I S U B**
   slowly: it syncs the disks (the logs of the freeze) and reboots.
2. `utils/freeze-report.sh`, and look at "GPU errors" and the last readings.
