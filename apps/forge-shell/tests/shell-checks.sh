#!/usr/bin/env bash
# Runs inside Forge's session (tests/run.sh starts it through
# forge-session's smoke harness): forged and forge-shell, then the shell's
# parts one by one, with a screenshot of each in /out.
set -u
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
shot() { sleep "${2:-1}"; grim "/out/$1.png" 2>/dev/null; }
ipc() { qs -p /usr/share/forge/shell ipc call shell "$@" 2>&1; }

export XDG_STATE_HOME=${HOME}/.local/state
mkdir -p ~/.config/forge
forged serve >/out/forged.log 2>&1 &
wl-paste --type text --watch cliphist store >/dev/null 2>&1 &
qs -p /usr/share/forge/shell >/out/shell.log 2>&1 &
sleep 4

check "the shell runs" "ipc state >/dev/null"
check "no QML errors at start" "! grep -E '@[^ ]+\.qml.*(Error|Unable to assign|is not a type|is not defined|Cannot assign|unavailable)' /out/shell.log"
check "forged answers" "forged state >/dev/null"
check "Hyprland frosts the shell's surfaces" "hyprctl layers -j | jq -e '[.. | objects | select(.namespace? == \"forge-bar\")] | length > 0' >/dev/null"
shot 01-desktop

weston-terminal >/dev/null 2>&1 &
sleep 1
notify-send -a Test "Hello from Forge" "A notification with a body that wraps onto a second line, to see it."
shot 02-notification
check "notifications pop up" "ipc state >/dev/null && grep -q . <(ipc notificationCount | grep -v '^0$')"

ipc control >/dev/null; shot 03-control
ipc control >/dev/null
ipc cheatsheet >/dev/null; shot 04-cheatsheet
check "cheat sheet opens" "[[ \$(ipc state) == cheatsheet ]]"
ipc cheatsheet >/dev/null
ipc notifications >/dev/null; shot 05-notification-centre
ipc notifications >/dev/null
ipc whichkey >/dev/null; shot 06-whichkey
ipc whichkey >/dev/null
ipc emoji >/dev/null; shot 07-emoji 2
ipc close >/dev/null
echo copied text | wl-copy; sleep 0.5
ipc clipboard >/dev/null; shot 08-clipboard
check "clipboard history lists what was copied" "cliphist list | grep -q 'copied text'"
ipc close >/dev/null
ipc power >/dev/null; shot 09-power
ipc close >/dev/null
ipc overview >/dev/null; shot 10-overview 2
ipc close >/dev/null
hyprctl dispatch 'hl.dsp.submap("resize")' >/dev/null; shot 11-resize-badge
hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null

ipc dismissPopups >/dev/null
forged set dnd on >/dev/null; sleep 1
notify-send -a Test "Quiet" "Should not pop up"; shot 12-dnd
check "do not disturb holds pop-ups back" "[[ \$(ipc popupCount) == 0 ]]"
forged set dnd off >/dev/null

# Hyprland's binds reach the shell as global shortcuts.
hyprctl dispatch 'hl.dsp.global("forge:control")' >/dev/null; sleep 0.5
check "a global shortcut opens the Control Center" "[[ \$(ipc state) == control ]]"
hyprctl dispatch 'hl.dsp.global("forge:control")' >/dev/null; sleep 0.3

# The switcher: two windows, Alt+Tab, let go: the other one is focused.
weston-terminal >/dev/null 2>&1 & sleep 1.5
before="$(hyprctl activewindow -j | jq -r .address)"
hyprctl dispatch 'hl.dsp.global("forge:switcherNext")' >/dev/null; sleep 0.6
shot 13-switcher 0.2
hyprctl dispatch 'hl.dsp.global("forge:switcherCommit")' >/dev/null; sleep 0.6
after="$(hyprctl activewindow -j | jq -r .address)"
check "Alt+Tab switches to the other window" "[[ -n '${before}' && '${before}' != '${after}' ]]"

check "no QML errors after use" "! grep -E '@[^ ]+\.qml.*(Error|Unable to assign|is not a type|is not defined|Cannot assign|unavailable)' /out/shell.log"
echo "${fails} failure(s)"
exit $(( fails > 0 ))
