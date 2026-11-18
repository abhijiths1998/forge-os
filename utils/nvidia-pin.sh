#!/usr/bin/env bash
# nvidia-pin.sh: hold the NVIDIA driver at its installed version, so
# `pacman -Syu` doesn't bring back one that freezes games.
#
#   utils/nvidia-pin.sh             status: installed versions, pinned or not
#   sudo utils/nvidia-pin.sh pin    add the driver packages to IgnorePkg
#   sudo utils/nvidia-pin.sh unpin  take them out again (to update the driver)
#
# Only the driver's own packages are touched; anything else in IgnorePkg
# stays. The kernel module, the userspace and its 32-bit half must always
# match, so they're pinned and unpinned together.
set -euo pipefail

CONF=/etc/pacman.conf
PKGS=(nvidia-open-dkms nvidia-dkms nvidia-open nvidia nvidia-utils lib32-nvidia-utils opencl-nvidia nvidia-settings)

# "name version" of each installed driver package. pacman -Q also answers
# for what a package provides (nvidia -> nvidia-open-dkms), hence the -u.
installed() {
    local p
    for p in "${PKGS[@]}"; do pacman -Q "${p}" 2>/dev/null || true; done | sort -u
}
ignored() { sed -n 's/^[[:space:]]*IgnorePkg[[:space:]]*=//p' "${CONF}" | tr ' ' '\n' | sed '/^$/d'; }

set_ignored() { # the full IgnorePkg list, one per line on stdin
    local list
    list="$(sort -u | tr '\n' ' ' | sed 's/ $//')"
    cp -n "${CONF}" "${CONF}.before-nvidia-pin"
    sed -i '/^[[:space:]]*IgnorePkg[[:space:]]*=/d' "${CONF}"
    [[ -n "${list}" ]] || return 0
    # Under [options], where pacman reads it.
    sed -i "/^\[options\]/a IgnorePkg = ${list}" "${CONF}"
}

case "${1:-status}" in
    status)
        echo "installed:"; installed | sed 's/^/  /'
        pinned=0
        while read -r name _; do
            if ignored | grep -qx "${name}"; then pinned=$((pinned + 1)); else echo "  not pinned: ${name}"; fi
        done < <(installed)
        (( pinned > 0 )) && echo "pinned: ${pinned} package(s) held by IgnorePkg" || echo "pinned: no"
        ;;
    pin)
        (( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }
        { ignored; installed | cut -d' ' -f1; } | set_ignored
        echo "pinned: $(installed | cut -d' ' -f1 | tr '\n' ' ')"
        ;;
    unpin)
        (( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }
        ignored | grep -vxF -f <(printf '%s\n' "${PKGS[@]}") | set_ignored || true
        echo "unpinned; the next pacman -Syu updates the driver"
        ;;
    *) echo "usage: $0 [status | pin | unpin]" >&2; exit 1 ;;
esac
