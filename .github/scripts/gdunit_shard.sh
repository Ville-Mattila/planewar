#!/usr/bin/env bash
# TA-68: run one gdUnit4 shard and apply the TA-67 guard (> 0 test cases reported).
# usage: gdunit_shard.sh <layer: unit|sim|net> <shard: all|<subdir>|rest> <report-name>
#   all     every test under test/<layer>
#   <dir>   only test/<layer>/<dir>
#   rest    everything under test/<layer> EXCEPT the dirs named in SHARD_DIRS (default "sim"), so a new
#           subdirectory is always covered by exactly one shard.
# Runs from the repo root; requires GODOT_BIN (setup-godot), RUNNER_TEMP and the gdUnit4 addon.
set -euo pipefail
layer="$1"; shard="$2"; name="$3"
SHARD_DIRS="${SHARD_DIRS:-sim}"
root="$PWD"
# runtest.sh starts a windowed Godot unless GODOT_BIN adds --headless.
{
  echo '#!/usr/bin/env bash'
  echo "exec $GODOT_BIN --headless \"\$@\""
} > "$RUNNER_TEMP/godot-headless"
chmod +x "$RUNNER_TEMP/godot-headless"
export GODOT_BIN="$RUNNER_TEMP/godot-headless"
cd godot
args=()
case "$shard" in
  all) args=(-a "res://test/$layer") ;;
  rest)
    for p in "test/$layer"/*; do
      b="$(basename "$p")"
      skip=0
      for s in $SHARD_DIRS; do
        if [ "$b" = "$s" ]; then skip=1; fi
      done
      if [ "$skip" = 1 ]; then continue; fi
      if [ -d "$p" ]; then
        # No pipes: under pipefail `find | grep -q` SIGPIPEs and skips (TA-67).
        if [ -z "$(find "$p" -name 'test_*.gd' -print -quit)" ]; then continue; fi
      else
        case "$b" in test_*.gd) ;; *) continue ;; esac
      fi
      args+=(-a "res://$p")
    done ;;
  *) args=(-a "res://test/$layer/$shard") ;;
esac
if [ "${#args[@]}" -eq 0 ]; then
  echo "::error::gdUnit4 shard '$name' selects no tests; a shard must exist"
  exit 1
fi
echo "gdUnit4 shard $name: ${args[*]}"
./addons/gdUnit4/runtest.sh "${args[@]}" -c --ignoreHeadlessMode -rd "reports/$name"
python3 "$root/tools/check_gdunit_report.py" "reports/$name" "$name"
