#!/usr/bin/env bash
# tests/smoke.sh [script]: start Forge's Hyprland session in the
# forge-os-check container, as a window on this desktop (Wayland only), (build/check.sh builds it) and run checks
# against it. With no script, runs tests/smoke-checks.sh.
#   apps/forge-session/tests/smoke.sh                 the standard checks
#   OUT=/tmp/shots apps/forge-session/tests/smoke.sh  keep the screenshots
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${OUT:-$(mktemp -d)}"
mkdir -p "${out}"
script="${1:-tests/smoke-checks.sh}"
case "${script}" in /*) ;; *) script="/${script}" ;; esac
# Hyprland needs a GPU even headless: pass the render nodes (and NVIDIA's
# device files on an NVIDIA machine; the check image carries the matching
# userspace).
devices=()
for d in /dev/dri/renderD* /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset; do
    [[ -e "${d}" ]] && devices+=(--device "${d}")
done
# Extra mounts and environment for other components' tests (forge-shell's
# tests add the shell and forged), e.g. SMOKE_ARGS="-v /x:/y".
read -r -a extra <<<"${SMOKE_ARGS:-}"
docker run --rm "${devices[@]}" "${extra[@]}" \
    -v "${here}/hypr:/usr/share/forge/hypr:ro" \
    -v "${here}/skel:/skel:ro" \
    -v "${here}/bin:/forgebin:ro" \
    -v "${here}/tests:/tests:ro" \
    -v "${out}:/out" \
    -v "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY:-wayland-0}:/run/t/host" \
    forge-os-check bash -c "
        useradd -m -u $(id -u) t >/dev/null
        mkdir -p /home/t/.config/hypr && cp /skel/*.lua /home/t/.config/hypr/ && chown -R t /home/t
        chown t /run/t
        su t -c 'dbus-run-session -- bash /tests/smoke-inside.sh bash ${script}'
    "
echo "screenshots and logs: ${out}"
