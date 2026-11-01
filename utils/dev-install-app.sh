#!/usr/bin/env bash
# dev-install-app.sh: build a Forge app from this checkout and install it
# for the current user, to try a change without building a package or ISO.
#
#   utils/dev-install-app.sh forge-thermal
#   utils/dev-install-app.sh forge-control forge-shot   (several at once)
#
# Goes to ~/.local: the bundle in ~/.local/lib/<app>, a command in
# ~/.local/bin (the desktop file's Exec name), and the desktop files in
# ~/.local/share/applications pointing at the bundle, which win over the
# system's own. An app that was running is restarted the way its autostart
# entry starts it. Undo with: rm -r ~/.local/lib/<app> and its link and
# desktop files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
(( $# )) || { echo "which app? $(cd "${ROOT}/apps" && ls -d forge-*/ | tr -d / | tr '\n' ' ')" >&2; exit 1; }

for app in "$@"; do
    src="${ROOT}/apps/${app}"
    [[ -f "${src}/pubspec.yaml" ]] || { echo "no Flutter app at apps/${app}" >&2; exit 1; }
    bin="$(sed -n 's/^set(BINARY_NAME "\(.*\)")/\1/p' "${src}/linux/CMakeLists.txt")"
    lib="${HOME}/.local/lib/${app}"
    echo "==> ${app}"

    (cd "${src}" && flutter build linux --release --no-tree-shake-icons | tail -n1)

    running=0
    pgrep -x "${bin}" >/dev/null && running=1 && pkill -x "${bin}" || true
    rm -rf "${lib}.new"
    cp -r "${src}/build/linux/x64/release/bundle" "${lib}.new"
    rm -rf "${lib}"
    mv "${lib}.new" "${lib}"

    autostart=""
    for desktop in "${src}"/data/*.desktop; do
        [[ -f "${desktop}" ]] || continue
        name="$(basename "${desktop}")"
        cmd="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "${desktop}" | head -n1)"
        # Exec's first word becomes the bundle's binary; the arguments stay.
        sed "s|^Exec=[^ ]*|Exec=${lib}/${bin}|" "${desktop}" > "${HOME}/.local/share/applications/${name}"
        [[ "${cmd}" == /* ]] || ln -sfn "${lib}/${bin}" "${HOME}/.local/bin/${cmd##*/}"
        [[ "${name}" == *autostart* ]] && autostart="$(sed -n 's/^Exec=[^ ]* *//p' "${desktop}" | head -n1)"
    done
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true

    if (( running )); then
        # shellcheck disable=SC2086  # the autostart arguments, word-split
        setsid "${lib}/${bin}" ${autostart} >/dev/null 2>&1 < /dev/null &
        echo "    restarted"
    fi
    echo "    installed in ${lib}"
done
