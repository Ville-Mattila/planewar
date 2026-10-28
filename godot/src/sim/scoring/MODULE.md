# sim/scoring - MODULE.md

Contract for `godot/src/sim/scoring/**`: the landing grade (`LandingGrade`, 08 SL-1 as simplified by R0 C3-13; 02 s17.1,
03 s6.4), 03 s3.2's `scoring` side table (`LandingLog`: every ship's last grade and q; GD-15) and the score events with the
per-player Pilot / Commander scores and the match result fields of 02 s17.1 (`ScoreKeeper`, GD-27). A-21 split of `sim/MODULE.md` (which keeps `LandingGrade` as a
named public type for `ui`). A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR
(ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | The quality score q of one touchdown and its grade (ACE / CLEAN / FAIR / HARD by q, BENT, CRASH, AUTO), the repair-bonus rule, and the per-ship record of the last grade read by `SimView.landing_grade_last` and the service's repair bonus. The score events of 02 s17.1 (kills, structures, assists, landings, salvage, Ice, Relay, Ore spent, match_win) onto the Pilot or Commander side of each player, and the per-player / per-team match result. Not here: detecting the landing, its damage and the LANDING event (`sim/docking/` `Touchdown`). |
| Lane owner tier | Opus (sim lane); Sonnet against this file |
| May depend on | `core`, `content` (`ScoringDef`, `ContentSet`), `sim` (`Collision` band constants, `EntityStore`, `DefRanges`; `sim/world/` `StateIO`, `InputSlots`, `PlayerTable`, `SimEvents`, `WorldDefs`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, signals, `Thread`, autoloads, RNG |
| Autoloads used | None |
| Status | implemented (GD-15, 2026-10-23; GD-27 2026-10-28); `Docking` owns one `LandingGrade` and one `LandingLog` (S4, economy section, format 13); `EconomyHub.score` owns the `ScoreKeeper` (format 14) |

## Public API

```gdscript
class_name LandingGrade extends RefCounted
enum Grade { CRASH, BENT, HARD, FAIR, CLEAN, ACE, AUTO }                    # R0 B.3 frozen ordinals (sim/MODULE.md Enumerations)
var w_vert: float; var w_horiz: float; var w_tilt: float; var w_offset: float   # scoring.landing.q_weights
var n_vert: float; var n_horiz: float; var n_tilt: float                       # scoring.landing.q_norms (8 m/s, 15 m/s, 25 deg)
var t_fair: float; var t_clean: float; var t_ace: float                         # scoring.landing.q_thresholds (0.40, 0.65, 0.85)
var hot_radius_m: float; var hot_window_s: float; var dead_stick_fuel01: float  # hot_enemy_range_m 1,500, hot_hit_window_s 5, 0.03
var manual_window_m: float; var repair_time_mult: float                        # typed ScoringDef.landing_grade.manual_window_m 150 (A-122), landing.repair_time_mult 0.9
static func from_def(scoring: ScoringDef) -> LandingGrade                     # null when a key (incl. the landing_grade block) is missing or a norm is <= 0
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

class_name ScoreKeeper extends RefCounted                                     # GD-27: EconomyHub.score; fed inside SimWorld.step()
var ledger: ScoreLedger;  var hits: ScoreHits
func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, events: SimEvents, hz: int) -> void
func score_of(slot: int) -> Vector2i                                          # (pilot, commander); SimView.player_score
func landing_points(grade: int, flags: int) -> float                          # grade points x hot_mult (bit1) + dead_stick_bonus (bit2); 0 unless manual (bit0) and HARD..ACE
func scan() -> void                                                           # events emitted since the last scan: HIT, LANDING, POSSESSED, BUILD_DONE, SALVAGE_DELIVERED
func on_dying(dying: PackedInt32Array, t: int) -> void                        # end of step 9, before the frees: scan, then kills / deaths / structures / assists
func end_tick(spent_ore: PackedInt32Array) -> void                            # end of step 10: scan, pilot time per class, Ore spent (commander_ore_spent on its high-water mark)
func finalize(winner_team: int) -> void                                       # MATCH_END: match_win to each member of the winner, once
func ore_mined(player: int, ore: int) -> void;  func ice_delivered(player: int, ice: int, possessed: bool) -> void   # seams of GD-12 / GD-14
func relay_captured(player: int, possessed: bool) -> void;  func relay_held(player: int, minutes: float) -> void       # seams of GD-23
func structure_value(team: int) -> int;  func result(winner_team: int, tick: int) -> MatchResult
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool

class_name ScoreLedger extends RefCounted                                     # per-player arrays (slot index): pilot, commander, kills, deaths, structures_built, structures_destroyed, manual_landings, sorties, ore_mined, ore_spent, ice_delivered; pilot_ticks[slot * 5 + class]
const SLOTS: int;  const CLASS_COUNT: int;  const CLASS_IDS: PackedStringArray   # dart, lancer, bomber, scout, hauler (04 s2.3 pilot_time_s order)
func _init() -> void
func credit(slot: int, pilot_side: bool, points: float) -> void               # whole points to the side, the fraction carries
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool

class_name ScoreHits extends RefCounted                                       # the assist damage window: a 4,096-record ring of enemy hits
const CAP: int
func _init() -> void
func record(victim_id: int, by_owner: int, by_pilot: bool, amount: float, t: int, window_ticks: int) -> void
func shares(victim_id: int, t: int, window_ticks: int, total: PackedFloat32Array, by_pilot: PackedFloat32Array) -> float
func write_state(buf: StreamPeerBuffer) -> void;  func read_state(buf: StreamPeerBuffer) -> bool

class_name MatchResult extends RefCounted                                     # SimWorld.match_result(); 02 s17.1 / 04 s2.3 MATCH_END (encoded by NET-22)
var winner_team: int;  var tick: int;  var structure_value: PackedInt32Array;  var players: Array[PlayerResult]   # active players in slot order; structure_value per team

class_name PlayerResult extends RefCounted
var slot: int;  var team: int;  var score_pilot: int;  var score_commander: int;  var kills: int;  var deaths: int
var structures_built: int;  var structures_destroyed: int;  var manual_landings: int;  var sorties: int
var ore_mined: int;  var ore_spent: int;  var ice_delivered: int;  var pilot_time_s: PackedInt32Array;  var medals: PackedByteArray   # pilot_time_s[5] seconds per class; medals empty until GD-28
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
- G6 Pilot / Commander (02 s17.1): a point earned by the entity its owner possesses (`PlayerTable.possessed`) is Pilot; the rest is
  Commander. Kills and structure kills of an unpossessed entity (AUTO / ORDERED) pay `commander_auto_kill_share` of the value
  to the Commander side. Only enemy-team kills of a killer that damaged the victim within `assist.window_s` score. Score never
  changes the match.
- G7 Points: kills = `kill_points` (+ `kill_hauler_loaded_bonus` for a Hauler with cargo or a tow); structure kills =
  (cost_ore + cost_ice) x `structure_destroyed_ratio` of a finished structure, `core_destroyed` for the Core; every enemy
  structure hit pays `structure_damage_points_per_hp` per hp dealt (overkill included); an assist (>= `assist.min_share` of the
  damage within the window, not the killer's owner) pays `assist.kill_share` of the kill value (Pilot side when most of that
  damage came from possessed attackers); landings pay `landing.points[grade]` for a manual HARD..ACE landing, x `hot_mult` for
  LANDING flags bit1, + `dead_stick_bonus` for bit2 (R0 B.24 A-121), always Pilot side; salvage, Ice, Relay and Ore spent per
  the def ratios; `match_win` to each member of the winning team at MATCH_END. Fractions carry; scores are whole points.
- G8 `commander_ore_spent` pays on the high-water mark of net Ore spent (`Build.spent_ore`), so cancel-and-repay earns nothing.
- G9 The result carries every 02 s17.1 field plus the 04 row's kills, deaths, structures_built and manual_landings; `medals`
  is empty until GD-28; encoding and `result_hash` belong to the server (NET-22).
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
`godot/test/unit/sim/scoring/test_score_kills.gd` (G6, G7: one test per kill / structure / assist event), `test_score_landing.gd` (landing points, hot, dead stick, typed `landing_grade`), `test_score_economy.gd` (salvage, Ice, Relay, Ore spent G8, match_win, split), `test_match_result.gd` (G9, S4 round trip).

## How to add X

- **A grade input (e.g. a new q term):** a `scoring.json` field with its schema and `_doc` (ADR-09), read in `from_def`,
  a term in `q` and a row in the grade table test; the weights must still sum to 1.
- **A score event:** a `scoring.json` ratio (schema + `_doc`, ADR-09), a handler in `ScoreKeeper` (or a public seam
  method for a system that has not landed) crediting `ledger.credit(slot, pilot_side, points)`, and one test in
  `test_score_*.gd`.
- **A result field:** a `ScoreLedger` array (in `_PER_SLOT` and `_STATE`; bump `SimSerialize.FORMAT`), a `PlayerResult`
  var set in `ScoreKeeper._row`, and a line in `test_match_result.gd`.

## Open items

- `ice_delivered` / `ore_mined` (GD-12, GD-14) and `relay_captured` / `relay_held` (GD-23) are called by those tasks when
  they land; nothing in the sim calls them yet. `medals[]` is filled by GD-28's evaluator.
- `MATCH_END`'s per-player tail is encoded by NET-22 (`server/`) from `SimWorld.match_result()`.
