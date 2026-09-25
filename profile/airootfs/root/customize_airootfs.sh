#!/usr/bin/env bash
# Runs once, in an arch-chroot of the freshly pacstrap'd airootfs, near the
# end of the ISO build (see mkarchiso's _make_customize_airootfs). Has
# network access (inherits the build container's network namespace), which
# is what lets the Chaotic-AUR keyring bootstrap below actually reach out.
set -e -u

# --- Live session user ---
# A real desktop login (not root) for the live/Calamares session. Password
# is empty; SDDM autologin (etc/sddm.conf.d/autologin.conf) is what actually
# gets a user to the desktop, so no one is ever prompted for this password.
useradd -m -G wheel,users,storage,power,network,video,audio,disk,input,uucp -s /bin/bash liveuser
passwd -d liveuser

# --- Services ---
systemctl set-default graphical.target
systemctl enable sddm.service
systemctl enable NetworkManager.service
systemctl disable systemd-networkd.service systemd-networkd-wait-online.service 2>/dev/null || true
systemctl disable iwd.service 2>/dev/null || true
systemctl enable bluetooth.service
systemctl enable fstrim.timer
systemctl enable irqbalance.service
systemctl enable ananicy-cpp.service
systemctl enable fwupd.service

# chaotic-keyring / chaotic-mirrorlist (in packages.x86_64) already installed
# the signing key into this system's own pacman keyring and populated
# /etc/pacman.d/chaotic-mirrorlist during pacstrap, so /etc/pacman.conf's
# [chaotic-aur] block (see airootfs/etc/pacman.conf) is usable as-is.

# --- App store ---
# Pamac (installed via packages.x86_64) shows Flatpak apps too via its
# optional flatpak support; add the Flathub remote system-wide so that's
# actually populated from first boot.
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
