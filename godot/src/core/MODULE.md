# core - MODULE.md

Contract for `godot/src/core/**` (03 s15.2, ADR-14). Written by TA-04 with `sphere.gd`; TA-06 owns any
later template alignment. A change to "Public API" or "Invariants" is a contract change: update the
contract tests first, in the same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines.
Section order follows `docs/templates/MODULE.md.template` (03 s15.1, TA-06); the signatures below are copied
from `godot/src/core/*.gd` (TA-06 review), not from the 03 s15.2 draft.

| Field | Value |
|---|---|
| Responsibility | Pure, Node-free utilities every other module uses: sphere math and cube-face addressing, entity id packing, PCG32 RNG, logging, configuration access, `Result` type, small math helpers. Owns `PLANET_RADIUS`. Does not know about entities, defs or the sim. |
| Lane owner tier | Opus for `sphere.gd`; Haiku for the rest |
| May depend on | Godot built-ins only (`tools/deps.json`: `core` has no edges) |
| Must never touch | Nodes, scenes, other modules; no `await`, no signals, no `Thread` (D2, D3) |
| Autoloads used | `Log` is defined here (`log.gd`, no `class_name`) and is the only autoload in `core` |
| Status | API frozen (2026-10-10); `PLANET_RADIUS` = 6,000 confirmed by the owner |

## Public API

Anything not listed is private (prefix `_`). Formulas and test vectors: 03 s2.

```gdscript
class_name Sphere                     # all static; see 03 s2
const PLANET_RADIUS: float; const RELIEF_MIN: float; const RELIEF_MAX: float
const CEILING_SOFT: float; const CEILING_HARD: float; const MAX_SIM_MAGNITUDE: float
const POLE_AXIS: Vector3; const PRIME_AXIS: Vector3; const SLOT_LON0_DEG: float; const SLOT_SPACING_DEG: float
const GRID_BUILD: int; const GRID_PATH: int; const GRID_HASH: int; const GRID_INTEREST: int
const DIR_NEG_U: int; const DIR_POS_U: int; const DIR_NEG_V: int; const DIR_POS_V: int   # 0..3, also edge ids
const EDGE_NEIGHBOUR_STRIDE: int                 # 3
const EDGE_NEIGHBOUR: PackedInt32Array          # row face * 4 + edge -> [nbr_face, nbr_edge, along_is_u] (03 s2.6), flat
static func altitude(p: Vector3) -> float
static func up_at(p: Vector3) -> Vector3
static func tangent_frame(p: Vector3) -> Basis                       # columns east, north, up
static func lat_lon(p: Vector3) -> Vector2                           # (lat, lon) radians
static func from_lat_lon(lat: float, lon: float, radius: float) -> Vector3
static func great_circle(a: Vector3, b: Vector3) -> float            # metres on the datum sphere
static func bearing(from: Vector3, to: Vector3) -> float             # radians clockwise from north
static func slerp_dir(a: Vector3, b: Vector3, t: float) -> Vector3
static func transport(n_old: Vector3, n_new: Vector3) -> Quaternion
static func face_frame(face: int) -> Basis                           # columns S_f, T_f, N_f
static func face_uv_to_dir(face: int, u: float, v: float) -> Vector3
static func dir_to_face_uv(d: Vector3) -> Vector3                    # (face, u, v)
static func cell_of(d: Vector3, n: int) -> int
static func cell_center_dir(cell: int, n: int) -> Vector3
static func cell_bounds_dirs(cell: int, n: int) -> PackedVector3Array   # corners (i,j) (i+1,j) (i+1,j+1) (i,j+1)
static func cell_face(cell: int, n: int) -> int;  static func cell_i(cell: int, n: int) -> int;  static func cell_j(cell: int, n: int) -> int
static func parent_cell(cell: int, n_from: int, n_to: int) -> int   # n_to < n_from, both powers of two
static func neighbour_cell(cell: int, n: int, dir: int) -> int       # dir 0 -u, 1 +u, 2 -v, 3 +v
static func neighbours8(cell: int, n: int) -> PackedInt32Array      # 8 ids; 7 at the 24 cube-corner cells
static func cells_in_radius(center: Vector3, radius_m: float, n: int) -> PackedInt32Array   # conservative
static func horizon_distance(h: float) -> float
static func is_occluded_by_datum(a: Vector3, b: Vector3) -> bool          # true iff the open segment (a, b) dips inside the datum sphere; endpoints never occlude (R0 B.9 A-10)

class_name EntityId                   # static; id packing
const NULL_ID: int;  const SLOT_MASK: int;  const GEN_MASK: int;  const GEN_SHIFT: int;  const GEN_MAX: int
const PROJECTILE_SLOT_MIN: int;  const WRECK_SLOT_MIN: int;  const WRECK_SLOT_END: int
const PROJECTILE_SLOT_END: int        # exclusive; ProjectileStore.SLOT_COUNT = PROJECTILE_SLOT_END - PROJECTILE_SLOT_MIN (TA-46, R0 B.9 A-20)
static func make(slot_index: int, gen_value: int) -> int;  static func slot(id: int) -> int;  static func gen(id: int) -> int
static func bump_gen(g: int) -> int
static func is_projectile(id: int) -> bool;  static func is_wreck(id: int) -> bool

class_name Rng extends RefCounted     # PCG32, deterministic given seed, serialisable
const STATE_BYTES: int                # serialised state size (24)
func _init(seed_value: int, stream: int = 0) -> void
func next_u32() -> int;  func next_float() -> float               # [0,1)
func range_i(lo: int, hi_inclusive: int) -> int;  func range_f(lo: float, hi: float) -> float
func state() -> PackedByteArray;  static func from_state(bytes: PackedByteArray) -> Rng
func fork(stream: StringName) -> Rng                              # deterministic sub-stream, serialised with the parent

Log                                   # autoload (log.gd extends Node, no class_name); the only Node in core
enum Level { DEBUG, INFO, WARN, ERROR };  const DEBUG: bool       # DEBUG = false for release builds (see log.gd)
func debug(tag: StringName, msg: String) -> void;  func info(tag: StringName, msg: String) -> void
func warn(tag: StringName, msg: String) -> void;   func error(tag: StringName, msg: String) -> void
func set_level(level: int) -> void;  func set_sink(cb: Callable) -> void        # tests and the server capture here

class_name Config                     # static; project settings and command-line overrides
static func get_flag(name: StringName) -> bool;  static func get_int(name: StringName, default: int) -> int
static func get_str(name: StringName, default: String) -> String
static func parse_override(args: PackedStringArray, key: String) -> PackedStringArray   # [value] for --key=value, ["true"] for --key
static func is_server() -> bool;  static func is_web() -> bool;  static func is_mobile() -> bool
static func default_offline_caps_profile() -> StringName

class_name Result extends RefCounted  # ok/err without exceptions
var ok: bool; var error: int; var message: String; var value: Variant
static func success(v: Variant = null) -> Result;  static func failure(code: int, msg: String) -> Result

class_name MathX                      # static helpers that keep warning annotations out of sim code
static func floori_div(a: int, b: int) -> int;  static func posmod_i(a: int, b: int) -> int
static func move_toward_v3(from: Vector3, to: Vector3, delta: float) -> Vector3
static func smoothstep01(e0: float, e1: float, x: float) -> float
```

## Conventions (03 s2.2, 2.5, 2.6)

- World frame: +Z is the Noon Pole, longitude 0 is +X (centre of face 0), longitude grows counter-clockwise
  seen from +Z. `tangent_frame((R,0,0))` = east +Y, north +Z, up +X.
- Faces: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z (Noon), 5 -Z (Midnight); `S_f x T_f = N_f` on every face, so no edge
  crossing reverses the along-edge coordinate. Ties on an edge go to the lower face index.
- `cell_id = face * n * n + j * n + i`, `i = floor(u * n)`, `j = floor(v * n)` clamped to `n - 1`. The grids
  1024 -> 256 -> 64 -> 8 nest by right shifts of `i` and `j` within a face.
- Start slot `k` (0..7) sits at lat 0, lon `SLOT_LON0_DEG + SLOT_SPACING_DEG * k` degrees: (u, v) = 0.25 / 0.75
  on an equatorial face centre line, 22.5 degrees (about 2.4 km) from the nearest cube edge. Player-count
  subsets come from `modes.json` `slots_by_player_count`, never from `2 * pi * i / N`.
- `transport` is not defined for antipodal directions (asserts in debug, returns identity in release).
- `great_circle` is scale-invariant (`atan2(|a x b|, a . b)`); inputs need not be normalised.
- `EDGE_NEIGHBOUR` is a flat `PackedInt32Array` of 24 rows x `EDGE_NEIGHBOUR_STRIDE` (3): row `face * 4 + edge` holds
  `[nbr_face, nbr_edge, along_is_u]` (03 s2.6 as amended by R0 B.9 A-8; a `const Array[PackedInt32Array]` is not a
  constant expression in GDScript).
- `is_occluded_by_datum(a, b)` (R0 B.9 A-10): true iff the point of the open segment (a, b) nearest the moon centre lies
  strictly inside the datum sphere (`|.| < PLANET_RADIUS`). Endpoints are excluded, so an entity below the datum (mare or
  crater floor, relief down to -500 m) neither occludes itself nor is hidden from a higher observer; `a == b` is false;
  the result is symmetric. Vision (03 s3.7, TA-37) and the horizon cull (03 s7.5) pass positions as they are, with no
  altitude clamp; the Sensor Mast exception is Vision's, not this function's.

## Invariants

- C1: `|face_uv_to_dir(dir_to_face_uv(d)) - d| < 1e-6` for all unit `d`.
- C2: `transport(n, n') * n == n'` to 1e-6, `|q| = 1`, tangents stay tangent and keep length; `transport(n, n)` is identity.
- C3: `neighbour_cell` is symmetric within faces and across edges: from `nb = neighbour_cell(c, dir)`, stepping
  `dir ^ 1` (same face) or the entered edge `EDGE_NEIGHBOUR[(face * 4 + dir) * 3 + 1]` (across an edge) returns `c`.
  `neighbours8` is symmetric.
- C4: `great_circle(a, b) == great_circle(b, a)`; `great_circle(a, a) == 0`.
- C5: `EDGE_NEIGHBOUR` equals the table regenerated from the face frames.
- C6: `Rng` produces the reference PCG32 sequence for seed 42 stream 54 (first 10 outputs committed).
- C7: no function allocates on the heap except those returning arrays.
- C8: `MAX_SIM_MAGNITUDE < 8192`.
- C9: no start slot `22.5 + 45 k` lies within 10 degrees of a cube edge (asserted from the constants).
- `PLANET_RADIUS` (6,000) is typed once, in `sphere.gd`; every other module derives from it (D6).

## Data owned

No persistent state. `Sphere` holds only `const` tables (face frames, `EDGE_NEIGHBOUR`). An `Rng` instance owns its
PCG32 state (24 bytes via `state()`). `Log` owns its level and sink. `Config` reads project settings and the command
line on each call; it caches nothing.

## Events emitted / consumed

None. `core` emits no `SimEvent`, no signals and accepts no `Command`. `Log` hands `(level, tag, msg)` to the sink set
by `set_sink`, or to `print()` when no sink is set.

## Performance budget

PC-mid, per call, `godot/test/perf/perf_core.gd`: `face_uv_to_dir` <= 0.6 us, `dir_to_face_uv` <= 0.8 us,
`cell_of` <= 1.0 us, `transport` <= 0.4 us, `great_circle` <= 0.3 us. GitHub-hosted runners print the numbers;
`--strict` gating runs on the pinned perf runner only.

## Test entry points

- `godot/test/unit/core/test_sphere.gd` (03 s2.8 vectors, C1-C5 on 10,000 random dirs, C8, C9, determinism)
- `godot/test/unit/core/test_entity_id.gd`, `godot/test/unit/core/test_rng.gd` (C6), `godot/test/unit/core/test_result.gd`
- `godot/test/unit/core/test_log.gd`, `godot/test/unit/core/test_config.gd`, `godot/test/unit/core/test_mathx.gd`
- `godot/test/perf/perf_core.gd` (`godot --headless --path godot -s res://test/perf/perf_core.gd`)

## How to add a cell helper

Add the static func to `sphere.gd` under the "cells" region; add a vector row in the 03 s2.8 style to
`test_sphere.gd`; list the signature above; run `gen_module_api.py --check`. Keep `sphere.gd` <= 400 lines;
split into a second static class (e.g. `SphereCells`) before crossing it.

## Open items

- `tools/gen_module_api.py --check` does not exist yet; the signature block above is checked by hand until TA-27 lands.
- No open CONTRACT-0 questions for `core`; the API is frozen (2026-10-10). TA-04's doc follow-ups are settled in
  `docs/reviews/R0-amendments-02.md`: A-8 (flat `EDGE_NEIGHBOUR`), A-9 (C3 as stated above is canonical; 03 s2.6 mirrors
  it), A-10 (`is_occluded_by_datum` semantics; TA-37 adds the both-endpoints-below-datum vector).
- TA-46 appended `EntityId.PROJECTILE_SLOT_END` (6,144, exclusive; R0 B.9 A-20); `sim/projectile_store.gd` derives
  `SLOT_COUNT` from it. `is_projectile` stays open-ended (`slot >= PROJECTILE_SLOT_MIN`, 03 s3.1; R0 B.10 A-42,
  `docs/reviews/R0-amendments-03.md`): it classifies the range, the store validates the index and generation, and no
  allocator mints a slot at or above `PROJECTILE_SLOT_END`. Decoders validate ids against the store, not the predicate.
