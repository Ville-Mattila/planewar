"""Spot values of economy, match_rules, modes, bot_promises and scoring (GD-05; R0 B.1, B.6, B.8 A-4; 02 s8.1, s12.1, s14, s15, s17.1)."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

DEFS = Path(__file__).resolve().parent.parent.parent / "godot" / "content" / "defs"


def _load(stem: str) -> dict:
    return json.loads((DEFS / f"{stem}.json").read_text(encoding="utf-8"))


class ModeIds(unittest.TestCase):
    def test_seven_modes_equal_r0_b6(self) -> None:
        ids = [m["id"] for m in _load("modes")["modes"]]
        self.assertEqual(ids, ["pvp_1v1", "pvp_2v2", "pvp_team", "coop", "custom", "skirmish", "campaign"])

    def test_slots_by_player_count(self) -> None:
        slots = _load("modes")["slots_by_player_count"]
        self.assertEqual(slots, {"2": [0, 2], "4": [0, 2, 4, 6], "6": [0, 1, 2, 4, 5, 6], "8": list(range(8))})

    def test_per_mode_timers_and_fill(self) -> None:
        by_id = {m["id"]: m for m in _load("modes")["modes"]}
        self.assertEqual((by_id["pvp_1v1"]["core_exposure_s"], by_id["pvp_1v1"]["hard_end_s"]), (1200, 1800))
        self.assertEqual((by_id["pvp_2v2"]["core_exposure_s"], by_id["pvp_2v2"]["hard_end_s"]), (1500, 2100))
        self.assertEqual((by_id["pvp_team"]["core_exposure_s"], by_id["pvp_team"]["hard_end_s"]), (1800, 2400))
        self.assertEqual(by_id["pvp_1v1"]["fill_rating_weight"], 0)
        self.assertEqual(by_id["pvp_2v2"]["fill_rating_weight"], 0.5)
        self.assertNotIn("fill_rating_weight", by_id["pvp_team"])
        self.assertIsNone(by_id["campaign"]["core_exposure_s"])


class BotPromiseCadence(unittest.TestCase):
    def test_tier_numbers_r0_c2_13(self) -> None:
        rows = _load("bot_promises")["bot_promises"]
        self.assertEqual([r["id"] for r in rows], ["easy", "normal", "hard", "brutal"])
        self.assertEqual([r["think_s"] for r in rows], [3, 1, 1, 1])
        self.assertEqual([r["reaction_s"] for r in rows], [6, 2, 0.5, 0])
        self.assertEqual([r["command_rate_cap"] for r in rows], [20, 40, 80, 150])


class EconomyAndRules(unittest.TestCase):
    def test_economy_anchors(self) -> None:
        eco = _load("economy")
        self.assertEqual((eco["start_ore"], eco["start_ice"]), (800, 300))
        self.assertEqual(eco["start_kit"], ["core", "refinery", "shipyard", "vehicle_bay", "harvester"])
        self.assertEqual((eco["early_share_lock_s"], eco["early_share_ore"]), (120, 800))

    def test_match_rules_caps_and_timers(self) -> None:
        mr = _load("match_rules")
        self.assertEqual(mr["caps"]["standard"], {"units": 80, "structures": 60, "projectiles": 2000, "wrecks": 200, "slots": 8})
        self.assertEqual(mr["caps"]["lite"]["slots"], 4)
        self.assertEqual((mr["core_value"], mr["core_shield_until_s"], mr["surrender_min_s_1v1"]), (2000, 480, 180))


class Scoring(unittest.TestCase):
    def test_spot_points(self) -> None:
        sc = _load("scoring")
        self.assertEqual(sc["kill_points"]["bomber"], 250)
        self.assertEqual(sc["landing"]["points"]["ace"], 50)
        self.assertEqual(sc["match_win"], 500)


if __name__ == "__main__":
    unittest.main()
