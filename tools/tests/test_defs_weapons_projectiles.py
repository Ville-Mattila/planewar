"""GD-03 spot values: godot/content/defs/weapons.json and projectiles.json against 02 s4.1-4.2 and R0 B.1.

Schema conformance is validate_content.py's job; these tests pin the values a balance change would move.
"""

from __future__ import annotations

import json
import unittest

from helpers import TOOLS

DEFS = TOOLS.parent / "godot" / "content" / "defs"


def load(stem: str) -> dict:
    return json.loads((DEFS / f"{stem}.json").read_text(encoding="utf-8"))


def by_id(rows: list[dict], ident: str) -> dict:
    return next(r for r in rows if r["id"] == ident)


class WeaponSpotValues(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.weapons = load("weapons")["weapons"]

    def test_gun_dart_damage_and_rof(self) -> None:
        w = by_id(self.weapons, "gun_dart")
        self.assertEqual((w["damage_min"], w["damage_max"]), (6, 14))
        self.assertEqual(w["rof"], 10)
        self.assertEqual(w["projectile"], "slug_light")

    def test_bomb_damage_and_rearm(self) -> None:
        w = by_id(self.weapons, "bomb")
        self.assertEqual(w["damage_min"], 400)
        self.assertEqual(w["rearm_ice"], 10)

    def test_siege_gun_minimum_range_and_mount(self) -> None:
        w = by_id(self.weapons, "siege_gun")
        self.assertEqual(w["range_min_m"], 300)
        self.assertEqual(w["range_m"], 1200)
        self.assertEqual(w["weapon_mount"], "ground")

    def test_rail_gun_range(self) -> None:
        self.assertEqual(by_id(self.weapons, "rail_gun")["range_m"], 2500)

    def test_rocket_lancer_lock(self) -> None:
        w = by_id(self.weapons, "rocket_lancer")
        self.assertEqual((w["lock_cone_deg"], w["lock_time_s"], w["turn_rate_dps"]), (20, 0.8, 90))

    def test_flak_gun_salvo_and_reload(self) -> None:
        w = by_id(self.weapons, "flak_gun")
        self.assertEqual((w["salvo"], w["reload_s"]), (2, 2.0))

    def test_tower_mounts(self) -> None:
        for ident in ("gun_turret", "rocket_tower", "flak_gun", "rail_gun"):
            self.assertEqual(by_id(self.weapons, ident)["weapon_mount"], "tower", ident)

    def test_ship_mounts(self) -> None:
        for ident in ("gun_dart", "gun_lancer", "bomb", "rocket_lancer"):
            self.assertEqual(by_id(self.weapons, ident)["weapon_mount"], "ship", ident)

    def test_nine_weapons(self) -> None:
        self.assertEqual(len(self.weapons), 9)


class ProjectileSpotValues(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.projectiles = load("projectiles")["projectiles"]

    def test_slugs_flak_and_rail_have_no_gravity_and_no_transport(self) -> None:
        for ident in ("slug_light", "slug_heavy", "flak_shell", "rail_slug"):
            p = by_id(self.projectiles, ident)
            self.assertIs(p["gravity"], False, ident)
            self.assertIs(p["transport"], False, ident)

    def test_bomb_is_ballistic_transported_and_shield_absorbed(self) -> None:
        p = by_id(self.projectiles, "bomb")
        self.assertEqual(p["behaviour"], "ballistic")
        self.assertIs(p["gravity"], True)
        self.assertIs(p["transport"], True)
        self.assertIs(p["shield_absorbed"], True)
        self.assertEqual(p["eject_down_mps"], 40)
        self.assertEqual((p["blast_radius_m"], p["blast_radius_structure_m"]), (15, 20))

    def test_rocket_proximity_fuse(self) -> None:
        p = by_id(self.projectiles, "rocket")
        self.assertEqual((p["fuse"], p["fuse_radius_m"], p["arm_s"]), ("proximity", 4, 0.2))

    def test_flak_timed_fuse_radius(self) -> None:
        p = by_id(self.projectiles, "flak_shell")
        self.assertEqual((p["fuse"], p["fuse_radius_m"], p["blast_radius_m"]), ("timed", 12, 25))

    def test_rail_slug_speed(self) -> None:
        self.assertEqual(by_id(self.projectiles, "rail_slug")["speed_mps"], 1500)

    def test_siege_shell_arms_after_one_second(self) -> None:
        self.assertEqual(by_id(self.projectiles, "siege_shell")["arm_s"], 1.0)

    def test_supply_canister_is_candidate_rendezvous(self) -> None:
        p = by_id(self.projectiles, "supply_canister")
        self.assertEqual((p["status"], p["behaviour"], p["hp"]), ("candidate", "rendezvous", 30))

    def test_every_projectile_has_hp_field(self) -> None:
        for p in self.projectiles:
            self.assertIn("hp", p, p["id"])


if __name__ == "__main__":
    unittest.main()
