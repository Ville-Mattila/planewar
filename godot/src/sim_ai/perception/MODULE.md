# sim_ai/perception - MODULE.md

Contract for `godot/src/sim_ai/perception/**`: what an AI observer knows (05 s7.1 rule 2, s7.2 "Perception", s7.8
Information and reaction delay) and the threat map on interest cells (05 s7.4); AI-22. Sub-module of `sim_ai` (R0 B.9
A-21 split pattern): `sim_ai/MODULE.md` keeps `AiDriver`'s accessors (`set_intel`, `threat_map`, `perception`). A change
to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py
--check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Per observer (a team, or a bot slot): contacts from the team's vision only, ghosts, memory, reaction delay, own assets; the 384-cell threat map (enemy DPS per band, values, own defence, last seen) and its queries; the AI driver's per-team intel at 1 Hz. Not: what a bot does with it (AI-23 / AI-27), client ghosts (06), Vision itself (`sim/vision`). |
| Lane owner tier | Opus (sim_ai lane) |
| May depend on | `core`, `content`, `sim` (`SimView` only; `tools/deps.json` row `sim_ai`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`; no `await`, signals, `Thread`, autoloads; never `SimView.alive` / `pos` / events of an entity the observer does not see |
| Autoloads used | None |
| Status | implemented (AI-22, 2026-10-21). Constants: `godot/test/sim/ai/ai22_params.json` until `bot_profiles.json` / the `threat` block land (needs content). |

## Public API

```gdscript
class_name PerceptionParams extends RefCounted      # one observer's information profile (bot_profiles.json R0 B.1 names)
const KEYS: PackedStringArray                       # vision (own | team), ghost_memory_s, reaction_delay_s (mirrors bot_promises reaction_s)
var own_vision: bool; var memory_ticks: int; var delay_ticks: int
static func from_dict(d: Dictionary, tick_hz: int) -> PerceptionParams   # null on a missing key or a bad vision

class_name ThreatParams extends RefCounted          # static tables shared by a session: per def, per threat profile, cell geometry, rings
const N: int; const CELLS: int; const AIR_DECK: int; const AIR_LOW: int; const AIR_HIGH: int; const GROUND: int; const BANDS: int
const KEYS: PackedStringArray                       # the `threat` block: ghost_half_life_s, cell_margin_m, fighter_share, fighter_radius_m, route_sample_m, band_agl_m, defence_floor_dps, fighters, ground_attackers
var decay_per_tick: float; var margin_m: float; var route_step_m: float; var defence_floor: float; var max_sensor_m: float
var value_by_def: PackedFloat32Array; var sensor_by_def: PackedFloat32Array; var reveal_by_def: PackedFloat32Array; var profile_by_def: PackedByteArray; var sclass_by_def: PackedByteArray
var profiles: int; var classes: int; var prof_class: PackedByteArray; var prof_dps: PackedFloat32Array; var prof_defence: PackedFloat32Array
var centre: PackedVector3Array; var circ_m: PackedFloat32Array; var in_cos: PackedFloat32Array; var near_start: PackedInt32Array; var near_cell: PackedInt32Array; var near_gap: PackedFloat32Array
var ring_start: PackedInt32Array; var ring_cell: PackedInt32Array; var ring_w: PackedFloat32Array   # ring k = range class k, then the sensor classes
static func from_content(c: ContentSet, threat: Dictionary, tick_hz: int) -> ThreatParams   # null on a missing key
static func sustained_dps(w: WeaponDef) -> float    # mean damage x shots/s (bursts, rof, salvo / reload)
func cell_of(p: Vector3, hint: int) -> int;  func ring_count() -> int

class_name SensorCover extends RefCounted           # one refresh's own sensors bucketed per cell; the 03 s3.7 pair rule
var n: int; var pos: PackedVector3Array; var r2: PackedFloat32Array; var reveal2: PackedFloat32Array; var mine: PackedByteArray; var cell: PackedInt32Array; var stats_pair_tests: int
func clear() -> void;  func add(p: Vector3, c: int, sensor_m: float, reveal_m: float, own_slot: bool) -> void;  func build() -> void
func covers(q: Vector3, qc: int, own_only: bool) -> bool

class_name Perception extends RefCounted            # one observer's contacts, ghosts and own assets
const FORMAT: int; const MAX_SLOT: int
var team: int; var slot: int; var prm: PerceptionParams; var tables: ThreatParams; var cover: SensorCover; var last_refresh: int
var n_known: int; var known: PackedInt32Array; var k_id: PackedInt32Array; var k_first: PackedInt32Array; var k_seen: PackedInt32Array; var k_def: PackedInt32Array; var k_cell: PackedInt32Array; var k_pos: PackedVector3Array
var n_own: int; var own_id: PackedInt32Array; var own_def: PackedInt32Array; var own_cell: PackedInt32Array; var own_pos: PackedVector3Array
var n_ghosts: int; var ghosts: PackedInt32Array; var n_fresh_cells: int; var fresh_cells: PackedInt32Array; var fresh_val: PackedFloat32Array; var n_fresh_keys: int; var fresh_keys: PackedInt32Array; var fresh_bin: PackedFloat32Array
var stats_view_calls: int; var stats_refreshes: int
func _init(observer_team: int, observer_slot: int, p: PerceptionParams, t: ThreatParams) -> void   # slot -1: the team
func refresh(v: SimView, tick: int) -> void
func usable(s: int, tick: int) -> bool;  func knows(id: int, tick: int) -> bool
func serialize() -> PackedByteArray;  func deserialize(bytes: PackedByteArray) -> bool

class_name ThreatMap extends RefCounted             # 05 s7.4: 384 cells x (7 float channels + last_seen)
const FORMAT: int; const CELLS: int; const AIR_DECK: int; const AIR_LOW: int; const AIR_HIGH: int; const GROUND: int
const ENEMY_VALUE: int; const OWN_VALUE: int; const OWN_DEFENCE: int; const CHANNELS: int
var tables: ThreatParams; var ch: PackedFloat32Array; var last_seen: PackedInt32Array; var updated: int; var stats_bins: int; var stats_cells: int
func _init(t: ThreatParams) -> void
func update(_v: SimView, perception: Perception, tick: int) -> void   # on the perception's refresh tick
func threat_at(cell: int, band: int) -> float;  func pressure(cell: int) -> float
func route_risk(from: Vector3, to: Vector3, band: int) -> float      # sum over the cells the arc crosses, sampled every route_sample_m
func hottest_own_cell() -> int                                          # max pressure / max(own_defence, floor) over own-value cells; -1 none
func serialize() -> PackedByteArray;  func deserialize(bytes: PackedByteArray) -> bool

class_name TeamIntel extends RefCounted             # the AI driver's per-team perception + map (05 s6 sampler), 1 Hz staggered
const FORMAT: int; const STAGGER: int; const PHASE: int
var tables: ThreatParams; var profile: PerceptionParams; var period: int; var stats_updates: int
func _init(t: ThreatParams, team_profile: PerceptionParams, period_ticks: int) -> void
func track(team: int, on: bool) -> void;  func tracked(team: int) -> bool;  func due(team: int, tick: int) -> bool
func step(tick: int, v: SimView) -> void
func threat_map(team: int) -> ThreatMap;  func perception(team: int) -> Perception
func serialize() -> PackedByteArray;  func deserialize(bytes: PackedByteArray) -> bool
```

## Invariants

- P1 (fog fairness, SC-43): a contact enters only from `SimView.visible_ids(team)`, so it was `visible_to(team)` at the
  refresh that entered it; a ghost is only ever a position the observer saw. Nothing reads `alive`, a position, an
  event or a def of an entity the observer does not see (the id cache holds facts read while it was seen).
- P2 (difficulty only removes, 05 s7.8): `own` vision keeps the team-visible contacts its slot's sensors cover
  (`SensorCover`, base def radii: never more than the team sees); `delay_ticks` postpones a new contact's use
  (`usable`, `knows`, the map); `memory_ticks` forgets a ghost after its last sight. A ghost is also forgotten when its
  last position is inside the observer's sensors and the team does not see it there.
- P3 (determinism, S4): perception, digest and map are functions of the bytes and the view; `known` keeps first-sight
  order (stable compaction); the digest is rebuilt in `known` order, so `TeamIntel.deserialize` + `ThreatMap.update`
  on the restored perception reproduces the channels bit for bit. The id cache and `SensorCover` are not state.
- P4 (map rule, 05 s7.4 at cell resolution): a source's DPS reaches cell h with w = 1 while d = max(D - circ(c), 0)
  <= range, linear to 0 at range + `cell_margin_m` (D: centre arc distance, c: the source's cell); towers by envelope at
  the band AGLs, `fighters` at `fighter_share` over `fighter_radius_m`, `ground_attackers` on GROUND; ghosts weigh
  exp(-age ln 2 / half-life); ENEMY_VALUE / OWN_VALUE in the asset's cell; `last_seen` = own cells + sensor rings.
- P5 (cost, 05 s10 "Threat maps 0.3 ms per team"): `update` is O(digest keys + ghosts + own + bins x ring) with no
  allocation; `refresh` is one `visible_ids` plus O(listed) reads; `TeamIntel` runs one team slice on its tick.

## Data owned

`Perception` (contacts by slot, digest, own list), `ThreatMap` channels and `last_seen`, `TeamIntel` tracked mask; in
the S4 bytes through `AiDriver.serialize` (FORMAT 2). `ThreatParams` is session configuration built from content.

## Performance budget

05 s10 row "Threat maps (per team, 1 Hz, spread) 0.3 ms"; 05 s7.2 Commander slice 0 (perception + threat) <= 0.7 ms.
`godot/test/unit/sim_ai/test_intel_perf.gd` on the S-SIM-1 world (`PerfTickWorld` 1,200 entities, 8 teams): figures in
`sim_ai/MODULE.md` (AI-22 perf note); timing via `PerfGate` (R0 B.17 A-97), work counters hard.

## Test entry points

`godot/test/unit/sim_ai/test_perception.gd`, `godot/test/unit/sim_ai/test_threat_map.gd`,
`godot/test/unit/sim_ai/test_team_intel.gd`, `godot/test/unit/sim_ai/test_intel_perf.gd` (fixtures
`godot/test/sim/ai/intel_kit.gd`, `ai22_params.json`); scenario `godot/test/sim/ai/test_sc43_fog_fairness.gd` (SC-43).

## How to add X

- A tier's information: a `bot_profiles.json` entry with `vision`, `ghost_memory_s`, `reaction_delay_s` (the promise's
  `reaction_s`); `PerceptionParams.from_dict` reads it.
- A threat source: give the def a weapon; a tower is classified by its `tower` envelope, a ship or ground unit by the
  `fighters` / `ground_attackers` lists of the `threat` block.

## Open items

- `needs sim:` `SimView.visible_ids` allocates and walks every live slot (~135 us of a ~270 us refresh at S-SIM-1);
  TA-63's `visible_enemy_ships(team, out)` (merged, ascending ids) covers enemy ships only, while a refresh also needs
  structures, ground units and the own assets: an O(visible) all-kinds team list (or a `visible_into`) would remove it. Team / owner are cached per id (they change only at spawn today); a capture needs a re-read.
- `needs content:` `bot_profiles.json` (the `perception` entries of `ai22_params.json`) and the `threat` block.
