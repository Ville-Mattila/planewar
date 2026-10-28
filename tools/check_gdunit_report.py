#!/usr/bin/env python3
"""TA-67 guard: a gdUnit4 layer report must exist and contain > 0 test cases.

usage: check_gdunit_report.py <reports/layer dir> <layer name>
Exit 0 ok, 1 missing/empty report. Prevents a layer being silently skipped.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def count_tests(report_dir: Path) -> int:
    files = sorted(report_dir.glob("report_*/results.xml"))
    if not files:
        return -1
    return int(ET.parse(files[-1]).getroot().get("tests", "0"))


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: check_gdunit_report.py <dir> <layer>", file=sys.stderr)
        return 2
    n = count_tests(Path(argv[1]))
    if n <= 0:
        why = "no results.xml" if n < 0 else "0 test cases"
        print(f"::error::gdUnit4 layer '{argv[2]}': {why} under {argv[1]}", file=sys.stderr)
        return 1
    print(f"gdUnit4 layer '{argv[2]}': {n} test cases reported")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
