"""ART-22: sfxgen determinism and analyze.py checks (clipping, loop seam, LUFS, centroid)."""

from __future__ import annotations

import json
import math
import tempfile
import unittest
from pathlib import Path

from helpers import TOOLS

import sys

sys.path.insert(0, str(TOOLS / "audio"))
import analyze  # noqa: E402
import sfxgen  # noqa: E402

FIX = Path(__file__).resolve().parent / "fixtures" / "audio"
SR = 22050


def load(name: str) -> dict:
    return json.loads((FIX / f"{name}.json").read_text(encoding="utf-8"))


def sine(freq: float, n: int, amp: float = 0.5) -> list[float]:
    return [amp * math.sin(2 * math.pi * freq * i / SR) for i in range(n)]


class RenderTests(unittest.TestCase):
    def test_fixtures_validate(self) -> None:
        for name in ("test_zap", "test_hum_loop"):
            self.assertEqual(sfxgen.validate_recipe(load(name)), [], name)

    def test_deterministic_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            _, h1 = sfxgen.render_file(load("test_zap"), Path(a))
            _, h2 = sfxgen.render_file(load("test_zap"), Path(b))
            self.assertEqual(h1, h2)
            self.assertEqual((Path(a) / "test_zap.wav").read_bytes(), (Path(b) / "test_zap.wav").read_bytes())

    def test_seed_changes_output(self) -> None:
        r = load("test_zap")
        other = dict(r, seed=r["seed"] + 1)
        self.assertNotEqual(sfxgen.to_pcm16(sfxgen.render(r)), sfxgen.to_pcm16(sfxgen.render(other)))

    def test_format_and_peak(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            wav, _ = sfxgen.render_file(load("test_zap"), Path(d))
            m = analyze.analyze_wav(wav)
        self.assertEqual(m["sample_rate"], 22050)
        self.assertAlmostEqual(m["peak_dbfs"], -3.0, delta=0.05)
        self.assertEqual(analyze.check(m, duration=(0.2, 2.0)), [])

    def test_invalid_recipe_rejected(self) -> None:
        bad = load("test_zap")
        bad["layers"][0]["wave"] = "triangle"
        self.assertTrue(sfxgen.validate_recipe(bad))
        bad = load("test_zap")
        del bad["layers"][0]["f0"]
        self.assertTrue(any("needs f0" in e for e in sfxgen.validate_recipe(bad)))
        bad = load("test_zap")
        bad["extra"] = 1
        self.assertTrue(sfxgen.validate_recipe(bad))


class AnalyzeTests(unittest.TestCase):
    def test_clipping_flagged(self) -> None:
        r = load("test_zap")
        del r["normalize_peak_db"]
        r["layers"][0]["gain"] = 4.0
        with tempfile.TemporaryDirectory() as d:
            wav, _ = sfxgen.render_file(r, Path(d))
            m = analyze.analyze_wav(wav)
        problems = analyze.check(m)
        self.assertGreater(m["clipped_samples"], 0)
        self.assertTrue(any(p.startswith("clipping") for p in problems), problems)

    def test_clean_signal_not_flagged(self) -> None:
        m = analyze.analyze_samples(sine(440, SR), SR)
        self.assertEqual(analyze.check(m, loop=True), [])

    def test_bad_loop_seam_flagged(self) -> None:
        # 440 Hz: 50 cycles take 2.5 s * ... cut at a quarter cycle so the end jumps to the start
        n = int(SR * 0.5) + int(SR / 440 / 4)
        m = analyze.analyze_samples(sine(440, n), SR)
        problems = analyze.check(m, loop=True)
        self.assertTrue(any("loop seam" in p for p in problems), (m, problems))
        self.assertEqual([p for p in analyze.check(m, loop=False) if "seam" in p], [])

    def test_crossfaded_loop_seam_ok(self) -> None:
        r = load("test_hum_loop")
        x = [v for v in sfxgen.render(r)]
        m = analyze.analyze_samples(x, SR)
        self.assertEqual([p for p in analyze.check(m, loop=True) if "seam" in p], [], m)

    def test_uncrossfaded_loop_seam_flagged(self) -> None:
        r = load("test_hum_loop")
        r["loop"] = False
        r["layers"][0]["sustain"] = 2.0013  # not a whole number of cycles
        m = analyze.analyze_samples(sfxgen.render(r), SR)
        self.assertTrue(any("loop seam" in p for p in analyze.check(m, loop=True)), m)

    def test_dc_offset_flagged(self) -> None:
        m = analyze.analyze_samples([0.2 + v for v in sine(440, SR, 0.1)], SR)
        self.assertTrue(any("DC offset" in p for p in analyze.check(m)))

    def test_lufs_reference(self) -> None:
        # BS.1770: a 997 Hz sine at -3.01 dBFS peak... full-scale sine reads -3.01 LUFS; 0.5 amp is 6 dB lower
        m = analyze.analyze_samples(sine(997, SR * 2, 0.5), SR)
        self.assertAlmostEqual(m["lufs"], -3.01 - 6.02, delta=0.3)

    def test_centroid_of_sine(self) -> None:
        m = analyze.analyze_samples(sine(1000, SR), SR)
        self.assertAlmostEqual(m["centroid_hz"], 1000, delta=40)
        self.assertTrue(any("centroid" in p for p in analyze.check(m, centroid=(2000, 4000))))
        self.assertEqual(analyze.check(m, centroid=(800, 1200)), [])

    def test_duration_limit(self) -> None:
        m = analyze.analyze_samples(sine(300, SR * 4 + 100, 0.3), SR)
        self.assertTrue(any("duration" in p for p in analyze.check(m)))


if __name__ == "__main__":
    unittest.main()
