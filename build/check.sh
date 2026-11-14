#!/usr/bin/env bash
# build/check.sh: the checks every change must pass, run in the
# forge-os-check container (build/Check.Containerfile) so any distro works.
#   build/check.sh            everything below
#   build/check.sh shell      shellcheck
#   build/check.sh python     ruff, and the Python tests (tests/)
#   build/check.sh lua        Forge's Hyprland config: binds, then Hyprland's own --verify-config
#   build/check.sh qml        qmllint on forge-shell
#   build/check.sh image      (re)build the container image
# Dart is checked with `flutter analyze` in each app (needs Flutter on the host).
set -euo pipefail
cd "$(dirname "$0")/.."
IMAGE=forge-os-check

image() { docker build -q -t "${IMAGE}" -f build/Check.Containerfile build >/dev/null; }
docker image inspect "${IMAGE}" >/dev/null 2>&1 || image

run() { docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "${PWD}:/src:ro" -w /src "${IMAGE}" bash -c "$1"; }

# Shell scripts: by shebang, wherever they live.
shell_files() {
    git ls-files -co --exclude-standard | while read -r f; do
        [[ -f "${f}" ]] || continue
        case "${f}" in *.sh) echo "${f}"; continue ;; esac
        head -c 40 "${f}" 2>/dev/null | grep -qE '^#!.*(ba)?sh' && echo "${f}"
    done
}
python_files() {
    git ls-files -co --exclude-standard | while read -r f; do
        [[ -f "${f}" ]] || continue
        case "${f}" in *.py) echo "${f}"; continue ;; esac
        head -c 40 "${f}" 2>/dev/null | grep -q '^#!.*python' && echo "${f}"
    done
}

check_shell() {
    echo "==> shellcheck"
    mapfile -t files < <(shell_files)
    run "shellcheck -x -S warning $(printf '%q ' "${files[@]}")"
}
check_python() {
    echo "==> ruff"
    mapfile -t files < <(python_files)
    run "ruff check --quiet --no-cache $(printf '%q ' "${files[@]}")"
    if [[ -d tests ]]; then
        echo "==> python tests"
        run "PYTHONDONTWRITEBYTECODE=1 python -m pytest -q -p no:cacheprovider tests"
    fi
}
check_lua() {
    echo "==> forge-session binds"
    run "cd apps/forge-session && lua tests/check-binds.lua hypr"
    echo "==> Hyprland --verify-config"
    docker run --rm -v "${PWD}/apps/forge-session/hypr:/usr/share/forge/hypr:ro" \
        -v "${PWD}/apps/forge-session/skel:/skel:ro" "${IMAGE}" bash -c '
        useradd -m t; mkdir -p /home/t/.config/hypr; cp /skel/*.lua /home/t/.config/hypr/; chown -R t /home/t
        su t -c "XDG_RUNTIME_DIR=/tmp Hyprland --verify-config -c /home/t/.config/hypr/hyprland.lua 2>&1" \
            | sed -n "/Config parsing result/,\$p" | tee /tmp/r; grep -q "config ok" /tmp/r'
}
check_qml() {
    [[ -d apps/forge-shell/shell ]] || return 0
    echo "==> qmllint"
    run "cd apps/forge-shell/shell && find . -name '*.qml' -print0 | xargs -0 /usr/lib/qt6/bin/qmllint -I . --unqualified disable --import disable"
}

case "${1:-all}" in
    shell) check_shell ;;
    python) check_python ;;
    lua) check_lua ;;
    qml) check_qml ;;
    image) image ;;
    all) check_shell; check_python; check_lua; check_qml; echo "==> all checks passed" ;;
    *) sed -n '2,12p' "$0"; exit 2 ;;
esac
