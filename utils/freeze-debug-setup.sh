#!/usr/bin/env bash
# freeze-debug-setup.sh: get a machine ready to catch the next hard freeze.
# (root)
#
#   sudo utils/freeze-debug-setup.sh
#
#  - linux-lts and its headers, so DKMS builds the NVIDIA module for a
#    second kernel to compare against (switch with grub-default-kernel.sh)
#  - journald syncs every 5 s instead of 5 min, so the seconds before a
#    freeze reach the disk
#  - Magic SysRq fully on, so Alt+PrtSc + R E I S U B can sync and reboot
#    a hung desktop instead of the power button throwing the logs away
set -euo pipefail

(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }

pacman -S --needed --noconfirm linux-lts linux-lts-headers

install -d /etc/systemd/journald.conf.d
printf '[Journal]\nSyncIntervalSec=5s\n' > /etc/systemd/journald.conf.d/sync-fast.conf
systemctl restart systemd-journald

echo 'kernel.sysrq = 1' > /etc/sysctl.d/90-sysrq.conf
sysctl -q -w kernel.sysrq=1

if command -v grub-mkconfig >/dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo
dkms status 2>/dev/null | grep -i nvidia || echo "no NVIDIA DKMS module (fine without an NVIDIA GPU)"
echo "Ready. On a freeze: hold Alt+PrtSc and type R E I S U B slowly, then run utils/freeze-report.sh."
