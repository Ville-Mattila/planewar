# sim/scoring - MODULE.md

Contract for `godot/src/sim/scoring/**`: the landing grade (`LandingGrade`, 08 SL-1 as simplified by R0 C3-13; 02 s17.1,
03 s6.4) and 03 s3.2's `scoring` side table (`LandingLog`: every ship's last grade and q). GD-15; GD-27 adds the score
events and the per-player Pilot / Commander scores here. A-21 split of `sim/MODULE.md` (which keeps `LandingGrade` as a
named public type for `ui`). A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR
(ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | The quality score q of one touchdown and its grade (ACE / CLEAN / FAIR / HARD by q, BENT, CRASH, AUTO), the repair-bonus rule, and the per-ship record of the last grade read by `SimView.landing_grade_last` and the service's repair bonus. Not here: detecting the landing, its damage and the LANDING event (`sim/docking/` `Touchdown`), points (GD-27). |
| Lane owner tier | Opus (sim lane); Sonnet against this file |
| May depend on | `core`, `content` (`ScoringDef`), `sim` (`Collision` band constants; `sim/world/` `StateIO`, `InputSlots`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (GD-15, 2026-10-23); `Docking` owns one `LandingGrade` (from `ContentSet.scoring`) and one `LandingLog` (S4, economy section, format 13) |

## Public API

```gdscript
class_name LandingGrade extends RefCounted
enum Grade { CRASH, BENT, HARD, FAIR, CLEAN, ACE, AUTO }                    # R0 B.3 frozen ordinals (sim/MODULE.md Enumerations)
var w_vert: float; var w_horiz: float; var w_tilt: float; var w_offset: float   # scoring.landing.q_weights
var n_vert: float; var n_horiz: float; var n_tilt: float                       # scoring.landing.q_norms (8 m/s, 15 m/s, 25 deg)
var t_fair: float; var t_clean: float; var t_ace: float                         # scoring.landing.q_thresholds (0.40, 0.65, 0.85)
var hot_radius_m: float; var hot_window_s: float; var dead_stick_fuel01: float  # hot_enemy_range_m 1,500, hot_hit_window_s 5, 0.03
var manual_window_m: float; var repair_time_mult: float                        # landing_grade.manual_window_m 150, landing.repair_time_mult 0.9
static func from_def(scoring: ScoringDef) -> LandingGrade                     # null when a key is missing or a norm is <= 0
func q(v_vert: float, v_horiz: float, tilt_deg: float, offset_m: float, pad_radius_m: float) -> float
func grade(band: int, q_value: float, manual: bool) -> Grade                  # band = Collision.L_SAFE / L_DAMAGE / L_DESTROY
static func repair_bonus(g: int) -> bool                                      # FAIR, CLEAN, ACE

class_name LandingLog extends RefCounted                                      # 03 s3.2 `scoring`, per ship
const NONE: int                                                              # g_grade of a slot with no landing (255)
var g_id: PackedInt32Array; var g_grade: PackedByteArray; var g_q: PackedFloat32Array   # per main-range entity slot
func _init() -> void
func record(id: int, grade: int, q: float) -> void
func grade_of(id: int) -> int;  func q_of(id: int) -> float                  # -1 / -1.0 when `id` has no landing of its own
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool
```

## Invariants

- G1 q = w_vert clamp(1 - v_vert / n_vert) + w_horiz clamp(1 - v_horiz / n_horiz) + w_tilt clamp(1 - tilt / n_tilt) +
  w_offset clamp(1 - offset / pad_radius_m), every term clamped to [0, 1] (a climbing ship's vertical term is 1; a pad
  radius <= 0 scores the offset term 0). Weights sum to 1 (validate_content.py), so q is in [0, 1].
- G2 grade: band DESTROY -> CRASH; band DAMAGE -> BENT; else not manual -> AUTO; else q >= t_ace ACE, >= t_clean CLEAN,
  >= t_fair FAIR, else HARD (thresholds inclusive). The physical outcome outranks AUTO; `Touchdown` turns BENT into CRASH
  when the hull damage empties the ship.
- G3 `repair_bonus(g)` is true exactly for FAIR, CLEAN and ACE (02 s17.1: "a manual landing graded FAIR or better"; those
  grades are never given to a landing that is not manual).
- G4 `LandingLog.grade_of(id)` is the grade of `id`'s own last landing: a slot re-used by another entity reads -1 until
  that entity lands (records are stamped with the EntityId). `read_state` refuses sizes other than `InputSlots.ENTITY_SLOTS`
  and grades beyond AUTO.
- G5 Every number is a def value (`scoring.json` `landing` and `landing_grade.manual_window_m`); the q norms equal the
  `flight_common` safe limits in the shipped content (test_landing_grade).

## Data owned

`LandingLog`: per main-range entity slot the EntityId, grade and q of its last landing. `LandingGrade` is immutable after
`from_def`.

## Events emitted / consumed

None (LANDING is `Touchdown`'s, `sim/docking/`).

## Performance budget

03 s4.2 row 10 reserved line "SL-1 landing grade lives in step 10 at < 0.05 ms": one `q` + `grade` per landing (a few
float operations); the per-landing cost is `Touchdown`'s (sim/docking/MODULE.md).

## Test entry points

`godot/test/unit/sim/scoring/test_landing_grade.gd`: G1 (q terms and clamps), G2 (24-row grade table over the 8 m/s,
15 m/s, 25 degree and pad_radius_m boundaries and the 15 / 25 m/s, 45 degree damage limits; threshold edges), G3, G4
(record, stale slot, S4 round trip, refusal), G5 (from_def against the shipped `scoring.json`).
`godot/test/unit/sim/test_enums.gd` (`LandingGrade.Grade` ordinals, S14).

## How to add X

- **A grade input (e.g. a new q term):** a `scoring.json` field with its schema and `_doc` (ADR-09), read in `from_def`,
  a term in `q` and a row in the grade table test; the weights must still sum to 1.
- **Score points (GD-27):** read the grade from LANDING (`extra[0]`) or `LandingLog`; points live in `scoring.landing.points`.

## Open items

- `ScoringDef` keeps `landing_grade` untyped: `from_def` reads `manual_window_m` from `ScoringDef.raw` (needs content: a
  typed field).
