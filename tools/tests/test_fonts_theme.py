"""tools/art/subset_font.py and tools/art/build_theme.py (ART-21, docs/07 s7)."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS / "art"))

import build_theme as T  # noqa: E402
import subset_font as S  # noqa: E402

FONTS = REPO / "godot" / "assets" / "ui" / "fonts"
BUDGET = 150 * 1024
FINNISH = "åäöÅÄÖ"


class FontSubsetTest(unittest.TestCase):
    def fonts(self) -> list[Path]:
        return sorted(FONTS.glob("*.subset.ttf"))

    def test_two_families_present_with_licences(self) -> None:
        self.assertEqual(len(self.fonts()), 2)
        for name in ("OFL-Inter.txt", "OFL-Rajdhani.txt"):
            self.assertIn("SIL OPEN FONT LICENSE Version 1.1", (FONTS / name).read_text(encoding="utf-8"))

    def test_payload_within_budget(self) -> None:
        self.assertLessEqual(sum(f.stat().st_size for f in self.fonts()), BUDGET)

    def test_finnish_and_ascii_covered(self) -> None:
        for f in self.fonts():
            cov = S.coverage(f.read_bytes())
            for ch in FINNISH + "AZaz09€–":
                self.assertIn(ord(ch), cov, f"{f.name} lacks {ch!r}")

    def test_charset_matches_font(self) -> None:
        spec = json.loads((REPO / "godot" / "content" / "ui" / "font_charset.json").read_text(encoding="utf-8"))
        want = set(S.charset_codepoints(spec))
        for f in self.fonts():
            cov = S.coverage(f.read_bytes())
            self.assertLessEqual(cov, want)
            self.assertGreater(len(cov), 300)

    def test_outline_data_valid(self) -> None:
        for f in self.fonts():
            t = S.read_tables(f.read_bytes())
            num = int.from_bytes(t["maxp"][4:6], "big")
            self.assertEqual(len(t["loca"]), 4 * (num + 1))
            self.assertEqual(int.from_bytes(t["loca"][-4:], "big"), len(t["glyf"]))

    def test_inter_digits_are_tabular(self) -> None:
        data = (FONTS / "Inter.subset.ttf").read_bytes()
        t = S.read_tables(data)
        m = S.parse_cmap(t["cmap"])
        names = S.post_names(t["post"])
        self.assertEqual(names, [])  # post 3.0: names dropped, advance widths are what matters
        adv = [int.from_bytes(t["hmtx"][4 * m[ord(c)]:4 * m[ord(c)] + 2], "big") for c in "0123456789"]
        self.assertEqual(len(set(adv)), 1)

    def test_cmap_roundtrip(self) -> None:
        m = {65: 5, 66: 6, 67: 7, 200: 9}
        self.assertEqual(S._cmap4(S.build_cmap(m), 20), m)

    def test_checksum_pad(self) -> None:
        self.assertEqual(S.checksum(b"\x00\x00\x00\x01"), 1)
        self.assertEqual(S.checksum(b"\x01"), 0x01000000)


class ThemeTest(unittest.TestCase):
    def test_committed_theme_is_current(self) -> None:
        self.assertEqual(T.OUT.read_text(encoding="utf-8"), T.build(json.loads(T.PALETTE.read_text(encoding="utf-8"))))

    def test_colours_only_from_palette(self) -> None:
        pal = json.loads(T.PALETTE.read_text(encoding="utf-8"))
        text = T.build(pal)
        for key in ("ui_text", "ui_text_dim", "ui_accent", "ui_focus", "ui_line"):
            self.assertIn(T.col(pal["ui"][key]), text)

    def test_min_text_size(self) -> None:
        self.assertGreaterEqual(T.SMALL_SIZE, 9)


if __name__ == "__main__":
    unittest.main()
