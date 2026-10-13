"""Spot values of godot/content/defs/structures.json and towers.json (GD-04; 02 s5, R0 B.1 / B.7)."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DEFS = ROOT / "godot" / "content" / "defs"


def _load(stem: str) -> dict[str, dict]:
    data = json.loads((DEFS / f"{stem}.json").read_text(encoding="utf-8"))
    return {e["id"]: e for e in data[stem]}


class StructureSpotValues(unittest.TestCase):
    def setUp(self) -> None:
        self.s = _load("structures")
        self.t = _load("towers")

    def test_no_storage_silo_anywhere(self) -> None:
        self.assertNotIn("storage_silo", self.s)
        self.assertNotIn("storage_silo", self.t)
        self.assertNotIn("storage_silo", (DEFS / "structures.json").read_text(encoding="utf-8"))

    def test_rail_lance_footprint_and_status(self) -> None:
        self.assertEqual(self.t["rail_lance"]["footprint"], [4, 5])
        self.assertEqual(self.t["rail_lance"]["status"], "core")

    def test_core_shield_and_pad(self) -> None:
        core = self.s["core"]
        self.assertEqual(core["integrated_shield"], {"charge_max": 2400, "recharge_per_s": 40, "recharge_delay_s": 5})
        self.assertEqual(core["pad_radius_m"], 12)
        self.assertEqual((core["storage_ore"], core["storage_ice"]), (3000, 800))
        self.assertFalse(core["buildable"])

    def test_storage_raises_for_refinery_and_outpost(self) -> None:
        self.assertEqual((self.s["refinery"]["storage_ore"], self.s["refinery"]["storage_ice"]), (1500, 500))
        self.assertEqual((self.s["outpost"]["storage_ore"], self.s["outpost"]["storage_ice"]), (250, 100))

    def test_relay_station_is_neutral_and_invulnerable(self) -> None:
        rs = self.s["relay_station"]
        self.assertEqual((rs["hp"], rs["invulnerable"], rs["buildable"], rs["pad_radius_m"]), (1, True, False, 12))

    def test_pad_radii_match_r0(self) -> None:
        radii = {k: v.get("pad_radius_m") for k, v in self.s.items() if "pad_radius_m" in v}
        self.assertEqual(radii, {"core": 12, "outpost": 10, "pad": 10, "hangar": 10, "relay_station": 12})

    def test_tower_blocks(self) -> None:
        for tid, tw in self.t.items():
            if tid == "shield_projector":
                self.assertIn("shield", tw)
                self.assertNotIn("tower", tw)
            else:
                self.assertIn("tower", tw, tid)
                self.assertEqual(tw["tower"]["target_priority"][0], "bomber", tid)

    def test_missile_tower_agl_and_hangar_upgrade(self) -> None:
        self.assertEqual(self.t["missile_tower"]["tower"]["target_agl_min"], 40)
        hangar = self.s["hangar"]
        self.assertEqual((hangar["upgrade_from"], hangar["upgrade_cost_ore"], hangar["upgrade_time_s"]), ("pad", 75, 15))


if __name__ == "__main__":
    unittest.main()
