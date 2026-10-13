#!/bin/bash
# Runs the specs in tests/ (tests/*.spec.qml) against this plugin's real QML
# and the installed Omarchy UI kit, inside a headless Quickshell. No window
# appears and nothing touches ~/.config/omarchy/shell.json.
#
# BarWidget.spec.qml in the repository root is not one of them: it is a QtTest
# case for the pure logic and runs under qmltestrunner.
#
#   tests/run.sh                        run every spec in tests/
#   tests/run.sh tests/Panel.spec.qml   run one spec; the path is relative to
#                                       the directory you run this from
#   SPEC_ONLY=Closes tests/run.sh       run only the tests whose name contains
#                                       "Closes"
set -uo pipefail

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
plugin=$(dirname "$here")
shell_src="${OMARCHY_PATH:-/usr/share/omarchy}/shell"

if [[ ! -d $shell_src/Commons || ! -d $shell_src/Ui ]]; then
  echo "Omarchy shell not found at $shell_src" >&2
  exit 2
fi
command -v qs >/dev/null || { echo "qs (Quickshell) not found" >&2; exit 2; }

# A throwaway shell config: the real Commons and Ui modules, plus the harness.
# KeyboardPanel is the one host component swapped out, because it is a
# layer-shell window and cannot map without a compositor.
work=$(mktemp -d)
cleanup() {
  rm -rf "$work"
  declare -F spec_teardown >/dev/null && spec_teardown
}
trap cleanup EXIT
cp -r "$shell_src/Commons" "$shell_src/Ui" "$work/"
cp "$here/harness/shell.qml" "$here/harness/Harness.qml" "$work/"
cp "$here/harness/KeyboardPanel.qml" "$work/Ui/KeyboardPanel.qml"

# Optional per-plugin fixtures (a local server, exported variables, ...). It
# may define spec_teardown to clean up after itself.
[[ -f $here/setup.sh ]] && source "$here/setup.sh"

if [[ $# -gt 0 ]]; then specs=("$@"); else specs=("$here"/*.spec.qml); fi

# Each spec runs once west and once east of UTC, so date math that mixes
# local and UTC time fails here rather than for a user in another timezone.
status=0
for spec in "${specs[@]}"; do
  [[ $spec == /* ]] || spec="$PWD/$spec"
  for tz in ${SPEC_TIMEZONES:-America/Los_Angeles Pacific/Auckland}; do
    echo "== $(basename "$spec") (TZ=$tz)"
    TZ=$tz PLUGIN_DIR="$plugin" SPEC_FILE="$spec" QT_QPA_PLATFORM=offscreen \
      timeout --kill-after=3 "${SPEC_TIMEOUT:-120}" qs -p "$work" 2>&1 \
      | sed -u 's/\x1b\[[0-9;]*m//g' \
      | grep --line-buffered -E "SPEC |$(basename "$plugin")/" \
      | grep --line-buffered -v "outside of the config folder" \
      | sed -u 's/^ *DEBUG qml: SPEC //'
    rc=${PIPESTATUS[0]}
    [[ $rc -eq 0 ]] || status=1
  done
done
exit $status
