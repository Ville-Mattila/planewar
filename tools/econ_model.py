#!/usr/bin/env python3
"""econ_model: reproduce 02 s8.7-8.9 from the defs and a bot-book JSON (GD-21; R0 C3-01).

A fixed-step (0.25 s) model of the Normal-bot economy. Every number comes from godot/content/defs/*.json (costs, build
times, power, Harvester cycle, Hauler transfer, storage, trickle) and godot/content/maps/cradle/features.json (field
and trap numbers); the *decisions* come from a bot-book JSON (tools/econ_books/*.json): an ordered list of steps that
the bot executes strictly in order, each as soon as its not_before_s has passed, its prerequisites stand, a construction
slot or factory queue is free and the team pool can pay (02 s8.7: "the Normal bot opening below is the target 05's
books implement"). When the steps run out, the book's `tail` cycles (Ice ceiling of 02 s8.5, Harvester cap).

    python tools/econ_model.py [--match 1v1|4v4|all] [--minutes] [--log] [--json] [--check]

Prints the model tables beside the 02 numbers (parsed from docs/02-game-design.md, never retyped) and every
discrepancy outside tolerance. Exit 0 unless --check (exit 1 on any miss; 2 on usage / book errors). Standard
library only. The comparison lives in econ_compare.py.

Model assumptions the doc does not state (each is a book/CLI-visible constant, listed in the PR):
  launch_delay_s        a Dart is "airborne" this long after it completes (0:25 -> 0:28)
  service_gate          sortie service clocks start when the first player-built Pad finishes (matches the doc's min-6 rows)
  hauler_min_load       a Hauler leaves the Refinery once the Extractor buffer holds this much Ice
Not modelled: repair, wrecks and salvage, the early share lock (the doc says it never binds), `max_miners`, the dock
queue wait, placement rules (presence, spacing), fuel/ammo detail beyond the doc's per-sortie service charge.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFS = ROOT / "godot" / "content" / "defs"
MAP = ROOT / "godot" / "content" / "maps" / "cradle" / "features.json"
BOOKS = Path(__file__).resolve().parent / "econ_books"
DT = 0.25
COMBAT = ("dart", "lancer", "bomber")


class BookError(Exception):
    """A book step that can never run (unknown id, missing prerequisite): fail loudly, never skip silently."""


def _load(name: str) -> dict:
    return json.loads((DEFS / name).read_text(encoding="utf-8"))


class Defs:
    """The def values the model reads, keyed by item id."""

    def __init__(self) -> None:
        self.eco = _load("economy.json")
        self.items: dict[str, dict] = {}
        for x in _load("structures.json")["structures"]:
            self.items[x["id"]] = dict(x, kind="structure")
        for x in _load("towers.json")["towers"]:
            self.items[x["id"]] = dict(x, kind="structure")
        for x in _load("ships.json")["ships"]:
            self.items[x["id"]] = dict(x, kind="unit")
        for x in _load("ground_units.json")["ground_units"]:
            self.items[x["id"]] = dict(x, kind="unit")
        nodes = json.loads(MAP.read_text(encoding="utf-8"))["nodes"]
        self.nodes = {n["id"]: n for n in nodes}

    def item(self, item_id: str) -> dict:
        if item_id not in self.items:
            raise BookError(f"unknown item id '{item_id}'")
        return self.items[item_id]

    def trip_time(self, d_m: float, loaded_d_m: float | None = None) -> float:
        """02 s8.2: d/speed + cargo/mine_rate + d/speed_loaded + unload_time_s."""
        h = self.items["harvester"]
        dl = d_m if loaded_d_m is None else loaded_d_m
        return d_m / h["ground_speed"] + h["cargo_ore"] / h["mine_rate"] + dl / h["ground_speed_loaded"] + h["unload_time_s"]

    def haul_cycle(self, d_m: float, load: float = 400.0, speed_out: float = 45.0, speed_back: float = 35.0) -> float:
        """02 s8.3: T_h = d/45 + 400/40 + d/35 + 400/40 (Hauler speeds are the doc's; transfer from economy.json)."""
        rate = self.eco["hauler_transfer_per_s"]
        return d_m / speed_out + load / rate + d_m / speed_back + load / rate


class Field:
    def __init__(self, defs: Defs, spec: dict) -> None:
        node = defs.nodes[spec["node"]]
        self.name = spec["name"]
        self.d = float(spec["d"])
        self.refinery = spec["refinery"]
        self.cap = float(spec.get("capacity", node["capacity"]))
        self.regen = float(spec.get("regen_per_s", node["regen_per_s"]))
        self.amount = self.cap


class Harv:
    def __init__(self, name: str, field: Field, t: float, first_trip: bool) -> None:
        self.name, self.field, self.trips = name, field, 0
        self.state = "mine" if first_trip else "out"      # the start-kit Harvester is already mining Field A
        self.until = t
        self.load = 0.0
        self.take = 0.0


class Ship:
    def __init__(self, kind: str, born: float) -> None:
        self.kind, self.born, self.next_service = kind, born, None


class Pool:
    """The team stockpile (summed start Ore, caps from structure storage)."""

    def __init__(self) -> None:
        self.ore = self.ice = 0.0
        self.cap_ore = self.cap_ice = 0.0
        self.overflow = 0.0
        self.acc = dict(ore_in=0.0, ore_spent=0.0, ice_in=0.0, ice_out=0.0)

    def credit(self, ore: float, ice: float) -> None:
        self.acc["ore_in"] += ore
        self.acc["ice_in"] += ice
        self.ore += ore
        self.ice += ice
        if self.ore > self.cap_ore:
            self.overflow += self.ore - self.cap_ore
            self.ore = self.cap_ore
        if self.ice > self.cap_ice:
            self.overflow += self.ice - self.cap_ice
            self.ice = self.cap_ice


class Struct:
    def __init__(self, item_id: str, label: str, done: float) -> None:
        self.id, self.label, self.done = item_id, label, done


class Player:
    def __init__(self, sim: "Sim", spec: dict) -> None:
        self.sim, self.spec, self.name = sim, spec, spec["name"]
        self.steps = list(spec["steps"])
        self.ptr = 0
        self.blocked_since: float | None = None
        self.tail = spec.get("tail", {})
        self.tail_ptr = 0
        self.structs: list[Struct] = []
        self.busy: list[float] = []                      # construction slot end times
        self.queues: list[dict] = []                     # {"fac": id, "items": [[item, work_left, field, label]]}
        self.harvs: list[Harv] = []
        self.ships: list[Ship] = []
        self.fields = {f["name"]: Field(sim.defs, f) for f in spec["fields"]}
        self.extractors: list[dict] = []
        self.haulers: list[dict] = []
        self.next_loss: list[tuple[float, str]] = [(float(t), u) for t, u in spec.get("loss_script", [])]
        every = spec.get("loss_every")
        if every:
            t, i = float(every["from_s"]), 0
            while t < sim.book["duration_s"]:
                self.next_loss.append((t, sim.book["loss_cycle"][i % len(sim.book["loss_cycle"])]))
                t, i = t + every["every_s"], i + 1
        self.next_loss.sort()
        self.counters: dict[str, int] = {}
        for item_id in sim.defs.eco["start_kit"]:
            if item_id == "harvester":
                self.add_harvester(0.0, "A", first=True)
            else:
                self.add_struct(item_id, f"{self.name}.{item_id}_0", 0.0)

    def add_struct(self, item_id: str, label: str, done: float) -> Struct:
        s = Struct(item_id, label, done)
        self.structs.append(s)
        if item_id in ("shipyard", "vehicle_bay"):
            self.queues.append({"fac": item_id, "items": []})
        return s

    def finished(self, item_id: str, t: float) -> int:
        return sum(1 for s in self.structs if s.id == item_id and s.done <= t)

    def label_done(self, label: str, t: float) -> bool:
        return any(s.label == label and s.done <= t for s in self.structs)

    def add_harvester(self, t: float, field: str, first: bool = False) -> None:
        n = len(self.harvs) + 1 + self.counters.get("h_lost", 0)
        self.harvs.append(Harv(f"{self.name}.H{n}", self.fields[field], t, first))
        h, hd = self.harvs[-1], self.sim.defs.items["harvester"]
        h.until = t + (hd["cargo_ore"] / hd["mine_rate"] if first else h.field.d / hd["ground_speed"])

    def slots(self, t: float) -> int:
        d = self.sim.defs
        n = d.eco["construction_slots_base"] + self.finished("outpost", t)
        return min(n, d.eco["construction_slots_max"])

    def combat(self) -> int:
        queued = sum(1 for q in self.queues for it in q["items"] if it[0] in COMBAT)
        return sum(1 for s in self.ships if s.kind in COMBAT) + queued

    def count(self, item_id: str) -> int:
        """Alive + queued units, or structures placed (finished or not) of this id."""
        queued = sum(1 for q in self.queues for it in q["items"] if it[0] == item_id)
        if item_id == "harvester":
            return len(self.harvs) + queued
        if item_id in self.sim.defs.items and self.sim.defs.items[item_id]["kind"] == "structure":
            return sum(1 for s in self.structs if s.id == item_id)
        return sum(1 for s in self.ships if s.kind == item_id) + queued


def expand_player(book: dict, entry: dict) -> dict:
    """A player entry with a `template` takes the book's template with "{p}" replaced by its name; `step_overrides`
    ({step as: {key: value}}) patch single steps (e.g. the frontier Outposts at 4:19 / 4:31)."""
    if "template" not in entry:
        return entry
    spec = json.loads(json.dumps(book["templates"][entry["template"]]).replace("{p}", entry["name"]))
    spec["name"] = entry["name"]
    for k in ("loss_script", "loss_every"):
        if k in entry:
            spec[k] = entry[k]
    for step in spec["steps"]:
        step.update(entry.get("step_overrides", {}).get(step.get("as", ""), {}))
    return spec


class Sim:
    def __init__(self, book: dict, defs: Defs | None = None) -> None:
        self.defs = defs or Defs()
        self.book = book
        self.t = 0.0
        self.reserve = 0.0
        self.blocked_cost: float | None = None
        self.pool = Pool()
        self.players = [Player(self, expand_player(book, p)) for p in book["players"]]
        n = len(self.players)
        self.pool.ore = self.defs.eco["start_ore"] * n
        self.pool.ice = self.defs.eco["start_ice"] * n
        self.pool.cap_ore = self.pool.cap_ice = 1e18
        self.refresh_caps()
        self.events: list[tuple[float, str]] = []
        self.minutes: list[dict] = []
        self.power_log: dict[int, tuple] = {0: tuple(round(x) for x in self.power())}
        self.first_pad: float | None = None
        self.launch_delay = book.get("launch_delay_s", 3.0)
        self.min_load = book.get("hauler_min_load", 40.0)

    def log(self, label: str) -> None:
        self.events.append((round(self.t, 2), label))

    def event_time(self, label: str) -> float | None:
        for t, lab in self.events:
            if lab == label:
                return t
        return None

    def refresh_caps(self) -> None:
        so = si = 0.0
        for p in self.players:
            for s in p.structs:
                if s.done <= self.t:
                    so += self.defs.items[s.id].get("storage_ore", 0)
                    si += self.defs.items[s.id].get("storage_ice", 0)
        self.pool.cap_ore, self.pool.cap_ice = so, si

    def power(self) -> tuple[float, float]:
        sup = dem = 0.0
        for p in self.players:
            for s in p.structs:
                if s.done <= self.t:
                    w = self.defs.items[s.id].get("power", 0)
                    if w > 0:
                        sup += w
                    else:
                        dem -= w
        return sup, dem

    def speed(self) -> float:
        sup, dem = self.power()
        ratio = 1.0 if dem <= 0 else min(1.0, sup / dem)
        return max(self.defs.eco["production_min_speed"], ratio)

    # -- world advance ----------------------------------------------------------------------------------------------
    def advance(self) -> None:
        t = self.t
        eco = self.defs.eco
        self.pool.credit(eco["core_trickle_ore_per_s"] * DT * len(self.players), 0.0)
        speed = self.speed()
        for p in self.players:
            self.advance_player(p, t, speed)
        self.refresh_caps()

    def advance_player(self, p: Player, t: float, speed: float) -> None:
        for s in p.structs:
            if s.done > t - DT and s.done <= t and not getattr(s, "logged", False) and s.done > 0:
                s.logged = True                                    # type: ignore[attr-defined]
                self.log(f"{s.label}.done")
                if s.id == "pad" and self.first_pad is None:
                    self.first_pad = s.done
        for q in p.queues:
            if q["items"] and q["items"][0][1] is not None:
                q["items"][0][1] -= DT * speed
                if q["items"][0][1] <= 0:
                    item, _, field, label = q["items"].pop(0)
                    self.complete_unit(p, item, field, label)
                    if q["items"]:
                        q["items"][0][1] = self.defs.items[q["items"][0][0]]["build_time_s"]
        self.advance_harvesters(p, t)
        self.advance_ice(p, t)
        self.advance_services(p, t)
        self.advance_losses(p, t)

    def complete_unit(self, p: Player, item: str, field: str | None, label: str) -> None:
        t = self.t
        self.log(f"{label}.done")
        if item == "harvester":
            p.add_harvester(t, field or "A")
            self.log(f"{p.harvs[-1].name}.created")
        elif item == "hauler":
            p.haulers.append({"state": "idle", "until": t, "load": 0.0, "ext": None})
        else:
            p.ships.append(Ship(item, t))
            if item in COMBAT:
                self.events.append((round(t + self.launch_delay, 2), f"{label}.airborne"))

    def advance_harvesters(self, p: Player, t: float) -> None:
        h_def = self.defs.items["harvester"]
        for h in p.harvs:
            f = h.field
            f.amount = min(f.cap, f.amount + f.regen * DT) if f.amount < f.cap else f.amount
            while h.until <= t:
                if h.state == "out":
                    h.state, h.until = "mine", h.until + 0.0
                    h.take = 0.0
                    h.until += h_def["cargo_ore"] / h_def["mine_rate"]
                elif h.state == "mine":
                    h.load = min(h_def["cargo_ore"], f.amount)
                    f.amount -= h.load
                    h.state, h.until = "back", h.until + f.d / h_def["ground_speed_loaded"]
                elif h.state == "back":
                    if not p.label_done(f.refinery, t):
                        h.until = t + DT
                        break
                    h.state, h.until = "unload", h.until + h_def["unload_time_s"]
                elif h.state == "unload":
                    self.pool.credit(h.load, 0.0)
                    h.trips += 1
                    self.log(f"{h.name}.delivery.{h.trips}")
                    h.load = 0.0
                    h.state, h.until = "out", h.until + f.d / h_def["ground_speed"]

    def advance_ice(self, p: Player, t: float) -> None:
        rate_x = self.defs.eco["hauler_transfer_per_s"]
        for e in p.extractors:
            if e["done"] <= t and e["amount"] > 0:
                add = min(e["rate"] * DT, e["amount"])
                e["amount"] -= add
                if e["piped"]:
                    self.pool.credit(0.0, add)
                else:
                    e["buffer"] = min(e["buffer_cap"], e["buffer"] + add)
        for hl in p.haulers:
            if hl["state"] == "idle":
                cand = [e for e in p.extractors if e["done"] <= t and not e["piped"] and e["buffer"] >= self.min_load
                        and not e.get("claimed")]
                if cand:
                    e = cand[0]
                    e["claimed"] = True
                    hl.update(state="out", ext=e, until=t + e["haul_d"] / 45.0)
            elif hl["until"] <= t:
                e = hl["ext"]
                if hl["state"] == "out":
                    hl["load"] = min(e["buffer"], 400.0)
                    e["buffer"] -= hl["load"]
                    hl.update(state="back", until=t + hl["load"] / rate_x + e["haul_d"] / 35.0)
                elif hl["state"] == "back":
                    hl.update(state="unload", until=t + hl["load"] / rate_x)
                elif hl["state"] == "unload":
                    self.pool.credit(0.0, hl["load"])
                    self.log(f"{p.name}.ice_delivery")
                    e["claimed"] = False
                    hl.update(state="idle", load=0.0, ext=None)

    def advance_services(self, p: Player, t: float) -> None:
        svc = self.book["service"]
        if self.first_pad is None:
            return
        for s in p.ships:
            if s.kind not in svc:
                continue
            if s.next_service is None:
                s.next_service = max(s.born + svc[s.kind]["period_s"], self.first_pad)
            if s.next_service <= t and self.pool.ice >= svc[s.kind]["ice"] and self.pool.ore >= svc[s.kind]["ore"]:
                self.pool.ice -= svc[s.kind]["ice"]
                self.pool.ore -= svc[s.kind]["ore"]
                self.pool.acc["ice_out"] += svc[s.kind]["ice"]
                self.pool.acc["ore_spent"] += svc[s.kind]["ore"]
                s.next_service = t + svc[s.kind]["period_s"]

    def advance_losses(self, p: Player, t: float) -> None:
        while p.next_loss and p.next_loss[0][0] <= t:
            _, unit = p.next_loss.pop(0)
            self.lose(p, unit, t)

    def lose(self, p: Player, unit: str, t: float) -> None:
        if unit == "harvester":
            if p.harvs:
                p.harvs.pop()
                p.counters["h_lost"] = p.counters.get("h_lost", 0) + 1
        else:
            for s in p.ships:
                if s.kind == unit:
                    p.ships.remove(s)
                    break
        self.log(f"{p.name}.lost.{unit}")

    # -- the bot ---------------------------------------------------------------------------------------------------
    def can_pay(self, item: dict) -> bool:
        """Pool can pay after the Ore reserved by teammates whose head step has waited longer (shared-pool fairness)."""
        ok = self.pool.ore - self.reserve >= item["cost_ore"] and self.pool.ice >= item.get("cost_ice", 0)
        if not ok:
            self.blocked_cost = item["cost_ore"]
        return ok

    def pay(self, item: dict) -> None:
        self.pool.ore -= item["cost_ore"]
        self.pool.ice -= item.get("cost_ice", 0)
        self.pool.acc["ore_spent"] += item["cost_ore"]
        self.pool.acc["ice_out"] += item.get("cost_ice", 0)

    def prereq_ok(self, p: Player, item: dict, step: dict) -> bool:
        t = self.t
        for r in item.get("requires", []):
            if p.finished(r, t):
                continue
            pending = any(s.id == r for s in p.structs)
            if not pending:
                raise BookError(f"{p.name}: step '{step.get('as', step['id'])}' needs '{r}', which is never placed before it")
            return False
        return True

    def run_step(self, p: Player, step: dict) -> bool:
        """Try one step now. True when it was executed."""
        t = self.t
        if t < step.get("not_before_s", 0.0):
            return False
        after = step.get("after")
        if after and not any(s.label == after and s.done <= t for s in p.structs):
            return False
        item = self.defs.item(step["id"])
        if not self.prereq_ok(p, item, step):
            return False
        label = step.get("as") or self.auto_label(p, step["id"])
        if step["do"] == "build":
            return self.do_build(p, step, item, label)
        if step["do"] == "produce":
            return self.do_produce(p, step, item, label)
        raise BookError(f"unknown action '{step['do']}'")

    def auto_label(self, p: Player, item_id: str) -> str:
        p.counters[item_id] = p.counters.get(item_id, 0) + 1
        return f"{p.name}.{item_id}{p.counters[item_id]}"

    def do_build(self, p: Player, step: dict, item: dict, label: str) -> bool:
        t = self.t
        p.busy = [b for b in p.busy if b > t]
        if len(p.busy) >= p.slots(t):
            return False
        if not self.can_pay(item):
            return False
        self.pay(item)
        done = t + item["build_time_s"]
        p.busy.append(done)
        p.add_struct(step["id"], label if "." in label else f"{p.name}.{label}", done)
        self.log(f"{p.structs[-1].label}.placed")
        if step["id"] == "ice_extractor":
            node = self.defs.nodes[step["node"]]
            p.extractors.append(dict(done=done, rate=node["rate_per_s"], amount=float(node["capacity"]),
                                     buffer=0.0, buffer_cap=float(item["buffer_ice"]), piped=bool(step.get("piped")),
                                     haul_d=float(step.get("haul_d", 0.0))))
        return True

    def do_produce(self, p: Player, step: dict, item: dict, label: str) -> bool:
        if step["id"] in ("harvester",):
            fac = "vehicle_bay"
        else:
            fac = item["produced_at"]
        qs = [q for q in p.queues if q["fac"] == fac and p.finished(fac, self.t) > 0]
        qs = [q for q in qs if len(q["items"]) < self.defs.eco["queue_max"]]
        if not qs or not self.can_pay(item):
            return False
        q = min(qs, key=lambda x: len(x["items"]))
        self.pay(item)
        label = label if "." in label else f"{p.name}.{label}"
        q["items"].append([step["id"], float(item["build_time_s"]) if not q["items"] else None, step.get("field"), label])
        self.log(f"{label}.queued")
        return True

    def tail_step(self, p: Player) -> dict | None:
        tl = p.tail
        if not tl:
            return None
        cyc = tl["cycle"]
        for _ in range(len(cyc)):
            s = cyc[p.tail_ptr % len(cyc)]
            if self.tail_skip(p, s):
                p.tail_ptr += 1
                continue
            return s
        return None

    def tail_skip(self, p: Player, s: dict) -> bool:
        if "max_alive" in s and p.count(s["id"]) >= s["max_alive"]:
            return True
        if s.get("ceiling"):
            rate = sum(e["rate"] for e in p.extractors if e["done"] <= self.t)
            return p.combat() >= max(p.tail.get("ceiling_floor", 0), rate * 60.0 / p.tail.get("ceiling_div", 8))
        return False

    def act(self) -> None:
        """Players act longest-blocked first; a player blocked on Ore reserves that Ore against the players after it."""
        self.reserve = 0.0
        order = sorted(range(len(self.players)),
                       key=lambda i: (self.players[i].blocked_since is None, self.players[i].blocked_since or 0.0, i))
        for i in order:
            p = self.players[i]
            self.blocked_cost = None
            for _ in range(8):
                if p.ptr < len(p.steps):
                    if self.run_step(p, p.steps[p.ptr]):
                        p.ptr += 1
                        p.blocked_since = None
                        continue
                    break
                s = self.tail_step(p)
                if s is None or not self.run_step(p, s):
                    break
                p.tail_ptr += 1
                p.blocked_since = None
            if self.blocked_cost is not None:
                if p.blocked_since is None:
                    p.blocked_since = self.t
                self.reserve += self.blocked_cost

    # -- snapshots -------------------------------------------------------------------------------------------------
    def snapshot(self, minute: int) -> None:
        sup, dem = self.power()
        a = self.pool.acc
        self.minutes.append(dict(
            minute=minute, ore=round(self.pool.ore), ice=round(self.pool.ice),
            harvesters=sum(len(p.harvs) for p in self.players), ships=sum(sum(1 for x in p.ships if x.kind in COMBAT) for p in self.players),
            ore_in=round(a["ore_in"]), ore_spent=round(a["ore_spent"]), ice_in=round(a["ice_in"]),
            ice_out=round(a["ice_out"]), power=(round(sup), round(dem))))
        for k in a:
            a[k] = 0.0

    def run(self) -> "Sim":
        total = self.book["duration_s"]
        self.snapshot(0)
        steps = int(round(total / DT))
        for i in range(1, steps + 1):
            self.t = round(i * DT, 4)
            self.advance()
            self.act()
            if i % int(30 / DT) == 0:
                self.power_log[int(self.t)] = tuple(round(x) for x in self.power())
            if i % int(60 / DT) == 0:
                self.snapshot(i // int(60 / DT))
        return self


def load_book(name: str) -> dict:
    return json.loads((BOOKS / f"{name}.json").read_text(encoding="utf-8"))


def run_book(name: str) -> Sim:
    return Sim(load_book(name)).run()


def fmt_t(t: float) -> str:
    return f"{int(t // 60)}:{int(t % 60):02d}"


def main(argv: list[str] | None = None) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))   # survives `python -I`, which drops the script dir
    import econ_compare
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--match", choices=("1v1", "4v4", "all"), default="all")
    ap.add_argument("--minutes", action="store_true", help="print the model minute table")
    ap.add_argument("--log", action="store_true", help="print the model event log")
    ap.add_argument("--json", action="store_true", help="print the comparison as JSON")
    ap.add_argument("--check", action="store_true", help="exit 1 when any number misses its tolerance")
    args = ap.parse_args(argv)
    matches = ("1v1", "4v4") if args.match == "all" else (args.match,)
    misses = 0
    out: dict[str, list] = {}
    for m in matches:
        try:
            sim = run_book(m)
        except BookError as exc:
            print(f"econ_model: book {m}: {exc}", file=sys.stderr)
            return 2
        rows = econ_compare.compare(m, sim)
        out[m] = rows
        misses += sum(1 for r in rows if not r["ok"])
        if not args.json:
            print(econ_compare.render(m, sim, rows, args.minutes, args.log))
    if args.json:
        print(json.dumps(out, indent=1))
    return 1 if (args.check and misses) else 0


if __name__ == "__main__":
    sys.exit(main())
