# sim/vision - MODULE.md

Contract for `godot/src/sim/vision/**`: tick step 11 (03 s3.7, s3.6 interest grid, s4.1; ADR-05; R0 C2-23; TA-37).
R0 B.9 A-21 split of `sim/MODULE.md`, which keeps `SimWorld`'s accessors (`vision`, `interest_start/count/ids`). A change
to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py
--check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Per team t: bit t of `EntityStore.visible_mask` and t's per-interest-cell entity lists (03 s3.6), at 10 Hz staggered by team, 5 Hz under cut rung 2. Range + datum-horizon occlusion per pair, the Sensor Mast reveal, own-team bits. Not: last-known ghosts (client presentation, 06), the one-period grace against flicker (`net/Interest`, 03 s3.7), terrain line of sight (v1.x, 08), tier A/B/C assignment (net). |
| Lane owner tier | Opus (sim lane) |
| May depend on | `core`, `content`, `sim` (R0 B.4: inside the sim module; `EntityStore`, `Spatial` constants, `WorldDefs`, `PlayerTable`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads (D2, D3); no RNG |
| Autoloads used | None |
| Status | implemented (TA-37, 2026-10-14). Lane-internal types: other lanes reach Vision only through `SimWorld.interest_*()`, `SimView.visible_to / visible_ids / visible_enemy_ships` and `visible_mask` (net encoder) |

## Public API

`SimWorld` composes one `Vision` (`SimWorld.vision`, read-only outside the sim lane) and calls `step` in tick step 11,
`bind` after each doctrine resolve and `rebuild_lists` after deserialize. Not in `tools/deps.json` named types.

```gdscript
class_name Vision extends RefCounted                                         # step 11; the rule of 03 s3.7, exact (V1)
const TEAMS: int; const OWNERS: int; const DEF_N: int                        # 8 teams; owner rows 0..7 + WorldDefs.NEUTRAL; def_id < 1024
const RUNG_2_VISION_HZ: int; const RUNG_VISION: int    # 5 Hz default of the def, rung 2; the base `hz` is rules.vision_hz via WorldDefs.vision_hz
var grid: InterestGrid; var groups: SensorGroups; var tick_hz: int; var hz: int; var rung_2_hz: int
var last_pass: PackedInt32Array                                              # per team: tick of its last pass, -1 before the first (not S4 state)
var sensor_r: PackedFloat32Array; var reveal_r: PackedFloat32Array          # [owner * DEF_N + def_id]: sensor_radius / deck_reveal_radius, 0 = none
func _init(store: EntityStore, defs: WorldDefs, ticks_per_s: int) -> void    # rung_2_hz = rules.rung_2_vision_hz; owner rows from defs.resolved(owner)
func bind(owner: int, r: ResolvedDefs) -> void                               # owner row from a doctrine resolve; grows the near table to the max reach
func period(rungs: PackedInt32Array) -> int;  func runs(team: int, tick: int, rungs: PackedInt32Array) -> bool   # V3; rungs = MatchRules.sim_budget_profile
func step(tick: int, rungs: PackedInt32Array) -> void                        # index once, then the passes of the teams scheduled on `tick`
func pass_team(t: int, tick: int) -> void;  func refresh(tick: int) -> void  # one pass on the current index / every team now (tests, tools)
func enemy_ships(team: int, out: PackedInt32Array) -> int                    # V10, behind SimView.visible_enemy_ships (TA-63)
func rebuild_lists() -> void                                                 # lists from the current mask, no bit changed (V6)
func ids_in_cell(team: int, cell: int) -> PackedInt32Array                   # allocating convenience over the flat lists
static func sees(sensor: Vector3, target: Vector3, sensor_radius: float, reveal_radius: float) -> bool   # the pair test

class_name InterestGrid extends RefCounted                                   # 384 interest cells: per-tick bucket index, near table, per-team lists
const N: int; const CELLS: int; const TEAMS: int; const GROUPS: int; const NEUTRAL_GROUP: int; const STRIDE: int   # 8, 384, 8, 9, 8, 1536
var bucket_start: PackedInt32Array; var bucket_count: PackedInt32Array; var items: PackedInt32Array   # bucket = cell * GROUPS + team group; store slots
var cell_n: PackedInt32Array; var touched: PackedInt32Array; var touched_n: int   # entities per cell; non-empty cells this tick
var centre: PackedVector3Array; var cone: PackedFloat64Array; var cone_cos: PackedFloat64Array; var cone_sin: PackedFloat64Array   # per cell: unit centre, circumradius + 1 m
var near_start: PackedInt32Array; var near_cell: PackedInt32Array; var near_gap: PackedFloat32Array; var reach_m: float
var cell_start: PackedInt32Array; var cell_count: PackedInt32Array; var ids: PackedInt32Array; var list_size: PackedInt32Array   # the lists (layout below)
static func interest_of_hash(hash_cell: int) -> int                          # GRID_HASH cell -> GRID_INTEREST cell (V8)
func ensure_reach(reach: float) -> void;  func index(store: EntityStore) -> void
func build_list(t: int, store: EntityStore, seen: PackedInt32Array, seen_n: int, own: bool) -> void
func seen_from_mask(t: int, store: EntityStore, out: PackedInt32Array) -> int

class_name SensorGroups extends RefCounted                                   # one team's sensors for one pass; exact pruning bounds (V1)
func gather(t: int, grid: InterestGrid, store: EntityStore, sensor_r: PackedFloat32Array, reveal_r: PackedFloat32Array) -> int
func cover(grid: InterestGrid) -> void;  func clear_cover() -> void
func scan(t: int, grid: InterestGrid, pos: PackedVector3Array, out: PackedInt32Array) -> int
```

**Two outputs, one result; keep both stable.** (1) `visible_mask` bit t (own team implied): NET-08 as merged (#32) reads
it through `SimView.visible_to` (the NET-15 adapter fills `SnapshotFrame.visible_mask`) and buckets cells itself. (2) The
per-team interest lists, the same bits grouped per cell once per pass (R0 C1-02), for net to read instead of re-bucketing:
`SimWorld.interest_start()`, `interest_count()`, `interest_ids()` return `InterestGrid.cell_start`, `cell_count`, `ids`
(shared, not copied; read-only and valid until the next `step()`, S3). For team t in 0..7 and interest cell c = `Sphere.cell_of(p, Sphere.GRID_INTEREST)` (face * 64 + row * 8 + col, 0..383), with
`i = t * 384 + c` and `n = interest_count()[i]`, t's ids in c are `interest_ids()[interest_start()[i] + k]` for k in [0, n);
`interest_start()[i]` is meaningful only when `n > 0`. Every entry is an `EntityId` (main or wreck range; projectiles are
never listed) carrying bit t at t's last pass: t's own entities and the other teams' and neutral entities t sees. Team t's
entries are contiguous, `interest_ids()[t * 1536, t * 1536 + list_size[t])`. The cell is the entity's cell at t's last pass
(it may have moved since by < one period of motion); an entity that died since is still listed until t's next pass, so check
`alive`. Inside a cell: own team first, then the rest in scan order (deterministic for identical state, otherwise unspecified).
After `SimWorld.deserialize` the lists are rebuilt from the mask with current cells (same ids per team; per cell after one period).

## Invariants

- V1: after team t's pass, bit t of `visible_mask[x]` for every live entity x whose team is not t equals the 03 s3.7 rule
  evaluated on that tick's store: some live non-wreck entity e of team t (team byte == t) with `sensor_r[row(e)] > 0`,
  `|p_e - p_x| <= sensor_r` and not `Sphere.is_occluded_by_datum(p_e, p_x)`, or with `|p_e - p_x| <= reveal_r[row(e)]`;
  row(e) = min(owner, NEUTRAL) * DEF_N + def_id. The pruning never changes a result (test_vision.gd brute force).
- V2: only defs with `deck_reveal_radius > 0` (Sensor Mast; the captured Relay Station) reveal through the datum, out to
  that radius (01 s6.2); every other sensor needs an unoccluded segment (A-10 endpoint semantics, below-datum units included).
- V3: period = floor(tick_hz / hz), or floor(tick_hz / rung_2_hz) (`rules.cut_ladder.rung_2_vision_hz`) while
  `sim_budget_profile` contains 2; team t passes on
  exactly the ticks with tick % period == t % period, so once per period and at most ceil(8 / period) teams per tick. A
  target entering range carries the bit within one period.
- V4: after t's pass every live entity of team t carries bit t; wrecks never sense; neutral entities (team byte >= 8) are
  seen like any other team's and never pass.
- V5: bit t set on slot s implies s is in t's list (so a pass clears exactly its previous list); t's list holds exactly the
  slots that carried bit t at its pass, each under its interest cell.
- V6: the result is a function of the store state only (an OR of exact pair tests; no RNG, Dictionary or iteration-order
  dependence): two identical worlds agree tick by tick, and S4 holds with Vision live (`rebuild_lists` changes no bit).
- V7: no Dictionary, no per-entity allocation on the tick path; one key slice per pass (`SensorGroups.gather`).
- V8: `InterestGrid.interest_of_hash(Spatial.cell_of(p)) == Sphere.cell_of(p, Sphere.GRID_INTEREST)`.
- V9 (precondition): a structure never changes position after its spawn. `InterestGrid.index` caches the structures'
  buckets until `EntityStore.structures` or any `team` byte changes; a future system that moves a structure re-keys it
  (changes the list) or extends that check.

- V10 (TA-63, R0 B.17 A-95): `SimView.visible_enemy_ships(team, out) -> int` fills the caller-owned `out` (resized once to
  `list_size[team]` when smaller, never shrunk or reallocated otherwise) with the live ships of another team (neutral included)
  in `ids[team * STRIDE, team * STRIDE + list_size[team])`, i.e. those carrying bit `team` at its last pass, in ascending EntityId order (a function of state alone: the list's own cell order is unspecified and
  differs after a restore), and returns the count (`out[n..]` untouched). O(listed), no allocation, no store walk: every id satisfies `alive`, `visible_to(team, id)`
  and is in `ships()`; own-team entities, structures, ground units, wrecks and ships dead since the pass are skipped; a team outside
  0..7 gives 0. Same set before and after `SimWorld.deserialize` + `rebuild_lists` (S4). `sim_ai` `TeamPicture` adopts it in a
  follow-up inside the AI-13 lane.

## Data owned

`InterestGrid` (bucket index, per-team lists, the near table and cell geometry shared per process as static caches),
`SensorGroups` scratch, `Vision.sensor_r / reveal_r` (owner-resolved `ShipDef / GroundUnitDef / StructureDef.sensor_radius`,
`StructureDef.deck_reveal_radius`). Writes `EntityStore.visible_mask` (serialized with the store, S4); reads `pos`, `team`,
`owner`, `def_id`, `kind`, `hash_cell` (step 7) and the live lists. Nothing of Vision's own is S4 state.

## Events emitted / consumed

None. (Alerts that need vision, e.g. BOMBERS_DETECTED, read `visible_mask` in their own system.)

## Performance budget

03 s4.2 row 11 "Vision": <= 1.1 ms p95 at S-SIM-1 scale (1,200 entities, 2,000 projectiles), `perf_tick.gd --full`
vision row; `perf_vision.gd` splits the index and one team's pass. Cost: index O(entities) once per tick; per pass
O(team sensors + candidates in covered cells x covering groups + the sensors inside the bounds). TA-37 measured on the
dev box (`perf_tick.gd --full`, 1,800 ticks, two rounds): default profile [1, 2] (5 Hz) p50 0.39-0.45 / p95 0.62-0.81 ms;
`--profile=1` (10 Hz, 3 or 2 passes per tick) p50 0.70-0.71 / p95 0.84-0.85 ms; `perf_vision.gd`: index p50 114 us, one
team's pass p50 194 us. A loaded box reads up to ~1.5x; the pinned runner (TA-42) is the gate (03 s4.4).

## Test entry points

`godot/test/unit/sim/vision/test_vision.gd` (V1, V2, V4, V8: range, horizon, the A-10 below-datum vectors, Sensor Mast
reveal, wrecks, neutrals, bit clearing, `sees` vs Sphere, random scenes vs brute force, `bind`),
`godot/test/unit/sim/vision/test_visible_enemy_ships.gd` (V10: brute force on 258 ships x 8 teams x 60 ticks, dead since the pass, kinds, neutral, `out` reuse, S4, per-team us beside the brute force),
`godot/test/unit/sim/vision/test_vision_lists.gd` (V3, V5, V6: stagger at 10 / 5 Hz, latency, lists vs mask and the
`SimWorld.interest_*` layout, two identical worlds, S4 round trip, `rebuild_lists`), `godot/test/unit/core/test_sphere.gd`
(`test_is_occluded_by_datum_below_datum_a10`), `godot/test/unit/sim/test_serialize.gd` (S4 with Vision in the tick),
`godot/test/perf/perf_vision.gd` and `godot/test/perf/perf_tick.gd` (budget).

## How to add X (recipes for the cheapest tier)

- A sensing def: give it `sensor_radius` (and `deck_reveal_radius` for a reveal) in its def JSON; `bind` picks it up.
- A new sensing condition (powered, built): filter in `SensorGroups.gather` only, add a brute-force clause in
  `VisionTestKit.brute`, keep the random-scene test green; record the rule in V1.

## Open items

- `rules.json` `vision_hz` (10) is read by `WorldDefs` and `Vision._init` (TA-56, A-66); `rung_2_hz` reads `cut_ladder.rung_2_vision_hz` (TA-49).
- A-76 (TA-56; `SensorGroups.gather` skips `F_BUILDING`, `VisionTestKit.brute` has the clause): a structure with `F_BUILDING` does **not** sense; an unpowered finished
  structure senses normally. 03 s4.2 row 11 now says ~400 sensors per pass; the 1.1 ms row is unchanged.
- `needs net:` NET-08 / NET-15 may switch `Interest`'s per-team V from re-bucketing the mask to `SimWorld.interest_*` (same bits);
  `net/Interest` adds the one-period grace (03 s3.7).
