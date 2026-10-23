# net/client - MODULE.md

Contract for `godot/src/net/client/**`: the client session of the match plane (NET-17; 01 s9.4, 04 s2.2, s5.1, s5.6, s3.7,
R0 C1-23, C2-12, B.10 A-36, B.11 A-56, B.19 A-103). `net/MODULE.md` is at its 300-line cap, so this subsystem has its own
file (as `net/events`, `net/keyframe`). A change to "Public API", "Wire layout" or "Invariants" is a contract change:
contract tests first, same PR (ADR-11); `tools/gen_module_api.py --check` must pass; <= 300 lines (ADR-14).

| Field | Value |
|---|---|
| Responsibility | `ClientSession`: state machine, packet routing through the total decoders, clock (drift estimator, time dilation), complete-tick acks, PING; `NetSimView`: the `SimView` over replicated state, sampled at a fractional render tick (`NetPose`: interpolation, gravity-aware dead reckoning <= 3 ticks, stale flag, known blips never extrapolated); the session message codecs (HELLO, LOADED, PING, SNAPSHOT_ACK, WELCOME, REFUSE, MATCH_STATE, PONG, MATCH_END head) and TEAM_STATE (0x85). Not here: prediction / INPUT (NET-18), TEAM_DETAIL accessors (NET-39), reconnect retry (NET-20), the server half (ServerSession NET-15). |
| Lane owner tier | Opus |
| May depend on | `core`, `content`; `net` (`Protocol`, `Codec`, `Roster`, `RosterSync`, `RosterCodec`, `SnapshotDecoder`, `BaselineStore`, `BaselineFrame`, `DeadReckon`, `PilotBlock`, `Transport`, `LocalTransport`, `LocalClock`, `KeyframeCodec`, `EventCodec`, `WireEvent`, `CommandCodec`); named `sim` types `SimView`, `Command`, `PilotInput`, `Terrain` (A-27) |
| Must never touch | Nodes, `await`, `Thread`, `WorkerThreadPool` (web is single-threaded, 03 s11); other `sim` types (`EntityStore` / `Spatial` constants are mirrored and pinned by `test_net_sim_view.gd`); `server/`, `presentation`, `ui` |
| Autoloads used | None |
| Status | implemented (NET-17); `team_state` / `player_state` / `order_head` / `pending_order` blocked on D1 (Open items CQ-2). |

## Public API

```gdscript
class_name ClientSession extends RefCounted           # net/client/client_session.gd (01 s9.4 signatures reproduced, extended)
enum State { CONNECTING, LOADING, PLAYING, RECONNECTING, ENDED }
signal state_changed(state: int)
const ACK_EVERY_TICKS: int; const PING_EVERY_TICKS: int   # 3 (SNAPSHOT_ACK 10/s), 30 (PING 1/s)
var state: int; var local_player: int; var team: int; var phase: int; var welcome: WelcomeInfo; var clock: ClientClock; var roster_sync: RosterSync
var decoder: SnapshotDecoder; var keyframes: KeyframeCodec; var refuse_reason: int; var end_reason: int; var events: Array[WireEvent]; var pilot_input: PilotInput
var ticks: int; var last_tick_us: int; var packets_in: int; var dropped: int; var malformed: int; var snapshots_ok: int; var held: int; var keyframes_applied: int; var acks_sent: int; var last_ack: int
func _init(transport: Transport, player: int) -> void
func configure(content: ContentSet, terrain: Terrain) -> void;  func configure_defs(defs: NetDefs, terrain: Terrain) -> void
func hello(content_hash: PackedByteArray, join_token: PackedByteArray, platform: int, input_class: int, role: int) -> bool   # sent on connect
func mark_loaded(map_hash: PackedByteArray) -> void    # LOADED once, in LOADING
func tick() -> void                                    # 30 Hz: poll, route, clock, acks, ping, view().sample(render_tick())
func view() -> NetSimView;  func render_tick() -> float;  func ack_tick() -> int;  func now_ms() -> float
func send_command(cmd: Command) -> void;  func set_pilot_input(input: PilotInput) -> void;  func leave() -> void
func receive(channel: int, bytes: PackedByteArray) -> void   # transport packet entry; the fuzz entry; never throws

class_name ClientClock extends RefCounted             # net/client/client_clock.gd (04 s5.1)
const INTERP_DELAY_TICKS: int; const INPUT_LEAD_TICKS: int; const DRIFT_ALPHA: float; const RTT_ALPHA: float   # 3, 1, 0.05, 0.2
const DILATION_MAX: float; const DILATION_GAIN: float; const RESYNC_MS: float; const EARLY_TICKS: int; const LEAD_MAX: float   # 0.05, 0.1, 500, 6, 8
var tick_ms: float; var synced: bool; var offset: float; var clock: float; var rate: float; var rtt_ms: float; var lead: float; var samples: int; var resyncs: int
func _init(tick_hz: int = 30) -> void;  func reset() -> void
func observe(server_tick: int, now_ms: float) -> void;  func observe_rtt(rtt: float) -> void;  func estimate(now_ms: float) -> float
func advance(now_ms: float) -> void;  func render_tick() -> float;  func input_tick() -> int;  func note_input_timing(late_inputs: int, early_ticks: int) -> void

class_name NetSimView extends SimView                 # net/client/net_sim_view.gd (04 s5.6, s3.7); every SimView accessor overridden except the ones listed below
const K_STRUCTURE: int; const K_SHIP: int; const K_GROUND: int; const K_WRECK: int; const F_ALIVE: int; const F_DOCKED: int; const F_POSSESSABLE: int   # EntityStore mirrors
const MASK_PROJECTILE: int; const BOOST_MASK: int; const SERVICE_DOCKED: int; const BYTE_MAX: float; const FUEL_DS: float; const NONE: int; const TEAMS: int
var team_id: int; var slot_id: int; var possessed_index: int; var render_tick: float; var stale: bool; var team_wire: TeamStateWire; var pose: NetPose
var roster: Roster; var decoder: SnapshotDecoder; var defs: NetDefs; var terrain: Terrain
func _init(roster_ref: Roster, decoder_ref: SnapshotDecoder) -> void;  func bind(net_defs: NetDefs, map_terrain: Terrain) -> void
func sample(at_render_tick: float) -> void            # R0 C2-12 signature
func set_possessor(index: int, player: int) -> void;  func set_team_state(w: TeamStateWire) -> void
func team_flags(t: int) -> int;  func team_flags_known(t: int) -> bool;  func unknown(id: int) -> bool   # 04 s3.7 unknown bit
func index_of(id: int) -> int;  func live(i: int) -> bool;  func id_at(i: int) -> int   # roster index of a live EntityId (-1); replicated entry; EntityId of an index
func alive(id: int) -> bool;  func pos(id: int) -> Vector3;  func vel(id: int) -> Vector3;  func basis(id: int) -> Basis;  func def_id(id: int) -> int;  func owner(id: int) -> int;  func team(id: int) -> int
func hp01(id: int) -> float;  func fuel01(id: int) -> float;  func ammo(id: int) -> int;  func bombs(id: int) -> int;  func rockets(id: int) -> int;  func control_state(id: int) -> int;  func possessor(id: int) -> int
func ai_tag(id: int) -> int;  func flags(id: int) -> int;  func radius(id: int) -> float;  func def_kind(id: int) -> int;  func boost_state(id: int) -> int;  func flip_cooldown01(id: int) -> float;  func dock_state(id: int) -> int
func service_progress(id: int) -> Vector3;  func service_state(id: int) -> int;  func incoming_rockets(id: int) -> int;  func tick() -> int;  func match_clock_s() -> float;  func terrain_height(dir: Vector3) -> float
func ships() -> PackedInt32Array;  func structures() -> PackedInt32Array;  func wrecks() -> PackedInt32Array;  func visible_ids(t: int) -> PackedInt32Array;  func visible_to(t: int, id: int) -> bool
func visible_enemy_ships(t: int, out: PackedInt32Array) -> int;  func ids_in_cell(cell: int) -> PackedInt32Array;  func ids_near(p: Vector3, r: float, mask: int) -> PackedInt32Array
func nearest_friendly_pad(id: int) -> int;  func tech_available(t: int, d: int) -> bool;  func stockpile(t: int) -> Vector3;  func stockpile_cap(t: int) -> Vector2i;  func power_balance(t: int) -> Vector2;  func unit_count(player: int) -> int
func read_poses(ids: PackedInt32Array, out_pos: PackedVector3Array, out_rot: PackedVector4Array) -> int   # R0 B.11 A-56 over the sampled mirror
# inherited SimView defaults (not received, 04 s5.6 / s3.7): overlay, cargo, cargo_kind, link, pad_queue, pad_occupant, order_head, order_issuer,
#   pending_order, projectiles_near, field_remaining, path_grid_version, supply01, shield01 (-1.0, GD-38), wreck_ore (-1.0, GD-41), production_queue,
#   production_progress01, auto_replenish_target, player_score, landing_grade_last, team_state, player_state, match_arc, match_phase

class_name NetRosterQueries                           # net/client/net_roster_queries.gd; static roster walks of NetSimView's list accessors
static func of_kinds(v: NetSimView, mask: int) -> PackedInt32Array;  static func visible_ids(v: NetSimView, t: int) -> PackedInt32Array
static func enemy_ships(v: NetSimView, t: int, out: PackedInt32Array) -> int;  static func in_cell(v: NetSimView, cell: int) -> PackedInt32Array
static func near(v: NetSimView, p: Vector3, r: float, mask: int) -> PackedInt32Array;  static func nearest_pad(v: NetSimView, i0: int) -> int;  static func tech_available(v: NetSimView, t: int, d: int) -> bool

class_name NetPose extends RefCounted                 # net/client/net_pose.gd: the sampled mirror (lazy per entry, cached per record)
const EXTRAP_MAX_TICKS: int; const ALPHA_EPS: float  # 3 (100 ms); 1e-4 (a render tick this close to a frame shows that frame)
var render_tick: float; var tick_a: int; var tick_b: int; var alpha: float; var newest: int; var eval_tick: float; var extrapolating: bool; var stale: bool
var generation: int; var computed: int; var converted: int; var store: BaselineStore; var roster: Roster; var gravity_def: PackedByteArray; var gravity: float; var dt: float
func _init(baseline: BaselineStore, roster_ref: Roster) -> void;  func sample(r: float) -> void;  func frame() -> BaselineFrame;  func present(i: int) -> bool
func pose_into(i: int, out_pos: PackedVector3Array, out_rot: PackedVector4Array, k: int) -> void
func pos_of(i: int) -> Vector3;  func vel_of(i: int) -> Vector3;  func rot_of(i: int) -> Vector4;  func has_ori(i: int) -> bool;  func is_blip(i: int) -> bool
static func fine_to_world(fine: int, cell: int) -> Vector3;  static func canonical(q: Quaternion) -> Quaternion

class_name NetDefs extends RefCounted                 # net/client/net_defs.gd: per-def tables from a ContentSet (base defs)
var tick_hz: int; var gravity: float; var hp: PackedFloat32Array; var fuel_s: PackedFloat32Array; var radius: PackedFloat32Array; var possessable: PackedByteArray; var pad: PackedByteArray; var gravity_def: PackedByteArray; var kind: PackedInt32Array
func _init(content: ContentSet = null) -> void;  func valid(def_id: int) -> bool;  func kind_of(def_id: int, slot: int) -> int;  func requires_of(def_id: int) -> PackedInt32Array

class_name TeamStateWire extends RefCounted           # net/client/team_state_wire.gd: one TEAM_STATE as wire integers
var tick: int; var ore: int; var ice: int; var ore_cap: int; var ice_cap: int; var power_supply: int; var power_demand: int; var unit_cap: int; var structure_cap: int; var flags: int
var member_slot: PackedInt32Array; var member_units: PackedInt32Array; var member_structures: PackedInt32Array
func copy_from(o: TeamStateWire) -> void;  func member_index(slot: int) -> int;  func add_member(slot: int, units: int, structures: int) -> void

class_name TeamStateCodec                             # net/client/team_state_codec.gd; static
const FIXED_BYTES: int; const MEMBER_BYTES: int; const MEMBERS_MAX: int; const FLAGS_MASK: int; const SLOTS: int   # 31 5 8 0x0F 8
static func encode(w: TeamStateWire) -> PackedByteArray   # empty when out of range
static func decode(b: PackedByteArray, out: TeamStateWire) -> bool;  static func valid(b: PackedByteArray) -> bool;  static func tick_of(b: PackedByteArray) -> int

class_name WelcomeInfo extends RefCounted             # net/client/welcome_info.gd
var conn_id: int; var slot: int; var team: int; var session_id: int; var secret: PackedByteArray; var tick: int; var server_ms: int; var map_id: String; var map_hash: PackedByteArray; var config: PackedByteArray
var player_slot: PackedInt32Array; var player_team: PackedInt32Array; var player_kind: PackedInt32Array; var player_doctrine: PackedInt32Array; var player_input: PackedInt32Array; var player_name: PackedStringArray
func add_player(p_slot: int, p_team: int, kind: int, doctrine: int, input_class: int, p_name: String) -> void;  func clear_players() -> void

class_name SessionCodec                               # net/client/session_codec.gd; static
const HELLO_FIXED_BYTES: int; const TOKEN_MAX: int; const WELCOME_FIXED_BYTES: int; const MAP_ID_MAX: int; const CONFIG_MAX: int; const NAME_MAX: int; const PLAYERS_MAX: int   # 67 160 37 64 256 24 8
const PONG_BYTES: int; const PING_BYTES: int; const ACK_BYTES: int; const MATCH_STATE_BYTES: int; const REFUSE_FIXED_BYTES: int; const REFUSE_TEXT_MAX: int; const MATCH_END_HEAD_BYTES: int   # 13 5 7 9 5 120 39
static func encode_hello(content_hash: PackedByteArray, join_token: PackedByteArray, build: int, platform: int, input_class: int, role: int, session_id: int = 0, secret: PackedByteArray = PackedByteArray()) -> PackedByteArray
static func encode_loaded(map_hash: PackedByteArray) -> PackedByteArray;  static func encode_ping(client_ms: int) -> PackedByteArray;  static func encode_snapshot_ack(ack_tick: int, keyframe_seq: int) -> PackedByteArray
static func encode_pong(client_ms: int, server_tick: int, server_ms: int) -> PackedByteArray;  static func decode_pong(b: PackedByteArray, out: PackedInt64Array) -> bool
static func encode_match_state(phase: int, tick: int, countdown_ticks: int, loaded_mask: int) -> PackedByteArray;  static func decode_match_state(b: PackedByteArray, out: PackedInt64Array) -> bool
static func encode_refuse(reason: int, server_version: int, text: String) -> PackedByteArray;  static func decode_refuse(b: PackedByteArray, out: PackedInt64Array) -> bool
static func decode_match_end_head(b: PackedByteArray, out: PackedInt64Array) -> bool
static func encode_welcome(w: WelcomeInfo) -> PackedByteArray;  static func decode_welcome(b: PackedByteArray, out: WelcomeInfo) -> bool;  static func utf8_ok(b: PackedByteArray, from: int, to: int) -> bool
```

## Wire layout

04 s2.3 rows, little-endian. HELLO: id, protocol_version u16, content_hash 32, join_token bytes8 (<= 160), client_build u32,
platform u8, input_class u8, role u8, reconnect_session_id u64, reconnect_secret 16 (zeros if none). LOADED: id, map_hash 32.
PING: id, client_ms u32. SNAPSHOT_ACK: id, ack_tick u32 (the newest complete tick, A-36), ack_keyframe_seq u16. PONG: id,
client_ms u32, server_tick u32, server_ms u32. MATCH_STATE: id, phase u8 (`SessionPhase`), tick u32, countdown_ticks u16,
loaded_mask u8. REFUSE: id, reason u8 (`RefuseReason`), server_version u16, text str8 (<= 120). WELCOME: id, conn_id u16, slot u8
(0-7, 255 spectator), team u8, session_id u64, reconnect_secret 16, tick u32, server_ms u32, map_id str8 (<= 64), map_hash 32,
config bytes16 (<= 256, opaque MatchConfig), player_count u8 (<= 8), players[] x (slot u8 0-7, team u8, kind u8 `PlayerKind`,
doctrine u8, input_class u8, name str8 <= 24); <= 700 B. MATCH_END: only the head (winner u8, reason u8 `MatchEndReason`, tick u32,
result_hash 32) is validated, the tail is bounded by 640 B. Wire text (map_id, names, REFUSE text) must be UTF-8 without NUL.
TEAM_STATE (channel 2, <= 72 B): id, tick u32 (> 0), ore, ice, ore_cap, ice_cap u32, power_supply, power_demand, unit_cap,
structure_cap u16, flags u8 (TeamStateView bits: CORE_EXPOSURE 1, LOW_POWER 2, CORE_SHIELD_UP 4 (GD-38), SPEND_LOCK_ACTIVE 8;
bits 4-7 zero), member_count u8 (0-8), members[] x (slot u8 0-7 unique, unit_count u16, structure_count u16): 31 + 5n B
(51 B with 4 members, 04 s4.6). It describes the receiving client's own team.

## Invariants

- CS1: every decoder here is total: validate the whole message, then write; a rejected message writes nothing and never
  errors (100,000 mutations per id: `test_session_codec.gd`, `test_team_state_codec.gd`; `ClientSession.receive`: 100,000
  mutated server messages, `test_client_session.gd`). Accepted messages re-encode to the identical bytes.
- CS2: `receive` drops (counts) a message on the wrong channel, with an unknown, reserved or client-to-server id, above
  `Protocol.max_bytes`, or out of state; never parses it (04 s11.4).
- CS3: the client acknowledges only complete ticks (`BaselineStore.complete_tick`, R0 B.10 A-36), 10/s via SNAPSHOT_ACK.
- CS4: `ClientClock.clock` never jumps while synced (each `advance` moves it by elapsed x 0.95 .. 1.05); it jumps only on
  the first sample after `reset` (WELCOME / reconnect) or a > 500 ms discontinuity. Under TARGET it converges within 2 s.
- CS5: `NetPose`: between frames lerp / slerp; past the newest frame dead reckoning (gravity term per
  `BaselineFrame.base_grav`) for at most 3 ticks, then frozen with `stale`; a known blip shows its stored bucket
  (`shown_levels`' rule: no gravity even when DYING) and is never interpolated or extrapolated (A-103); at integer ticks the
  float dr(t) equals `Codec.dequantize_pos(shown_levels)` within one quantum. No allocation per entity.
- CS6: `NetSimView` passes TEST-02 (`factories/net_sim_view_factory.gd`); its `exempt()` names exactly the failing clauses,
  each with a 04 s5.6 / s3.7 reason or an Open item (`test_factory_exempts_exactly_the_failing_clauses`).
- CS7: no Nodes, `await`, `Thread` or `WorkerThreadPool`; `tick()` is the only per-frame entry (web single-threaded).

## Performance budget

03 s10.2 "ClientSession.tick (decode + NetSimView + prediction) 1.0 ms PC / 3.0 ms mobile-web per 30 Hz tick" (R0 C1-23);
`NetSimView.sample` is O(1) (frame selection), poses are computed on first read per sample and the presentation read
(`read_poses`) belongs to 03 s10.2 "entity sync 2.4 ms". Bandwidth: TEAM_STATE 51 B x 2/s (04 s4.6 row). Measured
(`test/net/test_client_session_perf.gd`, canonical 940 entities, dev box): see the PR perf note; PerfGate report-only.

## Test entry points

`test/unit/net/test_client_clock.gd`, `test/unit/net/test_team_state_codec.gd`, `test/unit/net/test_session_codec.gd`,
`test/unit/net/test_net_sim_view.gd` (with `known_blip_fixture.gd`, shared with `test_known_blip_presentation.gd`),
`test/unit/sim/contract/factories/net_sim_view_factory.gd` (TEST-02), `test/net/test_client_session.gd`,
`test/net/test_client_session_perf.gd`; helpers `test/net/net_view_rig.gd`, `test/unit/net/net_fuzz.gd`.

## Open items

- CQ-1 (Architect): projectile entities (rockets, bombs, siege shells; 04 s3.6 "replicated as entities") have no roster
  index: the roster is sim slots 0-1,535 (A-54) and projectile slots are 4,096-6,143. TEST-02's rocket clauses (`alive`,
  `ids_in_cell`, `projectiles_near`, `read_poses`) are exempt until a mapping exists.
- CQ-2 (Architect, BLOCKED part): `deps.json` lets net name `SimView` but not the types its B.5 signatures return
  (`TeamStateView`, `PlayerStateView`, `OrderSpec`), so `NetSimView` cannot override `team_state` / `player_state` /
  `order_head` / `pending_order` without a D1 violation. CORE_SHIELD_UP (GD-38) is carried meanwhile: TEAM_STATE codec +
  `NetSimView.team_flags`. Ask: append the three to net's named sim types (R0 B.4).
- CQ-3 (sim lane / TEST-02): the scene writes `control_state` 5 (outside B.3's 0-2 and the 2-bit wire field) and checks
  `flip_cooldown01` to 1e-4 although the pilot block carries a u8 fraction (0.5 -> 128/255).
- GD-41 `wreck_ore` and GD-38 `shield01` inherit -1.0 (no codec carries wreck ore or dome charge yet; 04 s5.6 default);
  a future codec task replicates them and removes the two exemptions.
- TEAM_DETAIL-sourced accessors (`supply01`, `pad_occupant`, `order_head`, `order_issuer`, `auto_replenish_target`) land
  with NET-39; other teams' `stockpile` / `unit_count` / `visible_enemy_ships` are not received by design (04 s3.7).
