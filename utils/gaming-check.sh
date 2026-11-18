#!/usr/bin/env bash
# gaming-check.sh: is this machine set up the way games run best on it?
#
#   utils/gaming-check.sh
#
# Read-only: prints OK / WARN / INFO per item, and for each WARN what to do.
# Covers the kernel and NVIDIA driver (and that it's pinned), the crash-catching
# setup (SysRq, journal sync, crash logger), GameMode and MangoHud, power and
# thermal profiles, memory map limit and swap, and file indexing that would
# compete with a game for the disk.
set -uo pipefail

G="" Y="" N=""
[[ -t 1 ]] && G=$'\e[32m' Y=$'\e[33m' N=$'\e[0m'
ok() { printf '  %sOK%s    %s\n' "${G}" "${N}" "$*"; }
warn() { printf '  %sWARN%s  %s\n' "${Y}" "${N}" "$1"; [[ -n "${2:-}" ]] && printf '        → %s\n' "$2"; }
info() { printf '  INFO  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
pkg() { pacman -Q "$1" >/dev/null 2>&1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "Kernel and driver"
info "running $(uname -r)"
top="$(sed -n 's|^GRUB_TOP_LEVEL="\{0,1\}/boot/vmlinuz-\([^"]*\)"\{0,1\}|\1|p' /etc/default/grub 2>/dev/null)"
[[ -n "${top}" ]] && info "GRUB default: ${top}" || info "GRUB default: first entry (no GRUB_TOP_LEVEL)"
if lspci -n 2>/dev/null | grep -q ' 03[0-9][0-9]: 10de:'; then
    drv="$(cat /sys/module/nvidia/version 2>/dev/null)"
    [[ -n "${drv}" ]] && ok "NVIDIA driver ${drv} loaded" || warn "NVIDIA GPU present but the driver isn't loaded"
    grep -q 'nvidia-drm.modeset=1' /proc/cmdline && ok "nvidia-drm.modeset=1" \
        || warn "nvidia-drm.modeset=1 not on the kernel command line" "add it to GRUB_CMDLINE_LINUX_DEFAULT"
    if "${HERE}/nvidia-pin.sh" status | grep -q '^pinned: [0-9]'; then ok "driver pinned (IgnorePkg)"
    else warn "driver not pinned; pacman -Syu may update it" "sudo utils/nvidia-pin.sh pin"; fi
fi

echo; echo "Catching freezes"
[[ "$(sysctl -n kernel.sysrq 2>/dev/null)" == 1 ]] && ok "SysRq on (Alt+PrtSc + R E I S U B)" \
    || warn "SysRq limited ($(sysctl -n kernel.sysrq 2>/dev/null))" "sudo utils/freeze-debug-setup.sh"
grep -qs 'SyncIntervalSec=5s' /etc/systemd/journald.conf.d/*.conf && ok "journal syncs every 5 s" \
    || warn "journal syncs every 5 min: a freeze loses the last minutes" "sudo utils/freeze-debug-setup.sh"
systemctl --user is-active -q forge-crashlog && ok "forge-crashlog recording" \
    || warn "no crash logger running" "see utils/README.md, forge-crashlog"

echo; echo "Game tools"
if pkg gamemode && pkg lib32-gamemode; then
    ok "GameMode installed"
else
    warn "GameMode missing (Lutris asks for libgamemode.so on every launch)" "sudo pacman -S gamemode lib32-gamemode"
fi
pkg mangohud && ok "MangoHud installed" || info "MangoHud not installed (overlay for FPS and temps)"
have gamescope && ok "gamescope installed" || info "gamescope not installed"

echo; echo "Power and heat"
if [[ "$(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -n1)" == 1 ]]; then ok "on AC power"
else warn "on battery: the GPU is held far below its full power" "plug in for games"; fi
have powerprofilesctl && info "power profile: $(powerprofilesctl get)"
[[ -r /sys/firmware/acpi/platform_profile ]] && info "firmware profile: $(cat /sys/firmware/acpi/platform_profile)"
have forge-thermal && info "Forge Thermal profile: $(forge-thermal status | sed -n 's/^profile=//p')"
info "CPU governor $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null), EPP $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"

echo; echo "Memory and disk"
mmc="$(sysctl -n vm.max_map_count)"
(( mmc >= 1048576 )) && ok "vm.max_map_count ${mmc}" \
    || warn "vm.max_map_count ${mmc}: some games crash below 1048576" "echo 'vm.max_map_count = 1048576' | sudo tee /etc/sysctl.d/80-gaming.conf"
[[ -n "$(swapon --noheadings 2>/dev/null)" ]] && ok "swap: $(swapon --noheadings --show=NAME,SIZE | tr '\n' ' ')" \
    || warn "no swap: running out of RAM freezes instead of slowing down" "install zram-generator"
if have balooctl6 && balooctl6 status 2>/dev/null | grep -qi 'is running'; then
    if grep -qs "${HOME}/Games" "${HOME}/.config/baloofilerc"; then ok "file indexing skips ~/Games"
    else warn "KDE file indexing (Baloo) can read game files mid-game" "add ~/Games to System Settings → Search → excluded folders"; fi
fi
for d in "${HOME}/Games" /; do
    [[ -d "${d}" ]] || continue
    free="$(df -h --output=avail "${d}" | tail -n1 | tr -d ' ')"
    info "free space on ${d}: ${free}"
done
