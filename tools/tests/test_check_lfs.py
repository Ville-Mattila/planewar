"""LFS materialisation check (TA-17, R14): a pointer instead of a blob is reported; a blob is not."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))

import check_lfs  # noqa: E402

POINTER = (b"version https://git-lfs.github.com/spec/v1\n"
           b"oid sha256:91d39b17ff752ae0577d619534caeb2dd7b4367c11bcffaf1f37cb71db84588a\n"
           b"size 16384\n")
BLOB = bytes(range(256)) * 64


class PointerDetection(unittest.TestCase):
    def test_pointer_text_is_a_pointer(self) -> None:
        self.assertTrue(check_lfs.is_pointer(POINTER))

    def test_binary_blob_is_not_a_pointer(self) -> None:
        self.assertFalse(check_lfs.is_pointer(BLOB))

    def test_long_file_with_pointer_prefix_is_not_a_pointer(self) -> None:
        self.assertFalse(check_lfs.is_pointer(POINTER + b"x" * 2048))

    def test_find_pointers_reports_only_the_pointer(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "maps").mkdir()
            (root / "maps/face0.height.u16").write_bytes(POINTER)
            (root / "maps/face1.height.u16").write_bytes(BLOB)
            bad = check_lfs.find_pointers(root, ["maps/face0.height.u16", "maps/face1.height.u16", "maps/gone.u8"])
            self.assertEqual(bad, ["maps/face0.height.u16"])


if __name__ == "__main__":
    unittest.main()
