#!/usr/bin/env bash
# freeze-report.sh: after a hard freeze, gather what the logs kept about it.
#
#   utils/freeze-report.sh          the previous boot (the one that froze)
#   utils/freeze-report.sh -3       another boot (journalctl -b numbering)
#   utils/freeze-report.sh --list   recent boots: clean shutdown or not
#
# Prints the report and saves it to ~/forge-freeze-<date>.txt: how the boot
# ended, its kernel and NVIDIA driver, GPU errors (Xid, fallen off the bus),
# kernel warnings, the game that was running, the journal's last lines and
# the crash logger's last readings (forge-crashlog, else templog).
#
# "Clean" means logind announced a power-off or reboot; a boot without that
# ended in a freeze, a forced power-off or a lost battery.
set -uo pipefail

clean() { # boot -> 0 if it shut down cleanly
    journalctl -b "$1" --no-pager -o cat _COMM=systemd-logind 2>/dev/null \
        | grep -qE 'System is (powering down|rebooting|halting)|The system will (power off|reboot|halt) now'
}

if [[ "${1:-}" == --list ]]; then
    journalctl --list-boots --no-pager -q | tail -n 15 | while read -r idx _ _ d1 t1 _ _ d2 t2 _; do
        if (( idx == 0 )); then state="running"
        elif clean "${idx}"; then state="clean"
        else state="FROZE / forced off"; fi
        printf '%4s  %s %s -> %s %s  %s\n' "${idx}" "${d1}" "${t1:0:5}" "${d2}" "${t2:0:5}" "${state}"
    done
    exit 0
fi

B="${1:--1}"
[[ "${B}" =~ ^-[0-9]+$ ]] || { echo "usage: $0 [-N | --list]" >&2; exit 1; }
OUT="${HOME}/forge-freeze-$(date +%F_%H%M).txt"

report() {
    local id first last
    read -r _ id _ <<<"$(journalctl --list-boots --no-pager -q | awk -v b="${B}" '$1 == b')"
    [[ -n "${id}" ]] || { echo "no boot ${B} in the journal"; return; }
    first="$(journalctl -b "${B}" --no-pager -o short-iso -q | head -n1 | cut -d' ' -f1)"
    last="$(journalctl -b "${B}" --no-pager -o short-iso -q | tail -n1 | cut -d' ' -f1)"

    echo "=== Boot ${B} (${id})"
    echo "from ${first} to ${last}"
    if clean "${B}"; then echo "ended: clean shutdown/reboot"; else echo "ended: NO shutdown — froze or was forced off"; fi
    echo "kernel: $(journalctl -b "${B}" -k --no-pager -o cat -q | grep -m1 '^Linux version' | cut -d' ' -f3)"
    echo "nvidia: $(journalctl -b "${B}" -k --no-pager -o cat -q | grep -m1 'NVRM: loading' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
    echo "cmdline: $(journalctl -b "${B}" -k --no-pager -o cat -q | grep -m1 '^Command line:' | cut -d' ' -f3-)"

    echo; echo "=== GPU errors"
    journalctl -b "${B}" -k --no-pager -o short-iso -q \
        | grep -E 'NVRM: (Xid|GPU at|.*fallen off)|nvidia-modeset: ERROR|amdgpu.*(timeout|reset|hang)|GPU (hang|reset)' \
        | tail -n 20 || true
    echo "(nothing above = no GPU error reached the disk)"

    echo; echo "=== Kernel warnings and errors (last 25, noise filtered)"
    journalctl -b "${B}" -k -p warning --no-pager -o short-iso -q \
        | grep -vE 'MLD: clamping|ACPI (BIOS )?Error|_acpiDsmCallbackInit|PlatformRequestHandler|taints kernel|^\S+ \S+ kernel: $' \
        | tail -n 25

    echo; echo "=== Games and launchers (last 8 lines)"
    journalctl -b "${B}" --no-pager -o short-iso -q \
        | grep -iE 'lutris|steam|heroic|wine|proton|gamescope|umu' | grep -v MANGOHUD | tail -n 8 | cut -c1-220

    echo; echo "=== Last 30 journal lines"
    journalctl -b "${B}" --no-pager -o short-iso -q | grep -v 'MLD: clamping' | tail -n 30 | cut -c1-220

    echo; echo "=== Last readings before the end"
    local log
    log="$(ls -t "${HOME}"/.local/state/forge-crashlog/*_"${id:0:8}".csv 2>/dev/null | head -n1)"
    if [[ -n "${log}" ]]; then
        echo "${log}"
        { head -n1 "${log}"; tail -n 15 "${log}"; } | column -t -s,
    else
        log="$(ls -t "${HOME}"/.local/state/templog/*.log 2>/dev/null \
            | while read -r f; do [[ "$(tail -n1 "${f}" | cut -d' ' -f1)" == "$(date -d "${last}" +%H:%M)"* ]] && echo "${f}"; done | head -n1)"
        [[ -n "${log}" ]] && { echo "${log}"; tail -n 15 "${log}"; } || echo "no crash logger readings for this boot"
    fi
}

report | tee "${OUT}"
echo
echo "saved: ${OUT}"
