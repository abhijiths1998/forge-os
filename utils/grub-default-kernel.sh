#!/usr/bin/env bash
# grub-default-kernel.sh: pick which installed kernel GRUB boots by default.
#
#   utils/grub-default-kernel.sh                list kernels, mark the default
#   sudo utils/grub-default-kernel.sh lts       linux-lts first  (root)
#   sudo utils/grub-default-kernel.sh zen       linux-zen first  (root)
#   sudo utils/grub-default-kernel.sh linux     the stock kernel (root)
#
# Sets GRUB_TOP_LEVEL in /etc/default/grub (backed up once to
# /etc/default/grub.before-kernel-switch), so the kernel is the first
# menu entry and GRUB_DEFAULT=0 boots it; the others stay under Advanced
# options. Refuses a kernel that has no NVIDIA module when the machine has
# an NVIDIA GPU: that would boot to a black screen.
set -euo pipefail

CONF=/etc/default/grub

# pkgbase (linux-lts) -> module dir version (6.18.58-1-lts)
kver() {
    local d
    for d in /usr/lib/modules/*/; do
        [[ "$(cat "${d}pkgbase" 2>/dev/null)" == "$1" ]] && { basename "${d}"; return; }
    done
}

current() { sed -n 's|^GRUB_TOP_LEVEL="\{0,1\}/boot/vmlinuz-\([^"]*\)"\{0,1\}|\1|p' "${CONF}"; }

if [[ $# -eq 0 ]]; then
    def="$(current)"
    echo "running: $(uname -r)"
    for d in /usr/lib/modules/*/; do
        base="$(cat "${d}pkgbase" 2>/dev/null)" || continue
        mark=" "; [[ "${base}" == "${def}" ]] && mark="*"
        echo " ${mark} ${base#linux-} ($(basename "${d}"))"
    done
    [[ -n "${def}" ]] || echo "  (no GRUB_TOP_LEVEL: GRUB's own order decides)"
    exit 0
fi

case "$1" in
    lts|zen|hardened|rt) base="linux-$1" ;;
    linux) base=linux ;;
    *) echo "which kernel? lts, zen or linux" >&2; exit 1 ;;
esac
(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }

v="$(kver "${base}")"
[[ -n "${v}" ]] || { echo "${base} isn't installed (pacman -S ${base} ${base}-headers)" >&2; exit 1; }
if lspci -n | grep -q ' 03[0-9][0-9]: 10de:'; then
    ls /usr/lib/modules/"${v}"/{updates/dkms,extramodules,kernel/drivers/video}/nvidia.ko* >/dev/null 2>&1 \
        || { echo "no NVIDIA module for ${v}; install ${base}-headers and let DKMS build it first" >&2; exit 1; }
fi

cp -n "${CONF}" "${CONF}.before-kernel-switch"
if grep -q '^GRUB_TOP_LEVEL=' "${CONF}"; then
    sed -i "s|^GRUB_TOP_LEVEL=.*|GRUB_TOP_LEVEL=\"/boot/vmlinuz-${base}\"|" "${CONF}"
else
    echo "GRUB_TOP_LEVEL=\"/boot/vmlinuz-${base}\"" >> "${CONF}"
fi
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -v '^Found\|^Adding\|^Generating\|^done'
echo "default kernel: ${base} (${v}); reboot to use it"
grep -m1 'linux.*/vmlinuz' /boot/grub/grub.cfg | sed 's/^\s*/  /'
