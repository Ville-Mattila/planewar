#!/usr/bin/env bash
# Run gdUnit4 locally with no Godot window, the way CI does (.github/scripts/gdunit_shard.sh).
# runtest.sh starts a windowed Godot unless GODOT_BIN adds --headless; this wraps GODOT_BIN for one run.
# usage (from the repo root or anywhere): tools/gdunit_headless.sh -a res://test/unit [-c] [-rd reports]
set -euo pipefail
: "${GODOT_BIN:?set GODOT_BIN to the Godot 4.7.2 console binary}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '#!/usr/bin/env bash\nexec "%s" --headless "$@"\n' "$GODOT_BIN" > "$tmp/godot-headless"
chmod +x "$tmp/godot-headless"
cd "$(dirname "${BASH_SOURCE[0]}")/../godot"
GODOT_BIN="$tmp/godot-headless" ./addons/gdUnit4/runtest.sh "$@" --ignoreHeadlessMode
