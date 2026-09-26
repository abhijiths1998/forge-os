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

# --- Boot splash for the live medium ---
# plymouth (in packages.x86_64) is already installed and the "plymouth"
# hook is already in HOOKS (airootfs/etc/mkinitcpio.conf.d/archiso.conf),
# but plymouthd.conf can't be pre-seeded via the airootfs overlay (the
# plymouth package owns that path — same class of conflict grml-zsh-config
# hit with .zshrc). Set it here instead and regenerate the initramfs, the
# same pattern forge-postinstall.sh uses for the installed system.
plymouth-set-default-theme forge-os || true
mkinitcpio -P || true

# --- Replace WhiteSur's Apple-styled branding with forge-os's ---
# The launcher icon, Plasma splash logo, and SDDM login logo are all
# package-owned files (whitesur-icon-theme / whitesur-kde-theme), so they
# get overwritten here post-install rather than shipped via the airootfs
# overlay (which would hit the same kind of file-conflict pacman error).
# Wrapping the PNG in a trivial SVG (an <image> element with the PNG
# base64-embedded) is needed because several of these are referenced by
# a hardcoded ".svg" filename.
FORGE_LOGO_SVG=/tmp/forge-logo.svg
{
    printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="340" height="330" viewBox="0 0 340 330"><image width="340" height="330" xlink:href="data:image/png;base64,'
    base64 -w0 /usr/share/pixmaps/forge-os-logo.png
    printf '"/></svg>'
} > "${FORGE_LOGO_SVG}"

# Kickoff's launcher icon comes from the icon theme's "start-here*" icons,
# not a per-applet setting, so replace every "start-here" variant WhiteSur
# ships for the icon theme actually in use (WhiteSur-dark, see kdeglobals).
for f in /usr/share/icons/WhiteSur-dark/places/*/start-here*.svg \
         /usr/share/icons/WhiteSur-dark/status/symbolic/start-here-symbolic.svg; do
    if [[ -f "${f}" ]]; then
        cp "${FORGE_LOGO_SVG}" "${f}"
    fi
done

# Plasma splash screen (shown briefly between login and the desktop
# appearing) — Splash.qml hardcodes "images/logo.svg".
splash_logo=/usr/share/plasma/look-and-feel/com.github.vinceliuice.WhiteSur-dark/contents/splash/images/logo.svg
if [[ -f "${splash_logo}" ]]; then
    cp "${FORGE_LOGO_SVG}" "${splash_logo}"
fi

# SDDM login screen: theme.conf.user is WhiteSur-dark's own designated
# override file (theme.conf itself is read first, theme.conf.user takes
# precedence), so this is the sanctioned way to customize it, not a hack.
cat > /usr/share/sddm/themes/WhiteSur-dark/theme.conf.user <<'EOF'
[General]
type=image
background=/usr/share/backgrounds/forge-os/wallpaper.png
showlogo=shown
logo=/usr/share/pixmaps/forge-os-logo.png
EOF

rm -f "${FORGE_LOGO_SVG}"
