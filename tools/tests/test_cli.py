"""CLI behaviour: file mode, exit codes, output format, and the real repo."""

from __future__ import annotations

import io
import subprocess
import sys
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from helpers import TOOLS, RepoCase

import check_deps

REPO = TOOLS.parent


class Cli(RepoCase):
    def cli(self, *args: str) -> tuple[int, str]:
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = check_deps.main(["--root", str(self.root), *args])
        return code, buf.getvalue()

    def test_clean_exit_zero(self) -> None:
        code, out = self.cli()
        self.assertEqual((code, out), (0, ""))

    def test_violation_exit_one_and_format(self) -> None:
        self.write("godot/src/ui/a.gd", "extends Control\n")
        code, out = self.cli()
        self.assertEqual(code, 1)
        self.assertEqual(out.strip(), "godot/src/ui/a.gd:1: D7 class_name missing")

    def test_file_mode_checks_only_given_files(self) -> None:
        self.write("godot/src/ui/bad.gd", "extends Control\n")
        good = self.write("godot/src/ui/good.gd", "class_name Good\nextends Control\n")
        code, out = self.cli(str(good))
        self.assertEqual((code, out), (0, ""))
        code, out = self.cli(str(self.root / "godot/src/ui/bad.gd"))
        self.assertEqual(code, 1)
        self.assertIn("bad.gd:1: D7", out)

    def test_file_mode_ignores_unrelated_and_missing_files(self) -> None:
        other = self.write("docs/readme.md", "x")
        code, out = self.cli(str(other), str(self.root / "nope.gd"))
        self.assertEqual((code, out), (0, ""))

    def test_file_mode_still_sees_cross_file_layering(self) -> None:
        f = self.write("godot/src/sim/a.gd", "class_name A\nextends RefCounted\nvar s: ServerSession\n")
        code, out = self.cli(str(f))
        self.assertEqual(code, 1)
        self.assertIn("D1", out)

    def test_warnings_do_not_fail_unless_requested(self) -> None:
        self.write("godot/src/ui/a.gd", "class_name UiA\nextends Control\nconst R := 6000\n")
        code, out = self.cli()
        self.assertEqual(code, 0)
        self.assertIn("D6 warning:", out)
        self.assertEqual(self.cli("--quiet")[1], "")
        self.assertEqual(self.cli("--warnings-as-errors")[0], 1)

    def test_missing_deps_json_is_usage_error(self) -> None:
        (self.root / "tools/deps.json").unlink()
        self.assertEqual(self.cli()[0], 2)


class RealRepo(unittest.TestCase):
    def test_real_repo_passes_under_ten_seconds(self) -> None:
        t0 = time.monotonic()
        proc = subprocess.run([sys.executable, str(TOOLS / "check_deps.py")], capture_output=True, text=True, cwd=Path.cwd())
        elapsed = time.monotonic() - t0
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertLess(elapsed, 10.0)

    def test_deps_json_matches_b4_modules(self) -> None:
        import json

        cfg = json.loads((TOOLS / "deps.json").read_text(encoding="utf-8"))
        self.assertEqual(
            set(cfg["modules"]),
            {"core", "content", "sim", "sim_ai", "net", "server", "presentation", "camera", "input", "ui", "platform", "campaign", "app"},
        )
        self.assertEqual(cfg["d3_allowlist"], {"src/app/offline_host.gd": ["Thread"]})


if __name__ == "__main__":
    unittest.main()
