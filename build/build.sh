#!/usr/bin/env bash
# Build environment wrapper for forge-os.
#
# archiso's mkarchiso only runs on Arch Linux and needs root + loopback/mount
# access, so it runs inside a privileged Arch container rather than natively
# on this (Fedora/Nobara) host.
#
# Usage:
#   build/build.sh init    # one-time: seed profile/ from upstream releng skeleton
#   build/build.sh build   # produce the ISO into out/
#   build/build.sh shell   # drop into an interactive shell in the build container

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="forge-os-builder"
PKGCACHE_VOLUME="forge-os-pkgcache"

build_image() {
    docker build -t "$IMAGE_NAME" -f "$REPO_ROOT/build/Containerfile" "$REPO_ROOT/build"
}

fix_ownership() {
    # Container runs as root, so anything it writes into the bind-mounted
    # repo (out/, work/, or profile/ during init) ends up root-owned on the
    # host. Hand it back to the calling user.
    docker run --rm \
        -v "$REPO_ROOT:/build" \
        "$IMAGE_NAME" \
        chown -R "$(id -u)":"$(id -g)" /build
}

cmd="${1:-}"

case "$cmd" in
    init)
        build_image
        if [ -f "$REPO_ROOT/profile/profiledef.sh" ]; then
            echo "profile/ already initialized, skipping (delete profile/profiledef.sh to re-seed)."
            exit 0
        fi
        docker run --rm \
            -v "$REPO_ROOT:/build" \
            "$IMAGE_NAME" \
            bash -c "cp -r /usr/share/archiso/configs/releng/. /build/profile/"
        fix_ownership
        echo "Seeded profile/ from upstream releng. Now customize it (see docs/ROADMAP.md) and run 'build/build.sh build'."
        ;;
    build)
        build_image
        mkdir -p "$REPO_ROOT/out" "$REPO_ROOT/work"
        # Named volume for pacman's package cache: each `docker run --rm` is
        # a fresh container, so without this every retry re-downloads the
        # entire (large: KDE + gaming stack) package set from scratch.
        docker run --rm --privileged \
            -v "$REPO_ROOT:/build" \
            -v "$PKGCACHE_VOLUME:/var/cache/pacman/pkg" \
            -w /build \
            "$IMAGE_NAME" \
            mkarchiso -v -w /build/work -o /build/out /build/profile
        fix_ownership
        echo "ISO written to out/"
        ;;
    shell)
        build_image
        docker run --rm -it --privileged \
            -v "$REPO_ROOT:/build" \
            -v "$PKGCACHE_VOLUME:/var/cache/pacman/pkg" \
            -w /build \
            "$IMAGE_NAME" \
            bash
        ;;
    *)
        echo "Usage: $0 {init|build|shell}" >&2
        exit 1
        ;;
esac
