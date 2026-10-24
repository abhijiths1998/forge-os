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
#
# FORGE_WORK_DIR and FORGE_OUT_DIR put mkarchiso's work directory and the ISO
# somewhere other than work/ and out/ in the repo (CI uses a bigger disk).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="forge-os-builder"
PKGCACHE_VOLUME="forge-os-pkgcache"
WORK_DIR="${FORGE_WORK_DIR:-$REPO_ROOT/work}"
OUT_DIR="${FORGE_OUT_DIR:-$REPO_ROOT/out}"

build_image() {
    # Arch's current kwin version: a change re-runs the Containerfile step
    # that builds kwin-effects-glass, which must match KWin exactly.
    local kwin_version
    kwin_version="$(curl -fsSL https://archlinux.org/packages/extra/x86_64/kwin/json/ \
        | python3 -c 'import json, sys; d = json.load(sys.stdin); print("%s:%s-%s" % (d["epoch"], d["pkgver"], d["pkgrel"]))' \
        || echo unknown)"
    docker build -t "$IMAGE_NAME" --build-arg KWIN_VERSION="$kwin_version" \
        -f "$REPO_ROOT/build/Containerfile" "$REPO_ROOT/build"
}

fix_ownership() {
    # Container runs as root, so anything it writes into the bind-mounted
    # repo (out/, work/, or profile/ during init) ends up root-owned on the
    # host. Hand it back to the calling user.
    local dirs=(-v "$REPO_ROOT:/build")
    [ -d "$WORK_DIR" ] && dirs+=(-v "$WORK_DIR:/work")
    [ -d "$OUT_DIR" ] && dirs+=(-v "$OUT_DIR:/out")
    docker run --rm "${dirs[@]}" \
        "$IMAGE_NAME" \
        bash -c "chown -R $(id -u):$(id -g) /build \$(ls -d /work /out 2>/dev/null)"
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
        mkdir -p "$OUT_DIR" "$WORK_DIR"
        # The Forge apps (apps/) are built into the local repo first, in the
        # same container run, so mkarchiso finds them there.
        # Named volume for pacman's package cache: each `docker run --rm` is
        # a fresh container, so without this every retry re-downloads the
        # entire (large: KDE + gaming stack) package set from scratch.
        docker run --rm --privileged \
            -v "$REPO_ROOT:/build" \
            -v "$WORK_DIR:/work" \
            -v "$OUT_DIR:/out" \
            -v "$PKGCACHE_VOLUME:/var/cache/pacman/pkg" \
            -w /build \
            "$IMAGE_NAME" \
            bash -c "/build/apps/build-packages.sh \
                && mkarchiso -v -w /work -o /out /build/profile"
        fix_ownership
        echo "ISO written to $OUT_DIR"
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
