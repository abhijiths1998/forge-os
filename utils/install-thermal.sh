#!/usr/bin/env bash
# install-thermal.sh: put this checkout's forge-thermal on the running
# machine, for trying changes without building an ISO.  (root)
#
#   sudo utils/install-thermal.sh
#
# Installs /usr/local/bin/forge-thermal (the path polkit allows), the
# shipped profiles, the boot service, the resume hook and the polkit
# action. Leaves alone what's the user's: custom.conf and the saved choice.
# Removes the old PySide app if it's still there. Then re-applies the saved
# profile so a changed profile takes effect.
set -euo pipefail

(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }
R="$(cd "$(dirname "$0")/.." && pwd)/profile/airootfs"

install -m755 "${R}/usr/local/bin/forge-thermal" /usr/local/bin/forge-thermal
install -d /etc/forge-thermal/profiles
for f in "${R}"/etc/forge-thermal/profiles/*.conf; do
    install -m644 "${f}" /etc/forge-thermal/profiles/
done
install -m644 "${R}/etc/systemd/system/forge-thermal.service" /etc/systemd/system/
install -m755 "${R}/usr/lib/systemd/system-sleep/forge-thermal" /usr/lib/systemd/system-sleep/
install -m644 "${R}/usr/share/polkit-1/actions/org.forgeos.thermal.policy" /usr/share/polkit-1/actions/
rm -f /usr/local/bin/forge-thermal-gui /usr/share/applications/org.forgeos.thermal.desktop

systemctl daemon-reload
systemctl enable forge-thermal.service >/dev/null 2>&1 || true
/usr/local/bin/forge-thermal restore
echo "forge-thermal installed; profile: $(/usr/local/bin/forge-thermal status | sed -n 's/^profile=//p')"
