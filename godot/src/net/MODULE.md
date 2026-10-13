# net - MODULE.md

Contract for `godot/src/net/**`, v0.6 (NET-01 protocol, NET-02 field codec, NET-05 roster, NET-06 snapshot codec, NET-11 transports, NET-47 R0 B.9 A-23/A-24/A-26/A-28). Source of truth: 04 s2-s5 and s13, R0 Part B (B.3 enumerations,
B.4 deps, B.5 signatures). A change to "Public API", "Wire layout" or "Invariants" is a contract change: update the contract tests first, in the same PR (ADR-11); any wire-layout change bumps `Protocol.PROTOCOL_VERSION` and goes
through the Architect (10 s4); `tools/gen_module_api.py --check` (TA-27) must pass; this file stays <= 300 lines (ADR-14). NET-38 writes the final contract.

| Field | Value |
|---|---|
| Responsibility | The wire: protocol constants and the message catalogue, the snapshot codec (quantisation, tiers, deltas, keyframes), interest management, transports (`LocalTransport`, ENet, WebSocket), the client session (prediction, reconciliation, interpolation, `NetSimView`), event routing, replays. Server-authoritative 30 Hz; <= 30 KB/s and <= 1,200 B per unreliable packet per client (01 ADR-07, s8.3). |
| Lane owner tier | Opus (codec, interest, prediction, client session, replays); Sonnet for well-specified pieces against this file (protocol tables, transports, command payload codecs, event router) |
| May depend on | `core`, `content`; named `sim` types only: `SimWorld`, `Command`, `PilotInput`, `Kinematics`, `SimView`, `Assist`, `Terrain` (`tools/deps.json`) |
| Must never touch | Nodes in codec/protocol code, `server/` (feature lane), `platform/`, `presentation`, `ui`; no `Thread` and no `WorkerThreadPool` (web is single-threaded, 03 s11); WebSocket only on web in v1.0 (WebRTC is v1.1, S-NET-2) |
| Autoloads used | `Log` (never in per-entity loops) |
| Status | v0.4: `Protocol` (NET-01), `Codec` field quantisers (NET-02), `Roster`/`RosterCodec`/`RosterSync` (NET-05), `SnapshotCodec` and its baselines (NET-06), `Transport`/`LocalTransport`/`FaultModel` (NET-11) landed. Everything else is planned per 04 s19. |

## Public API

Anything not listed is private (prefix `_`).

```gdscript
class_name Protocol                                   # net/protocol.gd; all static (04 s2)
const PROTOCOL_VERSION: int                           # 1; bump on any layout change (04 s2.2)
const HELLO: int .. const DOCTRINE_PICK: int          # client -> server ids 0x01-0x0D (04 s2.3)
const WELCOME: int .. const LOBBY_STATE: int          # server -> client ids 0x80-0x93
const INVALID_ID: int; const SERVER_TO_CLIENT_MIN: int
const C2S_RESERVED_FIRST: int; const C2S_RESERVED_LAST: int; const S2C_RESERVED_FIRST: int; const S2C_RESERVED_LAST: int
const C2S_WEBRTC_FIRST: int; const C2S_WEBRTC_LAST: int; const S2C_WEBRTC_FIRST: int; const S2C_WEBRTC_LAST: int
const CH_CONTROL: int; const CH_INPUT: int; const CH_SNAPSHOT: int; const CH_EVENTS: int; const CHANNEL_COUNT: int
enum ChannelMode { RELIABLE_ORDERED, UNRELIABLE, UNRELIABLE_SEQUENCED }
const CHANNEL_MODE: PackedInt32Array                  # indexed by channel
const MAX_UNRELIABLE_BYTES: int; const MAX_RELIABLE_BYTES: int; const HASH_BYTES: int; const SECRET_BYTES: int
const PILOT_INPUT_BYTES: int; const INPUT_MAX_COUNT: int; const COMMAND_PAYLOAD_MAX: int; const SLOT_SPECTATOR: int; const SLOT_NONE: int; const DOCTRINE_HIDDEN: int; const ROSTER_NONE: int
const CATALOGUE_STRIDE: int; const CATALOGUE: PackedInt32Array   # rows [id, channel, max_bytes], 04 s2.3 order
const NAMES: PackedStringArray                        # in CATALOGUE row order
static func row_of(id: int) -> int                    # -1 when unknown or reserved
static func is_known(id: int) -> bool;  static func is_reserved(id: int) -> bool;  static func is_client_to_server(id: int) -> bool
static func channel_of(id: int) -> int                # -1 when unknown
static func max_bytes(id: int) -> int                 # parser limit incl. the id byte; 0 when unknown
static func channel_allows(channel: int, id: int) -> bool;  static func name_of(id: int) -> String;  static func message_count() -> int
# Wire enums owned by 04: Platform, InputClass, Role, ChatScope, LeaveReason, KeyframeRequest, RefuseReason,
#   KeyframeScope, ChatStatus, PlayerStatus, MatchEndReason, RosterRemoveReason, AdminNotice, SessionPhase.
# Wire mirrors of R0 B.3 sim enums: CommandKind, ResultCode, BuildReject, EventKind, ReleaseReason,
#   ControlState, DockState, PlayerKind, QuickPingKind.
# Flag bits: SNAP_HAS_A/B/C, SNAP_HAS_PILOT, SNAP_CONTINUED, SNAP_LAST; TEAM_CORE_EXPOSURE, TEAM_LOW_POWER,
#   TEAM_CORE_SHIELD_UP, TEAM_SPEND_LOCK_ACTIVE; PSTATUS_AUTO_ECONOMY, PSTATUS_ADJUTANT_ON; LOBBY_REVEALED,
#   LOBBY_SLOT_LOCKED/AUTO_ECONOMY/CONNECTED/BOT; TEAM_DETAIL_FULL; PROJ_HAS_FUSE.

class_name Codec                                      # net/codec.gd; all static, allocation-free (04 s3.2-s3.3)
const POS_EN_HALF: float; const POS_U_MIN: float; const POS_U_SPAN: float   # 1280 (A-23), -768, 4096 m
const POS_LEVELS: int; const POS_EN_QUANTUM: float; const POS_U_QUANTUM: float   # 65536; 3.906 cm; 6.25 cm
const POS_INVALID: int; const CELL_COUNT: int        # -1; 384 interest cells (Sphere.GRID_INTEREST)
const QUAT_FULL_MAX: int; const QUAT_COARSE_MAX: int; const QUAT_COARSE_SPARE_SHIFT: int; const QUAT_COARSE_SPARE_MASK: int
const VEL_UNIT: float; const VEL_MAX: int; const HP_MAX: int; const FLAG_CONTROL_MASK: int; const FLAG_DOCKED: int; const FLAG_FIRING: int
const FLAG_BOOSTING: int; const FLAG_BRAKING: int; const FLAG_CLASS_BIT: int; const FLAG_DYING: int
const POS_BYTES: int; const QUAT_BYTES: int; const QUAT_COARSE_BYTES: int; const VEL_BYTES: int; const HP_BYTES: int; const FLAGS_BYTES: int; const AI_TAG_BYTES: int; const FULL_RECORD_BYTES: int   # 8 4 3 3 1 1 1; 19
static func cell_centre(cell: int) -> Vector3;  static func cell_frame(cell: int) -> Basis   # datum centre; ENU columns
static func quantize_pos(p: Vector3) -> int           # packed vec3q: cell | e << 16 | n << 32 | u << 48 (clamps)
static func dequantize_pos(q: int) -> Vector3         # ZERO for an invalid cell
static func pos_in_range(p: Vector3) -> bool          # false when quantize_pos would clamp; true -500 m..ceiling_hard_m
static func pack_pos(cell: int, e: int, n: int, u: int) -> int;  static func pos_cell(q: int) -> int;  static func pos_e(q: int) -> int;  static func pos_n(q: int) -> int;  static func pos_u(q: int) -> int
static func quantize_quat(q: Quaternion) -> int       # quat_s3, u32
static func dequantize_quat(bits: int) -> Quaternion  # unit for any input bits
static func quantize_quat_coarse(q: Quaternion, spare7: int) -> int   # u24: 17 quaternion bits + 7 caller bits
static func dequantize_quat_coarse(bits: int) -> Quaternion;  static func coarse_spare(bits: int) -> int
const SPARE_LOW_MASK: int; const SPARE_CLASS_BIT: int; const SPARE_DYING: int; const FLAGS_DROPPED_BY_B: int   # 0x1F 0x20 0x40; 0x20
static func flags_to_spare(f: int) -> int;  static func spare_to_flags(s: int) -> int   # tier-B flags (A-24); braking reads false
static func quantize_vel(v: Vector3, cell: int) -> int   # 3 x i8 at 2 m/s in cell ENU; 0 for an invalid cell
static func dequantize_vel(bits: int, cell: int) -> Vector3;  static func quantize_hp(hp01: float) -> int;  static func dequantize_hp(b: int) -> float
static func make_flags(control_state: int, bits: int) -> int;  static func flags_control(f: int) -> int;  static func quantize_ai_tag(tag: int) -> int
static func write_pos(buf: PackedByteArray, at: int, q: int) -> int;  static func read_pos(buf: PackedByteArray, at: int) -> int
static func write_u32(buf: PackedByteArray, at: int, v: int) -> int;  static func read_u32(buf: PackedByteArray, at: int) -> int
static func write_u24(buf: PackedByteArray, at: int, v: int) -> int;  static func read_u24(buf: PackedByteArray, at: int) -> int
    # writers return the next offset or -1 (nothing written); readers return -1 / POS_INVALID when short

class_name Roster extends RefCounted                  # net/roster.gd (04 s3.1); roster index == sim slot, 1,280 entries
const CAPACITY: int; const REASON_COUNT: int; const NEVER: int   # 1280; 3; -1
func add(slot: int, generation: int, def_id: int, owner: int, team: int, tag: String = "") -> bool   # replaces; false out of range
func remove(slot: int, reason: int) -> bool           # reason = Protocol.RosterRemoveReason; false when absent/invalid
func has(slot: int) -> bool;  func count() -> int;  func clear() -> void;  func state_hash() -> int
func generation_of(slot: int) -> int;  func def_of(slot: int) -> int;  func owner_of(slot: int) -> int;  func team_of(slot: int) -> int
func tag_of(slot: int) -> String;  func removal_reason_of(slot: int) -> int   # NEVER while present / never removed

class_name RosterCodec                                # net/roster_codec.gd; ENTITY_META 0x88, ROSTER_REMOVE 0x90, REQUEST_KEYFRAME
const META_HEADER_BYTES: int; const META_FIXED_BYTES: int; const TAG_MAX_BYTES: int; const REMOVE_HEADER_BYTES: int
const REMOVE_ENTRY_BYTES: int; const COUNT_MAX: int; const KEYFRAME_REQUEST_BYTES: int   # 2 9 16 2 3 255 2
static func encode_meta(roster: Roster, slots: PackedInt32Array, out: Array[PackedByteArray]) -> int   # packets appended; split at 1,200 B
static func decode_meta(bytes: PackedByteArray, roster: Roster, out_slots: PackedInt32Array) -> int   # count; -1 malformed, nothing applied
static func encode_remove(slots: PackedInt32Array, reasons: PackedInt32Array, out: Array[PackedByteArray]) -> int
static func decode_remove(bytes: PackedByteArray, roster: Roster, out_slots: PackedInt32Array) -> int   # absent slots ignored
static func encode_request_keyframe(reason: int) -> PackedByteArray

class_name RosterSync extends RefCounted              # net/roster_sync.gd; client roster + held-record logic (04 s3.1)
const HOLD_TICKS: int; const REQUEST_MIN_TICKS: int; const MAX_HELD: int   # 30 (1 s); 150 (5 s); 64
var roster: Roster;  var requests_sent: int;  var removed_slots: PackedInt32Array;  var added_slots: PackedInt32Array
func on_meta(bytes: PackedByteArray) -> int;  func on_remove(bytes: PackedByteArray) -> int
func hold(now_tick: int, snap_tick: int, bytes: PackedByteArray, missing: PackedInt32Array) -> void
func take_ready(out_ticks: PackedInt32Array, out_bytes: Array[PackedByteArray]) -> int   # held records whose indices all arrived
func held_count() -> int;  func poll(now_tick: int) -> PackedByteArray   # drops records held >= 30 ticks; one REQUEST_KEYFRAME(ROSTER_GAP) per batch, <= 1 / 5 s

class_name Transport extends RefCounted               # net/transport.gd (04 s6.1); signals fire synchronously from poll()
enum DisconnectReason { TIMEOUT, REMOTE_CLOSE, LOCAL_CLOSE, ERROR }   # append-only
signal connected(conn: int);  signal disconnected(conn: int, reason: int);  signal packet(conn: int, channel: int, bytes: PackedByteArray)
func poll() -> void;  func send(conn: int, channel: int, bytes: PackedByteArray, reliable: bool) -> void   # channel mode decides delivery
func rtt_ms(conn: int) -> int;  func kind() -> StringName;  func platform_hint(conn: int) -> int
func close(conn: int, reason: int) -> void;  func stats(conn: int) -> TransportStats   # counts since the previous call

class_name TransportStats extends RefCounted          # bytes_in, bytes_out, packets_in, packets_out: int; loss_estimate: float

class_name LocalTransport extends Transport           # net/transport_local.gd (04 s6.2); in-process, kind() == &"local"
const CLIENT_CONN: int                                # 1: a client endpoint's only conn
var clock: LocalClock                                 # shared virtual clock; tests advance it, nothing sleeps
static func new_server(shared_clock: LocalClock = null) -> LocalTransport
func connect_client(platform: int = Protocol.Platform.LINUX) -> LocalTransport   # client endpoint; server conn ids 1, 2, ...
func server_conn_of() -> int                          # on a client endpoint: the server's conn id for it
func set_fault_model(model: FaultModel, to_clients: bool = true, to_server: bool = true) -> void   # server endpoint; null clears
func link_pipe(conn: int, outbound: bool) -> LocalPipe;  func is_connected_to(conn: int) -> bool;  func connection_count() -> int

class_name LocalClock extends RefCounted              # virtual time, 30 Hz ticks
func now_ms() -> float;  func tick() -> int;  func advance_tick() -> void;  func advance_ms(ms: float) -> void
class_name LocalPipe extends RefCounted               # one link direction
var model: FaultModel;  var sent_unreliable: int;  var dropped_unreliable: int;  var stale_dropped: int
func _init(clock: LocalClock) -> void;  func configure(m: FaultModel, stream: StringName) -> void;  func pending_count() -> int;  func push(channel: int, bytes: PackedByteArray) -> void
func collect(out_channels: PackedInt32Array, out_bytes: Array[PackedByteArray]) -> void   # appends the packets due now

class_name FaultModel extends RefCounted              # net/fault_model.gd (04 s15.1)
enum Preset { LAN, GOOD, TARGET, BAD, MOBILE_SWITCH, TAB_STALL }
var seed_value: int; var latency_ms: float; var jitter_ms: float; var loss: float; var reorder: float; var duplicate: float
var bandwidth_kbps: float; var burst_loss: Array[Vector2i]            # [from_tick, to_tick)
func stall_at(tick: int, ms: float) -> void;  func in_burst(tick: int) -> bool;  func has_stall() -> bool
static func preset(which: Preset, seed_arg: int = 1) -> FaultModel
static func tick_to_ms(tick: int) -> float;  func burst_end_tick(tick: int) -> int;  func stall_adjust(send_ms: float, at_ms: float) -> float

class_name SnapshotFrame extends RefCounted           # net/snapshot_frame.gd: prepare_tick input, rows 0..count-1 (SimView adapter: NET-15)
var tick: int;  var count: int;  var slot: PackedInt32Array;  var pos: PackedVector3Array;  var vel: PackedVector3Array;  var rot: PackedVector4Array
var hp01: PackedFloat32Array;  var flags: PackedByteArray;  var ai_tag: PackedByteArray;  var team: PackedByteArray;  var gravity: PackedByteArray
var under_fire: PackedByteArray;  var visible_mask: PackedInt32Array;  func resize(n: int) -> void
func set_entity(i: int, slot_id: int, p: Vector3, v: Vector3, q: Quaternion, hp: float, flag_byte: int, team_id: int, tag: int = 0, has_gravity: bool = false, visible: int = 0) -> void

class_name SnapshotCodec extends RefCounted           # net/snapshot_codec.gd: shared cache (indexed by roster index) + per-client encode
const HEADER_BYTES: int; const MAX_PACKET_BYTES: int; const MAX_PACKETS_PER_TICK: int; const SECTION_MAX: int; const TEAM_MAX: int; const CAPACITY: int
const GAP_MAX: int; const GAP_ESCAPE: int; const FULL_BODY_BYTES: int; const SMALL_SHIFT: int; const SMALL_MAX: int; const POS_SEND_MIN: int; const LARGE_MAX: int
const MASK_POS_SMALL: int; const MASK_POS_LARGE: int; const MASK_ORI: int; const MASK_VEL: int; const MASK_HP: int; const MASK_FLAGS: int; const MASK_CELL_CHANGED: int; const MASK_FULL: int
enum Tier { A, B, C }
enum Kind { NONE, FULL, DELTA, BLIP }
var gravity: float;  var dt: float;  var prepare_count: int;  var cache_tick: int;  var max_packets: int;  var deferred: int
var n_full: int;  var n_delta: int;  var n_blip: int;  var n_pos_small: int;  var n_pos_large: int   # cumulative record counters
var c_tick: PackedInt32Array;  var c_pos: PackedInt64Array;  var c_ori: PackedInt64Array;  var c_coarse: PackedInt32Array;  var c_vel: PackedInt32Array;  var c_fine: PackedInt64Array
var c_hp: PackedByteArray;  var c_flags: PackedByteArray;  var c_ai: PackedByteArray;  var c_team: PackedByteArray;  var c_grav: PackedByteArray;  var c_blip: PackedInt32Array
func _init(gravity_mps2: float, tick_hz: int) -> void;  func prepare_tick(frame: SnapshotFrame) -> void   # once per tick, before any encode
func coarse_of(s: int) -> int;  func blip_of(s: int) -> int;  func team_visible(team: int) -> PackedInt32Array   # lazy per tick; C candidates
func encode(store: BaselineStore, tick: int, a: PackedInt32Array, b: PackedInt32Array, c: PackedInt32Array, pilot: PilotBlock, out: Array[PackedByteArray]) -> int
static func pos_mask(res: Vector3i) -> int;  static func wire_residual(mask: int, res: Vector3i) -> Vector3i;  static func applied_residual(mask: int, res: Vector3i) -> Vector3i
static func delta_body_bytes(mask: int, tier_b: bool, own: bool) -> int

class_name SnapshotWriter extends RefCounted          # net/snapshot_writer.gd: packet assembly for encode()
var packets: int;  func start(tick: int, base_tick: int, pilot: PilotBlock, out: Array[PackedByteArray], limit: int) -> void
func place(s: int, tier: int, body: int) -> bool;  func finish() -> int;  func put_u24(v: int) -> void
func put_full(pos_q: int, ori: int, vel: int, hp: int, flags: int, ai_tag: int) -> void
func put_delta(mask: int, res: Vector3i, ori: int, tier_b: bool, vel: int, hp: int, flags: int, ai_tag: int) -> void

class_name SnapshotDecoder extends RefCounted         # net/snapshot_decoder.gd: validate the whole packet, then apply
enum Status { OK, MALFORMED, STALE, NO_BASELINE, MISSING_ROSTER }
const MAX_RECORDS: int;  var store: BaselineStore;  var roster: Roster;  var gravity_def: PackedByteArray;  var gravity: float;  var dt: float
var pilot: PilotBlock;  var pilot_tick: int;  var missing: PackedInt32Array;  var malformed: int;  var records_applied: int
func _init(gravity_mps2: float, tick_hz: int, team_id: int, roster_ref: Roster) -> void;  func current() -> BaselineFrame;  func decode(bytes: PackedByteArray) -> int

class_name BaselineStore extends RefCounted           # net/baseline_store.gd: ring of DEPTH (32) frames per client
const DEPTH: int;  var team: int;  var acked_tick: int;  var newest_tick: int;  var last_split: bool;  func _init(team_id: int = 0) -> void
func frame_at(t: int) -> BaselineFrame;  func begin(t: int, base_tick: int) -> BaselineFrame;  func ack(t: int) -> void;  func base_for(t: int) -> int;  func reset() -> void

class_name BaselineFrame extends RefCounted           # net/baseline_frame.gd: what one client holds per roster index after a tick
const CAPACITY: int; const ORI_UNKNOWN: int
var tick: int;  var base_tick: int;  var usable: bool;  var present: PackedByteArray;  var pos: PackedInt64Array;  var ori: PackedInt64Array;  var ori_c: PackedInt32Array
var vel: PackedInt64Array;  var hp: PackedByteArray;  var flags: PackedByteArray;  var ai: PackedByteArray;  var blip: PackedInt32Array;  var etick: PackedInt32Array
func clear(t: int) -> void;  func copy_from(src: BaselineFrame, t: int) -> void;  func set_blip(i: int, t: int, blip_bits: int) -> void
func set_full(i: int, t: int, pos_q: int, ori_bits: int, vel_bits: int, hp_b: int, flag_b: int, ai_tag: int) -> void
func set_delta(i: int, t: int, tier_b: bool, mask: int, pos_q: int, fine_vel: int, ori_bits: int, hp_b: int, flag_b: int, ai_tag: int) -> void
static func coarse_of_full(ori_bits: int) -> int;  func same_state(other: BaselineFrame) -> bool;  func state_hash() -> int

class_name DeadReckon                                 # net/dead_reckon.gd: static, scalar float64 so both ends agree
const BLIP_E8_MAX: int; const BLIP_ALT_STEP: float; const BLIP_ALT_MAX6: int; const BLIP_UNKNOWN: int; const FINE_PER_MPS: int
enum BlipState { MOVING, STATIC, UNDER_FIRE, DYING }
static func dr_levels(pos_q: int, fine: int, dticks: int, grav: bool, g: float, dt: float) -> Vector3i
static func dr_fine(pos_q: int, fine: int, dticks: int, grav: bool, g: float, dt: float) -> int;  static func pack_fine(e: int, n: int, u: int) -> int
static func fine_axis(fine: int, axis: int) -> int;  static func fine_from_bits(bits: int) -> int;  static func bits_from_fine(fine: int) -> int
static func vel_close(a: int, b: int) -> bool;  static func levels_ok(l: Vector3i) -> bool;  static func make_blip(pos_q: int, alt_m: float, state: int) -> int
static func blip_pos(cell: int, blip: int) -> int;  static func blip_state(blip: int) -> int

class_name PilotBlock extends RefCounted              # net/pilot_block.gd: 15 B, wire integers, clamped on write
const BYTES: int
enum Boost { READY, ACTIVE, COOLDOWN }
var fuel_ds: int;  var ammo: int;  var bombs: int;  var rockets: int;  var hull: int;  var incoming_rockets: int;  var boost_state: int;  var flip_cooldown: int
var dock_state: int;  var service_refuel: int;  var service_rearm: int;  var service_repair: int;  static func boost_byte(phase: int, remaining01: float) -> int
func write(buf: PackedByteArray, at: int) -> int;  func read(buf: PackedByteArray, at: int) -> bool;  func copy_from(o: PilotBlock) -> void;  func to_bytes() -> PackedByteArray

class_name PilotWire                                  # net/pilot_wire.gd: 8-byte PilotInput wire form (04 s2.4, R0 C2-09); static, pure
const BYTES: int; const THRUST_SCALE: float; const AXIS_SCALE: float; const BUTTONS_MASK: int; const OFF_RESERVED_A: int; const OFF_RESERVED_B: int; const OFF_TICK_LO: int
static func to_wire(input: PilotInput, tick: int) -> PackedByteArray;  static func write_into(buf: PackedByteArray, at: int, input: PilotInput, tick: int) -> int   # bytes 5-6 always 0
static func from_wire(bytes: PackedByteArray, offset: int, into: PilotInput = null) -> PilotInput   # null when short; reserved bytes not checked here
static func quantized(input: PilotInput) -> PilotInput   # what the server sees; the client predicts with this
static func tick_lo_at(bytes: PackedByteArray, offset: int) -> int;  static func reserved_zero(bytes: PackedByteArray, offset: int) -> bool;  static func axis_byte(a: float) -> int;  static func axis_value(b: int) -> float

class_name InputCodec                                 # net/input_codec.gd: INPUT 0x04 (12 B header + count x 8; 36 B at count 3); static
const HEADER_BYTES: int; const OFF_EPOCH: int; const OFF_BASE: int; const OFF_ACK: int; const OFF_COUNT: int;  enum Status { OK, MALFORMED }
static func encode(epoch: int, base_tick: int, ack_tick: int, inputs: Array[PilotInput], count: int) -> PackedByteArray   # empty when count not 1-3
static func validate(bytes: PackedByteArray) -> int   # V-INP shape: id, length, count 1-3, reserved bytes 0, tick_lo == (base + i) & 255
static func packet_bytes(count: int) -> int;  static func epoch_of(bytes: PackedByteArray) -> int;  static func base_tick_of(bytes: PackedByteArray) -> int;  static func ack_tick_of(bytes: PackedByteArray) -> int;  static func count_of(bytes: PackedByteArray) -> int

class_name InputSender extends RefCounted             # net/input_sender.gd: client side, 3-tick redundancy
var epoch: int;  var packets_built: int;  func reset(new_epoch: int) -> void
func push(tick: int, input: PilotInput) -> PilotInput   # consecutive ticks; returns the quantised input to predict with
func build(ack_tick: int) -> PackedByteArray            # newest <= 3 ticks, newest last; empty before the first push

class_name InputBuffer extends RefCounted             # net/input_buffer.gd: server jitter buffer per player (04 s5.1; R0 C2-08)
const RING: int; const WINDOW_PAST: int; const WINDOW_FUTURE: int; const DECAY_TICKS: int; const DECAY_FACTOR: float; const KEEP_BUTTONS: int; const STRIKE_EVERY: int   # 64; 2; 8; 10; 0.5; 100
var epoch: int;  var bridge: bool;  var miss_run: int;  var ack_tick: int;  var current: PilotInput;  var strikes: int;  var bridge_raised: int
var accepted: int;  var duplicates: int;  var late: int;  var rejected_window: int;  var rejected_epoch: int;  var rejected_malformed: int
func begin_epoch(new_epoch: int) -> void                # possession change: clears, starts in bridge, A is never replayed for B
func submit(packet: PackedByteArray, current_tick: int) -> int   # inputs stored; -1 whole packet rejected; per input window [tick - 2, tick + 8]
func take(tick: int) -> PilotInput                      # stored input, else decayed previous (axes x 0.5 per tick, thrust held) <= 10 ticks, then bridge (once)
```

Link semantics (04 s15.1; deterministic: each pipe draws from `Rng.new(seed_value).fork("s2c:<conn>" | "c2s:<conn>")`):
CH_CONTROL / CH_EVENTS (reliable ordered) are delayed, never lost, delivered in send order, held to the end of a burst or stall window. CH_INPUT may be lost, duplicated, reordered. CH_SNAPSHOT (unreliable sequenced) additionally
drops anything older than the newest delivered. A stall holds both directions and releases the backlog at its end.
Bandwidth limit: serialisation delay, then unreliable packets queued > 250 ms are dropped. Presets (one-way): LAN 0/0/0; GOOD 40 ms +-5, 0.5 %; TARGET 100 ms +-15, 3 %, 1 % reorder; BAD 250 ms +-40, 5 %, 2 % reorder, 0.5 % dup;
MOBILE_SWITCH = TARGET + loss window ticks 900-1019; TAB_STALL = GOOD + 45 s stall at tick 1,200. The 04 name `seed` is `seed_value` (`seed` is a GDScript global); presets are `FaultModel.preset()`, not `test/net/presets.gd`.

Planned (04 s19): `codec_commands.gd` (NET-04), `KEYFRAME` + rolling refresh (NET-07), `Interest` (NET-08), `ENetTransport` (NET-12), `WebSocketTransport` (NET-13), `ClientSession`, `NetSimView` (NET-17), `Prediction` (NET-18), `EventRouter` (NET-10), `ReplayWriter`/`ReplayReader` (NET-25).

## Wire layout

04 s2.3 is the catalogue; `Protocol.CATALOGUE` is that table as data (id, channel, Max B) and is pinned to the doc by `test_protocol.gd`. Multi-byte integers are little-endian (04 s3.5 worked example). Every packet's first byte is
the message id; ids 0x0E-0x7F and 0x94-0xFF are reserved (0x70-0x7F / 0xF0-0xFF for v1.1 WebRTC signalling) and 0x00 is never valid.

Field layouts (`Codec`, 04 s3.2-s3.3): vec3q = cell u16, e u16, n u16, u u16 with `e = dot(p - c, east)` etc. in the
ADR-03 ENU frame of `c = Sphere.cell_center_dir(cell, GRID_INTEREST) * PLANET_RADIUS`, level k = -1280 + k * 3.906 cm
(e, n) and -768 + k * 6.25 cm (u), rounded to nearest. quat_s3 = u32 LE: bits 0-1 index of the largest |component| in
x y z w order (ties: lowest index), bits 2-11 / 12-21 / 22-31 the other three ascending as 10-bit two's complement of
`round(c * 511 * sqrt(2))`, signs flipped so the dropped component is positive (04 s3.5's `9A 2F 4C 71` has index 2).
Coarse = u24 LE: index bits 0-1, 5-bit codes (scale 15 * sqrt(2)) at bits 2, 7, 12, caller bits 17-23; the encoder may
step one code to its other neighbour when that lowers the angular error (decoder unchanged). Velocity = i8 e, n, u at
2 m/s in the ENU frame of the record's position cell (04 s3.5 `37 00 F4` = (110, 0, -24) m/s). hp = round(hp01 * 255).
Flags = control state bits 0-1, then DOCKED, FIRING, BOOSTING, BRAKING, CLASS_BIT, DYING (bits 2-7). Tier-B coarse spare bits (A-24): spare 0-4 = flags 0-4, spare 5 = flags bit 6, spare 6 = flags bit 7; BRAKING is dropped.
`CHAT_RELAY` (0x8C) Max is 222, as in 04 s2.3 (A-26). `SessionPhase` is defined only in `Protocol` (A-28).

SNAPSHOT (04 s3.4, s3.5; NET-06): header id, tick u32, baseline_tick u32 (0 = no baseline, FULL only), flags; sections
A, B, C in that order, each a u8 count (1-255) then records. A record starts with the roster-index gap: u8 1-254 from the
previous record of the packet (the chain runs across sections and restarts per packet; 0 only for index 0 as the first
record), or 0xFF + u16 index. Next byte 0xFF = FULL (vec3q, quat_s3, vel, hp, flags, +ai_tag own team); otherwise A/B: a
DELTA mask (bit 7 and bit 6 clear, not both POS bits), groups in mask-bit order; C: a C-BLIP (e8 clamped to 254 so it
never reads 0xFF, n8, alt6 | state << 6). POS_SMALL = 3 x i8 in 4-quanta steps (15.6 cm E/N, 25 cm U), POS_LARGE = 3 x
i16 quanta, both against `DeadReckon.dr_levels` of the client's entry. B ORI = coarse u24 with the A-24 flags; B bit 5 = ai_tag (own team = roster team equals the client's). The 15-byte pilot block ends the first packet of a tick.

## Invariants

- N1: every id in 04 s2.3 is defined exactly once, on the channel 04 s2.1 lists; a message received on another
  channel, with an unknown/reserved id, or longer than `max_bytes(id)` is dropped and counted, never parsed (04 s11.4).
- N2: wire enums are append-only; the mirrors of sim enums equal the ordinals in `sim/MODULE.md` / R0 B.3.
- N3: no packet on channels 1 and 2 exceeds `MAX_UNRELIABLE_BYTES` (1,200).
- N4: no Nodes, `await`, `Thread` or `WorkerThreadPool` in `net/` codec or protocol code; web runs single-threaded.
- N5: decoders never throw or stall on malformed input (fuzz harness NET-23: 100,000 mutations per id).
- N6: `LocalSimView` and `NetSimView` pass the same `SimView` contract test (NET-17).
- N7: `Codec` round trips within 04 s3.2/s3.3: e, n <= 2.0 cm (incl. float32 storage), u <= 3.1 cm (+ <= 0.5 mm) for
  every point from -500 m to `ceiling_hard_m` (A-23); quat_s3 <= 0.4 deg; coarse <= 6 deg; velocity <= 1 m/s per ENU axis; hp <= 0.5/255.
- N8: `Codec` quantisers and decoders allocate nothing and never error: any input bits decode to a defined value
  (unit quaternion, ZERO, or the -1 / POS_INVALID sentinel).
- N9: the server mirror (`BaselineStore` per client) and the client's frame for every fully received tick are
  identical (`same_state`): both change only through `BaselineFrame.set_*` with `DeadReckon` arithmetic. A frame is a delta baseline only when its tick went out as one packet (`usable`); `prepare_tick` runs once per tick.
- N10: `SnapshotDecoder.decode` validates the whole packet before applying; anything but OK changes nothing.

## Data owned

The wire catalogue and enums above. No def files are read by `Protocol`; `rules.gravity` / `tick_hz` reach the codec as arguments.

## Performance budget

Bandwidth: 04 s4.6 (24 KB/s typical, 30 KB/s cap per client, 01 s8.3). CPU: the 03 s4.2 "events + interest + encode + replay" row (R0 B.7) covers `prepare_tick` and per-client encoding; `Protocol` lookups are O(1). NET-06
measured (400 entities, desktop, p50): prepare_tick 1.26 ms, encode 1.1-1.2 ms and decode 0.53 ms per client.

## Test entry points

`test/unit/net/test_protocol.gd` (NET-01 catalogue vs 04 s2.1/s2.3, enum ordinals, PROTOCOL_VERSION); `test/unit/net/test_codec_roundtrip.gd` (NET-02 codec_roundtrip_test: 10,000 points, cell corners, A-23 envelope, A-24 flags, quaternions, velocity, hp, sizes); `test/net/test_codec_full_records.gd`; `test/perf/bench_codec.gd` (BENCH_CODEC).
NET-06: `test/unit/net/test_snapshot_codec.gd` (04 s3.5 53 B example, masks, dead reckoning, blip, pilot block, A-24), `test_snapshot_malformed.gd` (20,000 mutations), `test/net/test_snapshot_delta.gd` (3,000 ticks), `test_snapshot_budget.gd` (splitting, bandwidth, determinism); `test/perf/bench_snapshot.gd` (BENCH_SNAPSHOT); helper `test/net/snap_rig.gd`.
NET-03: `test/unit/net/test_pilot_wire.gd` (all byte values round trip, reserved bytes, V-INP shape, 20,000 mutations), `test_input_buffer.gd` (window, duplicates, stale epoch, strikes, 10-tick decay then one bridge, hand-off, determinism), `test/net/test_input_link.gd` (LocalTransport: BAD preset recovers single/double loss, triple loss drops one tick, silence bridge once, slow client, determinism).
`godot/test/unit/net/test_roster.gd` + `godot/test/net/test_roster_sync.gd` (NET-05: add/remove with every reason, meta/remove round trips and sizes, malformed rejected, held record applied after meta, timeout at exactly 30 ticks with one REQUEST_KEYFRAME, re-add in the hold window, determinism, LocalTransport pair).
`godot/test/unit/net/test_transport_local.gd` (NET-11: channel ordering/reliability, determinism per seed, burst, stall, bandwidth, close, stats).
`godot/test/net/test_fault_presets.gd` (NET-11: loss/latency/reorder/dup statistics per preset over 6,000 packets, MOBILE_SWITCH, TAB_STALL).
Planned: interest benchmarks (NET-08), fuzz_test.gd (NET-23).

## How to add X

**A message id.** Architect (contract change): add the row to 04 s2.3 and s2.1, then the constant, `CATALOGUE` row and `NAMES` entry here, bump `PROTOCOL_VERSION`, run `test_protocol.gd`. **A wire enum value.** Append only; sim mirrors: append in `sim/MODULE.md` first.

## Open items

NET-02 CQ-1..3, CHAT_RELAY, `SessionPhase` closed by NET-47 (A-23..A-26, A-28). NET-06 asks the Architect: CQ-4 SNAPSHOT has no packet index, so a split tick cannot become a baseline (proposal: flags bits 6-7, PROTOCOL_VERSION 2); CQ-5 04 does not say how section C tells FULL from C-BLIP (e8 clamped to 254); CQ-6 04 s3.4 POS_SMALL text predates A-23 (now 15.6 cm, +-19.8 m E/N, bytes unchanged); CQ-7 sub-step residuals are not sent, entries keep velocity at 1/1024 m/s, gravity VEL is sent only past one 2 m/s step.
NET-03 asks: `PilotInput`'s doc comment (sim) says `to_bytes`/`from_bytes` land with NET-03; the wire form lives in `net/PilotWire` (04 s2.4 `to_wire`/`from_wire`), sim comment needs updating (sim lane). Silence (R0 C2-08) drops FLIP/DOCK/RELEASE/FIRE bits in reused inputs (04 silent; NQ10 tick count 10 vs 60 is still open).
