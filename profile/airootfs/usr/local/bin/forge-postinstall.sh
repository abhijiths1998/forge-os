#!/usr/bin/env bash
# Run by Calamares' shellprocess module, chrooted into the freshly
# installed target, after unpackfs has copied the live system across and
# packages.conf has removed the live-only packages. Cleans up things that
# only made sense on the live medium.
#
# Fails loudly on purpose: a nonzero exit makes Calamares report the install
# as failed. `mkinitcpio -P || true` once let it report success on a system
# with no bootable initramfs. Only genuinely optional steps get `|| true`.
set -euo pipefail

# mkarchiso moves the kernels out of the airootfs /boot and into the ISO's
# own boot directory, so the squashfs unpackfs copied has an empty /boot and
# GRUB would find nothing to boot. Every Arch kernel package also keeps a
# copy at /usr/lib/modules/<version>/vmlinuz, named by its pkgbase file.
kernels=()
for moddir in /usr/lib/modules/*/; do
    [[ -f "${moddir}pkgbase" && -f "${moddir}vmlinuz" ]] || continue
    pkgbase="$(<"${moddir}pkgbase")"
    install -Dm644 "${moddir}vmlinuz" "/boot/vmlinuz-${pkgbase}"
    kernels+=("${pkgbase}")
done
if (( ${#kernels[@]} == 0 )); then
    echo "forge-postinstall: no kernels found under /usr/lib/modules" >&2
    exit 1
fi

# The live ISO's mkinitcpio config carries archiso-only hooks (loopback
# mount, PXE, etc.) that must not ship on the installed system, and its
# linux.preset only knows the 'archiso' preset, which points at the
# archiso.conf deleted here, so replace every preset with a plain one.
# No fallback images: without autodetect each one was ~327MiB, and
# together they overflowed the ESP that /boot now lives on.
rm -f /etc/mkinitcpio.conf.d/archiso.conf
rm -f /etc/mkinitcpio.d/*.preset
for pkgbase in "${kernels[@]}"; do
    cat > "/etc/mkinitcpio.d/${pkgbase}.preset" <<EOF
# mkinitcpio preset file for the '${pkgbase}' package (written by forge-os)

ALL_kver="/boot/vmlinuz-${pkgbase}"
PRESETS=('default')

default_image="/boot/initramfs-${pkgbase}.img"
EOF
done

# Forcing the NVIDIA modules into the initramfs (nvidia.conf) and the kms
# hook (which pulls in nouveau and ~100MiB of its firmware) made every
# image ~222MiB. The NVIDIA driver loads from the root filesystem just fine;
# nvidia-drm.modeset=1 on the kernel command line still applies.
rm -f /etc/mkinitcpio.conf.d/nvidia.conf

# Calamares offers full-disk encryption and LVM, and neither initcpiocfg nor
# grubcfg is in its exec sequence, so unlock/activate the root device here.
# Without this, choosing "Encrypt system" gave an install that reported
# success and then couldn't find its root filesystem.
rootdev="$(findmnt -nvo SOURCE /)"
storage_hooks=()
crypt_name="$(lsblk -snro NAME,TYPE "${rootdev}" | awk '$2 == "crypt" && !seen++ { print $1 }')"
if [[ -n "${crypt_name}" ]]; then
    crypt_backing="$(cryptsetup status "${crypt_name}" | awk '$1 == "device:" { print $2 }')"
    crypt_uuid="$(cryptsetup luksUUID "${crypt_backing}")"
    storage_hooks+=(encrypt)
    sed -i "s|^GRUB_CMDLINE_LINUX=\"|&cryptdevice=UUID=${crypt_uuid}:${crypt_name} |" /etc/default/grub
fi
if lsblk -snro TYPE "${rootdev}" | grep -x lvm >/dev/null; then
    storage_hooks+=(lvm2)
fi

cat > /etc/mkinitcpio.conf.d/base.conf <<EOF
HOOKS=(base udev plymouth autodetect microcode modconf keyboard keymap consolefont block ${storage_hooks[*]} filesystems fsck)
EOF
plymouth-set-default-theme forge-os 2>/dev/null || true
mkinitcpio -P

# GRUB reads its background before any kernel is loaded, and it's the btrfs
# root GRUB had trouble reading, so keep the image on the ESP next to
# grub.cfg, where /etc/default/grub's GRUB_BACKGROUND expects it. Runs
# before Calamares' bootloader module calls grub-mkconfig.
install -Dm644 /usr/share/backgrounds/forge-os/wallpaper.png /boot/grub/forge-os-background.png

# --- Strip archiso's live-session plumbing ---
# unpackfs copies the live system verbatim, so everything archiso's releng
# profile set up for a throwaway live medium lands on the installed system
# too unless it's removed here.

# Root autologin on tty1 (Ctrl+Alt+F1 was an instant root shell), and
# password-based root login over SSH.
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
rm -f /etc/ssh/sshd_config.d/10-archiso.conf

# The live root account has an empty password. Calamares' users module has
# already run, so if the user set a root password it's in place; if not,
# lock the account (sudo via the wheel group still works).
if [[ -z "$(getent shadow root | cut -d: -f2)" ]]; then
    passwd -l root
fi

# Volatile journal: logs vanished on every reboot, which is why a crashing
# Plasma session left nothing behind to diagnose. And lid-close / suspend
# key handling was disabled, which on a laptop means it never sleeps.
rm -f /etc/systemd/journald.conf.d/volatile-storage.conf
rm -f /etc/systemd/logind.conf.d/do-not-suspend.conf

# Live-only services. sshd, cloud-init and the VM guest agents are enabled
# by releng for its use cases, not wanted on a desktop by default; forge-os
# uses NetworkManager, not networkd. `|| true` per unit: some may not exist.
for unit in choose-mirror.service livecd-talk.service livecd-alsa-unmuter.service \
            sshd.service \
            cloud-init-local.service cloud-init-main.service cloud-init-network.service \
            cloud-config.service cloud-final.service \
            vboxservice.service vmtoolsd.service vmware-vmblock-fuse.service \
            hv_fcopy_daemon.service hv_kvp_daemon.service hv_vss_daemon.service \
            systemd-networkd.socket systemd-networkd-wait-online.service; do
    systemctl disable "${unit}" 2>/dev/null || true
done
rm -f /etc/systemd/system/{choose-mirror,livecd-talk,livecd-alsa-unmuter}.service

# The live keyring lives on a tmpfs that pacman-init.service rebuilds every
# boot; on an installed system that silently discarded any key the user
# added. Replace it with a real on-disk keyring built once, here.
systemctl disable pacman-init.service 2>/dev/null || true
rm -f /etc/systemd/system/pacman-init.service /etc/systemd/system/etc-pacman.d-gnupg.mount
rm -rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate
# gpg-agent would otherwise keep the target busy and fail Calamares' umount.
gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true

# mkarchiso strips /var/lib/pacman/sync from the live image and unpackfs
# copies that across as-is, so without this the installed system boots with
# no repo databases: Pamac shows nothing and `pacman -S` fails until the
# user thinks to run `pacman -Sy`. Best-effort, since an offline install
# should still finish.
pacman -Sy --noconfirm || true

# NOPASSWD sudo was a live-session convenience; require a password for real.
cat > /etc/sudoers.d/g_wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
chmod 0440 /etc/sudoers.d/g_wheel

# Live-session-only autologin.
rm -f /etc/sddm.conf.d/autologin.conf

# archiso's "To install Arch Linux follow the installation guide" banner.
# pam_motd shows it on every login, SDDM included (it lands in the journal
# as an INFO_UNKNOWN auth message on every graphical login).
rm -f /etc/motd

# Best-effort snapshot setup: mount.conf already lays /.snapshots down as
# its own @snapshots subvolume (the layout ArchWiki's snapper guide
# expects); this just registers it with snapper and turns on the timers.
# `snapper create-config` can't be used: it insists on creating /.snapshots
# itself and refuses when it exists, which it always does here, and the old
# `|| true` hid that, so installs shipped with no snapper config at all.
# Writing the config directly is everything create-config does besides that.
if [[ "$(findmnt -no FSTYPE /)" == btrfs ]] && command -v snapper >/dev/null 2>&1; then
    install -Dm640 /usr/share/snapper/config-templates/default /etc/snapper/configs/root
    sed -i 's|^SUBVOLUME=.*|SUBVOLUME="/"|' /etc/snapper/configs/root
    sed -i 's|^SNAPPER_CONFIGS=.*|SNAPPER_CONFIGS="root"|' /etc/conf.d/snapper
    chmod 750 /.snapshots
    systemctl enable snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
    systemctl enable grub-btrfsd.service 2>/dev/null || true
fi
