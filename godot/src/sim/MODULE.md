# sim - MODULE.md

Contract for `godot/src/sim/**`. Committed by CONTRACT-0 from R0 Part B (B.3 enumerations, B.4 deps, B.5 motion, tick
order, signatures) and 03 s15.4; supersedes 01 s9.4's signature-level listing. A change to "Public API", "Enumerations"
or "Invariants" is a contract change: contract tests first, same PR (ADR-11); `tools/gen_module_api.py --check` (TA-27)
must pass; <= 300 lines (ADR-14). Subsystems with their own lane (`sim/steer/`, `sim/orders/`, `sim/control/`, `sim/scoring/`)
open `godot/src/sim/<subsystem>/MODULE.md` from the template with their first code and are listed here by name (R0 B.9 A-21).

| Field | Value |
|---|---|
| Responsibility | Everything that changes game state: entity store, kinematics, ground motion, projectiles, collision, combat, economy, production, build, docking and service, orders (`sim/orders/`), control states (`sim/control/`), pure steering controllers (`sim/steer/`), scoring (`sim/scoring/` LandingGrade), vision, spatial index, pathing, terrain sampling, command validation, events, alert kinds, serialization; the abstract AI hook. Deterministic given (map, defs, seed, command stream, AI hook) on one machine. No Nodes, no net, no AI decisions (AI lives in `sim_ai` and reaches the sim only through `SimAiHook` / `CommandSinkBase`). |
| Lane owner tier | Opus (all systems); Sonnet for well-specified systems against this file (Production, Build placement, Docking, GroundMotion); 05's lane writes `sim/steer/`, `sim/orders/`, `sim/control/`; Haiku for sim tests from scenario JSON |
| May depend on | `core`, `content` (R0 B.4, `tools/deps.json`) |
| Must never touch | Nodes, `net`, `presentation`, `ui`, `sim_ai`; no `await`, no signals, no `Thread` (D2, D3) |
| Public types other lanes may name (D1) | `input`: `PilotInput`. `ui`: `SimView`, `SimEvent`, `Command`, `CommandResult`, `PilotInput`, `AlertKind`, `OrderSpec`, `LandingGrade`, read-only `Terrain`. `campaign`: commands, events, `SimView`, `CommandSinkBase`. `net`: `SimWorld`, `Command`, `PilotInput`, `Kinematics`, `SimView`, `Assist`, `Terrain` (read) |
| Autoloads used | `ContentDB` (read at `load_map` into local references; never afterwards), `Log` |
| Status | API frozen with CONTRACT-0 (2026-10-10); amendments 01 (R0 B.8, same day) appended `ProjectileState`, `TeamStateView`, `PlayerStateView`; amendments 02 (R0 B.9, 2026-10-13) appended the `step_projectile` `out` parameter, `brake_fade_mps` and the projectile 0-tick quarantine; internals open until S-SIM-1 (TA-22) |

## Public API

R0 B.5 signatures; "(03)" marks symbols 03 s15.4 adds. Anything not listed is private (prefix `_`).

```gdscript
# planned: SimWorld, SimAiHook, CommandSinkBase, Command, CommandResult, GroundMotion, Build, Pathing, MatchRules, MatchArc, PlayerKind, SimView, TeamStateView, PlayerStateView, SimEvent, OrderSpec, AlertKind, Assist, LandingGrade
class_name SimWorld extends RefCounted
func load_map(map: MapDef, seed: int, rules: MatchRules) -> Result            # rules carries mode, caps profile, sim_budget_profile
func add_player(slot: int, team: int, doctrine: StringName, kind: PlayerKind) -> void
func remove_player(slot: int) -> void                                        # disconnect: sim flags; the AI hook's caretaker takes over (05)
func set_ai_hook(hook: SimAiHook) -> void                                    # sim_ai attaches here; sim never imports sim_ai
func apply_command(cmd: Command) -> CommandResult
func step() -> void                                                          # one tick in the tick order below
func tick() -> int
func view() -> SimView                                                       # LocalSimView
func drain_events() -> Array[SimEvent]
func serialize() -> PackedByteArray                                          # includes the AI hook's opaque bytes
static func deserialize(bytes: PackedByteArray, content: ContentDB, hook: SimAiHook) -> SimWorld
func profile() -> PackedFloat32Array                                         # 14 rows of 03 s4.4 for the last tick
func set_budget_profile(level: int) -> void                                  # activate cut rungs 1..level of 03 s4.3 at runtime
func terrain() -> Terrain                                                    # read-only sampler shared with presentation
func store() -> EntityStore;  func projectiles() -> ProjectileStore          # (03) net encoder and tests only; presentation uses view()

class_name SimAiHook extends RefCounted                                      # abstract; sim_ai's AiDriver implements it (05 s1.3)
func on_tick(tick: int, view: SimView, sink: CommandSinkBase) -> void        # tick-order step 3
class_name CommandSinkBase extends RefCounted                                # abstract; SimWorld passes its implementation to on_tick; campaign's MissionRuntime receives one
func submit(cmd: Command) -> CommandResult
func drive(id: int, input: PilotInput) -> bool                               # writes the input slot; false if POSSESSED or dead
func set_ai_tag(id: int, tag: int) -> void

class_name Command extends RefCounted
enum Kind { ORDER, BUILD, CANCEL_BUILD, PRODUCE, CANCEL_PRODUCE, SET_RALLY, POSSESS, RELEASE, REQUEST_POSSESS, HANDOVER,
            PILOT_INPUT, TOGGLE_AUTO_REPLENISH, SURRENDER, SET_ADJUTANT, DEBUG_SPAWN, DEBUG_SET }   # 0-15 frozen; DEBUG_* only when rules.debug_commands
var tick: int; var player: int; var kind: Kind; var target: int; var payload: PackedByteArray   # payload layouts: 04 s2.5
static func order(player: int, ids: PackedInt32Array, spec: OrderSpec) -> Command                  # (03) builders
static func build(player: int, def_id: int, cell: int, rotation: int) -> Command
static func produce(player: int, factory: int, def_id: int, count: int) -> Command
static func possess(player: int, id: int) -> Command;  static func release(player: int) -> Command
static func pilot(player: int, tick: int, input: PilotInput) -> Command
static func set_adjutant(player: int, enabled: bool, profile: int, toggles: int) -> Command      # profile 0 assist, 1 caretaker, 2 economy

class_name CommandResult extends RefCounted
enum Code { ACCEPTED, REJECTED_DEAD, REJECTED_NOT_OWNER, REJECTED_NOT_POSSESSABLE, REJECTED_ALREADY_POSSESSED, REJECTED_NO_RIGHTS,
            REJECTED_CAP, REJECTED_COST, REJECTED_PLACEMENT, REJECTED_RATE, REJECTED_MALFORMED, REJECTED_INVALID_ORDER,
            REJECTED_UPLINK, REJECTED_PHASE, REJECTED_LOCKED }               # 0-14 frozen
var code: Code; var reject: int                                              # reject = Build.Reject when code == REJECTED_PLACEMENT

class_name PilotInput extends RefCounted
var thrust: float; var pitch: float; var yaw: float; var roll: float; var buttons: int   # towers: pitch/yaw = slew rates; ground: thrust fwd, BRAKE stop, yaw steer
const BOOST := 1; const BRAKE := 2; const FLIP := 4; const FIRE1 := 8; const FIRE2 := 16; const DOCK := 32; const RELEASE := 64   # bit7 reserved
# wire form: net's PilotWire.to_wire / from_wire (R0 B.10 A-46, NET-03); PilotInput itself has no codec
    # 04 s2.4 layout, 8 bytes: u8 thrust, i8 pitch, i8 yaw, i8 roll, u8 buttons, u8 reserved (0), u8 reserved (0), u8 tick_lo

class_name Kinematics                                                        # all static, pure: no Node, no RNG, no Time (03 s5.2-5.3)
static func step_ship(s: ShipState, input: PilotInput, def: ShipDef, common: FlightCommonDef, rules: RulesDef, terrain: Terrain, dt: float) -> ShipState
static func step_projectile(p: Vector3, v: Vector3, def: ProjectileDef, rules: RulesDef, dt: float, out: ProjectileState = null) -> ProjectileState   # R0 B.9 A-12 (TA-43): fills and returns `out` (ProjectileMotion's one scratch); allocates when null
static func thrust_efficiency(v_fwd: float, cruise: float, fade_start: float) -> float
static func ceiling_efficiency(altitude: float, rules: RulesDef) -> float
static func k_up_effective(v_fwd: float, def: ShipDef, rules: RulesDef) -> float
class_name ShipState extends RefCounted                                      # sim/ship_state.gd (R0 B.8 A-7: own file, ADR-14); reused scratch
var p: Vector3; var v: Vector3; var fwd: Vector3; var up: Vector3; var rates: Vector3
var boost_time: float; var flip_time: float; var fuel: float
var terrain_hit: bool; var hit_normal_speed: float; var ceiling_forced: bool; var over_dive_excess: float
class_name ProjectileState extends RefCounted                                # sim/projectile_state.gd (R0 B.8 A-8); one reused scratch per ProjectileMotion
var p: Vector3; var v: Vector3                                               # after one step per 03 s5.4; guided re-aim and ttl stay in ProjectileMotion / ProjectileStore
class_name GroundMotion extends RefCounted                                   # 03 s5.3; step() inside SimWorld only

class_name Build extends RefCounted
enum Reject { OK, ELIMINATED, PREREQ, CAP, OCCUPIED, SLOPE, NODE, NOT_VISIBLE, ENEMY_RADIUS, NO_RADIUS,
              NO_PRESENCE, SPACING, FUNDS, SPEND_LOCKED }                    # 0-13 frozen
func can_place(player: int, def_id: int, cell: int, rotation: int) -> Build.Reject   # the one placement validator (03 s3.6)
func place(player: int, def_id: int, cell: int, rotation: int) -> int
func footprint_cells(def_id: int, cell: int, rotation: int) -> PackedInt32Array      # (03) crosses cube edges via neighbour_cell

class_name Pathing extends RefCounted
func request(from: Vector3, to: Vector3, mask: int) -> int                   # ticket
func result(ticket: int) -> PackedVector3Array                               # empty while pending; path grid version stamped
func set_weight(cell: int, w: int) -> void;  func weight(cell: int) -> int

class_name MatchRules extends RefCounted                                     # sim/match_rules.gd: 03 config + 02 phase API (R0 C2-12)
enum Phase { PLAYING, EXPOSURE, ENDED }                                      # rules state (no LOADING)
var mode: StringName; var caps_profile: StringName; var caps: CapsDef; var sim_budget_profile: PackedInt32Array   # CapsDef: content type (03 s15.3, R0 B.8 A-8): id, units, structures, projectiles, wrecks, slots
var core_exposure_s: float; var hard_end_s: float                           # from modes.json per mode (campaign: per mission)
var debug_commands: bool; var profile_enabled: bool; var friendly_fire: bool; var adjutant_allowed: StringName   # off | economy | full
var sun_period_s: float; var ranked: bool
func phase(tick: int) -> Phase;  func arc(tick: int) -> MatchArc
class_name MatchArc                                                          # enum holder: OPEN, EXPAND, SIEGE, OVERTIME (clock band, 05 uses it)
class_name PlayerKind                                                        # enum holder: HUMAN, BOT, OPEN

class_name SimView extends RefCounted                                        # LocalSimView (direct arrays) and NetSimView (replicated) implement it
func alive(id: int) -> bool                                                  # 01 s9.4 accessors from here ...
func pos(id: int) -> Vector3;  func vel(id: int) -> Vector3;  func basis(id: int) -> Basis
func def_id(id: int) -> int;  func owner(id: int) -> int;  func team(id: int) -> int
func hp01(id: int) -> float;  func fuel01(id: int) -> float;  func ammo(id: int) -> int;  func bombs(id: int) -> int
func control_state(id: int) -> int                                           # Control state enum below
func possessor(id: int) -> int                                               # player slot or -1
func ids_in_cell(cell: int) -> PackedInt32Array;  func ids_near(p: Vector3, radius: float, mask: int) -> PackedInt32Array
func stockpile(team: int) -> Vector3                                         # ore, ice, power_ratio
func visible_to(team: int, id: int) -> bool                                  # ... to here
func tick() -> int
func visible_ids(team: int) -> PackedInt32Array                              # (03) live list, rebuilt per vision pass
func ships() -> PackedInt32Array;  func structures() -> PackedInt32Array;  func wrecks() -> PackedInt32Array   # (03) live-slot lists
func flags(id: int) -> int;  func radius(id: int) -> float;  func def_kind(id: int) -> int                       # (03)
func cargo(id: int) -> float;  func cargo_kind(id: int) -> int;  func link(id: int) -> int                       # (03)
func boost_state(id: int) -> int;  func flip_cooldown01(id: int) -> float;  func rockets(id: int) -> int
func dock_state(id: int) -> int                                              # Dock state enum below
func service_progress(id: int) -> Vector3                                    # fuel, ammo, repair 0..1
func service_state(id: int) -> int                                           # Service state enum below
func pad_queue(pad: int) -> PackedInt32Array;  func pad_occupant(pad: int) -> int;  func nearest_friendly_pad(id: int) -> int
func order_head(id: int) -> OrderSpec                                        # = standing order
func order_issuer(id: int) -> int;  func pending_order(id: int) -> OrderSpec
func incoming_rockets(id: int) -> int;  func projectiles_near(p: Vector3, r: float, team_mask: int) -> PackedInt32Array
func ai_tag(id: int) -> int;  func field_remaining(node: int) -> int;  func path_grid_version(face: int) -> int
func stockpile_cap(team: int) -> Vector2i;  func power_balance(team: int) -> Vector2;  func unit_count(player: int) -> int
func supply01(id: int) -> float
func production_queue(factory: int) -> PackedInt32Array;  func production_progress01(factory: int) -> float
func tech_available(team: int, def_id: int) -> bool;  func auto_replenish_target(player: int, def_id: int) -> int
func player_score(slot: int) -> Vector2i                                     # pilot, commander (banked == total; no banking)
func landing_grade_last(id: int) -> int                                      # LandingGrade.Grade
func team_state(team: int) -> TeamStateView;  func player_state(slot: int) -> PlayerStateView                   # (03) reused per-slot views, refilled on call (S3)
func terrain_height(dir: Vector3) -> float                                   # (03) convenience over Terrain
func match_arc() -> int;  func match_phase() -> int;  func match_clock_s() -> float
# Non-replicated fields on NetSimView return the def default and set the `unknown` bit (04 s5.6). NetSimView adds sample(render_tick: float).

class_name TeamStateView extends RefCounted                                  # sim/team_state_view.gd (R0 B.8 A-8): read-only view of 03 s3.2 `TeamState`; wire form 04 TEAM_STATE 0x85
var team: int; var unknown: bool                                             # unknown: NetSimView only, true when no TEAM_STATE for this team (other teams)
var ore: int; var ice: int; var ore_cap: int; var ice_cap: int               # team pool and stockpile cap (B.1 storage_ore/ice summed)
var power_supply: float; var power_demand: float
var unit_cap: int; var structure_cap: int                                    # per player, from MatchRules.caps
var members: PackedInt32Array                                                # player slots on the team; per-player counts via player_state(slot)
var eliminated: bool; var flags: int                                         # eliminated = no Core left on the team
const CORE_EXPOSURE := 1; const LOW_POWER := 2; const CORE_SHIELD_UP := 4; const SPEND_LOCK_ACTIVE := 8   # flags bits, 04 0x85 order
class_name PlayerStateView extends RefCounted                                # sim/player_state_view.gd (R0 B.8 A-8): read-only view of 03 s3.2 `PlayerState`
var slot: int; var team: int; var kind: int; var unknown: bool              # kind = PlayerKind; unknown as above (TEAM_DETAIL players / PLAYER_STATUS not received)
var doctrine: StringName; var possessed: int                                 # possessed = EntityId or 0
var commander_rights: bool; var eliminated: bool                             # eliminated = own Core lost (02 s12.1); rights false once eliminated
var connected: bool; var disconnect_tick: int                                # disconnect_tick -1 while connected; bots are always connected
var adjutant_profile: int; var adjutant_toggles: int                         # profile -1 off, else SET_ADJUTANT profile (0 assist, 1 caretaker, 2 economy); toggles bit0..3
var unit_count: int; var structure_count: int                                # counted against unit_cap / structure_cap
var early_spend_left_ore: int                                                # -1 = lock over or not own team (economy.early_share_ore, 04 s3.7)

class_name SimEvent extends RefCounted
enum Kind { SPAWN, DEATH, HIT, BOMB_IMPACT, DOCKED, SERVICED, LAUNCHED, ORDER_DONE, ORDER_FAILED, POSSESSED, RELEASED,
            BUILD_STARTED, BUILD_DONE, STRUCTURE_LOST, LOW_POWER, ALERT, CORE_EXPOSURE, MATCH_END, CAP_REACHED, WRECK_SPAWNED,
            WRECK_SALVAGED, CEILING_RELEASE, HANDOVER, PLAYER_ELIMINATED, LOCK_ACQUIRED, LOCK_BROKEN, CAPTURE_PROGRESS, CAPTURED,
            SALVAGE_DELIVERED, LANDING, SHIELD_COLLAPSE, POSSESS_REQUESTED, CANISTER_DEPLOYED, CANISTER_COLLECTED }   # 0-33 frozen
var kind: Kind; var tick: int; var a: int; var b: int; var pos: Vector3; var value: float; var team: int; var extra: PackedByteArray

class_name Terrain extends RefCounted;  func load_map(map_dir: String) -> Error;  func height_at(dir: Vector3) -> float;  func normal_at(dir: Vector3) -> Vector3   # 03 s6.2/s8.4 (TA-13); read-only after load; flat datum until load_map
func biome_at(dir: Vector3) -> int;  func surface_point(dir: Vector3) -> Vector3;  func slope_deg_at(cell: int) -> float;  func slope_deg_at_dir(dir: Vector3) -> float; func height_texel(face: int, x: int, y: int) -> int;  func is_loaded() -> bool;  var map_hash: String;  var face_resolution: int   # cell = face*n*n + j*n + i; SHA-256 per file + map_hash verified; mismatch -> ERR_FILE_CORRUPT / ERR_INVALID_DATA, sampler stays flat
class_name EntityStore extends RefCounted                                    # 03 s3.2 arrays as public typed vars; alloc(range) / free(slot) / alive(id)
func alloc(entity_kind: int, tick: int) -> int;  func free_slot(slot_index: int, tick: int) -> bool   # (TA-11) NULL_ID when the range is full; free = gen bump + clear_slot + quarantine
func alive(id: int) -> bool;  func id_of(slot_index: int) -> int;  func clear_slot(s: int) -> void;  func live_count() -> int
func free_count(range_id: int) -> int;  func quarantined_count(range_id: int) -> int   # RANGE_MAIN 1..1279, RANGE_WRECK 1280..1535
var ships: PackedInt32Array; var ground: PackedInt32Array; var structures: PackedInt32Array; var wrecks: PackedInt32Array   # live slots, ascending
class_name ProjectileStore extends RefCounted                                # 03 s3.3
func _init(cap_live: int, quarantine_ticks: int = QUARANTINE_TICKS) -> void                 # (TA-11) cap_live = MatchRules.caps.projectiles; index = slot - 4096
func alloc(projectile_kind: int, tick: int) -> int;  func free_slot(index: int, tick: int) -> bool;  func alive(id: int) -> bool;  func live_count() -> int;  func free_count() -> int;  func quarantined_count() -> int
func index_of(id: int) -> int;  func id_of(index: int) -> int;  func clear_slot(i: int) -> void;  var live: PackedInt32Array   # live indices, ascending
class_name Spatial extends RefCounted                                        # sim/spatial.gd (TA-14): counting-sort GRID_HASH hash, _init(store, projectiles)
func rebuild() -> void;  func ids_near(p: Vector3, radius: float, mask: int) -> PackedInt32Array;  func ids_in_hash_cell(cell: int) -> PackedInt32Array
static func cell_of(p: Vector3) -> int;  func item_id(item: int) -> int;  func ring_cells(cell: int, k: int) -> int   # (TA-14) = Sphere.cell_of(p, 64); ring k in {1, 2} into var `ring`
    # mask bits 1 << EntityStore.kind (1 STRUCTURE .. 8 WRECK) | 16 PROJECTILE; centre distance <= radius; ring 1 ~94 m, ring 2 ~188 m (proof: spatial.gd)
class_name Collision extends RefCounted                                      # sim/collision.gd (TA-14), step 8 + 8b; _init(store, projectiles, spatial, terrain)
func configure(projectile_radius: PackedFloat32Array, pad_radius_by_def: PackedFloat32Array, common: FlightCommonDef, tick_hz: int) -> void
func report_terrain(slot: int, tick: int, hit_normal_speed: float) -> void;  func step(tick: int) -> void   # step 5 reports ShipState.terrain_hit
static func classify_terrain(hit_normal_speed: float, common: FlightCommonDef) -> int;  static func landing_band(v_vert: float, v_hor: float, tilt_deg: float, common: FlightCommonDef) -> int
static func sweep_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> float                 # entry t in [0, 1], -1.0 on a miss
    # Contact records c_kind/c_class/c_a/c_b/c_value/c_point/c_vec[0, contact_count): kind 0 HIT, 1 GROUND, 2 TERRAIN (class 0 SCRAPE,
    # 1 DAMAGE, 2 DESTROY), 3 RAM, 4 PAD (band 0 SAFE, 1 DAMAGE, 2 DESTROY); consumed by Combat (9) and Docking (10); collision.gd header
class_name OrderSpec extends RefCounted                                      # 05 owns fields (kind, flags, haul_mode, target, points, issuer, progress; escort_slot, focus, escort_mode for SL-2)
class_name AlertKind                                                         # enum holder, sim/alert_kind.gd
class_name Assist                                                            # sim/steer/assist.gd, static: auto_dock(...), link_bridge(...) (05)
class_name LandingGrade extends RefCounted                                   # sim/scoring/landing_grade.gd (03 s6.4)
```

## Enumerations (append-only; ordinals frozen; R0 B.3)

Growth is a change to this file only (03 amendment 1): append at the end, never reorder, rename or delete. 04's codec,
06's `alerts.json` and 07's alert sounds key on the ordinals; `godot/test/unit/net/test_protocol.gd` parses the bullets
below (label, then `N NAME` pairs), so their format is part of the contract (R0 B.9 A-21).

- `SimEvent.Kind` (`sim/sim_event.gd`): 0 SPAWN, 1 DEATH (entity, killer, cause), 2 HIT (target, attacker, damage u16, part), 3 BOMB_IMPACT, 4 DOCKED, 5 SERVICED, 6 LAUNCHED, 7 ORDER_DONE, 8 ORDER_FAILED (reason: INVALID_TARGET, UNREACHABLE, STUCK, OVERRIDDEN by slot, INVALID_ON_RESUME, NO_PAD, NO_AMMO), 9 POSSESSED, 10 RELEASED (`ReleaseReason`), 11 BUILD_STARTED, 12 BUILD_DONE, 13 STRUCTURE_LOST, 14 LOW_POWER, 15 ALERT (AlertKind, subject, pos, severity), 16 CORE_EXPOSURE, 17 MATCH_END, 18 CAP_REACHED, 19 WRECK_SPAWNED, 20 WRECK_SALVAGED, 21 CEILING_RELEASE, 22 HANDOVER, 23 PLAYER_ELIMINATED, 24 LOCK_ACQUIRED, 25 LOCK_BROKEN, 26 CAPTURE_PROGRESS, 27 CAPTURED, 28 SALVAGE_DELIVERED, 29 LANDING (entity, pad, grade u8, q u8, manual, hot, v_vert, v_horiz), 30 SHIELD_COLLAPSE, 31 POSSESS_REQUESTED, 32 CANISTER_DEPLOYED, 33 CANISTER_COLLECTED (32-33 SL-5, v1 stretch; emitted only when built). Grades travel only in `LANDING`, never as extra `DOCKED` fields.
- `Command.Kind` (`sim/command.gd`): 0 ORDER, 1 BUILD, 2 CANCEL_BUILD, 3 PRODUCE, 4 CANCEL_PRODUCE, 5 SET_RALLY, 6 POSSESS, 7 RELEASE, 8 REQUEST_POSSESS, 9 HANDOVER, 10 PILOT_INPUT, 11 TOGGLE_AUTO_REPLENISH, 12 SURRENDER, 13 SET_ADJUTANT (payload `enabled u8, profile u8 (0 assist, 1 caretaker, 2 economy), toggles u8 (bit0 economy, bit1 replenish, bit2 defence, bit3 expand)`; `REJECTED_NO_RIGHTS` in ranked lobbies), 14 DEBUG_SPAWN, 15 DEBUG_SET. `DOCTRINE_PICK` is a protocol message (04 0x0D) and `SUPPLY_DROP` an order kind, neither a Command.
- `OrderSpec.Kind` (`sim/orders/order_spec.gd`): 0 MOVE, 1 PATROL, 2 ATTACK, 3 ESCORT, 4 HARVEST_HERE, 5 HAUL, 6 RETURN, 7 HOLD, 8 GUARD, 9 SUPPLY_DROP (SL-5, v1 stretch), 10 PATROL_ROUTE (v1.x), 11 ATTACK_VIA (v1.x). `HaulMode`: 0 FERRY, 1 TOW, 2 CAPTURE. `EscortMode` (SL-2): 0 FORM, 1 FOCUS, 2 BREAK. Flags: 1 QUEUE, 2 PREPEND (system), 4 LOW. No `Route` type in v1 (R0 C3-12, B.4).
- `AlertKind` (`sim/alert_kind.gd`): 0 CORE_UNDER_ATTACK, 1 CORE_EXPOSURE_WARNING, 2 CORE_EXPOSURE, 3 BASE_UNDER_ATTACK, 4 STRUCTURE_LOST, 5 LOW_POWER, 6 BOMBERS_DETECTED, 7 HANDOVER_REQUEST, 8 HARVESTER_ATTACKED, 9 UNIT_LOST, 10 ICE_LOW, 11 POLE_CONTESTED, 12 TEAMMATE_PING, 13 BUILD_DONE, 14 PRODUCTION_BLOCKED_CAP, 15 FACTORY_IDLE, 16 PENDING_ORDER, 17 LINK_WEAK, 18 ADJUTANT, 19 ORDER_OVERRIDDEN, 20 STORAGE_FULL, 21 TOWER_OFFLINE, 22 WAITING_FOR_ICE, 23 WAITING_FOR_ORE, 24 RELAY_CONTESTED, 25 RELAY_CAPTURED, 26 CORE_SHIELD_DOWN, 27 SPEND_LOCKED, 28 METEOR_WARN (v1.x), 29 DUSK_WARN (moving sun, campaign/custom), 30 SUPPLY_AWAY (SL-5), 31 WING_STATE (SL-2).
- `CommandResult.Code`: 0 ACCEPTED, 1 REJECTED_DEAD, 2 REJECTED_NOT_OWNER, 3 REJECTED_NOT_POSSESSABLE, 4 REJECTED_ALREADY_POSSESSED, 5 REJECTED_NO_RIGHTS, 6 REJECTED_CAP, 7 REJECTED_COST, 8 REJECTED_PLACEMENT (payload `Build.Reject`), 9 REJECTED_RATE, 10 REJECTED_MALFORMED, 11 REJECTED_INVALID_ORDER, 12 REJECTED_UPLINK (altitude >= 1,950 m), 13 REJECTED_PHASE (wrong lobby/match phase), 14 REJECTED_LOCKED (early share lock / ranked restriction).
- `Build.Reject`: 0 OK, 1 ELIMINATED, 2 PREREQ, 3 CAP, 4 OCCUPIED, 5 SLOPE, 6 NODE, 7 NOT_VISIBLE, 8 ENEMY_RADIUS, 9 NO_RADIUS, 10 NO_PRESENCE, 11 SPACING, 12 FUNDS, 13 SPEND_LOCKED.
- Control state (`control_state` u8): 0 AUTO, 1 ORDERED, 2 POSSESSED. AI overlay (`overlay` u8): 0 NONE, 1 SAFETY, 2 RECOVER_CEILING, 3 LINK_BRIDGE. `ReleaseReason`: 0 PLAYER, 1 DEATH, 2 CEILING, 3 HANDOVER, 4 DISCONNECT, 5 MATCH, 6 INVALID, 7 ADMIN. Service state: 0 NONE, 1 DOCKED, 2 TOWING, 3 CAPTURING, 4 BUILDING. Dock state (pilot block): 0 FLYING, 1 LANDING_ASSIST, 2 DOCKED, 3 LAUNCHING.
- `MatchRules.Phase`: 0 PLAYING, 1 EXPOSURE, 2 ENDED. `MatchArc`: 0 OPEN, 1 EXPAND, 2 SIEGE, 3 OVERTIME. `PlayerKind`: 0 HUMAN, 1 BOT, 2 OPEN. (`SessionPhase` 0 POOLED .. 8 ABORTED is 04's, defined in `net/protocol.gd` as `Protocol.SessionPhase` and driven by `server/`, R0 B.9 A-28.)
- `LandingGrade.Grade`: 0 CRASH, 1 BENT, 2 HARD, 3 FAIR, 4 CLEAN, 5 ACE, 6 AUTO.
- `PilotInput.buttons`: bit0 BOOST, bit1 BRAKE, bit2 FLIP, bit3 FIRE1, bit4 FIRE2, bit5 DOCK, bit6 RELEASE, bit7 reserved.
- `EntityStore.kind` u8: 0 STRUCTURE, 1 SHIP, 2 GROUND, 3 WRECK; `flags` bits 1 ALIVE, 2 DOCKED, 4 LANDED, 8 POSSESSABLE, 16 BUILDING, 32 POWERED, 64 CEILING_FORCED, 128 TETHERED; `dirty` 1 POSE, 2 VITALS, 4 CONTROL, 8 CARGO, 16 SPAWNED, 32 DIED; u8 none = 255. `ProjectileStore.kind`: 0 SLUG, 1 BOMB, 2 ROCKET, 3 FLAK, 4 RAIL, 5 SIEGE_SHELL, 6 CANISTER (reserved); `flags` 1 ALIVE, 2 ARMED, 4 GUIDED (TA-11, 03 s3.2-3.3).
- `QuickPing.Kind` is UI-owned (06 `content/ui/pings.json`, listed in R0 B.3); the sim only relays `TEAMMATE_PING` alerts.

## Tick order (`SimWorld.step()`, normative, R0 B.5)

1 apply queued `Command`s (incl. POSSESS/RELEASE handoffs by `ControlMachine`); 2 store this tick's human `PilotInput`s into
input slots; 3 AI hook `SimAiHook.on_tick(tick, view, sink)`: think slice + act for every AI-driven entity, writing input slots
through `CommandSinkBase.drive` (refused for POSSESSED); 4 assist substitution: `Assist.auto_dock()` / `Assist.link_bridge()`
overwrite input slots where active; 5 kinematics: `step_ship` ships, `GroundMotion.step` ground, turret slew towers; 6 projectiles
(straight / ballistic / guided / rendezvous); 7 spatial rebuild (counting sort); 8 collision: projectile vs entity sweeps, 8b
projectile vs terrain, ship vs terrain (destroy / damage / land / scrape), ship vs ship, ship vs structure; 9 combat: fire, damage
rolls, flak bursts, shields, deaths (deferred free), wrecks; 10 economy / production / build / docking service / salvage / Core
shield and Exposure timers / caps / scoring (LandingGrade); 11 vision (10 Hz staggered, 5 Hz under cut rung 2); 12 events drained by the caller.

Motion rules (R0 B.5): slugs, flak shells and rail slugs fly straight in the world frame (`p += v * dt`, no transport,
no gravity, no damping) and are never entities; bombs and siege shells are CF-transported under `-g n`; rockets fly at
constant speed, guided within `turn_rate_dps` / `lock_cone_deg`; lead solvers are straight-line intercepts with no
gravity term. Flight law and the tail-down landing rule: R0 B.5 and 03 s5.3, field names from R0 B.1 (brake ramp
`clamp(v_fwd / flight_common.brake_fade_mps, 0, 1)`, A-13). Body axes (TA-12): right = fwd x up; `PilotInput` pitch + nose up,
yaw + nose left (about body up), roll + right wing down. Flip (A-11): scripted half roll (roll-stick sign at the FLIP press,
default +) over the first `flip_duration_s / 2`, then a half loop; ends upright, heading reversed, rates zero; stick ignored meanwhile;
`v` turns with the body each flip tick and is scaled by `flip_speed_retain` on the last (A-29). Fuel (A-32, 02 s2.3): burn/s = thrust
+ `fuel_burn_boost_per_s` boosting + `fuel_burn_brake_per_s` braking + `fuel_burn_idle_per_s`; an empty tank cuts thrust, boost and brake.

## Invariants

- S1: `step()` mutates state only through systems in the tick order; `apply_command` queues, never mutates (commands apply in step 1 of the next `step()`), except `PILOT_INPUT`, which is stored into the per-player input slot.
- S2: `EntityId`s are never reused within 64 ticks of free (units, structures, wrecks). Projectile slots are exempt (0-tick quarantine, owner 2026-10-13, R0 B.9 A-20): a freed projectile slot may be re-allocated the same tick; the generation bump keeps every projectile `EntityId` unique, and 04 keys projectile entities by the full id.
- S3: `view()` reads are valid until the next `step()`; it never allocates on read except list getters.
- S4: `serialize()` then `deserialize()` then `step()` equals `step()` on the original byte for byte (same machine) for 1,000 random ticks; `serialize()` appends the AI hook's opaque bytes and `deserialize` hands them back to the hook.
- S5: every `SimEvent` has `tick == tick()` of the step that produced it.
- S6: no float literal other than 0.0, 0.5, 1.0, 2.0, -1.0 appears in `src/sim/**` (D6); every sim constant lives in a def (ADR-09).
- S7: the only RNG is `SimWorld.rng` and its forks.
- S8: `Kinematics.step_ship` and `sim/steer/` are pure (no Node, RNG, Time or global state).
- S9: `height_at` is identical on every peer for identical map files (SHA verified at load; test_terrain.gd flipped-byte, vectors, seam tests).
- S10: `apply_command` validates ownership, rights, caps, cost, placement (`Build.can_place`), phase and rate before accepting; the rate limit is 04's token bucket per player (10 commands/s sustained, burst 30; `REJECTED_RATE`); a rejected command has no effect.
- S11: `CommandSinkBase.drive` never writes the input slot of a POSSESSED entity.
- S12: `CANCEL_PRODUCE` / `CANCEL_BUILD` succeed only for the player who queued/placed the item, or a teammate if that player is disconnected, eliminated or a bot (R0 C3-08).
- S13: production queues never exceed `economy.queue_max` (5).
- S14: enumeration ordinals in this file equal the GDScript enums; appending is the only allowed change.
- S15: the def JSON the sim reads validates against `tools/schemas/*.schema.json` (`tools/validate_content.py`); field names are R0 B.1's.
- S16: after `Spatial.rebuild()` every live entity and projectile is in exactly its `Sphere.cell_of(pos, GRID_HASH)` cell; `ids_near` equals the brute-force set at any radius; `Spatial` holds no Dictionary (test_spatial.gd).
- S17: `Collision` emits one classified `TERRAIN` contact per contact episode (A-30; kill speed destroys at any tick) and a `PAD` contact on every tick a not-DOCKED ship is inside a friendly pad's volume (A-31) (test_collision.gd).

## Data owned

03 s3.2 and s3.3 arrays and side tables (incl. `orders`, `tether_target`, `scoring`); the loaded `Terrain`; `MatchRules`;
the `ResolvedDefs` per doctrine; the event array; the pending command queue (<= 256 per tick; overflow rejects with
`REJECTED_RATE`). Def files read (through `ContentDB` at `load_map`): `rules`, `ships` (+ `flight_common`), `ground_units`,
`weapons`, `projectiles`, `structures`, `towers`, `doctrines`, `economy`, `match_rules`, `modes`, `order_rules` (schemas: `tools/schemas/`).

## Events emitted / consumed

Emits every `SimEvent.Kind` above (exactly one system per kind). Consumes `Command`s (all `Command.Kind`s) and `PilotInput`. No signals (D2).

## Performance budget

R0 B.7 / 03 s4.2 per row (kinematics 3.0, projectiles 2.5, spatial 1.2, collision 5.0, combat 1.2, economy 0.8, vision 1.1 ms
p95 at 1,200 entities + 2,000 projectiles); perf tick harness on scenario s_sim_1.json (S-SIM-1, TA-22). Pass: p95 <= 25 ms, p99 <= 33 ms per instance, 6 instances on the target SKU.

## Test entry points

Existing (checked by check_deps D10): `godot/test/sim/` (scenario layer), `godot/test/perf/perf_tick.gd`,
`godot/test/unit/sim/test_entity_store.gd` (alloc/free/quarantine, S2), `godot/test/unit/sim/test_projectile_store.gd`,
`godot/test/soak/`, `tools/tests/test_validate_content.py` (CONTRACT-0: the def schemas the sim reads).
TA-12: `godot/test/unit/sim/test_kinematics.gd` (lift law, level flight, test_slug_hits_coaltitude_target),
`godot/test/unit/sim/test_kinematics_purity.gd` (S8), `godot/test/sim/test_flight.gd`, `godot/test/perf/perf_kinematics.gd`;
TA-48: `godot/test/unit/sim/test_kinematics_flip_fuel.gd` (flip redirect, fuel per mode, empty tank, replay).
TA-14: `godot/test/unit/sim/test_spatial.gd` (S16, ring coverage), `godot/test/unit/sim/test_collision.gd` (S17, classification,
pads, rams), `godot/test/sim/test_collision_sweeps.gd` (1,000 slug / rail geometries, determinism), `godot/test/perf/perf_collision.gd`.

Planned (plain text until on disk, D10; each task adds its file and moves it above): godot/test/unit/sim/test_enums.gd (S14,
TA-18), test_build.gd (placement incl. cross-edge footprints), test_landing.gd (tail-down rule and grade),
test_pathing.gd, test_serialize.gd (S4), test_command_validator.gd (S10, S12); godot/test/sim/scenarios/*.json
(possess/release, build radius and Outpost presence, victory, Core shield and Exposure, caps); godot/test/contract/test_sim_view_contract.gd.

## How to add X

Recipes (SimEvent kind, order kind, AlertKind / Command.Kind / CommandResult.Code / Build.Reject, def field) live in 03 s15.4 (R0 B.10 A-47).

## Open items

- CONTRACT-0 Q1-Q8 (`docs/reviews/R0-amendments-01.md`, R0 B.8): own files for `ShipState` / `ProjectileState` (A-7, A-8); views above (A-8); `CapsDef` is content's; per-file weapon / projectile namespaces (A-1: resolve `WeaponDef.projectile` via `ContentDB.projectile_index`, never `def_index`); A-3 settled 2026-10-13: Foundry's x0.85 applies to `weapon_mount: ship` only.
- Amendments 02 (`docs/reviews/R0-amendments-02.md`, R0 B.9): A-11 flip form, A-12 `step_projectile` `out`, A-13 `brake_fade_mps`, A-14 fixture rule, A-20 projectile quarantine 0, A-21 subsystem `MODULE.md` rule; code follow-ups TA-43, TA-44, TA-45, TA-48 all done (`Kinematics` takes content's `*Def` types, `sim/fixture/` deleted; A-30/A-31/A-34/A-35 consumers: TA-14, AI-10).
- Amendments 03 (R0 B.10): A-41 DOCKED ships are not stepped (03 s4.1 rule 9); A-42 `is_projectile` open-ended; A-46, A-47 done (TA-14).
- TA-14 findings: ring 1 covers ~94 m (3D), not the 139 m of 03 s2.7 / s3.6 / s6.1 (corner edge length, not strip width); `ids_near`
  picks ring 2 above it. Pad plane = structure `pos` / `up` (GD-15 may add a deck offset); Build (TA-19) must size pad structures' `radius`
  so the approach column is clear. `Collision.shooter_grace_ticks` (03 s6.1 "10 ticks") needs a def field (`needs content:`).
- Owners: TA-11 entity store, TA-12 kinematics, TA-14 projectiles, TA-18 tick driver + `LocalSimView` (+ `possessed` live list), TA-22 S-SIM-1, TA-37 vision, TA-38 ground motion; 05 lane `sim/steer/`, `sim/orders/`, `sim/control/`.
