"""ART-32 licence ledger gate: passing and failing fixture trees, plus the real repository."""

from __future__ import annotations

import contextlib
import csv
import io
import tempfile
import unittest
from pathlib import Path

from helpers import TOOLS

import check_licences

REPO = TOOLS.parent
SHA = "a" * 64
HEADER = check_licences.COLUMNS


def _row(path: str, licence: str = "original", attribution: str = "no", sha: str = SHA,
         asset_id: str | None = None) -> list[str]:
    return [asset_id or path.replace("/", "_"), path, sha, "tools/x.py from tools/y.json",
            "in-house", licence, attribution, "0", "2026-10-10", ""]


class Fixture:
    """A throwaway repo tree: write files, then write the ledger rows."""

    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def close(self) -> None:
        self._tmp.cleanup()

    def file(self, rel: str, data: bytes = b"x") -> None:
        target = self.root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

    def ledger(self, rows: list[list[str]], header: list[str] | None = None) -> None:
        target = self.root / check_licences.LEDGER
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(header or HEADER)
            writer.writerows(rows)

    def check(self) -> list[str]:
        return check_licences.check(self.root)


class PassingFixtures(unittest.TestCase):
    def setUp(self) -> None:
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def test_seeded_tree_passes(self) -> None:
        self.fx.file("godot/assets/textures/atlas.png")
        self.fx.file("godot/assets/textures/atlas.png.import")
        self.fx.file("godot/assets/textures/.gitkeep")
        self.fx.ledger([_row("godot/assets/textures/atlas.png")])
        self.assertEqual(self.fx.check(), [])

    def test_allowed_licences_on_matching_media_pass(self) -> None:
        self.fx.file("godot/assets/ui/fonts/inter.ttf")
        self.fx.file("godot/assets/audio/sfx/boom.ogg")
        self.fx.file("godot/assets/audio/music/bed.wav")
        self.fx.file("godot/assets/models/ship.glb")
        self.fx.ledger([
            _row("godot/assets/ui/fonts/inter.ttf", licence="OFL-1.1"),
            _row("godot/assets/audio/sfx/boom.ogg", licence="CC-BY-4.0", attribution="yes"),
            _row("godot/assets/audio/music/bed.wav", licence="CC0-1.0"),
            _row("godot/assets/models/ship.glb", licence="commissioned"),
        ])
        self.assertEqual(self.fx.check(), [])

    def test_audio_and_fonts_outside_assets_are_scoped_and_pass_with_rows(self) -> None:
        self.fx.file("godot/content/sounds/click.wav")
        self.fx.ledger([_row("godot/content/sounds/click.wav", licence="CC0-1.0")])
        self.assertEqual(self.fx.check(), [])

    def test_addons_and_non_media_outside_assets_are_not_scoped(self) -> None:
        self.fx.file("godot/addons/gdUnit4/sound.wav")
        self.fx.file("godot/src/app/app.gd")
        self.fx.ledger([])
        self.assertEqual(self.fx.check(), [])


class FailingFixtures(unittest.TestCase):
    def setUp(self) -> None:
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def _assert_one(self, errors: list[str], *needles: str) -> None:
        self.assertEqual(len(errors), 1, errors)
        for needle in needles:
            self.assertIn(needle, errors[0])

    def test_asset_without_row_fails(self) -> None:
        self.fx.file("godot/assets/textures/orphan.png")
        self.fx.ledger([])
        self._assert_one(self.fx.check(), "godot/assets/textures/orphan.png", "no row")

    def test_unledgered_audio_outside_assets_fails(self) -> None:
        self.fx.file("godot/content/sounds/click.ogg")
        self.fx.ledger([])
        self._assert_one(self.fx.check(), "godot/content/sounds/click.ogg", "no row")

    def test_row_for_missing_file_fails(self) -> None:
        self.fx.ledger([_row("godot/assets/textures/ghost.png")])
        self._assert_one(self.fx.check(), "does not exist", "ghost.png")

    def test_forbidden_nc_sa_licence_fails(self) -> None:
        self.fx.file("godot/assets/audio/sfx/boom.ogg")
        self.fx.ledger([_row("godot/assets/audio/sfx/boom.ogg", licence="CC-BY-NC-SA-4.0",
                             attribution="yes")])
        self._assert_one(self.fx.check(), "not on the allowed list (forbidden)")

    def test_gpl_licence_fails(self) -> None:
        self.fx.file("godot/assets/textures/a.png")
        self.fx.ledger([_row("godot/assets/textures/a.png", licence="GPL-3.0")])
        self._assert_one(self.fx.check(), "GPL-3.0", "not on the allowed list")

    def test_unknown_licence_fails(self) -> None:
        self.fx.file("godot/assets/textures/a.png")
        self.fx.ledger([_row("godot/assets/textures/a.png", licence="free for non-commercial")])
        self._assert_one(self.fx.check(), "not on the allowed list")

    def test_cc_by_on_texture_fails(self) -> None:
        self.fx.file("godot/assets/textures/a.png")
        self.fx.ledger([_row("godot/assets/textures/a.png", licence="CC-BY-4.0", attribution="yes")])
        self._assert_one(self.fx.check(), "only for SFX and music")

    def test_cc_by_without_attribution_fails(self) -> None:
        self.fx.file("godot/assets/audio/sfx/boom.ogg")
        self.fx.ledger([_row("godot/assets/audio/sfx/boom.ogg", licence="CC-BY-4.0", attribution="no")])
        self._assert_one(self.fx.check(), "attribution_required=yes")

    def test_ofl_on_non_font_fails(self) -> None:
        self.fx.file("godot/assets/textures/a.png")
        self.fx.ledger([_row("godot/assets/textures/a.png", licence="OFL-1.1")])
        self._assert_one(self.fx.check(), "only for fonts")

    def test_wrong_header_fails(self) -> None:
        self.fx.file("godot/assets/textures/a.png")
        self.fx.ledger([_row("godot/assets/textures/a.png")], header=HEADER[:-1])
        self._assert_one(self.fx.check(), "header must be")

    def test_bad_sha_fails(self) -> None:
        self.fx.file("godot/assets/textures/a.png")
        self.fx.ledger([_row("godot/assets/textures/a.png", sha="xyz")])
        self._assert_one(self.fx.check(), "sha256")

    def test_duplicate_path_fails(self) -> None:
        self.fx.file("godot/assets/textures/a.png")
        self.fx.ledger([_row("godot/assets/textures/a.png", asset_id="one"),
                        _row("godot/assets/textures/a.png", asset_id="two")])
        self._assert_one(self.fx.check(), "duplicate path")

    def test_missing_ledger_fails(self) -> None:
        self.fx.file("godot/assets/textures/a.png")
        self._assert_one(self.fx.check(), "ledger file is missing")


class RealRepository(unittest.TestCase):
    def test_repository_ledger_passes(self) -> None:
        self.assertEqual(check_licences.check(REPO), [])

    def test_main_exit_codes(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check_licences.main(["--root", str(REPO)]), 0)
        fx = Fixture()
        self.addCleanup(fx.close)
        fx.file("godot/assets/textures/orphan.png")
        fx.ledger([])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(check_licences.main(["--root", str(fx.root)]), 1)


if __name__ == "__main__":
    unittest.main()
