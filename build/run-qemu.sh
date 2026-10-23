#!/usr/bin/env bash
# Boot the forge-os ISO (or an installed test disk) in QEMU with UEFI + KVM.
#
# Usage:
#   build/run-qemu.sh live      # boot the newest out/*.iso, no disk attached
#   build/run-qemu.sh install   # boot the ISO with the test disk attached, to run Calamares
#   build/run-qemu.sh disk      # boot the installed test disk only (post-install testing)
#   build/run-qemu.sh reset     # delete the test disk and its UEFI vars
#
# The test disk and UEFI variable store live in vm/ (gitignored). The vars
# file is per-VM so GRUB's boot entry written by the installer survives
# reboots, like a real machine's NVRAM.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$REPO_ROOT/vm"
DISK="$VM_DIR/forge-os-test.qcow2"
VARS="$VM_DIR/OVMF_VARS.4m.fd"
DISK_SIZE="${DISK_SIZE:-60G}"
MEM="${MEM:-8G}"
CPUS="${CPUS:-4}"

# Arch's edk2-ovmf path first, then Fedora/Debian-style fallbacks.
find_ovmf() {
    local name="$1" dir
    for dir in /usr/share/edk2/x64 /usr/share/edk2/ovmf /usr/share/OVMF; do
        for f in "$dir/$name.4m.fd" "$dir/$name.fd"; do
            [[ -f "$f" ]] && { echo "$f"; return 0; }
        done
    done
    echo "OVMF $name not found; install edk2-ovmf" >&2
    return 1
}

latest_iso() {
    local iso
    iso="$(ls -t "$REPO_ROOT"/out/*.iso 2>/dev/null | head -n1 || true)"
    [[ -n "$iso" ]] || { echo "No ISO in out/; run build/build.sh build first" >&2; return 1; }
    echo "$iso"
}

ensure_vm() {
    mkdir -p "$VM_DIR"
    [[ -f "$VARS" ]] || cp "$(find_ovmf OVMF_VARS)" "$VARS"
    [[ -f "$DISK" ]] || qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
}

cmd="${1:-}"
common=(
    -enable-kvm -machine q35 -cpu host -smp "$CPUS" -m "$MEM"
    -drive "if=pflash,format=raw,readonly=on,file=$(find_ovmf OVMF_CODE)"
    -device virtio-vga-gl -display gtk,gl=on
    -device virtio-net-pci,netdev=n0 -netdev user,id=n0
    -device qemu-xhci -device usb-tablet
    -audiodev pipewire,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0
)

case "$cmd" in
    live)
        tmpvars="$(mktemp)"; trap 'rm -f "$tmpvars"' EXIT
        cp "$(find_ovmf OVMF_VARS)" "$tmpvars"
        qemu-system-x86_64 "${common[@]}" \
            -drive "if=pflash,format=raw,file=$tmpvars" \
            -cdrom "$(latest_iso)" -boot d
        ;;
    install)
        ensure_vm
        qemu-system-x86_64 "${common[@]}" \
            -drive "if=pflash,format=raw,file=$VARS" \
            -drive "file=$DISK,if=virtio,format=qcow2,discard=unmap" \
            -cdrom "$(latest_iso)" -boot d
        ;;
    disk)
        [[ -f "$DISK" ]] || { echo "No test disk yet; run '$0 install' first" >&2; exit 1; }
        qemu-system-x86_64 "${common[@]}" \
            -drive "if=pflash,format=raw,file=$VARS" \
            -drive "file=$DISK,if=virtio,format=qcow2,discard=unmap"
        ;;
    reset)
        rm -f "$DISK" "$VARS"
        echo "Test disk and UEFI vars removed."
        ;;
    *)
        echo "Usage: $0 {live|install|disk|reset}" >&2
        exit 1
        ;;
esac
