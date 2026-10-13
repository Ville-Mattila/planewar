#!/usr/bin/env bash
# Installs the gdUnit4 addon (allowed addon, CLAUDE.md; 6.2.x only) from the official GitHub release tag
# into godot/addons/gdUnit4. Run from the repository root. Not committed: CI installs it per job.
set -euo pipefail
TAG="${GDUNIT4_TAG:-v6.2.2}"
case "$TAG" in v6.2.*) ;; *) echo "gdUnit4 must be 6.2.x, got $TAG" >&2; exit 1 ;; esac
tmp="$(mktemp -d)"
curl -fsSL --retry 5 --retry-delay 5 -o "$tmp/g.tar.gz" "https://github.com/MikeSchulze/gdUnit4/archive/refs/tags/${TAG}.tar.gz"
tar -xzf "$tmp/g.tar.gz" -C "$tmp"
mkdir -p godot/addons
rm -rf godot/addons/gdUnit4
cp -r "$tmp"/gdUnit4-*/addons/gdUnit4 godot/addons/gdUnit4
chmod +x godot/addons/gdUnit4/runtest.sh 2>/dev/null || true
rm -rf "$tmp"
echo "gdUnit4 ${TAG} installed"
ls godot/addons/gdUnit4 | head -20
