# sim/pathing - MODULE.md

Contract for `godot/src/sim/pathing/**`: the time-sliced A* of ADR-05 / 03 s3.6 / R0 C1-05 (S-NAV-1 = TA-20).
R0 B.9 A-21 split: `Pathing`'s cross-lane surface (`request`, `result`, `set_weight`, `weight`; R0 B.5) is also listed
in `sim/MODULE.md`; everything else here is lane-internal. A change to "Public API" or "Invariants" is a contract
change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Ground-unit routes on the 6 x 256^2 path grid: baked weights (`face<f>.path.u8`), per-cell max slope from `Terrain`, per-face change counters, a ticketed FIFO queue advanced once per tick (step 3b) under `rules.path_expansions_per_tick`, a region hierarchy (connected parts of 16 x 16-cell clusters) that proves NO_PATH and confines the cell search to a corridor, and the route cache for Harvester loops. Not: following a path (05 `sim_ai`), ground motion (TA-38), choosing goals. |
| Lane owner tier | Opus (sim lane); Sonnet for recipes against this file |
| May depend on | `core`, `sim` (`Terrain`; R0 B.4: inside the sim module) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, clocks, RNG (D2, D3) |
| Autoloads used | None |
| Status | implemented (TA-20 spike, S-NAV-1 partial pass ratified by R0 B.11 A-55: regions hierarchy, metre cost with the inflated great-circle heuristic, weights 0 and 255 both impassable, `path_expansions_per_tick` 120, cut rung 8 = 60); wired by TA-50 (2026-10-14): `SimWorld` step 3b, `CommandSinkBase.pathing()`, S4 bytes, memory 8.8 -> 5.7 MB (u8 tags, u8 parent index, no arc tables; ticket pool split into `PathTickets`) |

## Public API

`Pathing` is the only class other code should name; the rest is internal to this folder (public for tests and the
`godot/spikes/s_nav_1` harness). Masks: bits 0-7 = the unit's `max_slope_deg` in whole degrees (`mask_for`), 0 = no
slope limit (weights only).

```gdscript
class_name PathTickets extends RefCounted                                    # ticket pool + FIFO ring; Pathing's base (own-member access, P8)
const NO_TICKET: int; const ST_UNKNOWN: int; const ST_PENDING: int; const ST_DONE: int; const ST_NO_PATH: int
const MAX_TICKETS: int; const MAX_CELLS: int
func status(ticket: int) -> int;  func done_tick(ticket: int) -> int;  func request_tick(ticket: int) -> int
func release(ticket: int) -> void;  func pending() -> int
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # S4: slots, ring, result cells

class_name Pathing extends PathTickets                                       # _init(expansions: int) = rules.path_expansions_per_tick
const JOB_COST: int
var expansions_per_tick: int; var hier_min_cells: int; var grid: PathLabel; var clusters: PathClusters; var cache: PathCache
var ticks: int; var requests: int; var cache_hits: int; var splice_misses: int; var fallbacks: int
var expansions_total: int; var abstract_units: int
func load_weights(map_dir: String) -> Error;  func set_weights(bytes: PackedByteArray) -> bool
func set_terrain(t: Terrain) -> void;  func override_slope(cell: int, slope_deg: int) -> void;  func prepare(mask: int) -> void
func set_heuristic_pct(pct: int) -> void;  static func mask_for(max_slope_deg: float) -> int
static func from_rules(rules: RulesDef) -> Pathing                           # (TA-49) rules.path_expansions_per_tick + path_heuristic_pct (A-51)
func request(from: Vector3, to: Vector3, mask: int) -> int                   # R0 B.5; NO_TICKET when 160 are pending
func result(ticket: int) -> PackedVector3Array;  func result_cells(ticket: int) -> PackedInt32Array
func advance() -> int                                                        # step 3b, once per tick; returns units spent
func set_weight(cell: int, w: int) -> void;  func weight(cell: int) -> int;  func version(face: int) -> int
func baked_weight(cell: int) -> int                                          # P10 (GD-39): the loaded map's bake weight of a cell, from the in-memory bake; 1 on the flat datum
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # S4 (TA-50): needs the same map loaded

class_name PathGrid extends RefCounted                                       # weights, slopes, versions, centres, neighbours
const N: int; const SHIFT: int; const LOW: int; const FACES: int; const CELLS: int
const W_BLOCKED: int; const W_ZERO: int; const SLOPE_UNKNOWN: int; const SLOPE_NO_LIMIT: int
var weights: PackedByteArray; var slope_q: PackedByteArray; var face_version: PackedInt32Array; var nb: PackedInt32Array
var terrain: Terrain; var weights_custom: bool; var slopes_custom: bool        # S4 writes weights / slope_q only when set
func set_weights(bytes: PackedByteArray) -> bool;  func set_terrain(t: Terrain) -> void;  func version_of(face: int) -> int
static func read_faces(map_dir: String) -> PackedByteArray
func center_dir(cell: int) -> Vector3;  static func cell_of(p: Vector3) -> int;  static func cluster_of(cell: int) -> int
func passable(cell: int, limit_q: int) -> bool;  func neighbours(cell: int) -> void;  func sample_slope(cell: int) -> int
func override_slope(cell: int, slope_deg: int) -> void;  static func limit_q_of(mask: int) -> int
func set_weight(cell: int, w: int) -> bool;  static func blocks(w: int) -> bool;  func version_sum(face_bits: int) -> int
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # face counters, changed weights / slopes
static func put_z(buf: StreamPeerBuffer, bytes: PackedByteArray) -> void;  static func get_z(buf: StreamPeerBuffer, size: int) -> PackedByteArray

class_name PathSearch extends PathGrid                                       # resumable cell A*, one in flight
const RUNNING: int; const FOUND: int; const EXHAUSTED: int; const CLUSTERS: int; const MAX_REG: int; const REGIONS: int
const MASK_SLOTS: int; const NO_REGION: int
var heuristic_pct: int; var state: int; var start: int; var goal: int; var limit_q: int; var corridor: PackedInt32Array
var label: PackedByteArray; var corridor_stamp: int; var corridor_on: bool; var touched: int
func begin(s: int, t: int, lq: int, use_corridor: bool) -> void;  func run(budget: int) -> int
func new_corridor(sl: int) -> void;  func add_corridor(region: int) -> void;  func label_at(i: int) -> int;  func weight_at(cell: int) -> int
func found_cost() -> float;  func write_path(out: PackedInt32Array, off: int, cap: int) -> int
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # + labels, the search in flight

class_name PathLabel extends PathSearch                                      # cluster labelling on the grid's own arrays
const CS: int
static func cell0(c: int) -> int;  func label_cluster(sl: int, c: int, lq: int) -> int
func link_cluster(sl: int, c: int, lq: int, nbr8: PackedInt32Array) -> int
func reg_dir(k: int) -> Vector3;  func reg_weight(k: int) -> float;  func adj_out(i: int) -> int

class_name PathRegions extends RefCounted                                    # region graph per mask slot, lazy + versioned
const CN: int; const CS: int; const CLUSTERS: int; const MAX_REG: int; const REGIONS: int; const OVERFLOW: int
const MASK_SLOTS: int; const BUILD_COST: int; const LINK_COST: int
var grid: PathLabel; var builds: int; var overflows: int; var orphans: int
func invalidate() -> void;  func slot_for(mask: int) -> int;  func prepare(mask: int) -> void;  func on_flip(cell: int) -> void
func region_of(cell: int, sl: int) -> int;  func region_count(c: int, sl: int) -> int
func adjacency(region: int, k: int, sl: int) -> int;  func neighbour(c: int, k: int) -> int
func ensure_labels(sl: int, c: int) -> int;  func ensure_links(sl: int, c: int) -> int
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # versions, counters, graph data (zstd)

class_name PathClusters extends PathRegions                                  # resumable region A*, corridor stamping
var heuristic_pct: int; var state: int; var start: int; var goal: int; var slot: int
func begin(from_r: int, to_r: int, to_dir: Vector3, sl: int) -> void;  func run(budget: int) -> int
func mark_corridor() -> void;  func mark_region(r: int, sl: int) -> void;  func mark_around(cell: int, sl: int) -> int
func route() -> PackedInt32Array
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # + the region search in flight

class_name PathCache extends RefCounted                                      # (start cluster, goal cell, mask) -> cells, LRU
const ENTRIES: int; const STRIDE: int
var cells: PackedInt32Array; var length: PackedInt32Array; var start_cell: PackedInt32Array; var faces: PackedInt32Array
var vsum: PackedInt32Array
static func key_of(start: int, goal: int, mask: int) -> int;  func lookup(key: int, grid: PathGrid) -> int
func insert(key: int, src: PackedInt32Array, off: int, n: int, grid: PathGrid) -> bool;  func segment(e: int, from: int) -> PackedInt32Array
func exit_index(e: int) -> int;  func size() -> int;  func clear() -> void
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool   # LRU state + live cells; index rebuilt
```

## Invariants

- P1: every DONE result is a chain of `Sphere.neighbours8` steps from the start cell to the goal cell; every cell after
  the start is passable for the mask (weight not 0 / 255, slope <= mask); no diagonal step has a blocked orthogonal
  cell beside it, so no straight segment between consecutive centres touches a blocked cell.
- P2: ST_NO_PATH only when the goal is unreachable for the mask (region exhaustion is a proof: the region graph is a
  superset of cell connectivity while `orphans == 0`; `test_region_graph_is_consistent_with_cell_adjacency`).
- P3: at `heuristic_pct` 0 with `hier_min_cells` covering the query, the route cost equals brute-force Dijkstra under
  the cost model `arc(a, b) * (w_a + w_b) / 2` (in-face, across an edge, at a corner); with inflation p the hierarchy
  bound measured is <= 1.3 x optimal on the fixtures.
- P4: `advance()` spends at most `expansions_per_tick` units when the region graphs of the masks in use are prepared
  and no flip is pending; a lazy label / link build is atomic and may overrun once per tick.
- P5: tickets are served FIFO: `done_tick` is non-decreasing in request order (cache answers excepted: they are DONE
  at `request`); a released ticket never delays later ones.
- P6: identical calls (weights, terrain, requests, advance count) give identical cells and identical units per tick;
  no clock, RNG or Dictionary iteration feeds a result.
- P7: a cache entry is served only while the version sum of the faces it crosses is unchanged; `set_weight` bumps the
  face counter (`version`) on every call.
- P9 (TA-50): `read_state(write_state())` on a Pathing that loaded the same map writes the same bytes and, advanced
  in lockstep, gives the same units, tickets and cells, also with a cell or region search in flight
  (`test_state_round_trip_mid_search_continues_identically`; world level: `test_serialize.gd` S4). A search's tags
  outside its own sid and the start cell's parent are never read; the reader zeroes them.
- P10 (GD-39): `baked_weight(cell)` is the byte of the bake `load_weights` read (and SHA-256 checked) and keeps as a read-only `_bake` array (384 KB, never written by `set_weight`, not saved: deserialize reloads the map, so S4 and FORMAT are unchanged); no file access in the tick. `set_weights` (fixtures) clears it and the flat datum has none: every cell bakes to 1. `sim/salvage` `WreckPaths` calls `set_weight(cell, 255)` for a resting wreck and `set_weight(cell, baked_weight(cell))` when it leaves (salvage W11).
- P8: no per-expansion allocation; no packed array inside a container; other classes never index another object's
  large packed arrays (copy-on-write; use the accessor methods).

## Data owned

Weights 384 KB, slope 384 KB, labels 2 x 384 KB, search g 1.5 MB + u8 tag 384 KB + u8 parent index 384 KB, corridor 48 KB,
region graph ~0.9 MB, ticket pool 640 KB, cache 256 KB: **5.67 MB measured** (TA-50, MEMORY_STATIC after load + two prepares,
`test_mem_mb_after_load_and_prepare_is_at_most_6`; TA-20 measured 8.8 MB). The 03 s11.3 row is re-baselined to this (A-55).

## Events emitted / consumed

None. Consumes no `Command`; `set_weight` is called by Build / structure placement (TA-19) and map load.

## Performance budget

03 s4.2 row 3b: 0.5 ms per tick (unchanged until S-SIM-1 on the pinned runner, R0 B.11 A-55 / A-62). Measured in `docs/spikes/TA-20/REPORT.md`
at 120 expansions, dev box quiet: amortised 0.27-0.34 ms, p95 1.56-1.70 ms, max 3.6 ms; ~15 us per expansion in-tick (cold arrays), 4.55 us warm.

## Test entry points

`godot/test/unit/sim/pathing/test_pathing.gd` (P1-P7), `godot/test/unit/sim/pathing/test_pathing_state.gd` (P9, memory, u8
parents), helpers `godot/test/unit/sim/pathing/nav_test_kit.gd`; wiring `godot/test/sim/test_path_scenario.gd`;
harness `godot/spikes/s_nav_1/run.tscn` (03 s14.3 measurements).

## How to add X (recipes for the cheapest tier)

- **A ground unit kind:** call `prepare(Pathing.mask_for(def.max_slope_deg))` at map load; at most `MASK_SLOTS` (2)
  distinct masks keep a graph, a third evicts one round-robin.
- **A blocking structure:** `set_weight(cell, PathGrid.W_BLOCKED)` per footprint cell (TA-19); followers re-path when
  `version(face)` changes along their route (05 s5.7).

## Open items

- Wired (TA-50): `SimWorld` owns one `Pathing` (`from_rules`: `rules.path_expansions_per_tick`, `rules.path_heuristic_pct`),
  `load_map` loads the weights, sets the terrain and prepares each distinct ground-unit mask (in def order, <= `MASK_SLOTS`; not
  on the flat datum, not on deserialize: the graphs are in the bytes). Step 3b assigns
  `SimWorld.path_expansions_per_tick()` (cut rung 8, TA-49) to `expansions_per_tick` before `advance()`. S4 bytes are the interim `StateIO` form; TA-21 compacts.
- `rules.path_heuristic_pct` (25) exists (A-51); TA-49 feeds it to `set_heuristic_pct`. `JOB_COST`, `BUILD_COST`, `LINK_COST` and
  `MASK_SLOTS` stay named consts: they are the time-slicing's own unit prices and slot count, not sim-affecting balance (ADR-09 as read in A-51).
- Baked per-path-cell max slope (and optionally region labels for the v1 masks) so `prepare` stops sampling texels at load: **TA-54** (tools, M3).
