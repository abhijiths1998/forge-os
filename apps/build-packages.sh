#!/usr/bin/env bash
# Build the Forge apps (every apps/*/PKGBUILD) and Forge's builds of other
# packages (every packages/*/PKGBUILD: Konsole with a fix) into the build
# container's local repo, so mkarchiso installs them like any other package
# (profile/pacman.conf lists that repo first).
#
# Runs inside the forge-os-builder container, as root, with the repo at
# /build (build/build.sh does this before mkarchiso). The toolchains come
# from the Containerfile. Each app is built from a copy, as an unprivileged
# user (makepkg refuses root), so the repo itself stays clean.
set -euo pipefail
shopt -s nullglob

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_REPO=/var/cache/forge-os-local-repo

pkgbuilds=("${REPO_ROOT}"/apps/*/PKGBUILD "${REPO_ROOT}"/packages/*/PKGBUILD)
if [ ${#pkgbuilds[@]} -eq 0 ]; then
    echo "==> nothing to build"
    exit 0
fi

id builder >/dev/null 2>&1 || useradd -m builder
work="$(mktemp -d)"
chown builder: "${work}"
trap 'rm -rf "${work}"' EXIT

# Shared Flutter code the apps use by relative path (path: ../forge_ui).
if [ -d "${REPO_ROOT}/apps/forge_ui" ]; then
    cp -r "${REPO_ROOT}/apps/forge_ui" "${work}/forge_ui"
    rm -rf "${work}/forge_ui/.dart_tool"
    chown -R builder: "${work}/forge_ui"
fi

# Everything built here must be in the ISO's package list too, or mkarchiso
# quietly leaves it out (forge-control once was).
missing=()
for pkgbuild in "${pkgbuilds[@]}"; do
    app="$(basename "$(dirname "${pkgbuild}")")"
    grep -qx "${app}" "${REPO_ROOT}/profile/packages.x86_64" || missing+=("${app}")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "==> not in profile/packages.x86_64: ${missing[*]}" >&2
    exit 1
fi

for pkgbuild in "${pkgbuilds[@]}"; do
    app="$(basename "$(dirname "${pkgbuild}")")"
    echo "==> building ${app}"
    cp -r "$(dirname "${pkgbuild}")" "${work}/${app}"
    rm -rf "${work}/${app}/build" "${work}/${app}/.dart_tool"
    chown -R builder: "${work}/${app}"
    # The flutter-bin SDK is owned by another uid; git (which flutter runs)
    # refuses such repos unless they're marked safe.
    su builder -c "
        set -e
        export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
        export FLUTTER_SUPPRESS_ANALYTICS=true
        cd '${work}/${app}'
        makepkg --noconfirm --nodeps --force
    "
    cp "${work}/${app}"/*.pkg.tar.zst "${LOCAL_REPO}/"
done

repo-add "${LOCAL_REPO}/forge-os-local.db.tar.gz" "${LOCAL_REPO}"/*.pkg.tar.zst
