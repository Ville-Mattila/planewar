# sim_ai/brains - MODULE.md

Contract for `godot/src/sim_ai/brains/**`: the per-class ship autopilots of 05 s6.2-6.4 (AI-13 Dart; AI-14 Lancer,
Bomber, Scout) on one think / act pipeline (`DartBrain`) with the shared sub-machines. Sub-module of `sim_ai` (R0 B.9
A-21 split pattern, as `sim_ai/perception`): `sim_ai/MODULE.md` keeps `AiBrain`, `AiState`, `AiDriver`, `AiTag` and the
autopilot helpers the brains call (`Guidance`, `TeamPicture`, `LandingPilot`, `EscortPilot`, `Separation`,
`TargetChooser`). A change to "Public API" or "Invariants" is a contract change: contract tests first, same PR (ADR-11);
`tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | Dart, Lancer, Bomber and Scout brains: modes (the replicated `AiTag.Tag`), order dispatch, PULL_UP, the RTB rule, AttackRun (bombs, rockets), air combat, the Scout's search and flee. Not: Hauler / Harvester / tower / Crawler brains (AI-15..AI-18), the Commander. |
| Lane owner tier | Opus (sim_ai lane) |
| May depend on | `core`, `content`, `sim` (`SimView`, `CommandSink`, steer); the rest of `sim_ai` |
| Must never touch | Nodes, `net`, `presentation`, `ui`; no `await`, signals, `Thread`, autoloads; never a `SimView` read of an entity the team does not see (05 s6) |
| Autoloads used | None |
| Status | AI-13 (2026-10-21): Dart. AI-14: Lancer, Bomber, Scout; AiState FORMAT 6 (`lock_tick`); `AiBrain.bind_intel`. Constants: fixtures `godot/test/sim/ai/ai13_autopilots.json`, `ai14_autopilots.json` until AI-19 (needs content). |

## Public API

```gdscript
class_name DartBrain extends AiBrain               # AI-13: 05 s6.2 Dart; AiState.mode = its AiTag.Tag, also written as the ai_tag
const B_RTB_SENT: int; const B_RUN_DONE: int; const DOCKED_STATE: int; const SEP_PHASES: int; const B_RESUMED: int   # B_RESUMED: AI-14
var prm: DartParams; var gains: FlightGains; var probe_params: ProbeParams; var terrain: Terrain; var modes: DartModes; var stats_pull_ups: int
var stats_longest_pull_up: int; var stats_sinking_acts: int; var stats_thinks: int; var stats_refreshes: int; var stats_shape_loss: int; var stats_checks: int; var stats_check_loss: int   # deterministic perf counters
static func from_content(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> DartBrain   # null on a missing key; FlightCommonDef from c (A-90)
static func fill(b: DartBrain, c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF, escorts: bool = true, targets: bool = true) -> bool   # AI-14: the shared build of every class brain
func bind_intel(intel: TeamIntel) -> void          # AI-14: DartModes.intel and AttackRun.intel (the driver binds it)
func bind_rng(rng: Rng) -> void;  func think_batch(ids: PackedInt32Array, n: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void;  func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void   # the AiBrain contract
func think_one(id: int, view: SimView, st: AiState, sink: CommandSink, tick: int) -> void   # one think (rigs, perf)
class_name DartModes extends RefCounted            # AI-13: the per-order thinks (RETURN, ESCORT, ATTACK, MOVE, PATROL / HOLD / GUARD / AUTO) and the choice point
const B_RUN_DONE: int
var prm: DartParams; var terrain: Terrain; var landing: LandingPilot; var escort: EscortPilot; var run: AttackRun; var combat: DartCombat; var targets: TargetParams; var stats_choices: int; var picture: TeamPicture
var intel: TeamIntel; var engages: bool; var auto_guard: bool; var ground: bool; var stats_ground: int   # AI-14 class switches (Invariants CB2)
func _init(params: DartParams, t: Terrain, lp: LandingPilot, ep: EscortPilot, ar: AttackRun, dc: DartCombat, tp: TargetParams) -> void
static func patrol_point(home: Vector3, k: int, n: int, radius: float) -> Vector3;  static func is_combat(m: int) -> bool
func choice_due(s: int, tick: int) -> bool         # the think phase of the choice point (every choice_period_thinks, staggered by slot)
func think_return(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int
func think_escort(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int
func think_attack(id: int, s: int, m: int, head: OrderSpec, view: SimView, st: AiState, tick: int) -> int
func think_move(id: int, s: int, head: OrderSpec, view: SimView, st: AiState) -> int
func fly(id: int, s: int, dir: Vector3, band: float, view: SimView, st: AiState, m: int, speed: float = -1.0) -> int   # AI-14: level flight in a band (the Scout leg)
func think_patrol(id: int, s: int, m: int, head: OrderSpec, kind: int, view: SimView, st: AiState, tick: int) -> int
class_name DartCombat extends RefCounted           # AI-13: INTERCEPT / ENGAGE (straight-line gun, R0 C1-03) / EXTEND / EVADE
const F_BOOST: int; const F_FLIP: int
var prm: DartParams; var gains: FlightGains; var rng: Rng; var stats_draws: int; var stats_engage_acts: int; var stats_engage_visible: int
func _init(params: DartParams, flight_gains: FlightGains) -> void
func think(id: int, mode: int, view: SimView, st: AiState, tick: int) -> int
func act_engage(id: int, view: SimView, st: AiState, out: PilotInput, p: Vector3, v: Vector3, b: Basis, tick: int) -> void   # the act's own reads passed in
static func aim_offset(dir: Vector3, err: Vector2, up: Vector3) -> Vector3   # the burst's small aim error applied to `dir` (no rotation per tick)
static func gauss2(r: Rng) -> Vector2              # two standard normals (Box-Muller), the per-burst aim error
class_name AttackRun extends RefCounted            # AI-13: the 05 s6.3 sub-machine R1-R5 (Dart; Lancer / Bomber with AI-14)
enum Step { NONE, ROUTE, RUN_IN, RELEASE, EGRESS, REATTACK, DONE };  enum Band { LOW, DECK, HIGH }
const F_ABORTED: int; const F_RELEASING: int; const F_DIVING: int; const F_BOOST: int; const F_FLIP: int   # bflags bits
var prm: DartParams; var terrain: Terrain; var dart_dive: bool
var rockets: bool; var abort_on_hit: bool; var release_range: float; var breakaway: float; var round_damage: float; var reserve_rounds: int; var intel: TeamIntel   # AI-14
var stats_band_scans: int; var stats_band_queries: int; const FIRE_RESERVE: int; const FIRE_CHECKED: int   # AI-14: R1 work counters; fire_mask bits
func _init(params: DartParams, t: Terrain) -> void
static func step_of(st: AiState, s: int) -> int;  static func band_of(st: AiState, s: int) -> int
func begin(id: int, view: SimView, st: AiState, aim: Vector3, tick: int) -> void;  func think(id: int, target: int, view: SimView, st: AiState, tick: int) -> int
func act(id: int, view: SimView, st: AiState, out: PilotInput) -> void   # R3 sight + stick (FIRE2), egress BOOST / FLIP
func resume(id: int, view: SimView, st: AiState, tick: int) -> int;  func rounds(id: int, view: SimView) -> int   # AI-14: 05 s2.5 re-plan; bombs or rockets
class_name DartParams extends RefCounted           # AI-13: the brain's numbers from ap_dart + ship / rules / order_rules / weapon / tower defs
const KEYS: PackedStringArray; const GUN_KEYS: PackedStringArray; const BOMB_KEYS: PackedStringArray; const EVADE_KEYS: PackedStringArray; const GUIDE_KEYS: PackedStringArray
const INTERCEPT_KEYS: PackedStringArray; const RUN_KEYS: PackedStringArray; const LAUNCH_KEYS: PackedStringArray; const RTB_KEYS: PackedStringArray; const ORDER_KEYS: PackedStringArray
const THREAT_NONE: int; const THREAT_GUN: int; const THREAT_FLAK: int; const THREAT_MISSILE: int
var tick_hz: int; var think_ticks: int; var cruise_speed: float; var boost_speed: float; var dt: float; var gravity: float; var cruise_agl: float; var deck_agl: float; var max_alt: float
var patrol_radius: float; var intercept_radius: float; var clear_tti: float; var pull_up_tti: float; var fire_range: float; var fire_cone_k: float; var burst_ticks: int; var cycle_ticks: int
var aim_error_rad: float; var slug_speed: float; var aoa_comp_max: float; var dive_rad: float; var release_tol: float; var pullout_margin_s: float; var hp_drop: float; var evade_ticks: int
var evade_turn_rad: float; var kp_alt: float; var vz_max: float; var wp_radius: float; var check_ticks: int; var sample_s: float; var pull_up_hold_ticks: int; var launch_tilt_rad: float; var deck_speed: float
var aoa_comp_cos: float; var vision_period: int
var boost_close: float; var lost_ticks: int; var engage_extra: float; var engage_margin: float; var overshoot: float; var extend_ticks: int; var choice_period: int; var patrol_points: int
var patrol_switch: float; var hp_window_ticks: int; var standoff: float; var break_ttc: float; var ip_dist: float; var ip_arrive: float; var band_low: float; var band_high: float
var continue_rad: float; var egress_turn_rad: float; var egress_ticks: int; var abort_hp01: float; var max_passes: int; var predict_dt: float; var predict_steps: int; var dive_release_frac: float
var pitch_over_agl: float; var launch_climb_agl: float; var launch_max_speed: float; var arrival: float; var move_agl: float; var patrol_engage: float; var hold_orbit: float
var guard_orbit: float; var guard_engage: float; var loiter_alt: float; var ghost_ticks: int; var bomb_def: ProjectileDef; var bomb_damage: float; var bomb_interval: float; var rules: RulesDef
var threat_kind: PackedByteArray; var threat_range: PackedFloat32Array; var threat_scan: float; var hp_by_def: PackedFloat32Array; var rtb_ammo: int
var has_gun: bool; var has_bombs: bool; var has_rockets: bool; var secondary: WeaponDef   # AI-14: the blocks a class needs follow its weapons
static func from_content(ap: Dictionary, def: ShipDef, c: ContentSet) -> DartParams;  func ticks(s: float) -> int;  static func block(d: Dictionary, k: String) -> Dictionary
class_name LancerBrain extends DartBrain           # AI-14: 05 s6.4 Lancer (AUTO GUARD on the structure cluster, ground-first, rockets on the lock)
var lp: LancerParams; var stats_lock_starts: int; var stats_fire2_acts: int; var stats_cluster_queries: int; var stats_weapon_acts: int; var stats_weapon_visible: int
static func create(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> LancerBrain   # null on a missing key
class_name BomberBrain extends DartBrain           # AI-14: 05 s6.4 Bomber (AUTO DOCKED, level AttackRun, RETURN after any ATTACK, never dogfights)
static func create(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> BomberBrain
class_name ScoutBrain extends DartBrain            # AI-14: 05 s6.4 Scout (AUTO SEARCH over the team's last_seen cells, FLEE)
var sp: ScoutParams; var stats_scans: int; var stats_flees: int
static func create(c: ContentSet, ap: Dictionary, def: ShipDef, t: Terrain, ring2_m: float = INF) -> ScoutBrain
class_name LancerParams extends RefCounted         # AI-14: ap_lancer `guard_cluster_m` + `rocket` block, the rocket WeaponDef lock
const KEYS: PackedStringArray; const ROCKET_KEYS: PackedStringArray
var guard_cluster: float; var lock_range: float; var bomber_reserve: int; var bomber_known: float; var breakaway: float; var cone_cos: float; var lock_ticks: int; var rocket_damage: float; var bomber_def: int
static func from_content(ap: Dictionary, def: ShipDef, c: ContentSet) -> LancerParams
class_name ScoutParams extends RefCounted          # AI-14: ap_scout `flee_radius_m` + `search` block, rtb.fuel_reserve_s, armed ship defs
const KEYS: PackedStringArray; const SEARCH_KEYS: PackedStringArray
var flee_radius: float; var search_agl: float; var flee_ticks: int; var flee_clear: float; var fuel_reserve_s: float; var fuel_s: float; var armed_by_def: PackedByteArray
static func from_content(ap: Dictionary, def: ShipDef, c: ContentSet) -> ScoutParams
```

## Invariants

- Dart (AI-13, 05 s6.2-6.3; `test_dart_brain.gd`, `test_sc_dart.gd` SC-01 / SC-28 / SC-29, `test_sc_dart_terrain.gd` SC-09 / SC-10 / SC-11 on cradle): DB1 the mode is an `AiTag.Tag` and is the `ai_tag` (set on change and the tick PULL_UP starts); per-entity state is AiState only (FORMAT 5; 6 since AI-14), `TeamPicture` / `TargetContext` are scratch, `target_count` is derived; restore + continue is byte-identical with the driver configured before `deserialize`, so its rebind loop is exercised (`test_dart_brain_is_deterministic_and_restores_s4`, three Darts on one Bomber saved mid-burst, counts compared). DB2 one TerrainProbe pass per think (6 samples); TTI / PULL_UP keep the ballistic probe; the climb command is A-69 over every sample: `v_cmd.radial >= v_r + climb_need` (`Guidance.cleared`, signed), then the deck floor, the sink limit (one `pull_up_loss`; the sink scaled by room / loss) and no climb at `max_alt_m`. DB3 PULL_UP starts at act every `pull_up_check_ticks` (staggered by slot) on the 1.0 s re-sample < 0 OR the A-89 budget (one `pull_up_loss` while sinking; no conservative pre-bound exists: the loss is INF where the chosen elevation has no climb and is not monotone, a (speed, sink) grid bound was undercut by random states), and at think on TTI < `safety_pull_up_tti_s`; it ends (R0 B.17 A-92) at the first think with TTI >= `safety_clear_tti_s`, `pull_up_min_hold_s` held and `climb_need_mps` <= 0, then `prev_mode`; no max hold in v1 (`stats_longest_pull_up` reported); the SAFETY overlay keeps its 05 s2.4 exit. DB4 vision only: choice points take `TeamPicture`, rebuilt once per team per Vision epoch (team t's bits change only in its own pass, so the cache equals the live set every tick: `test_team_picture_is_built_once_per_vision_epoch_and_stays_exact`); an ATTACK on a never-seen entity flies no run; an invisible target's last seen position is `goal`, lost after `lost_s`. DB5 the choice point runs every `choice_period_thinks` (6th) think; the separation term refreshes every `SEP_PHASES` (3rd) think, never on a choice think, and every think while a pair closes (AI-11's rule); engaged, a target chased out of the radius is kept until lost. DB6 ENGAGE steers the nose onto the erroneous lead (`aoa_comp_max_deg`); outside fire range on the think's cached lead (`aim_lead`), inside it on the per-tick lead; `standoff_m` (200) and the ram break-off `break_ttc_s` (2.0) are the 05 s6.2 ENGAGE append of R0 B.17 A-93 (keys in `intercept`). DB7 Deck legs fly at `deck_speed_mps` (160, SC-09's speed). DB8 a run done with no bombs prepends a system RETURN; the RTB rule (every think; the fuel floor cached in `rtb_floor` at the choice period) prepends one per head; no pad: LOITER over home.
- CB1 (AI-14) one pipeline: `LancerBrain`, `BomberBrain`, `ScoutBrain` extend `DartBrain` and differ only in its hooks
  (`_dispatch`, `_on_home`, `_weapons`, `_return_after_attack`, `_needs_rtb`) and the DartModes / AttackRun switches;
  DB1-DB3 and DB8 hold for every class: the mode is an `AiTag.Tag` written only by `_mode` / `_enter_pull_up`
  (`set_ai_tag`; the new words are A-94's reserved FLEE 16 and SEARCH 17, no ordinal appended), PULL_UP ends by the
  A-92 rule (`test_pull_up_exit_waits_for_the_climb_need_in_every_class_brain`), the RTB rule's ammo term needs a gun
  (`DartParams.has_gun`). Per-entity state is AiState only; `lock_tick` (FORMAT 6, FORMAT 5 refused) is the one field
  AI-14 adds; restore + continue mid-lock is byte-identical (`test_class_brains_are_deterministic_and_restore_s4_mid_lock`).
- CB2 switches: `DartModes.engages` (false: Bomber, Scout: PATROL / GUARD / AUTO fly without the choice point),
  `auto_guard` (Lancer: AUTO is a GUARD orbit round `home`), `ground` (Lancer: Perception contacts of enemy ground units
  and structures seen at its last refresh join the ship candidates; a ground pick flies an AttackRun, mode BOMB);
  AttackRun `rockets` (R3 by the lock: from `release_range`, salvo ceil(hp / rocket damage) less the bomber reserve,
  ends when the salvo is gone or inside `breakaway`), `abort_on_hit` (Bomber: damage in R1 aborts to egress; from R2 the
  run continues, 05 s6.3's hull abort still applies), `dart_dive` off for both. With intel bound the R1 band reads the
  team Perception's towers (seen at its last refresh) instead of a `threat_scan` (2.5 km) structure query.
- CB3 05 s2.5 release mid-run: an entity seen POSSESSED or in an overlay at act gets `B_RESUMED`; its first think after
  re-plans a running AttackRun (`AttackRun.resume`): no rounds -> DONE (the brain prepends RETURN); within `ip_dist_m`
  and `continue_deg` of the nose -> RUN_IN from there; else a new IP; EGRESS / REATTACK go on (SC-19, SC-20, SC-21).
- LB Lancer (05 s6.4; `test_lancer_brain.gd`): AUTO GUARD centre = centroid of the friendly structures within
  `guard_cluster_m` of the home pad, one structure query per AUTO start (`stats_cluster_queries`); orbit
  `guard_orbit_radius_m` at `cruise_alt_agl_m`, choice point over `guard_engage_radius_m`. Rockets in INTERCEPT, ENGAGE
  and R3: FIRE2 only while the target is in the seeker cone (`lock_cone_deg` full angle) within `lock_range_m`;
  `lock_tick` = the start of that continuous hold; the sim's seeker fires `lock_ticks` later (LOCK_ACQUIRED on the same
  tick). `bomber_reserve` rockets are kept unless the target is a bomber while a bomber contact (seen or a Perception
  ghost) is within `bomber_known_m` (`fire_mask` FIRE_RESERVE, evaluated on the first think and every choice period).
  Exactly one `visible_to` per weapons act (`stats_weapon_visible == stats_weapon_acts`). ESCORT is DartModes'
  (EscortPilot) as for the Dart.
- BB Bomber (05 s6.4; `test_ai14_brains.gd`, `test_sc_bomber.gd`): AUTO = DOCKED; airborne with no order
  (`order_tick` -1) it asks once for a system RETURN (no pad free: LOITER over home, pad choice retried each choice
  period); PATROL / GUARD without a choice point; an ATTACK on a ship is DONE at once; after any ATTACK: RETURN.
- SB Scout (05 s6.4; `test_ai14_brains.gd`, `test_sc38_scout.gd`): SEARCH picks max `staleness_s / (1 + dist_km)` over
  the 384 cells of the team map's `last_seen` (never seen: the match age) with no AIR_HIGH threat whose round trip
  (here -> cell -> home) fits `(fuel - rtb.fuel_reserve_s) x v_cruise`; it re-picks when the team has seen the cell
  since the choice, is over it, or a threat moved into it, at most once per choice period (`stats_scans`); nothing
  qualifies or no intel: PATROL round home. FLEE (before the order; not in a landing's approach): the nearest armed
  enemy ship of the TeamPicture within `flee_radius_m` that closes or flies at the Scout -> away, FLIP when ahead and
  ready, deck band, BOOST; ends after `search.flee_s` or beyond `search.flee_clear_m` (re-armed by the same rule).
- Content note for AI-19 (R0 B.17 A-93; fixture `ai14_autopilots.json`): `ap_lancer`, `ap_bomber`, `ap_scout` all
  require the 05 s4.4 top level (`cruise_alt_agl_m` 200 / 400 / 500), `separation`, `landing` and the A-93 `guidance`
  (8 keys; `deck_speed_mps` = the class v_boost below 160: 115 / 95 / 190) and `intercept` (12 keys, ap_dart's values)
  blocks. `ap_lancer` adds `target_*`, `gun` (with `aoa_comp_max_deg`; `fire_range_m` 700), `evade`, `rtb.ammo`,
  `formation`, `attack_run` (12 keys; `ip_dist_m` 1500, `band_low_agl_m` 200, `max_passes` 3) and the AI-14 keys
  `guard_cluster_m` (800) and `rocket` {`lock_range_m` 1200, `bomber_reserve` 2, `bomber_known_m` 5000, `breakaway_m`
  300}, `target_weights.structure_building` 0.8. `ap_bomber` adds `bomb` and `attack_run` (`max_passes` 3); no `gun`,
  `evade`, `formation`, `target_*`. `ap_scout` adds `flee_radius_m` (1000) and the AI-14 `search` block {`agl_m` 500,
  `flee_s` 6, `flee_clear_m` 1800}. Ranges: as A-93 for the shared blocks; `rocket` keys > 0 (`bomber_reserve` integer
  >= 0), `search` keys > 0.
- Measured (dev laptop): SC-01 airborne 1.27 s, AGL 150-302 m, <= 1,307 m from the pad; SC-28 10 / 10 kills, Bomber first 10 / 10; SC-29 Deck, 100 % of 18 s in Flak range below 150 m AGL; SC-09 min clearance 30 / 24 m, SC-10 trench 100 % low, rille legs no contact; SC-11 cradle pull-up +0 ticks; 0 unrecoverable states in every tick checked while sinking (265 / 502 / 61 / 139 / 141 / 41).
- Measured AI-14 (dev laptop): SC-19 released 1,799 m out at 10.1 degrees, no ROUTE before the next release, bombs
  6 -> 3, Refinery 1.00 -> 0.60; SC-20 released at 58.1 degrees, ROUTE first, then RELEASE, 5 impacts near, Refinery
  0.20; SC-21 run DONE 16 ticks after the release, system RETURN head the next tick, touchdown 1.99 / 0.02 m/s, tilt
  0.1 degrees, DOCKED; SC-38 >= 15 cells per seed in 3 min, survived 10 / 10 (all unhurt), contact in 9 / 10; Lancer
  first rocket exactly `lock_ticks` (24) after the hold began.
- Perf (`test_dart_perf.gd`, guards row x CI_FACTOR 2 only; counters asserted: choice share 1/6, refresh share <= 0.5, <= 1 `pull_up_loss` per shaped think and per act check, 1 picture per team per epoch). Dev laptop, host scale 1.00: quiet think 41 / median 36 / p95 72 us; engaged think 56 / 41 / 83; act patrol 8.5, act engage in fire range 18.4 us; TeamPicture 221 us for 261 ships = 295 us per tick at 8 teams (cap 450). Engaged think components: hold 29, separation refresh think 68, choice think 73 (choose_engaged 33, combat.think 8.5); act engage: act_engage 8.9 (track_velocity 3.2, lead 1.6) + act_batch reads and the check 5-6. Priced by R0 B.17 A-96: the act row is a fleet mean, asserted as (1 - 0.25) act_patrol + 0.25 act_engage < 12 us, act_engage < 18 us (3 x row) until the pinned runner; engaged think < 50 us; `pull_up_loss` calls per act while sinking == 1 / `pull_up_check_ticks`. R0 B.17 A-97: the timing bounds assert only with PLANEWAR_PINNED_RUNNER=1 (PERF_REPORT lines on hosted runners); the counters (and one `visible_to` per ENGAGE act) are hard everywhere. `_send_rtb` allocates an OrderSpec and a Command per send (rare).
- Perf AI-14 (`test_ai14_perf.gd`, 05 s10 think row 25 us, act row 6 us; PerfGate report-only on hosted runners,
  R0 B.17 A-97; counters hard: one structure query per Lancer AUTO start, one `visible_to` per Lancer weapons act,
  choice share <= 1/6, Scout scans <= one per choice period). Dev laptop, full unit run, beside the same run's
  `test_dart_perf.gd` (Dart quiet think 47.3, engaged 69.5, act patrol 9.3, act engage 19.5 us): Lancer guard think
  46.6 / median 47 / p95 78 us, engaged act with the rocket lock 16.9 us; Bomber run think 61.8 / 61 / 67 (its R1
  descent pays the A-89 sink limit's `pull_up_loss` in `_shape`), act 7.3; Scout search think 39.3 / 38 / 49, act 7.1,
  a scan think 81 us (at most one per choice period: ~14 us amortised). The laptop varied ~2.5x during the day (a loaded
  run: Lancer 101-152, Bomber 178-183, Scout 71-100 beside Dart quiet 118-126). Lever taken: the R1 band from the
  Perception towers (the AI-13 2.5 km `ids_near` cost 167 us of a Bomber think). The hosted A/B (TEST-04) covers the Dart
  only; a class-brain A/B scenario is a follow-up (A-98).
- Open (needs sim): order completion (05 C4) is not wired, so a finished ATTACK stays the head (`B_RUN_DONE`: AUTO patrol under it) and a MOVE orbits its point; Docking (GD-15) is not built, so DOCKED waits; `Spatial.ids_near` beyond `ring2_m` is O(touched cells), and `TeamPicture` builds once per team per Vision epoch from `SimView.visible_enemy_ships` (AI-42, ascending EntityId as the old `ships()` walk). Open (needs content, AI-19): the AI-13 keys of `ai13_autopilots.json` (`guidance`, `intercept`, `attack_run` blocks, `gun.aoa_comp_max_deg`, `evade.heading_change_deg`, `rtb.ammo`). Open (threat map, s7.4; the map exists since AI-22, not wired: AI-13's acceptance does not ask): the IP bearing is the direct one (AI-22 enables R1: score candidate IPs by `driver.threat_map(team).route_risk(ip, target, band)` over the last 5 km), the Autocannon "stay > 450 m" rule (enabled: `threat_at(cell(target), AIR_DECK) > 0` with `AIR_HIGH == 0` marks a gun-only cell) and the `attacked` factor (HIT feed: a `Perception` contact that hit a friendly, recorded only when `visible_to`) are not applied; rail towers do not set a band.
- Open AI-14 (needs sim): GD-15 docking (SC-21 docks by the test's stand-in on an R0 B.5 safe touchdown); the interim
  structure collision sphere (`WorldDefs.radius_of`: footprint half-diagonal, Core ~52 m) covers a pad's own approach,
  so a ship rams its home Core before the A-53 column (the tests set the Core's radius to its pad radius: TA-19 /
  GD-15); order completion for brains (C4 `complete_head`, A-61 / AI-15): a finished ATTACK stays queued behind the
  RETURN. Open (content, AI-19): the content note above. Open (threat map): the IP bearing is still the direct one.

## Test entry points

`godot/test/unit/sim_ai/test_dart_brain.gd`, `test_dart_perf.gd` (AI-13; fixtures `godot/test/sim/ai/dart_kit.gd`,
`ai13_autopilots.json`); `godot/test/sim/ai/test_sc_dart.gd` (SC-01, SC-28, SC-29), `test_sc_dart_terrain.gd` (SC-09,
SC-10, SC-11 on cradle). AI-14: `godot/test/unit/sim_ai/test_ai14_contract.gd`, `test_lancer_brain.gd`,
`test_ai14_brains.gd`, `test_ai14_perf.gd` (fixtures `godot/test/sim/ai/ai14_kit.gd`, `ai14_autopilots.json`);
scenarios `godot/test/sim/ai/test_sc_bomber.gd` (SC-19, SC-20, SC-21), `test_sc38_scout.gd` (SC-38).

## How to add X

- A class brain: extend `DartBrain`, build with `DartBrain.fill`, override the hooks; its numbers in its `ap_*` (a
  `XParams.from_content` with no defaults); its words from `AiTag.Tag` (append in `sim_ai/MODULE.md` only when missing).
