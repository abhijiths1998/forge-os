#!/usr/bin/env bash
# forge-os post-install setup: run this on a bare Arch Linux install
# (e.g. straight after archinstall) to get NVIDIA drivers, a gaming stack,
# system optimizations, and a browser, all through an interactive menu.
#
# Usage:
#   ./setup.sh
#
# Safe to re-run: every step uses `pacman -S --needed` and idempotent
# config writes, so running it again just fills in anything you skipped.
set -euo pipefail

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

if [[ ! -f /etc/arch-release ]]; then
    echo "This script is for Arch Linux (or an Arch derivative). Aborting." >&2
    exit 1
fi

if [[ "${EUID}" -eq 0 ]]; then
    echo "Run this as your normal user, not root — it calls sudo itself" \
         "for the steps that need it." >&2
    exit 1
fi

if ! sudo -v; then
    echo "Need sudo access to continue." >&2
    exit 1
fi
# Keep the sudo timestamp alive for the duration of the script.
( while true; do sudo -n true; sleep 60; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT

# gum (https://github.com/charmbracelet/gum) is what gives this script its
# UI; bootstrap it with a plain pacman call before anything else.
if ! command -v gum >/dev/null 2>&1; then
    echo "Installing gum (for the menus below)..."
    sudo pacman -S --needed --noconfirm gum
fi

title() {
    gum style --border double --align center --width 60 --margin "1 2" \
        --padding "1 2" --foreground 212 "$1"
}
section() {
    gum style --foreground 99 --bold "$1"
}

title "forge-os post-install setup"

# ---------------------------------------------------------------------------
# Repos: multilib (needed for Steam/lib32-*) and Chaotic-AUR (prebuilt AUR
# binaries — GE-Proton helpers, Heroic, vkBasalt, Brave, legacy NVIDIA, etc.)
# ---------------------------------------------------------------------------

enable_multilib() {
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        return
    fi
    section "Enabling [multilib]..."
    sudo sed -i \
        '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/{s/^#//}' \
        /etc/pacman.conf
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
    fi
}

enable_chaotic_aur() {
    if grep -q "^\[chaotic-aur\]" /etc/pacman.conf; then
        return
    fi
    section "Enabling Chaotic-AUR..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
}

if gum confirm "Enable multilib + Chaotic-AUR repos? (needed for Steam, GE-Proton, Brave, and most of the options below)"; then
    enable_multilib
    enable_chaotic_aur
    sudo pacman -Sy
fi

# ---------------------------------------------------------------------------
# NVIDIA
# ---------------------------------------------------------------------------

NVIDIA_PACKAGES=()
NVIDIA_CHOICE="Skip"

if lspci -nnk 2>/dev/null | grep -iq nvidia; then
    NVIDIA_CHOICE=$(gum choose \
        "nvidia-open-dkms (recommended — RTX / GTX 16xx and newer)" \
        "Legacy proprietary (pre-2018 GPUs, via Chaotic-AUR)" \
        "Skip" \
        --header "NVIDIA GPU detected. Install a driver?")
else
    gum style --foreground 240 "No NVIDIA GPU detected via lspci — skipping driver install (you can still pick a browser/gaming tools below)."
fi

case "${NVIDIA_CHOICE}" in
    nvidia-open-dkms*)
        NVIDIA_PACKAGES=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland vulkan-icd-loader lib32-vulkan-icd-loader)
        ;;
    "Legacy proprietary"*)
        # 470xx covers most Kepler/Maxwell/Pascal cards. Very old GPUs
        # (pre-Kepler) need nvidia-390xx-dkms or nvidia-340xx-dkms instead —
        # install those manually from Chaotic-AUR if 470xx doesn't work.
        NVIDIA_PACKAGES=(nvidia-470xx-dkms nvidia-470xx-utils lib32-nvidia-470xx-utils nvidia-470xx-settings)
        ;;
esac

# ---------------------------------------------------------------------------
# Gaming stack
# ---------------------------------------------------------------------------

GAMING_CHOICES=$(gum choose --no-limit --height 15 \
    --header "Gaming tools (space to toggle, enter to confirm):" \
    --selected="Steam,GameMode,MangoHud,ProtonUp-Qt (GE-Proton installer),Discord" \
    "Steam" "Lutris" "Heroic Games Launcher" "Wine (staging) + Winetricks" \
    "GameMode" "MangoHud" "GOverlay" "vkBasalt" "ProtonUp-Qt (GE-Proton installer)" \
    "Gamescope" "Discord" "OBS Studio" "Controller support (udev rules)")

GAMING_PACKAGES=()
while IFS= read -r choice; do
    case "${choice}" in
        Steam) GAMING_PACKAGES+=(steam) ;;
        Lutris) GAMING_PACKAGES+=(lutris) ;;
        "Heroic Games Launcher") GAMING_PACKAGES+=(heroic-games-launcher-bin) ;;
        "Wine (staging) + Winetricks") GAMING_PACKAGES+=(wine-staging winetricks) ;;
        GameMode) GAMING_PACKAGES+=(gamemode lib32-gamemode) ;;
        MangoHud) GAMING_PACKAGES+=(mangohud lib32-mangohud) ;;
        GOverlay) GAMING_PACKAGES+=(goverlay) ;;
        vkBasalt) GAMING_PACKAGES+=(vkbasalt lib32-vkbasalt) ;;
        "ProtonUp-Qt (GE-Proton installer)") GAMING_PACKAGES+=(protonup-qt) ;;
        Gamescope) GAMING_PACKAGES+=(gamescope) ;;
        Discord) GAMING_PACKAGES+=(discord) ;;
        "OBS Studio") GAMING_PACKAGES+=(obs-studio) ;;
        "Controller support (udev rules)") GAMING_PACKAGES+=(game-devices-udev) ;;
    esac
done <<< "${GAMING_CHOICES}"

# ---------------------------------------------------------------------------
# Optimization
# ---------------------------------------------------------------------------

OPT_CHOICES=$(gum choose --no-limit --height 10 \
    --header "System optimizations:" \
    "zram (compressed swap in RAM)" "ananicy-cpp (auto process priority)" \
    "irqbalance" "reflector (fast mirror ranking)" "fstrim.timer (SSD TRIM)" \
    "power-profiles-daemon" "linux-zen kernel (kept alongside stock linux)")

OPT_PACKAGES=()
DO_ZRAM=0 DO_ANANICY=0 DO_IRQBALANCE=0 DO_REFLECTOR=0 DO_FSTRIM=0 DO_PPD=0 DO_ZEN=0
while IFS= read -r choice; do
    case "${choice}" in
        "zram (compressed swap in RAM)") OPT_PACKAGES+=(zram-generator); DO_ZRAM=1 ;;
        "ananicy-cpp (auto process priority)") OPT_PACKAGES+=(ananicy-cpp ananicy-rules-git); DO_ANANICY=1 ;;
        irqbalance) OPT_PACKAGES+=(irqbalance); DO_IRQBALANCE=1 ;;
        "reflector (fast mirror ranking)") OPT_PACKAGES+=(reflector); DO_REFLECTOR=1 ;;
        "fstrim.timer (SSD TRIM)") DO_FSTRIM=1 ;;
        power-profiles-daemon) OPT_PACKAGES+=(power-profiles-daemon); DO_PPD=1 ;;
        "linux-zen kernel (kept alongside stock linux)") OPT_PACKAGES+=(linux-zen linux-zen-headers); DO_ZEN=1 ;;
    esac
done <<< "${OPT_CHOICES}"

# ---------------------------------------------------------------------------
# Browser (Brave first: it's the default choice, just press enter)
# ---------------------------------------------------------------------------

BROWSER_CHOICE=$(gum choose "Brave" "Firefox" "Chromium" "Skip" --header "Default browser:")
BROWSER_PACKAGES=()
case "${BROWSER_CHOICE}" in
    Brave) BROWSER_PACKAGES=(brave-bin) ;;
    Firefox) BROWSER_PACKAGES=(firefox) ;;
    Chromium) BROWSER_PACKAGES=(chromium) ;;
esac

# ---------------------------------------------------------------------------
# Desktop essentials: keyring + app store. Pre-selected — these are the kind
# of basics you want by default, not something to hunt for in a menu.
# ---------------------------------------------------------------------------

ESSENTIALS_CHOICES=$(gum choose --no-limit --height 6 \
    --header "Desktop essentials:" \
    --selected="Pamac (AUR + Flatpak + pacman app store),GNOME Keyring + Seahorse (credential storage),Flatpak + Flathub (app store content)" \
    "Pamac (AUR + Flatpak + pacman app store)" \
    "GNOME Keyring + Seahorse (credential storage)" \
    "Flatpak + Flathub (app store content)")

ESSENTIALS_PACKAGES=()
DO_FLATPAK=0
while IFS= read -r choice; do
    case "${choice}" in
        "Pamac (AUR + Flatpak + pacman app store)") ESSENTIALS_PACKAGES+=(pamac) ;;
        "GNOME Keyring + Seahorse (credential storage)") ESSENTIALS_PACKAGES+=(gnome-keyring seahorse libsecret) ;;
        "Flatpak + Flathub (app store content)") ESSENTIALS_PACKAGES+=(flatpak); DO_FLATPAK=1 ;;
    esac
done <<< "${ESSENTIALS_CHOICES}"

# ---------------------------------------------------------------------------
# Summary + confirm
# ---------------------------------------------------------------------------

ALL_PACKAGES=("${NVIDIA_PACKAGES[@]}" "${GAMING_PACKAGES[@]}" "${OPT_PACKAGES[@]}" "${BROWSER_PACKAGES[@]}" "${ESSENTIALS_PACKAGES[@]}")

if [[ "${#ALL_PACKAGES[@]}" -eq 0 ]]; then
    gum style --foreground 240 "Nothing selected — nothing to do."
    exit 0
fi

section "About to install:"
printf '  %s\n' "${ALL_PACKAGES[@]}"

if ! gum confirm "Proceed?"; then
    echo "Aborted."
    exit 0
fi

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

gum spin --spinner dot --title "Installing packages..." -- \
    sudo pacman -S --needed --noconfirm "${ALL_PACKAGES[@]}"

if [[ -n "${NVIDIA_PACKAGES[*]:-}" ]]; then
    section "Configuring NVIDIA (mkinitcpio + kernel cmdline)..."
    echo 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' | \
        sudo tee /etc/mkinitcpio.conf.d/nvidia.conf >/dev/null
    sudo mkinitcpio -P

    if [[ -f /etc/default/grub ]]; then
        if ! grep -q 'nvidia-drm.modeset=1' /etc/default/grub; then
            sudo sed -i \
                's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 nvidia-drm.modeset=1"/' \
                /etc/default/grub
        fi
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    elif [[ -d /boot/loader/entries ]]; then
        for entry in /boot/loader/entries/*.conf; do
            [[ -f "${entry}" ]] || continue
            if grep -q '^options ' "${entry}" && ! grep -q 'nvidia-drm.modeset=1' "${entry}"; then
                sudo sed -i 's/^options \(.*\)/options \1 nvidia-drm.modeset=1/' "${entry}"
            fi
        done
    else
        gum style --foreground 240 "Unrecognized bootloader — add 'nvidia-drm.modeset=1' to your kernel cmdline manually."
    fi
fi

if [[ "${DO_ZRAM}" -eq 1 ]]; then
    section "Configuring zram..."
    printf '[zram0]\nzram-size = min(ram / 2, 8192)\ncompression-algorithm = zstd\n' | \
        sudo tee /etc/systemd/zram-generator.conf >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl start systemd-zram-setup@zram0.service || true
fi

[[ "${DO_ANANICY}" -eq 1 ]] && sudo systemctl enable --now ananicy-cpp.service
[[ "${DO_IRQBALANCE}" -eq 1 ]] && sudo systemctl enable --now irqbalance.service
[[ "${DO_FSTRIM}" -eq 1 ]] && sudo systemctl enable --now fstrim.timer
[[ "${DO_PPD}" -eq 1 ]] && sudo systemctl enable --now power-profiles-daemon.service
if [[ "${DO_REFLECTOR}" -eq 1 ]]; then
    section "Ranking mirrors with reflector (this can take a minute)..."
    sudo systemctl enable reflector.timer
    gum spin --spinner dot --title "Running reflector..." -- \
        sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist || true
fi

if [[ " ${GAMING_PACKAGES[*]} " == *" game-devices-udev "* ]]; then
    sudo udevadm control --reload-rules
    sudo udevadm trigger
fi

if [[ "${DO_FLATPAK}" -eq 1 ]]; then
    section "Adding the Flathub remote..."
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

if [[ " ${ESSENTIALS_PACKAGES[*]} " == *" gnome-keyring "* ]]; then
    gum style --foreground 240 "Note: gnome-keyring is installed, but auto-unlock-on-login needs a pam_gnome_keyring line in your display manager's PAM config (varies by DM) — see the ArchWiki's GNOME Keyring page if you want that wired up."
fi

title "Done!"
gum style --foreground 99 "A reboot is recommended, especially if you installed NVIDIA drivers or the linux-zen kernel."
if gum confirm "Reboot now?"; then
    sudo reboot
fi
