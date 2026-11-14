# Tools to check Forge OS without an Arch host: linters (shellcheck, ruff,
# qmllint), Hyprland and Quickshell (config checks, headless runs), Neovim,
# and QEMU for ISO tests. Used by build/check.sh.
FROM archlinux:latest
RUN pacman -Syu --noconfirm --needed \
        shellcheck ruff python python-dbus python-gobject python-pytest \
        hyprland hypridle hyprlock quickshell qt6-declarative qt6-tools \
        neovim lua luajit git base-devel \
        qemu-full edk2-ovmf socat jq imagemagick librsvg \
        weston sway foot grim wayland-utils mesa \
    && pacman -Scc --noconfirm

# NVIDIA's userspace at the version the ISO pins, for headless Hyprland
# runs on a machine whose only GPU is NVIDIA (tests pass /dev/dri and
# /dev/nvidia* through; the kernel module is the host's, so these must
# match it).
ARG NVIDIA_VERSION=610.57.04-1
RUN cd /tmp \
    && curl -fsSLO "https://archive.archlinux.org/packages/n/nvidia-utils/nvidia-utils-${NVIDIA_VERSION}-x86_64.pkg.tar.zst" \
    && pacman -Sy --noconfirm --needed egl-gbm egl-wayland \
    && pacman -U --noconfirm "nvidia-utils-${NVIDIA_VERSION}-x86_64.pkg.tar.zst" \
    && rm -f /tmp/*.pkg.tar.zst && pacman -Scc --noconfirm
