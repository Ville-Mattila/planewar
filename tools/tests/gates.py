"""Environment gates for the tools tests (TA-17).

A gate turns a missing prerequisite into a skip with a message on a developer machine and into a failure on CI. CI is
recognised by the `CI` environment variable (GitHub Actions sets it). CI checks out with LFS materialised and installs
numpy, so nothing may be skipped there: a skip would hide a broken checkout or a missing dependency.

Prerequisites covered:
- numpy (the moon baker): `python -I` ignores the user site-packages, so numpy can be invisible locally.
- Git LFS blobs: a fresh worktree may hold ~130-byte pointer files instead of the blobs (`git lfs pull` fixes it).
  Detection is tools/check_lfs.py's `is_pointer`, so the rule is the same in both places.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import check_lfs  # noqa: E402

NUMPY_SKIP = ("numpy or moonbake not importable on this machine: run without `python -I` (it ignores the user "
              "site-packages) or `python -m pip install -r tools/requirements.txt`")


def on_ci() -> bool:
    """True on GitHub Actions (and any runner that sets CI=1/true/yes)."""
    return os.environ.get("CI", "").strip().lower() in {"1", "true", "yes"}


def gate(reason: str) -> None:
    """Call from a test or setUp when a prerequisite is missing: skip locally, fail on CI."""
    if on_ci():
        raise AssertionError(f"CI must not skip: {reason}")
    raise unittest.SkipTest(reason)


def numpy_import_failed(exc: ImportError) -> None:
    """Call from an `except ImportError` around the numpy import: re-raise on CI, return locally."""
    if on_ci():
        raise exc


def pointer_files(path: Path) -> list[Path]:
    """Files at `path` (or under it) that are still Git LFS pointers. A missing path has none."""
    if path.is_file():
        files = [path]
    elif path.is_dir():
        files = sorted(p for p in path.rglob("*") if p.is_file())
    else:
        return []
    return [p for p in files if check_lfs.is_pointer(p.read_bytes())]


def require_blobs(*paths: Path) -> None:
    """Skip locally (fail on CI) when any file under `paths` is a Git LFS pointer instead of its blob."""
    bad = [p for path in paths for p in pointer_files(path)]
    if bad:
        shown = ", ".join(str(p) for p in bad[:3]) + (" ..." if len(bad) > 3 else "")
        gate(f"{len(bad)} Git LFS pointer file(s), not the blob ({shown}); run `git lfs pull` in this checkout")
