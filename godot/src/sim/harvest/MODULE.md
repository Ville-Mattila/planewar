# sim/harvest - MODULE.md

Contract for `godot/src/sim/harvest/**`: Ore Fields and the Harvester cycle of tick-order step 10 (GD-12; 02 s8.2, 05 s6.6;
A-21 split of `sim/MODULE.md`). A change to "Public API" or "Invariants" is a contract change: contract tests first,
same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | The Ore Fields of a match (capacity, regen, radius, `max_miners`, Ore left), regen that stops at Core Exposure, mining while a Harvester stands still in a field with a free miner slot, and unloading at a friendly finished Refinery's docks over `unload_time_s`, credited through `Economy.credit`. Not here: driving (the autopilot writes the input slot, `GroundMotion` moves the unit), choosing a field (`sim_ai` `HarvestPicker`), the dock queue wait beyond "WAITING until a dock is free" and Ice extraction / Haulers. `SimWorld.load_map` loads the fields (`OreFields.load_map_dir`). |
| Lane owner tier | Sonnet against this file (Opus review) |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/`: `WorldDefs`, `StateIO`, `InputSlots`; `sim/economy/` `Economy`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (GD-12, 2026-11-05); `EconomyHub.harvest.step` runs in step 10 after docking service; `SimSerialize.FORMAT` 15 |

## Public API

```gdscript
class_name OreFields extends RefCounted                                      # one table per world: `EconomyHub.harvest.fields`
var dirs: PackedVector3Array;  var capacity: PackedInt32Array;  var amount: PackedFloat32Array    # per field index (map file order)
var regen_per_s: PackedFloat32Array;  var radius_m: PackedFloat32Array;  var max_miners: PackedInt32Array
var miners: PackedInt32Array                                                 # derived by Harvest each step, never saved
func add(dir: Vector3, cap: int, regen_rate: float, radius: float, miners_max: int) -> int   # a full field; its index
func load_map_dir(map_dir: String) -> int                                    # clears, then loads `<dir>/features.json` nodes (SimWorld.load_map calls it; -1 when unreadable)
func clear() -> void
func load_nodes(nodes: Array) -> int                                         # the `ore_field` nodes of a map's features.json, in file order; count added
func count() -> int;  func remaining(i: int) -> int;  func capacity_of(i: int) -> int;  func radius_of(i: int) -> float
func max_miners_of(i: int) -> int;  func miners_of(i: int) -> int;  func dir_of(i: int) -> Vector3
func field_at(dir: Vector3) -> int                                           # nearest field whose radius contains `dir`, else -1
func regen(dt: float) -> void                                                # below capacity only, clamped to it
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # S4: the whole table (self-describing)

class_name Harvest extends RefCounted                                        # GD-12; EconomyHub.harvest, step 10
enum State { TRAVEL = 0, MINING = 1, WAITING = 2, UNLOADING = 3 }
var fields: OreFields
func _init(store: EntityStore, defs: WorldDefs, rules: MatchRules, economy: Economy)
func step(t: int, dt: float) -> void                                         # regen (PLAYING only), then every Harvester in ascending slot order
static func state_of(link: int) -> State;  static func index_of(link: int) -> int;  static func pack(state: State, index: int) -> int
# Reads: `SimView.field_remaining(node)` = `OreFields.remaining(node)` (0 out of range); `SimView.link(id)` of a Harvester = `pack(state, index)`
```

Field numbers come from the map recipe (02 s9: `capacity`, `regen_per_s`, `radius_m`, `max_miners`); the Harvester's from
`ground_units.json` (`cargo_ore`, `mine_rate`, `unload_time_s`, resolved per owner, so Foundry's +25 % cargo applies) and the
dock count from `structures.json` `docks`; the delivery reach is `economy.json` `salvage_deliver_m` (A-105), shared with salvage.

## Invariants

- H1 Table. A field index is the order of the map's `ore_field` nodes (`SimView.field_remaining(node)` uses it). `amount` starts at
  `capacity`, stays within [0, capacity]; the only writers are `Harvest.step` (regen, mining) and `read_state`.
- H2 Regen. Each tick a field below capacity gains `regen_per_s x dt`, never past capacity, and only while
  `MatchRules.phase(t) == PLAYING`: it stops at Core Exposure (and at ENDED) and does not resume (02 s8.2).
- H3 Claim. A Harvester (a K_GROUND unit whose resolved def has `mine_rate` > 0 and `cargo_ore` > 0) that is stopped
  (`vel` is zero, which `GroundMotion` writes for a stopped unit), not full, and inside a field's `radius_m` claims a mining slot when the
  field has `miners < max_miners` and at least 1 Ore left: `link` = `pack(MINING, field)`. Slots go in ascending unit slot
  order within a pass; a claim is kept until it ends (the unit moves, is full, or the field is empty), so an earlier arrival is never evicted.
  Ground units hold no other use of `link`.
- H4 Mining. A MINING unit that is stopped takes `min(mine_rate x dt, cargo_ore - cargo, amount)` from the field into `cargo`
  every tick (`cargo_kind` = ORE while `cargo` > 0). It ends (`link` 0 = TRAVEL, slot freed) when full or when the field is
  empty: a partial load is kept (02 s8.2 "takes what is there") and the autopilot re-targets (`HarvestPicker`); it also ends the tick the unit moves.
  A moving unit never mines.
- H5 Docks. A stopped unit with `cargo` > 0 within `radius(refinery) + salvage_deliver_m` (centre distance) of a friendly,
  finished, living structure with `docks` > 0 takes that Refinery (the first in reach with a free dock, else the first in
  reach) and is WAITING; it becomes UNLOADING when fewer than `docks` units are UNLOADING there (ascending unit slot order), with
  `timer_a` = `unload_time_s x cargo / cargo_ore` seconds. A Refinery that is gone, an enemy's, or a unit that moves, drops the unit to
  TRAVEL with its cargo kept.
- H6 Delivery. When `timer_a` reaches 0 the unit's whole `cargo` is credited: `Economy.credit(team, round(cargo), 0, owner)` (the cap
  clamps; the `Build.delivered_ore` ledger counts what fit), `cargo` and `cargo_kind` go to 0, TRAVEL. No event: score and
  stockpile pick it up from the ledger. A unit that dies loses its cargo and its claim (miners and docks are re-counted from the units each pass).
- H7 Trip time. With a unit that drives straight and stops at once (the test stand-in), the measured interval between two deliveries at
  `d` = 450 m and 600 m is within 5 % of `Economy.harvest_trip_time(d)` (02 s8.2: 108.5 s, 136.0 s); the cycle adds no time beyond the
  four terms of the formula (`mine` = `cargo_ore / mine_rate` stationary, `unload_time_s` stationary).
- H8 State (S4). The only state outside `EntityStore` is `OreFields.amount` with its table, written after the ScoreKeeper in the
  economy section (`SimSerialize.FORMAT` 15); the table is saved whole so a restored world needs no loader. Unit state is `link`,
  `cargo`, `cargo_kind`, `timer_a`; `miners` and the per-Refinery dock counts are re-derived every pass.
- H1a Loading. `SimWorld.load_map` of a map id calls `fields.load_map_dir` after terrain and path grid: the field table equals the
  `ore_field` nodes of features.json, each full; the flat datum (no map id) has none. Test: `test_harvest_map.gd`.
- H9 Cost. `step` returns at once with no ground unit and no field. Otherwise one pass over the ground units (twice) and the fields;
  the Refinery list is rebuilt only when `Economy.structure_epoch` or the structure count moves. No Dictionary, no per-unit allocation.

## Data owned

`OreFields` (the field table and Ore left; saved), the derived Refinery list and dock counts (not saved).

## Events emitted / consumed

None. Consumes nothing.

## Performance budget

03 s4.2 row 10 (economy / production / build; the Economy row of `TickProfiler`, budget 0.8 ms). 200 ground units
(Harvesters) cost two small passes per tick: bound in `test_harvest_perf.gd` (PerfGate; hard counters on the pass, see the PR).

## Test entry points

`godot/test/unit/sim/harvest/test_ore_fields.gd` (H1, H2, H8: table, load_nodes, field_at, regen, Exposure stop, state bytes, `field_remaining`),
`test_harvest_cycle.gd` (H3-H8: trip time at 450 / 600 m, `max_miners`, slot freeing, depletion, docks, enemy Refinery, Exposure leaves mining, S4 mid-cycle),
`test_harvest_map.gd` (H1a), `test_harvest_perf.gd` (H9). Fixtures: `harvest_test_kit.gd` (flat-datum world, field / Refinery / Harvester by metres of arc, a straight-line stand-in driver).

## How to add X (recipes for the cheapest tier)

- **A field from a map:** add an `ore_field` node to the recipe's features.json; `SimWorld.load_map` loads it (table cleared first,
  so a second load or a restore never doubles it; `deserialize` then replaces it with the saved table, H8). Test: `test_harvest_map.gd`.
- **A second Refinery-like structure:** give its def `docks` > 0 in `structures.json`; nothing else.
