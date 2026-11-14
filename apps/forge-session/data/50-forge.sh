# shellcheck shell=sh
# Forge OS: the session's environment, from forge-gpu-env (forge-session).
# uwsm sources this before Hyprland starts (env-hyprland.d), so Hyprland and
# every systemd user service get it.
if command -v forge-gpu-env >/dev/null 2>&1; then
    eval "$(forge-gpu-env)"
fi
