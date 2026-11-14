#!/usr/bin/env bash
# tests/run.sh: forge-shell in Forge's real Hyprland session (forge-session's
# smoke harness: Hyprland 0.57 nested on this desktop), with forged; the
# checks and screenshots are tests/shell-checks.sh.
#   OUT=/tmp/shots apps/forge-shell/tests/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "${here}/../.." && pwd)"
export SMOKE_ARGS="-v ${here}/shell:/usr/share/forge/shell:ro \
-v ${here}/bin/forge-shell:/usr/local/bin/forge-shell:ro \
-v ${repo}/profile/airootfs/usr/local/bin/forged:/usr/local/bin/forged:ro \
-v ${repo}/profile/airootfs/usr/share/fonts/plus-jakarta-sans:/usr/share/fonts/plus-jakarta-sans:ro \
-v ${here}/tests/shell-checks.sh:/tests-shell/shell-checks.sh:ro"
exec "${repo}/apps/forge-session/tests/smoke.sh" /tests-shell/shell-checks.sh
