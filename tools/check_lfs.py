"""LFS materialisation check (TA-17, docs/03 R14 and s8.6).

Every tracked file whose `.gitattributes` filter is `lfs` must hold its blob, not a Git LFS pointer (a checkout without
`git lfs pull`, or with LFS disabled, leaves ~130-byte text pointers that would desync maps and textures silently).
Usage: python tools/check_lfs.py [--root DIR]   Exit 0 all materialised, 1 pointers found, 2 git error.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

POINTER_PREFIX = b"version https://git-lfs.github.com/spec/v1\n"
MAX_POINTER_BYTES = 1024  # real pointers are ~130 bytes; a blob that starts with the prefix is still a pointer


def is_pointer(data: bytes) -> bool:
    return data.startswith(POINTER_PREFIX) and len(data) <= MAX_POINTER_BYTES


def find_pointers(root: Path, rel_paths: list[str]) -> list[str]:
    """The subset of rel_paths (relative to root) that are missing-blob LFS pointers; missing files are skipped."""
    bad = []
    for rel in rel_paths:
        path = root / rel
        if path.is_file() and is_pointer(path.read_bytes()):
            bad.append(rel)
    return bad


def lfs_tracked(root: Path) -> list[str]:
    """Tracked files whose filter attribute is `lfs` (git ls-files plus git check-attr)."""
    listed = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=True).stdout
    names = [n.decode("utf-8") for n in listed.split(b"\0") if n]
    if not names:
        return []
    attrs = subprocess.run(
        ["git", "-C", str(root), "check-attr", "-z", "filter", "--stdin"],
        input=b"\0".join(n.encode("utf-8") for n in names) + b"\0", capture_output=True, check=True).stdout
    fields = attrs.split(b"\0")
    out = []
    for i in range(0, len(fields) - 2, 3):
        if fields[i + 2] == b"lfs":
            out.append(fields[i].decode("utf-8"))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=".", help="repository root (default: current directory)")
    a = ap.parse_args(argv)
    root = Path(a.root).resolve()
    try:
        tracked = lfs_tracked(root)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"check_lfs: git failed: {exc}", file=sys.stderr)
        return 2
    bad = find_pointers(root, tracked)
    for rel in bad:
        print(f"{rel}: Git LFS pointer, not the blob (run git lfs pull)", file=sys.stderr)
    print(f"check_lfs: {len(tracked) - len(bad)}/{len(tracked)} LFS files materialised")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
