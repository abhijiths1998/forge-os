#!/usr/bin/env bash
# Run by Calamares' shellprocess module, chrooted into the freshly
# installed target, after unpackfs has copied the live system across and
# packages.conf has removed the live-only packages. Cleans up things that
# only made sense on the live medium.
set -u

# The live ISO's mkinitcpio config carries archiso-only hooks (loopback
# mount, PXE, etc.) that must not ship on the installed system.
rm -f /etc/mkinitcpio.conf.d/archiso.conf
cat > /etc/mkinitcpio.conf.d/base.conf <<'EOF'
HOOKS=(base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)
EOF
plymouth-set-default-theme forge-os 2>/dev/null || true
mkinitcpio -P || true

# NOPASSWD sudo was a live-session convenience; require a password for real.
cat > /etc/sudoers.d/g_wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/g_wheel

# Live-session-only autologin.
rm -f /etc/sddm.conf.d/autologin.conf

# Best-effort snapshot setup: mount.conf already lays /.snapshots down as
# its own @snapshots subvolume (the layout ArchWiki's snapper guide
# expects); this just registers it with snapper and turns on the timers.
if findmnt -no FSTYPE / | grep -q btrfs && command -v snapper >/dev/null 2>&1; then
    snapper --no-dbus -c root create-config / || true
    systemctl enable snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
    systemctl enable grub-btrfsd.service 2>/dev/null || true
fi
