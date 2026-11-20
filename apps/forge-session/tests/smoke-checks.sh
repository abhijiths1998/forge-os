#!/usr/bin/env bash
# The standard session checks (run by tests/smoke.sh inside the session).
set -u
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

check "Hyprland answers" "hyprctl version >/dev/null"
check "no config errors" "[[ -z \"\$(hyprctl configerrors | grep -v '^$')\" ]]"
# shellcheck disable=SC2034  # used inside the check strings
binds="$(hyprctl binds -j)"
check "binds carry descriptions" "jq -e 'map(select(.has_description)) | length > 90' <<<\"\${binds}\" >/dev/null"
check "every description has a category" "jq -e 'map(select(.has_description and (.description | test(\"^\\\\[[^]]+\\\\] \") | not))) | length == 0' <<<\"\${binds}\" >/dev/null"
check "tearing allowed for games" "hyprctl getoption general:allow_tearing -j | jq -e '.int == 1 or .bool == true' >/dev/null"
check "Hyprland's own wallpaper off" "hyprctl getoption misc:disable_hyprland_logo -j | jq -e '.int == 1 or .bool == true' >/dev/null"

# A window: weston-terminal stands in for an app. Tiling is off by default,
# so it must float.
weston-terminal >/dev/null 2>&1 &
sleep 2
check "new windows float (tiling off)" "hyprctl clients -j | jq -e '.[0].floating == true' >/dev/null"
grim /out/01-window.png 2>/dev/null

# Snap left through the bind's Lua function.
hyprctl eval 'forge.binds and true' >/dev/null 2>&1
hyprctl dispatch 'hl.dsp.focus({ window = "class:.*" })' >/dev/null 2>&1
hyprctl eval 'require("/usr/share/forge/hypr/lib/snap.lua").snap("left")' >/dev/null
sleep 1
half="$(hyprctl monitors -j | jq '.[0] | ((.width / .scale) - 36) / 2 | floor')"
check "Super+Left snaps to the left half" "hyprctl clients -j | jq -e --argjson half ${half} '.[0].at[0] == 12 and (.[0].size[0] - \$half | fabs) <= 1' >/dev/null"
grim /out/02-snapped.png 2>/dev/null

# Tiling on for this workspace: the window tiles.
hyprctl eval 'forge.tiling.toggle()' >/dev/null
sleep 1
check "tiling on tiles the window" "hyprctl clients -j | jq -e '.[0].floating == false' >/dev/null"
check "tiling choice saved" "jq -e '.workspaces[\"1\"] == true' ~/.local/state/forge/tiling.json >/dev/null"
hyprctl eval 'forge.tiling.toggle()' >/dev/null
sleep 1
check "tiling off floats it again" "hyprctl clients -j | jq -e '.[0].floating == true' >/dev/null"

# Resize mode: the submap switches and Escape leaves it.
hyprctl dispatch 'hl.dsp.submap("resize")' >/dev/null
check "resize mode enters" "[[ \$(hyprctl submap) == resize ]]"
hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null

# Workspaces.
hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })' >/dev/null
check "Super+3 goes to workspace 3" "hyprctl activeworkspace -j | jq -e '.id == 3' >/dev/null"

echo "${fails} failure(s)"
exit $(( fails > 0 ))
