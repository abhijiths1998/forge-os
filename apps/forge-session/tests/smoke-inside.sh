#!/usr/bin/env bash
# Runs inside the forge-os-check container (tests/smoke.sh starts it): a
# Forge's Hyprland session nested in the host desktop, then checks over
# hyprctl. Screenshots land in /out.
set -u
export XDG_RUNTIME_DIR=/run/t PATH=/forgebin:${PATH}
mkdir -p "${XDG_RUNTIME_DIR}" && chmod 700 "${XDG_RUNTIME_DIR}"
# Hyprland runs nested, as a window in the desktop that started the test
# (its Wayland socket is passed in as "host"); Aquamarine needs a parent
# that speaks xdg_wm_base 6, which KWin and Hyprland do and headless
# Weston/sway don't.
unset DISPLAY
WAYLAND_DISPLAY=host Hyprland -c "${HOME}/.config/hypr/hyprland.lua" >/out/hypr.log 2>&1 &
for _ in $(seq 40); do ls "${XDG_RUNTIME_DIR}"/hypr/*/.socket.sock >/dev/null 2>&1 && break; sleep 0.3; done
HYPRLAND_INSTANCE_SIGNATURE="$(ls "${XDG_RUNTIME_DIR}/hypr" | head -1)"
export HYPRLAND_INSTANCE_SIGNATURE
export WAYLAND_DISPLAY=wayland-1
# The nested output comes up at scale 2; tests want real-size layouts.
hyprctl eval 'hl.monitor({ output = "WAYLAND-1", mode = "preferred", position = "0x0", scale = 1 })' >/dev/null
sleep 1
"$@"
