"""TEST-03 check_perf_gates: positive and negative fixtures per rule, plus the real tree."""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from helpers import TOOLS

import check_perf_gates as cpg

REPO = TOOLS.parent

TIMED = "func t() -> void:\n\tvar t0: int = Time.get_ticks_usec()\n"


class CheckTextTests(unittest.TestCase):
    def test_no_timing_is_ok(self) -> None:
        self.assertEqual(cpg.check_text("func t() -> void:\n\tpass\n")[0], "ok")

    def test_ungated_usec_fails_with_line(self) -> None:
        status, msg = cpg.check_text(TIMED)
        self.assertEqual(status, "fail")
        self.assertTrue(msg.startswith("2:"))

    def test_ungated_msec_fails(self) -> None:
        self.assertEqual(cpg.check_text("var a := Time.get_ticks_msec()\n")[0], "fail")

    def test_perfgate_reference_ok(self) -> None:
        self.assertEqual(cpg.check_text(TIMED + "\tassert_bool(PerfGate.check(\"a\", 1.0, 2.0, \"c\")).is_true()\n")[0], "ok")

    def test_marker_ok(self) -> None:
        self.assertEqual(cpg.check_text("extends X\n" + cpg.MARKER + "\n" + TIMED)[0], "ok")

    def test_marker_must_be_the_whole_comment_line(self) -> None:
        self.assertEqual(cpg.check_text("# note: " + cpg.MARKER + " is not\n" + TIMED)[0], "fail")

    def test_commented_call_is_ignored(self) -> None:
        self.assertEqual(cpg.check_text("# Time.get_ticks_usec()\n")[0], "ok")

    def test_perfgate_in_comment_only_does_not_count(self) -> None:
        self.assertEqual(cpg.check_text("# PerfGate later\n" + TIMED)[0], "fail")

    def test_inline_gate_is_a_notice(self) -> None:
        text = TIMED + "\tOS.get_environment('PLANEWAR_PINNED_RUNNER')\n"
        self.assertEqual(cpg.check_text(text)[0], "inline")


class ScanTests(unittest.TestCase):
    def _tree(self, files: dict[str, str]) -> Path:
        tmp = Path(tempfile.mkdtemp())
        for rel, text in files.items():
            p = tmp / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        return tmp

    def test_layers_scanned_perf_layer_not(self) -> None:
        root = self._tree({
            "godot/test/unit/a/test_bad.gd": TIMED,
            "godot/test/sim/test_bad.gd": TIMED,
            "godot/test/net/test_bad.gd": TIMED,
            "godot/test/perf/perf_ok.gd": TIMED,
            "godot/test/unit/test_good.gd": TIMED + "PerfGate.check()\n",
        })
        errors, _ = cpg.scan(root)
        self.assertEqual(len(errors), 3)
        self.assertTrue(all(e.split(":")[0].endswith("test_bad.gd") for e in errors))

    def test_main_exit_codes(self) -> None:
        bad = self._tree({"godot/test/unit/test_bad.gd": TIMED})
        good = self._tree({"godot/test/unit/test_ok.gd": "pass\n"})
        with contextlib.redirect_stderr(io.StringIO()), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(cpg.main(["--root", str(bad)]), 1)
            self.assertEqual(cpg.main(["--root", str(good)]), 0)

    def test_real_tree_is_clean(self) -> None:
        errors, _ = cpg.scan(REPO)
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
