"""GD-02 spot values: godot/content/defs/ships.json and ground_units.json against R0 B.1 and 02 s2-3.

Schema conformance is validate_content.py's job; these tests pin the values a balance change would move.
"""

from __future__ import annotations

import json
import unittest

from helpers import TOOLS

DEFS = TOOLS.parent / "godot" / "content" / "defs"


def load(stem: str) -> dict:
    return json.loads((DEFS / f"{stem}.json").read_text(encoding="utf-8"))


def ship(data: dict, ident: str) -> dict:
    return next(s for s in data["ships"] if s["id"] == ident)


def unit(data: dict, ident: str) -> dict:
    return next(u for u in data["ground_units"] if u["id"] == ident)


class ShipSpotValues(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ships = load("ships")
        cls.rules = load("rules")

    def test_bomber_a_thrust_is_14(self) -> None:
        self.assertEqual(ship(self.ships, "bomber")["a_thrust"], 14)

    def test_hauler_a_thrust_is_15(self) -> None:
        self.assertEqual(ship(self.ships, "hauler")["a_thrust"], 15)

    def test_every_ship_hovers_at_least_two_g(self) -> None:
        for s in self.ships["ships"]:
            self.assertGreaterEqual(s["a_thrust"], 2.0 * self.rules["gravity"], s["id"])

    def test_dart_rate_accel_is_720(self) -> None:
        self.assertEqual(ship(self.ships, "dart")["rate_accel_dps2"], 720)

    def test_k_up_flight_per_ship(self) -> None:
        self.assertEqual(ship(self.ships, "dart")["k_up_flight"], 1.0)
        self.assertEqual(ship(self.ships, "bomber")["k_up_flight"], 1.2)
        self.assertEqual(ship(self.ships, "scout")["k_up_flight"], 0.8)

    def test_dart_loadout(self) -> None:
        dart = ship(self.ships, "dart")
        self.assertEqual(dart["primary"], {"weapon": "gun_dart", "ammo": 400})
        self.assertEqual(dart["secondary"], {"weapon": "bomb", "count": 2})

    def test_bomber_has_no_gun(self) -> None:
        self.assertIsNone(ship(self.ships, "bomber")["primary"])

    def test_hauler_loaded_cruise_and_tow(self) -> None:
        hauler = ship(self.ships, "hauler")
        self.assertEqual(hauler["v_cruise_loaded"], 35)
        self.assertEqual(hauler["cargo_ice"], 400)
        self.assertEqual(hauler["tow_slots"], 1)

    def test_lancer_hp_and_fuel(self) -> None:
        lancer = ship(self.ships, "lancer")
        self.assertEqual(lancer["hp"], 220)
        self.assertEqual(lancer["fuel_s"], 300)

    def test_scout_sensor_radius(self) -> None:
        self.assertEqual(ship(self.ships, "scout")["sensor_radius"], 2000)

    def test_bomber_requires_hangar(self) -> None:
        self.assertEqual(ship(self.ships, "bomber")["requires"], ["hangar"])

    def test_flight_common_landing_limits(self) -> None:
        fc = self.ships["flight_common"]
        self.assertEqual(fc["landing_safe_v_vert"], 8)
        self.assertEqual(fc["landing_safe_v_hor"], 15)
        self.assertEqual(fc["landing_safe_pitch_deg"], 25)

    def test_flight_common_tether_and_dock(self) -> None:
        fc = self.ships["flight_common"]
        self.assertEqual(fc["tether_len_m"], 25)
        self.assertEqual(fc["auto_dock_radius_m"], 150)


class GroundSpotValues(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.units = load("ground_units")

    def test_harvester_cargo_and_speed(self) -> None:
        h = unit(self.units, "harvester")
        self.assertEqual(h["cargo_ore"], 300)
        self.assertEqual(h["ground_speed"], 12)
        self.assertEqual(h["ground_speed_loaded"], 10)

    def test_siege_crawler_weapon_and_ammo(self) -> None:
        c = unit(self.units, "siege_crawler")
        self.assertEqual(c["weapon"], "siege_gun")
        self.assertEqual(c["ammo"], 20)

    def test_siege_crawler_requires_outpost(self) -> None:
        self.assertEqual(unit(self.units, "siege_crawler")["requires"], ["vehicle_bay", "outpost"])

    def test_every_ground_unit_produced_at_vehicle_bay(self) -> None:
        for u in self.units["ground_units"]:
            self.assertEqual(u["produced_at"], "vehicle_bay", u["id"])


if __name__ == "__main__":
    unittest.main()
