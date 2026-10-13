"""UX-29 locale tools: build_po, check_locale, po_to_csv (docs/06 s11), plus the real repository tables."""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS / "locale"))

import build_po  # noqa: E402
import check_locale  # noqa: E402
import locale_lib as L  # noqa: E402
import po_to_csv  # noqa: E402

HEADER = ",".join(L.COLUMNS)
GOOD = (
    HEADER + "\n"
    'ui.menu.play,Play,Pelaa,10,Button,\n'
    'barks.hit.1,{callsign} hit.,{callsign} osui.,,Bark,\n'
    'ui.count#one,{count} ship,{count} alus,,Plural,\n'
    'ui.count#other,{count} ships,{count} alusta,,Plural,\n'
)


class Tree:
    """A throwaway locale dir with one CSV domain and an empty godot tree."""

    def __init__(self, csv_text: str = GOOD) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.locale = self.root / "locale"
        (self.locale / "src").mkdir(parents=True)
        (self.root / "godot" / "src").mkdir(parents=True)
        (self.root / "godot" / "scenes").mkdir(parents=True)
        self.write_csv(csv_text)

    def write_csv(self, text: str, name: str = "ui_menu.csv") -> None:
        (self.locale / "src" / name).write_text(text, encoding="utf-8", newline="\n")

    def errors(self) -> list[str]:
        t = L.load_table(self.locale)
        return check_locale.check_rows(t) + check_locale.check_keys(t, check_locale.scan_keys(self.root / "godot"))

    def close(self) -> None:
        self._tmp.cleanup()


def run(main, argv: list[str]) -> tuple[int, str]:
    err = io.StringIO()
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
        code = main(argv)
    return code, err.getvalue()


class CheckLocaleTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tree = Tree()
        self.addCleanup(self.tree.close)

    def test_good_table_passes(self) -> None:
        self.assertEqual(self.tree.errors(), [])

    def test_placeholder_mismatch_fails(self) -> None:
        self.tree.write_csv(HEADER + "\nbarks.hit.1,{callsign} hit.,{call} osui.,,,\n")
        self.assertTrue(any("placeholders differ" in e for e in self.tree.errors()))

    def test_max_len_fails_for_fi_and_en(self) -> None:
        self.tree.write_csv(HEADER + "\nui.a.b,Hi,Pitkä teksti,5,,\nui.a.c,Long english,x,5,,\n")
        errs = self.tree.errors()
        self.assertTrue(any("fi is" in e for e in errs))
        self.assertTrue(any("en is" in e for e in errs))

    def test_default_max_len_is_1_4_times_en(self) -> None:
        self.tree.write_csv(HEADER + "\nui.a.b,Hello world,Hello worldxxxx,,,\n")  # 15 -> 15.4 ok
        self.assertEqual(self.tree.errors(), [])
        self.tree.write_csv(HEADER + "\nui.a.b,Hello world,Hello worldxxxxx,,,\n")  # 16 > 15.4
        self.assertTrue(any("fi is" in e for e in self.tree.errors()))

    def test_bad_id_duplicate_and_empty_en(self) -> None:
        self.tree.write_csv(HEADER + "\nBad Id,x,,,,\nui.a.b,x,,,,\nui.a.b,y,,,,\nui.a.c,,,,,\n")
        joined = "\n".join(self.tree.errors())
        self.assertIn("lowercase dotted", joined)
        self.assertIn("duplicate id", joined)
        self.assertIn("English text is empty", joined)

    def test_plural_needs_both_forms(self) -> None:
        self.tree.write_csv(HEADER + "\nui.n#one,{count} a,,,,\n")
        self.assertTrue(any("plural needs both" in e for e in self.tree.errors()))

    def test_bad_header_and_column_count(self) -> None:
        self.tree.write_csv("id,en\nui.a.b,x\n")
        self.assertTrue(any("header must be" in e for e in self.tree.errors()))
        self.tree.write_csv(HEADER + "\nui.a.b,x\n")
        self.assertTrue(any("expected 6 columns" in e for e in self.tree.errors()))

    def test_missing_id_for_tr_and_scene_key(self) -> None:
        (self.tree.root / "godot" / "src" / "x.gd").write_text(
            'var a := tr("ui.menu.play")\nvar b := tr(&"ui.missing.one")\nvar c := tr_n("ui.count", "ui.count", 2)\n'
            'var d := tr("ui.%s.name" % x)\n', encoding="utf-8")
        (self.tree.root / "godot" / "scenes" / "s.tscn").write_text(
            '[node name="L" type="Label"]\ntext = "ui.gone.too"\ntext = "Not a key"\n', encoding="utf-8")
        errs = self.tree.errors()
        self.assertEqual(sorted(e.split("'")[1] for e in errs), ["ui.gone.too", "ui.missing.one"])

    def test_cli_exit_codes_and_coverage_gate(self) -> None:
        args = ["--locale-dir", str(self.tree.locale), "--godot-dir", str(self.tree.root / "godot")]
        self.assertEqual(run(check_locale.main, args)[0], 0)
        self.tree.write_csv(HEADER + "\nui.a.b,x,,,,\n")
        self.assertEqual(run(check_locale.main, args)[0], 0)
        code, err = run(check_locale.main, args + ["--require-fi-full"])
        self.assertEqual(code, 1)
        self.assertIn("coverage", err)

    def test_en_json_is_merged_and_collisions_fail(self) -> None:
        (self.tree.locale / "en.json").write_text('{"hud.speed": "SPD", "ui.menu.play": "Dup"}', encoding="utf-8")
        errs = self.tree.errors()
        self.assertEqual([e for e in errs if "duplicate" in e].__len__(), 1)
        self.assertTrue(any("ui.menu.play" in e for e in errs))


class BuildPoTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tree = Tree()
        self.addCleanup(self.tree.close)
        self.table = L.load_table(self.tree.locale)

    def test_po_contents_and_plurals(self) -> None:
        fi = L.render_po(self.table, "fi")
        self.assertIn('msgid "ui.menu.play"\nmsgstr "Pelaa"', fi)
        self.assertIn('msgid "ui.count"\nmsgid_plural "ui.count"\nmsgstr[0] "{count} alus"\nmsgstr[1] "{count} alusta"', fi)
        self.assertEqual(L.parse_po(fi)["ui.count"], ["{count} alus", "{count} alusta"])

    def test_escape_roundtrip(self) -> None:
        raw = 'say "hi"\\n\nnext'
        self.assertEqual(L.po_unescape(L.po_escape(raw)), raw)

    def test_check_detects_stale_files(self) -> None:
        self.assertEqual(run(build_po.main, ["--locale-dir", str(self.tree.locale)])[0], 0)
        self.assertEqual(run(build_po.main, ["--locale-dir", str(self.tree.locale), "--check"])[0], 0)
        self.tree.write_csv(GOOD.replace("Pelaa", "Pelaa nyt"))
        self.assertEqual(run(build_po.main, ["--locale-dir", str(self.tree.locale), "--check"])[0], 1)

    def test_pseudolocale_keeps_placeholders_and_expands(self) -> None:
        ps = L.pseudolocalize("{callsign} airborne now.")
        self.assertIn("{callsign}", ps)
        self.assertGreaterEqual(len(ps), int(len("{callsign} airborne now.") * 1.4))
        self.assertTrue(ps.startswith("[") and ps.endswith("]"))
        self.assertNotIn("airborne", ps)
        self.assertEqual(L.placeholders(L.pseudolocalize("{btn:fire1} to fire")), {"{btn:fire1}"})

    def test_pseudo_build_and_check(self) -> None:
        out = self.tree.root / "pseudo"
        args = ["--locale-dir", str(self.tree.locale), "--pseudo", "--out", str(out)]
        self.assertEqual(run(build_po.main, args)[0], 0)
        self.assertEqual(check_locale.check_pseudo(self.table, (out / "en_XA.po").read_text(encoding="utf-8")), [])
        broken = (out / "en_XA.po").read_text(encoding="utf-8").replace("{callsign}", "{x}")
        self.assertTrue(check_locale.check_pseudo(self.table, broken))

    def test_malformed_csv_fails_build(self) -> None:
        self.tree.write_csv("id,en\nui.a.b,x\n")
        self.assertEqual(run(build_po.main, ["--locale-dir", str(self.tree.locale)])[0], 1)


class PoToCsvTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tree = Tree()
        self.addCleanup(self.tree.close)

    def test_roundtrip_is_identity(self) -> None:
        po = L.render_po(L.load_table(self.tree.locale), "fi")
        before = (self.tree.locale / "src" / "ui_menu.csv").read_text(encoding="utf-8")
        self.assertEqual(po_to_csv.import_po(self.tree.locale, "fi", po), 0)
        self.assertEqual((self.tree.locale / "src" / "ui_menu.csv").read_text(encoding="utf-8"), before)

    def test_translation_edit_lands_in_csv(self) -> None:
        po = L.render_po(L.load_table(self.tree.locale), "fi").replace("Pelaa", "Aloita").replace("{count} alusta", "{count} alusta!")
        self.assertEqual(po_to_csv.import_po(self.tree.locale, "fi", po), 0)
        rows = {r.id: r for r in L.load_table(self.tree.locale).rows}
        self.assertEqual(rows["ui.menu.play"].fi, "Aloita")
        self.assertEqual(rows["ui.count#other"].fi, "{count} alusta!")
        self.assertEqual(rows["ui.menu.play"].max_len, "10")

    def test_unknown_id_and_english_rejected(self) -> None:
        self.assertEqual(po_to_csv.import_po(self.tree.locale, "fi", 'msgid "ui.nope.x"\nmsgstr "x"\n'), 1)
        self.assertEqual(po_to_csv.import_po(self.tree.locale, "en", ""), 1)

    def test_dry_run_does_not_write(self) -> None:
        before = (self.tree.locale / "src" / "ui_menu.csv").read_text(encoding="utf-8")
        po = L.render_po(L.load_table(self.tree.locale), "fi").replace("Pelaa", "Aloita")
        self.assertEqual(po_to_csv.import_po(self.tree.locale, "fi", po, dry_run=True), 0)
        self.assertEqual((self.tree.locale / "src" / "ui_menu.csv").read_text(encoding="utf-8"), before)


class RepositoryTest(unittest.TestCase):
    def test_committed_tables_pass_and_po_is_fresh(self) -> None:
        self.assertEqual(run(check_locale.main, [])[0], 0)
        self.assertEqual(run(build_po.main, ["--check"])[0], 0)


if __name__ == "__main__":
    unittest.main()
