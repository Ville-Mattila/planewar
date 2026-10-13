#!/usr/bin/env bash
# Usage: export_preset.sh <preset-name> [release|debug]
# Runs a real export of one preset from godot/export_presets.cfg and fails if the output is missing
# or the export log reports configuration errors. Run from the repository root; godot on PATH.
# Output lands where the preset's export_path says (relative to godot/, i.e. <repo>/build/<preset>/...).
set -uo pipefail
preset="$1"; mode="${2:-release}"
cfg=godot/export_presets.cfg
path="$(awk -v n="$preset" '
  /^\[preset\.[0-9]+\]$/ {insec=1; match_=0; next}
  /^\[/ {insec=0}
  insec && /^name=/ { gsub(/^name="|"$/,""); if ($0==n) match_=1 }
  insec && match_ && /^export_path=/ { gsub(/^export_path="|"$/,""); print; exit }' "$cfg")"
if [ -z "$path" ]; then echo "::error::preset $preset not found in $cfg"; exit 1; fi
# CI-only patches, never committed:
# - the project has no icon yet (config/icon unset), which the Android and iOS exporters report as an error;
# - the iOS exporter needs an App Store team id (a secret in real builds).
if ! grep -q '^config/icon=' godot/project.godot; then
  python3 .github/scripts/placeholder_icon.py godot/ci_placeholder_icon.png 1024
  sed -i '/^config\/name=/a config/icon="res://ci_placeholder_icon.png"' godot/project.godot
  godot --headless --path godot --import >/dev/null 2>&1 || true
fi
if [ "$preset" = "ios_xcode" ]; then
  sed -i 's|^application/app_store_team_id=""|application/app_store_team_id="ABCDE12345"|' "$cfg"
fi
mkdir -p "godot/$(dirname "$path")"
log="$(mktemp)"
start=$(date +%s)
godot --headless --path godot "--export-$mode" "$preset" "$path" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
end=$(date +%s)
out="$(realpath -m "godot/$path")"
grep -E "^WARNING:" "$log" | sed 's/^/::warning::/'
echo "export rc=$rc seconds=$((end-start)) output=$out"
if [ "$rc" -ne 0 ] || grep -Eq "^(SCRIPT )?ERROR:|Cannot export project|configuration errors|Failed to export|No export template" "$log"; then
  echo "::error::export of preset $preset failed"; exit 1
fi
if [ ! -s "$out" ] && [ ! -d "$out" ]; then echo "::error::missing export output $out"; exit 1; fi
ls -l "$(dirname "$out")"
