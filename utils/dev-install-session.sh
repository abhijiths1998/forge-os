#!/usr/bin/env bash
# dev-install-session.sh: put the Forge desktop session from this checkout on
# this machine, to try it from the login screen without building an ISO.
#
#   sudo utils/dev-install-session.sh
#   sudo FORGE_HYPRBARS=/path/to/hyprbars.so utils/dev-install-session.sh
#
# Installs the session entry, forge-session(-start), forge-keep, Forge
# Compositor, Forge's hyprland.conf (the fallback), the portal choice and
# the theme sync, and Forge Shell. Build first:
#   cd compositor && cargo build --release
#   cd apps/forge-shell && flutter build linux --release --no-tree-shake-icons
# Plasma stays as it is; pick "Forge" or "Plasma" at the login screen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AIR="${ROOT}/profile/airootfs"
BUNDLE="${ROOT}/apps/forge-shell/build/linux/x64/release/bundle"
COMPOSITOR="${ROOT}/compositor/target/release/forge-compositor"

[[ ${EUID} -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
[[ -x "${BUNDLE}/forge-shell" ]] || { echo "build apps/forge-shell first" >&2; exit 1; }
[[ -x "${COMPOSITOR}" ]] || { echo "build the compositor first: cd compositor && cargo build --release" >&2; exit 1; }

install -Dm644 "${AIR}/usr/share/wayland-sessions/forge.desktop" /usr/share/wayland-sessions/forge.desktop
install -Dm644 "${AIR}/usr/share/forge/hyprland.conf" /usr/share/forge/hyprland.conf
install -Dm644 "${AIR}/usr/share/xdg-desktop-portal/forge-portals.conf" /usr/share/xdg-desktop-portal/forge-portals.conf
# The KWin-only "Forge (safe mode)" entry is gone (KWin is now only the
# automatic fallback); take it off machines that had it.
rm -f /usr/share/wayland-sessions/forge-kwin.desktop
install -Dm644 "${AIR}/usr/lib/systemd/user/forge-session.target" /usr/lib/systemd/user/forge-session.target
for bin in forge-session forge-session-start forge-keep forge-theme-sync forge-dialog; do
    install -Dm755 "${AIR}/usr/local/bin/${bin}" "/usr/local/bin/${bin}"
done

# The title-bar plugin, if it was built (packages/forge-hyprbars/PKGBUILD
# says how; it must match this Hyprland's version).
BARS="${FORGE_HYPRBARS:-}"
if [[ -n "${BARS}" ]]; then
    install -Dm755 "${BARS}" /usr/lib/forge/hyprbars.so
fi

install -Dm755 "${COMPOSITOR}" /usr/local/bin/forge-compositor

rm -rf /usr/lib/forge-shell
cp -r "${BUNDLE}" /usr/lib/forge-shell
ln -sfn /usr/lib/forge-shell/forge-shell /usr/local/bin/forge-shell

echo "Installed. Log out and pick \"Forge\" at the login screen."
