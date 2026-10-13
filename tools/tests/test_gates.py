"""Gates (TA-17): a missing prerequisite skips locally and fails on CI; a present one passes silently."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from typing import ContextManager
from unittest import mock

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))

import gates  # noqa: E402

POINTER = (b"version https://git-lfs.github.com/spec/v1\n"
           b"oid sha256:91d39b17ff752ae0577d619534caeb2dd7b4367c11bcffaf1f37cb71db84588a\n"
           b"size 16384\n")
BLOB = bytes(range(256)) * 64


def _env(ci: str | None) -> ContextManager[object]:
    """An environment with CI set to `ci`, or without CI at all when `ci` is None."""
    base = {k: v for k, v in os.environ.items() if k != "CI"}
    if ci is not None:
        base["CI"] = ci
    return mock.patch.dict(os.environ, base, clear=True)


class CiDetection(unittest.TestCase):
    def test_unset_is_not_ci(self) -> None:
        with _env(None):
            self.assertFalse(gates.on_ci())

    def test_github_actions_value_is_ci(self) -> None:
        with _env("true"):
            self.assertTrue(gates.on_ci())

    def test_other_values_are_not_ci(self) -> None:
        with _env("0"):
            self.assertFalse(gates.on_ci())


class GateBehaviour(unittest.TestCase):
    def test_gate_skips_locally(self) -> None:
        with _env(None), self.assertRaises(unittest.SkipTest) as cm:
            gates.gate("missing thing")
        self.assertIn("missing thing", str(cm.exception))

    def test_gate_fails_on_ci(self) -> None:
        with _env("true"), self.assertRaises(AssertionError) as cm:
            gates.gate("missing thing")
        self.assertIn("CI must not skip", str(cm.exception))

    def test_numpy_import_failure_is_swallowed_locally(self) -> None:
        with _env(None):
            gates.numpy_import_failed(ImportError("no numpy"))  # must return

    def test_numpy_import_failure_is_reraised_on_ci(self) -> None:
        exc = ImportError("no numpy")
        with _env("true"), self.assertRaises(ImportError) as cm:
            gates.numpy_import_failed(exc)
        self.assertIs(cm.exception, exc)


class LfsPointerGate(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def test_pointer_file_skips_locally(self) -> None:
        (self.root / "face0.u8").write_bytes(POINTER)
        with _env(None), self.assertRaises(unittest.SkipTest) as cm:
            gates.require_blobs(self.root)
        self.assertIn("git lfs pull", str(cm.exception))

    def test_pointer_file_fails_on_ci(self) -> None:
        (self.root / "face0.u8").write_bytes(POINTER)
        with _env("true"), self.assertRaises(AssertionError):
            gates.require_blobs(self.root)

    def test_pointer_in_subdirectory_is_found(self) -> None:
        (self.root / "maps").mkdir()
        (self.root / "maps" / "face0.u8").write_bytes(POINTER)
        self.assertEqual(gates.pointer_files(self.root), [self.root / "maps" / "face0.u8"])

    def test_real_blobs_pass_silently(self) -> None:
        (self.root / "face0.u8").write_bytes(BLOB)
        (self.root / "meta.json").write_text('{"ok": true}\n', encoding="utf-8")
        with _env("true"):
            gates.require_blobs(self.root)  # no raise on CI
        with _env(None):
            gates.require_blobs(self.root)  # no raise locally either

    def test_missing_path_is_not_a_pointer(self) -> None:
        self.assertEqual(gates.pointer_files(self.root / "absent"), [])
        with _env("true"):
            gates.require_blobs(self.root / "absent")  # the test itself reports a missing file


if __name__ == "__main__":
    unittest.main()
