import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import check_gdunit_report as g  # noqa: E402


def write(d: Path, tests: int) -> None:
    r = d / "report_1"
    r.mkdir(parents=True)
    (r / "results.xml").write_text(f'<testsuites tests="{tests}"></testsuites>')


class T(unittest.TestCase):
    def test_positive(self) -> None:
        with tempfile.TemporaryDirectory() as t:
            write(Path(t), 5)
            self.assertEqual(g.main(["x", t, "unit"]), 0)

    def test_negative_empty(self) -> None:
        with tempfile.TemporaryDirectory() as t:
            write(Path(t), 0)
            self.assertEqual(g.main(["x", t, "unit"]), 1)

    def test_negative_missing(self) -> None:
        with tempfile.TemporaryDirectory() as t:
            self.assertEqual(g.main(["x", t, "unit"]), 1)


if __name__ == "__main__":
    unittest.main()
