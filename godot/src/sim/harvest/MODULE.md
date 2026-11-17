# sim/harvest - MODULE.md

Contract for `godot/src/sim/harvest/**`: Ore Fields and the Harvester cycle of tick-order step 10 (GD-12; 02 s8.2, 05 s6.6),
Cold Traps, Ice Extractor buffers, the Refinery pipe and Hauler transfer (GD-14; 02 s8.3); A-21 split of `sim/MODULE.md`. A change to "Public API" or "Invariants" is a contract change: contract tests first,
same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | The Ore Fields of a match (capacity, regen, radius, `max_miners`, Ore left), regen that stops at Core Exposure, mining while a Harvester stands still in a field with a free miner slot, and unloading at a friendly finished Refinery's docks over `unload_time_s`, credited through `Economy.credit`. Not here: driving (the autopilot writes the input slot, `GroundMotion` moves the unit), choosing a field (`sim_ai` `HarvestPicker`), the dock queue wait beyond "WAITING until a dock is free". `SimWorld.load_map` loads the fields (`OreFields.load_map_dir`). **Ice (GD-14):** the Cold Traps of a match (`IceNodes`: capacity, `rate_per_s`, `radius_m`, Ice left, no regen), a finished Ice Extractor on one filling its `buffer_ice` at the node rate, a friendly finished Refinery within its `pipe_radius_m` piping that buffer into the stockpile continuously, and a Hauler moving `hauler_transfer_per_s` Ice per second from an Extractor buffer into its hold and from its hold into the stockpile at a friendly Refinery. Not here: choosing a trap or a trip (`sim_ai` Hauler brain, 05), Relay capture (GD-23; the Relay Station pad services the holder through `sim/docking/` unchanged, test I8), any `SimView` read of a node (the buffer is `SimView.cargo(extractor)`). |
| Lane owner tier | Sonnet against this file (Opus review) |
| May depend on | `core`, `content`, `sim` (incl. `sim/world/`: `WorldDefs`, `StateIO`, `InputSlots`; `sim/economy/` `Economy`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (GD-12, 2026-11-05); `EconomyHub.harvest.step` runs in step 10 after docking service; `SimSerialize.FORMAT` 15. GD-14 (2026-11-16): `EconomyHub.ice.step` runs right after it; `SimSerialize.FORMAT` 16 |

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

class_name IceNodes extends RefCounted                                       # GD-14; one table per world: `EconomyHub.ice.nodes`
var dirs: PackedVector3Array;  var capacity: PackedInt32Array;  var amount: PackedFloat32Array   # per node index (map file order)
var rate_per_s: PackedFloat32Array;  var radius_m: PackedFloat32Array
func add(dir: Vector3, cap: int, rate: float, radius: float) -> int          # a full node; its index
func load_map_dir(map_dir: String) -> int                                    # clears, then loads `<dir>/features.json` `cold_trap` nodes (SimWorld.load_map calls it; -1 when unreadable)
func clear() -> void;  func load_nodes(nodes: Array) -> int                  # the `cold_trap` nodes in file order; count added
func count() -> int;  func remaining(i: int) -> int;  func capacity_of(i: int) -> int;  func rate_of(i: int) -> float;  func radius_of(i: int) -> float;  func dir_of(i: int) -> Vector3
func node_at(dir: Vector3) -> int                                            # nearest node whose radius contains `dir`, else -1
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # S4: the whole table (self-describing)

class_name IceExtract extends RefCounted                                     # GD-14; EconomyHub.ice, step 10 after Harvest
var nodes: IceNodes;  var ship_scans: int                                    # ship_scans: diagnostic hard counter, not state
func _init(store: EntityStore, defs: WorldDefs, economy: Economy, score: ScoreKeeper)   # score may be null (no result counters)
func step(dt: float) -> void                                                 # Extractors in ascending slot order, then Haulers in ascending slot order
func refinery_for(extractor: int) -> int                                     # slot of the friendly finished Refinery piping this Extractor, -1 for none
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

- I1 Nodes (02 s8.3, s9). A node index is the order of the map's `cold_trap` nodes in features.json; `amount` starts at `capacity`,
  stays within [0, capacity], and never regenerates ("Ice does not regenerate"); the only writers are `IceExtract.step` and `read_state`.
  `SimWorld.load_map` of a map id calls `nodes.load_map_dir` (the flat datum has none). Test: `test_ice_nodes.gd`.
- I2 Extractor. A finished (`F_BUILDING` clear), living structure whose def has `buffer_ice` > 0 and whose centre direction lies in a
  node (`node_at`) takes `min(rate_per_s x dt, amount, buffer_ice - cargo)` from the node into its own `cargo` every tick
  (`cargo_kind` ICE (2) while `cargo` > 0); the buffer never passes `buffer_ice` (400). An Extractor in no node, or on an empty one, takes nothing.
  The buffer is `SimView.cargo(extractor)`; a dying Extractor loses it.
- I3 Pipe (02 s8.3). An Extractor with a friendly finished living structure whose def has `docks` > 0 (the Refinery) within that def's
  `pipe_radius_m` (centre distance) is piped: each tick the whole Ice in its buffer, `floor(cargo)`, goes to the stockpile through
  `Economy.credit(team, 0, n, owner)`, at most the room under the Ice cap (nothing is lost: a full stockpile leaves the Ice in the buffer, which
  then fills to `buffer_ice` and stops the node). A piped Extractor therefore credits the node rate: 0.8 Ice/s at the Home Cold Trap
  (100 s -> 80 Ice, +-1). An enemy Refinery, a site and a dead one do not pipe; beyond the radius the buffer fills and Haulers carry it (I4).
- I4 Hauler load. A ship whose resolved def has `cargo_ice` > 0 (the Hauler), within `radius(extractor) + salvage_deliver_m` (centre
  distance, the reach of GD-12 / W8) of a friendly finished Extractor with Ice in its buffer, and not in the reach of a friendly
  Refinery while it holds Ice (I5 wins), takes `min(hauler_transfer_per_s x dt, buffer, cargo_ice - cargo)` from the buffer into its own `cargo` (`cargo_kind`
  ICE). One Extractor per Hauler per tick (the first in ascending slot order). 40 Ice/s: 400 Ice in 10 s.
- I5 Hauler unload. The same ship with `cargo` > 0 within `radius(refinery) + salvage_deliver_m` of a friendly finished living
  structure with `docks` > 0 moves `min(hauler_transfer_per_s x dt, cargo, Ice room)` into the stockpile: the credit is `roundi(before) - roundi(after)`
  of the hold (whole Ice, sums to `roundi(load)`), `Economy.credit(team, 0, n, owner)`, `ScoreKeeper.ice_delivered(owner, n, possessed)` (a
  possessed Hauler scores the Pilot side). `cargo_kind` goes to 0 when the hold is empty. A full stockpile leaves the hold as it is.
  A Hauler towing a wreck is unaffected (a wreck's Ore is `cargo` of the wreck, Salvage).
- I6 Teams. Only the Hauler's own team's Extractors and Refineries count in I3-I5.
- I7 State (S4). `IceNodes.amount` with its table is the only state outside `EntityStore` (written after the Ore Fields in the economy
  section, `SimSerialize.FORMAT` 16); buffers and holds are `cargo` / `cargo_kind`; the Extractor, Refinery and node lookups are derived
  each pass (the Refinery and Extractor lists are rebuilt when `Economy.structure_epoch` or the structure count moves).
- I8 Relay pad service (02 s5.3, s2.3). The Relay Station def is a service pad (`pads` 1, `pad_radius_m` 12); a ship docked on one held by its
  own team is served at the normal costs, a ship of another team is not. The capture that sets the holder is GD-23 (`sim/relay/`); a capturer may land on a pad it does not hold (R0 B.30 A-146) and `Docking` serves only ships of the pad's team (docking D14, A-147). Test: `test_relay_pad_service.gd`.
- I9 Cost. `step` returns at once with no Extractor and no ship carrying Ice (a count of Ice holds, re-counted when the ship count changes; `IceExtract.ship_scans` counts the ship passes run). Otherwise one pass over the Extractors and one over the ships;
  no Dictionary, no per-entity allocation. Test: `test_ice_perf.gd` (PerfGate).

## Data owned

`OreFields` (the field table and Ore left; saved), `IceNodes` (the Cold Trap table and Ice left; saved), the derived Refinery / Extractor lists and dock counts (not saved).

## Events emitted / consumed

None. Consumes nothing.

## Performance budget

03 s4.2 row 10 (economy / production / build; the Economy row of `TickProfiler`, budget 0.8 ms). 200 ground units
(Harvesters) cost two small passes per tick: bound in `test_harvest_perf.gd` (PerfGate; hard counters on the pass, see the PR).

## Test entry points

`godot/test/unit/sim/harvest/test_ore_fields.gd` (H1, H2, H8: table, load_nodes, field_at, regen, Exposure stop, state bytes, `field_remaining`),
`test_harvest_cycle.gd` (H3-H8: trip time at 450 / 600 m, `max_miners`, slot freeing, depletion, docks, enemy Refinery, Exposure leaves mining, S4 mid-cycle),
`test_harvest_map.gd` (H1a), `test_harvest_perf.gd` (H9). GD-14: `test_ice_nodes.gd` (I1, I7), `test_ice_extract.gd` (I2-I7), `test_relay_pad_service.gd` (I8), `test_ice_perf.gd` (I9); fixtures `ice_test_kit.gd`. Fixtures: `harvest_test_kit.gd` (flat-datum world, field / Refinery / Harvester by metres of arc, a straight-line stand-in driver).

## How to add X (recipes for the cheapest tier)

- **A field from a map:** add an `ore_field` node to the recipe's features.json; `SimWorld.load_map` loads it (table cleared first,
  so a second load or a restore never doubles it; `deserialize` then replaces it with the saved table, H8). Test: `test_harvest_map.gd`.
- **A Cold Trap from a map:** add a `cold_trap` node (`capacity`, `rate_per_s`, `radius_m`) to features.json; `load_map` loads it. Test: `test_ice_nodes.gd`.
- **A second Refinery-like structure:** give its def `docks` > 0 in `structures.json`; nothing else.
