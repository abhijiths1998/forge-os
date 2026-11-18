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
useradd -m -G wheel,users,storage,power,network,video,audio,disk,input,uucp -s /bin/zsh liveuser
passwd -d liveuser
# The live session opens the installer once Hyprland is up (the installed
# system's users get the plain user.lua from /etc/skel instead).
install -Dm644 -o liveuser -g liveuser /dev/stdin /home/liveuser/.config/hypr/user.lua <<'EOF'
-- Live session only: open the installer when the desktop is up.
hl.on("hyprland.start", function()
    hl.exec_cmd("forge-live-installer")
end)
EOF

# --- Version ---
# Forge OS's os-release, and the installer's version, from forge-os-release.
/usr/local/bin/forge-os-release --write
forge_version="$(/usr/local/bin/forge-os-release)"
sed -i -E "s/^( *(shortVersion|version): *).*/\1${forge_version}/; s/^( *(shortVersionedName|versionedName): *).*/\1\"Forge OS ${forge_version}\"/" \
    /etc/calamares/branding/forge-os/branding.desc

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
systemctl enable power-profiles-daemon.service
systemctl enable forge-thermal.service
# forge-mind keeps its file index fresh per user (systemd --user)
systemctl --global enable forge-mind-index.timer
# forge-gamed: game library + controller reader; the Guide button opens
# Forge Gaming from anywhere (systemd --user, graphical session)
systemctl --global enable forge-gamed.service
systemctl enable fwupd.service
# Printing (system-config-printer sets printers up).
systemctl enable cups.socket

# chaotic-keyring / chaotic-mirrorlist (in packages.x86_64) already installed
# the signing key into this system's own pacman keyring and populated
# /etc/pacman.d/chaotic-mirrorlist during pacstrap, so /etc/pacman.conf's
# [chaotic-aur] block (see airootfs/etc/pacman.conf) is usable as-is.

# --- App store ---
# Pamac (installed via packages.x86_64) shows Flatpak apps too via its
# optional flatpak support; add the Flathub remote system-wide so that's
# actually populated from first boot.
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
# adw-gtk3 for GTK 3 Flatpak apps, the theme the desktop's GTK apps use, so
# they take forge-theme-sync's colours too. Best effort: a slow mirror
# mustn't fail the build.
flatpak install -y --noninteractive --system flathub org.gtk.Gtk3theme.adw-gtk3 \
    org.gtk.Gtk3theme.adw-gtk3-dark 2>/dev/null || true

# --- Boot splash for the live medium ---
# plymouth (in packages.x86_64) is already installed and the "plymouth"
# hook is already in HOOKS (airootfs/etc/mkinitcpio.conf.d/archiso.conf),
# but plymouthd.conf can't be pre-seeded via the airootfs overlay (the
# plymouth package owns that path — same class of conflict grml-zsh-config
# hit with .zshrc). Set it here instead and regenerate the initramfs, the
# same pattern forge-postinstall.sh uses for the installed system.
plymouth-set-default-theme forge-os || true
mkinitcpio -P || true

# --- Replace WhiteSur's Apple start-here icons with the forge emblem ---
# Everything else Forge Glass needs (SDDM theme, wallpaper, Plymouth) is
# forge-os's own and ships in the airootfs overlay. The one leftover is
# whitesur-icon-theme's "start-here" icons, drawn as an Apple logo: what any
# app asking for the distro logo gets. They're pacman-owned, so they're
# overwritten here rather than shipped via the overlay (which would hit the
# same kind of file-conflict pacman error grml-zsh-config did).
# Wrapping the PNG in a trivial SVG (an <image> element with the PNG
# base64-embedded) is needed because the theme hardcodes ".svg" names.
EMBLEM_SVG=/tmp/forge-emblem.svg
{
    printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="512" height="512" viewBox="0 0 512 512"><image width="512" height="512" xlink:href="data:image/png;base64,'
    base64 -w0 /usr/share/pixmaps/forge-os-emblem.png
    printf '"/></svg>'
} > "${EMBLEM_SVG}"

for theme in WhiteSur WhiteSur-dark WhiteSur-light; do
    for f in /usr/share/icons/"${theme}"/places/*/start-here*.svg \
             /usr/share/icons/"${theme}"/status/symbolic/start-here-symbolic.svg; do
        if [[ -f "${f}" ]]; then
            cp "${EMBLEM_SVG}" "${f}"
        fi
    done
done
rm -f "${EMBLEM_SVG}"
