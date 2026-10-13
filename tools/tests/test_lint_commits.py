"""REPO-06 commit-subject lint: subject rules, the real backlog, and a throwaway git range."""

from __future__ import annotations

import contextlib
import io
import subprocess
import tempfile
import unittest
from pathlib import Path

from helpers import TOOLS

import lint_commits

REPO = TOOLS.parent


def _git(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@example.invalid",
         "-c", "commit.gpgsign=false", *args],
        capture_output=True, text=True, check=True,
    )
    return proc.stdout.strip()


class SubjectRules(unittest.TestCase):
    IDS = frozenset({"TA-03", "REPO-06", "V11-01"})

    def ok(self, subject: str) -> None:
        self.assertIsNone(lint_commits.check_subject(subject, self.IDS), subject)

    def bad(self, subject: str) -> None:
        self.assertIsNotNone(lint_commits.check_subject(subject, self.IDS), subject)

    def test_task_id_subjects_pass(self) -> None:
        self.ok("TA-03: S-CI-1 CI pipeline (#10)")
        self.ok("REPO-06: PR template and commit lint")
        self.ok("V11-01: a digit in the prefix")

    def test_wave_prefix_passes(self) -> None:
        self.ok("WAVE: M0.4/M0.5 log; TA-03 done")

    def test_unknown_id_fails(self) -> None:
        self.bad("TA-99: not in the backlog")

    def test_missing_id_fails(self) -> None:
        self.bad("fix stuff")
        self.bad("Merge branch 'main' into task/x")

    def test_lowercase_id_fails(self) -> None:
        self.bad("ta-03: lower case is not an id")

    def test_empty_text_fails(self) -> None:
        self.bad("TA-03:")
        self.bad("TA-03:   ")

    def test_missing_colon_space_fails(self) -> None:
        self.bad("TA-03 no colon")
        self.bad("TA-03:no space")

    def test_real_backlog_has_known_ids(self) -> None:
        ids = lint_commits.load_ids(REPO / "docs" / "backlog" / "backlog.json")
        for task_id in ("TA-03", "TA-05", "REPO-06", "TEST-01", "V11-01"):
            self.assertIn(task_id, ids)


class GitRange(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        _git(self.repo, "init", "-q")
        self.base = self._commit("init")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _commit(self, subject: str) -> str:
        marker = self.repo / "f.txt"
        marker.write_text(subject, encoding="utf-8")
        _git(self.repo, "add", "f.txt")
        _git(self.repo, "commit", "-q", "-m", subject)
        return _git(self.repo, "rev-parse", "HEAD")

    def run_lint(self) -> tuple[int, str]:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = lint_commits.main([f"{self.base}..HEAD", "--repo", str(self.repo)])
        return code, buf.getvalue()

    def test_valid_range_exits_zero(self) -> None:
        self._commit("TA-03: first")
        self._commit("WAVE: log")
        code, out = self.run_lint()
        self.assertEqual(code, 0, out)

    def test_bad_commit_in_range_exits_one_and_names_it(self) -> None:
        self._commit("TA-03: first")
        self._commit("quick fix without id")
        code, out = self.run_lint()
        self.assertEqual(code, 1)
        self.assertIn("quick fix without id", out)

    def test_empty_range_exits_zero(self) -> None:
        code, _ = self.run_lint()
        self.assertEqual(code, 0)

    def test_bad_range_exits_two(self) -> None:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            code = lint_commits.main(["no-such-rev..HEAD", "--repo", str(self.repo)])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
