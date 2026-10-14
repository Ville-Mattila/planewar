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
| Status | spike implementation (TA-20, 2026-10-14); not yet wired into `SimWorld` step 3b or S4 bytes (Open items) |

## Public API

`Pathing` is the only class other code should name; the rest is internal to this folder (public for tests and the
`godot/spikes/s_nav_1` harness). Masks: bits 0-7 = the unit's `max_slope_deg` in whole degrees (`mask_for`), 0 = no
slope limit (weights only).

```gdscript
class_name Pathing extends RefCounted                                        # _init(expansions: int) = rules.path_expansions_per_tick
const NO_TICKET: int; const ST_UNKNOWN: int; const ST_PENDING: int; const ST_DONE: int; const ST_NO_PATH: int
const MAX_TICKETS: int; const MAX_CELLS: int; const JOB_COST: int
var expansions_per_tick: int; var hier_min_cells: int; var grid: PathLabel; var clusters: PathClusters; var cache: PathCache
var ticks: int; var requests: int; var cache_hits: int; var splice_misses: int; var fallbacks: int
var expansions_total: int; var abstract_units: int
func load_weights(map_dir: String) -> Error;  func set_weights(bytes: PackedByteArray) -> bool
func set_terrain(t: Terrain) -> void;  func override_slope(cell: int, slope_deg: int) -> void;  func prepare(mask: int) -> void
func set_heuristic_pct(pct: int) -> void;  static func mask_for(max_slope_deg: float) -> int
func request(from: Vector3, to: Vector3, mask: int) -> int                   # R0 B.5; NO_TICKET when 160 are pending
func status(ticket: int) -> int;  func result(ticket: int) -> PackedVector3Array;  func result_cells(ticket: int) -> PackedInt32Array
func done_tick(ticket: int) -> int;  func request_tick(ticket: int) -> int;  func release(ticket: int) -> void;  func pending() -> int
func advance() -> int                                                        # step 3b, once per tick; returns units spent
func set_weight(cell: int, w: int) -> void;  func weight(cell: int) -> int;  func version(face: int) -> int

class_name PathGrid extends RefCounted                                       # weights, slopes, versions, centres, neighbours
const N: int; const SHIFT: int; const LOW: int; const FACES: int; const CELLS: int
const W_BLOCKED: int; const W_ZERO: int; const SLOPE_UNKNOWN: int; const SLOPE_NO_LIMIT: int
var weights: PackedByteArray; var slope_q: PackedByteArray; var face_version: PackedInt32Array; var nb: PackedInt32Array
var terrain: Terrain; var arc_u: PackedFloat32Array; var arc_d: PackedFloat32Array
func set_weights(bytes: PackedByteArray) -> bool;  func set_terrain(t: Terrain) -> void;  func version_of(face: int) -> int
func center_dir(cell: int) -> Vector3;  static func cell_of(p: Vector3) -> int;  static func cluster_of(cell: int) -> int
func passable(cell: int, limit_q: int) -> bool;  func neighbours(cell: int) -> void;  func sample_slope(cell: int) -> int
func override_slope(cell: int, slope_deg: int) -> void;  static func limit_q_of(mask: int) -> int
func set_weight(cell: int, w: int) -> bool;  static func blocks(w: int) -> bool;  func version_sum(face_bits: int) -> int

class_name PathSearch extends PathGrid                                       # resumable cell A*, one in flight
const RUNNING: int; const FOUND: int; const EXHAUSTED: int; const CLUSTERS: int; const MAX_REG: int; const REGIONS: int
const MASK_SLOTS: int; const NO_REGION: int
var heuristic_pct: int; var state: int; var start: int; var goal: int; var limit_q: int; var corridor: PackedInt32Array
var label: PackedByteArray; var corridor_stamp: int; var corridor_on: bool; var touched: int
func begin(s: int, t: int, lq: int, use_corridor: bool) -> void;  func run(budget: int) -> int
func new_corridor(sl: int) -> void;  func add_corridor(region: int) -> void;  func label_at(i: int) -> int;  func weight_at(cell: int) -> int
func found_cost() -> float;  func write_path(out: PackedInt32Array, off: int, cap: int) -> int

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

class_name PathClusters extends PathRegions                                  # resumable region A*, corridor stamping
var heuristic_pct: int; var state: int; var start: int; var goal: int; var slot: int
func begin(from_r: int, to_r: int, to_dir: Vector3, sl: int) -> void;  func run(budget: int) -> int
func mark_corridor() -> void;  func mark_around(cell: int, sl: int) -> int;  func route() -> PackedInt32Array

class_name PathCache extends RefCounted                                      # (start cluster, goal cell, mask) -> cells, LRU
const ENTRIES: int; const STRIDE: int
var cells: PackedInt32Array; var length: PackedInt32Array; var start_cell: PackedInt32Array; var faces: PackedInt32Array
var vsum: PackedInt32Array
static func key_of(start: int, goal: int, mask: int) -> int;  func lookup(key: int, grid: PathGrid) -> int
func insert(key: int, src: PackedInt32Array, off: int, n: int, grid: PathGrid) -> bool;  func segment(e: int, from: int) -> PackedInt32Array
func exit_index(e: int) -> int;  func size() -> int;  func clear() -> void
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
- P8: no per-expansion allocation; no packed array inside a container; other classes never index another object's
  large packed arrays (copy-on-write; use the accessor methods).

## Data owned

Weights 384 KB, slope 384 KB, labels 2 x 384 KB, search g / tag / parent 4.5 MB, corridor 48 KB, region graph ~0.6 MB,
arc tables 512 KB, ticket pool 640 KB, cache 256 KB: ~8.8 MB measured (`mem_mb`), over the 2 MB of 03 s13 (Open items).

## Events emitted / consumed

None. Consumes no `Command`; `set_weight` is called by Build / structure placement (TA-19) and map load.

## Performance budget

03 s4.2 row 3b: 0.5 ms per tick. Measured in `docs/spikes/TA-20/REPORT.md`; `path_expansions_per_tick` calibration there.

## Test entry points

`godot/test/unit/sim/pathing/test_pathing.gd` (P1-P7), helpers `godot/test/unit/sim/pathing/nav_test_kit.gd`;
harness `godot/spikes/s_nav_1/run.tscn` (03 s14.3 measurements).

## How to add X (recipes for the cheapest tier)

- **A ground unit kind:** call `prepare(Pathing.mask_for(def.max_slope_deg))` at map load; at most `MASK_SLOTS` (2)
  distinct masks keep a graph, a third evicts one round-robin.
- **A blocking structure:** `set_weight(cell, PathGrid.W_BLOCKED)` per footprint cell (TA-19); followers re-path when
  `version(face)` changes along their route (05 s5.7).

## Open items

- Wiring (follow-up): `SimWorld` owns a `Pathing`, calls `load_weights` + `set_terrain` + `prepare` in `load_map`,
  `advance()` at step 3b (row `ROW_PATHING`), exposes it to the AI hook, and serialises tickets / cache for S4 (TA-21).
- `needs content:` `path_expansions_per_tick` recalibrated per REPORT; `heuristic_pct`, `JOB_COST`, `BUILD_COST`,
  `LINK_COST` and `MASK_SLOTS` belong in `rules.json` (named consts until then, ADR-09).
- `needs tools (moonbake):` bake the per-path-cell max slope (and optionally region labels for the v1 masks) so
  `prepare` stops sampling texels at load.
- Memory over the 03 s13 2 MB row; options in the REPORT.
