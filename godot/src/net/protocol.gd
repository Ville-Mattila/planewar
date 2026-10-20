class_name Protocol
## Wire protocol constants (04 s2): PROTOCOL_VERSION, message ids, channel map, the 04 s2.3 catalogue
## (id, channel, parser max bytes) as data, and the wire enums the catalogue names. All static, no state
## besides a lazily built 256-entry lookup; no Nodes. Any change to a value here is a contract change
## (04 s2.2: bump PROTOCOL_VERSION on any layout change). Enumerations are append-only (R0 B.3).

## 04 s2.2. A mismatch is REFUSE(VERSION); there is no negotiation in v1.
const PROTOCOL_VERSION: int = 1

# region message ids (04 s2.3). < 0x80 client -> server, >= 0x80 server -> client.
const HELLO: int = 0x01
const LOADED: int = 0x02
const COMMAND: int = 0x03
const INPUT: int = 0x04
const SNAPSHOT_ACK: int = 0x05
const PING: int = 0x06
const CHAT: int = 0x07
const QUICK_PING: int = 0x08
const INTEREST_HINT: int = 0x09
const LEAVE: int = 0x0A
const REQUEST_KEYFRAME: int = 0x0B
const SPECTATE_FOLLOW: int = 0x0C
const DOCTRINE_PICK: int = 0x0D             # R0 C2-16
const WELCOME: int = 0x80
const REFUSE: int = 0x81
const MATCH_STATE: int = 0x82
const COMMAND_RESULT: int = 0x83
const SNAPSHOT: int = 0x84
const TEAM_STATE: int = 0x85
const KEYFRAME: int = 0x86
const EVENTS: int = 0x87
const ENTITY_META: int = 0x88
const POSSESS_ACK: int = 0x89
const RELEASED: int = 0x8A
const PONG: int = 0x8B
const CHAT_RELAY: int = 0x8C
const PLAYER_STATUS: int = 0x8D
const MATCH_END: int = 0x8E
const PROJECTILE_BATCH: int = 0x8F
const ROSTER_REMOVE: int = 0x90
const ADMIN_NOTICE: int = 0x91
const TEAM_DETAIL: int = 0x92               # R0 C2-05
const LOBBY_STATE: int = 0x93               # R0 C2-16

const INVALID_ID: int = 0x00                # unassigned and not reserved: never valid
const SERVER_TO_CLIENT_MIN: int = 0x80
## Reserved ranges (04 s2.3): receiving a reserved id is a protocol violation (04 s11.4).
const C2S_RESERVED_FIRST: int = 0x0E
const C2S_RESERVED_LAST: int = 0x7F
const S2C_RESERVED_FIRST: int = 0x94
const S2C_RESERVED_LAST: int = 0xFF
const C2S_WEBRTC_FIRST: int = 0x70          # v1.1 WebRTC signalling (S-NET-2)
const C2S_WEBRTC_LAST: int = 0x7F
const S2C_WEBRTC_FIRST: int = 0xF0
const S2C_WEBRTC_LAST: int = 0xFF
# endregion

# region channels (04 s2.1, 01 s9.4)
const CH_CONTROL: int = 0                   # reliable, ordered
const CH_INPUT: int = 1                     # unreliable, unsequenced
const CH_SNAPSHOT: int = 2                  # unreliable, sequenced (newest wins)
const CH_EVENTS: int = 3                    # reliable, ordered
const CHANNEL_COUNT: int = 4

enum ChannelMode { RELIABLE_ORDERED, UNRELIABLE, UNRELIABLE_SEQUENCED }
## Indexed by channel. ENet maps RELIABLE_ORDERED -> TRANSFER_MODE_RELIABLE, UNRELIABLE ->
## TRANSFER_MODE_UNRELIABLE, UNRELIABLE_SEQUENCED -> TRANSFER_MODE_UNRELIABLE_ORDERED (04 s2.1).
const CHANNEL_MODE: PackedInt32Array = [0, 1, 2, 0]
# endregion

# region framing limits (04 s2.1-s2.4, s3)
const MAX_UNRELIABLE_BYTES: int = 1200      # R2 s5.4: fragmented unreliable ENet packets turn reliable
const MAX_RELIABLE_BYTES: int = 65535       # KEYFRAME parser limit; ENet fragments, one WebSocket frame
const HASH_BYTES: int = 32                  # CONTENT_HASH, MAP_HASH, result_hash (SHA-256)
const SECRET_BYTES: int = 16                # reconnect_secret
const PILOT_INPUT_BYTES: int = 8            # 04 s2.4
const INPUT_MAX_COUNT: int = 3              # INPUT carries 1-3 inputs
const COMMAND_PAYLOAD_MAX: int = 256        # 04 s2.5
const SLOT_SPECTATOR: int = 255             # WELCOME.slot
const SLOT_NONE: int = 255                  # RELEASED.new_possessor
const DOCTRINE_HIDDEN: int = 255            # WELCOME / LOBBY_STATE until REVEALED
const ROSTER_NONE: int = 0xFFFF             # event roster field: entity not in this client's roster
# endregion

# region catalogue (04 s2.3) as data: rows of [id, channel, max_bytes]
## Max is the hard parser limit (04 s11.4). CHAT_RELAY is 222 = 1+8+1+1+4+(2+200)+4+1 (R0 B.9 A-26).
const CATALOGUE_STRIDE: int = 3
const CATALOGUE: PackedInt32Array = [
	HELLO, CH_CONTROL, 230,
	LOADED, CH_CONTROL, 33,
	COMMAND, CH_CONTROL, 270,
	INPUT, CH_INPUT, 36,
	SNAPSHOT_ACK, CH_INPUT, 7,
	PING, CH_INPUT, 5,
	CHAT, CH_CONTROL, 210,
	QUICK_PING, CH_CONTROL, 14,
	INTEREST_HINT, CH_CONTROL, 8,
	LEAVE, CH_CONTROL, 2,
	REQUEST_KEYFRAME, CH_CONTROL, 2,
	SPECTATE_FOLLOW, CH_CONTROL, 5,
	DOCTRINE_PICK, CH_CONTROL, 3,
	WELCOME, CH_CONTROL, 700,
	REFUSE, CH_CONTROL, 125,
	MATCH_STATE, CH_CONTROL, 9,
	COMMAND_RESULT, CH_CONTROL, 5,
	SNAPSHOT, CH_SNAPSHOT, 1200,
	TEAM_STATE, CH_SNAPSHOT, 72,
	KEYFRAME, CH_EVENTS, 65535,
	EVENTS, CH_EVENTS, 1200,
	ENTITY_META, CH_EVENTS, 1200,
	POSSESS_ACK, CH_EVENTS, 60,
	RELEASED, CH_EVENTS, 13,
	PONG, CH_INPUT, 13,
	CHAT_RELAY, CH_CONTROL, 222,
	PLAYER_STATUS, CH_CONTROL, 6,
	MATCH_END, CH_CONTROL, 640,
	PROJECTILE_BATCH, CH_SNAPSHOT, 1200,
	ROSTER_REMOVE, CH_EVENTS, 768,
	ADMIN_NOTICE, CH_CONTROL, 130,
	TEAM_DETAIL, CH_EVENTS, 1200,
	LOBBY_STATE, CH_CONTROL, 30,
]
## Names in CATALOGUE row order (04 s2.3 spelling).
const NAMES: PackedStringArray = [
	"HELLO", "LOADED", "COMMAND", "INPUT", "SNAPSHOT_ACK", "PING", "CHAT", "QUICK_PING",
	"INTEREST_HINT", "LEAVE", "REQUEST_KEYFRAME", "SPECTATE_FOLLOW", "DOCTRINE_PICK",
	"WELCOME", "REFUSE", "MATCH_STATE", "COMMAND_RESULT", "SNAPSHOT", "TEAM_STATE", "KEYFRAME",
	"EVENTS", "ENTITY_META", "POSSESS_ACK", "RELEASED", "PONG", "CHAT_RELAY", "PLAYER_STATUS",
	"MATCH_END", "PROJECTILE_BATCH", "ROSTER_REMOVE", "ADMIN_NOTICE", "TEAM_DETAIL", "LOBBY_STATE",
]
# endregion

# region wire enums owned by 04 (append-only)
enum Platform { WIN, MAC, LINUX, ANDROID, IOS, WEB, SERVER_BOT }               # HELLO.platform
enum WireInputClass { TOUCH, GAMEPAD, POINTER }                                    # HELLO.input_class
enum Role { PLAYER, SPECTATOR, ADMIN }                                         # HELLO.role
enum ChatScope { TEAM, ALL }                                                   # ALL reserved (custom lobbies)
enum LeaveReason { QUIT, TO_MENU, CRASH_REPORTED }
enum KeyframeRequest { DESYNC, ROSTER_GAP, RESUME }                            # REQUEST_KEYFRAME.reason
enum RefuseReason { VERSION, CONTENT_HASH, TOKEN_INVALID, TOKEN_EXPIRED, MATCH_FULL, MATCH_ENDED,
		BANNED, SERVER_DRAINING, RATE_LIMIT }
enum KeyframeScope { ALL, ROSTER_REPAIR }                                      # R0 B.3: TIER_C_ONLY removed
enum ChatStatus { OK, BLOCKED_AGE, MUTED, RATE, INVALID }                      # CHAT_RELAY.status
enum PlayerStatus { CONNECTED, DISCONNECTED_GRACE, BOT_TAKEOVER, RECONNECTED, LEFT, ELIMINATED_COMMANDER }
enum MatchEndReason { CORES_DESTROYED, HARD_END_VALUE, SURRENDER, ABANDONED, ADMIN }
enum RosterRemoveReason { DEATH, OUT_OF_VISION, LEFT_INTEREST }                # R0 C2-35
enum AdminNotice { SERVER_DRAIN_WARNING, PAUSE, RESUME, KICK }
## R0 B.3 SessionPhase: the one definition (R0 B.9 A-28), driven by ServerSession; MATCH_STATE.phase
## shows LOBBY..ENDED to clients.
enum SessionPhase { POOLED, ALLOCATED, LOBBY, LOADING, COUNTDOWN, PLAYING, ENDED, REPORTED, ABORTED }
# endregion

# region wire mirrors of sim enums (R0 B.3; ordinals pinned to sim/MODULE.md by test_protocol.gd)
## Command.Kind -> COMMAND.kind
enum CommandKind { ORDER, BUILD, CANCEL_BUILD, PRODUCE, CANCEL_PRODUCE, SET_RALLY, POSSESS, RELEASE,
		REQUEST_POSSESS, HANDOVER, PILOT_INPUT, TOGGLE_AUTO_REPLENISH, SURRENDER, SET_ADJUTANT,
		DEBUG_SPAWN, DEBUG_SET }
## CommandResult.Code -> COMMAND_RESULT.code
enum ResultCode { ACCEPTED, REJECTED_DEAD, REJECTED_NOT_OWNER, REJECTED_NOT_POSSESSABLE,
		REJECTED_ALREADY_POSSESSED, REJECTED_NO_RIGHTS, REJECTED_CAP, REJECTED_COST, REJECTED_PLACEMENT,
		REJECTED_RATE, REJECTED_MALFORMED, REJECTED_INVALID_ORDER, REJECTED_UPLINK, REJECTED_PHASE,
		REJECTED_LOCKED, REJECTED_PREREQ }
## Build.Reject -> COMMAND_RESULT.detail when code = REJECTED_PLACEMENT
enum BuildReject { OK, ELIMINATED, PREREQ, CAP, OCCUPIED, SLOPE, NODE, NOT_VISIBLE, ENEMY_RADIUS,
		NO_RADIUS, NO_PRESENCE, SPACING, FUNDS, SPEND_LOCKED }
## SimEvent.Kind -> EVENTS kind byte (04 s3.6); MATCH_END (17) never travels in EVENTS.
enum EventKind { SPAWN, DEATH, HIT, BOMB_IMPACT, DOCKED, SERVICED, LAUNCHED, ORDER_DONE, ORDER_FAILED,
		POSSESSED, RELEASED, BUILD_STARTED, BUILD_DONE, STRUCTURE_LOST, LOW_POWER, ALERT, CORE_EXPOSURE,
		MATCH_END, CAP_REACHED, WRECK_SPAWNED, WRECK_SALVAGED, CEILING_RELEASE, HANDOVER,
		PLAYER_ELIMINATED, LOCK_ACQUIRED, LOCK_BROKEN, CAPTURE_PROGRESS, CAPTURED, SALVAGE_DELIVERED,
		LANDING, SHIELD_COLLAPSE, POSSESS_REQUESTED, CANISTER_DEPLOYED, CANISTER_COLLECTED }
enum ReleaseReason { PLAYER, DEATH, CEILING, HANDOVER, DISCONNECT, MATCH, INVALID, ADMIN }   # RELEASED.reason
enum ControlState { AUTO, ORDERED, POSSESSED }                                 # snapshot flags bits 0-1
enum DockState { FLYING, LANDING_ASSIST, DOCKED, LAUNCHING }                   # pilot block dock_state
enum PlayerKind { HUMAN, BOT, OPEN }                                           # WELCOME players[].kind
## QuickPing.Kind (06 content/ui/pings.json, R0 B.3) -> QUICK_PING.kind
enum QuickPingKind { ATTACK_HERE, DEFEND_HERE, NEED_ESCORT, ENEMY_BOMBERS, ON_MY_WAY, NEED_ICE, THANKS,
		RETREAT, WING_FORM, WING_ATTACK, WING_RELEASE, NEED_SUPPLY }
# endregion

# region flag bits (04 s2.3, s3.4)
const SNAP_HAS_A: int = 1                   # SNAPSHOT.flags
const SNAP_HAS_B: int = 2
const SNAP_HAS_C: int = 4
const SNAP_HAS_PILOT: int = 8
const SNAP_CONTINUED: int = 16
const SNAP_LAST: int = 32
const SNAP_INDEX_SHIFT: int = 6             # bits 6-7: packet index 0-3 within the tick (R0 B.10 A-36)
const TEAM_CORE_EXPOSURE: int = 1           # TEAM_STATE.flags = TeamStateView constants (R0 B.8 A-8)
const TEAM_LOW_POWER: int = 2
const TEAM_CORE_SHIELD_UP: int = 4
const TEAM_SPEND_LOCK_ACTIVE: int = 8
const PSTATUS_AUTO_ECONOMY: int = 1         # PLAYER_STATUS.flags
const PSTATUS_ADJUTANT_ON: int = 2
const LOBBY_REVEALED: int = 1               # LOBBY_STATE.flags
const LOBBY_SLOT_LOCKED: int = 1            # LOBBY_STATE.slots[].flags
const LOBBY_SLOT_AUTO_ECONOMY: int = 2
const LOBBY_SLOT_CONNECTED: int = 4
const LOBBY_SLOT_BOT: int = 8
const TEAM_DETAIL_FULL: int = 1             # TEAM_DETAIL.flags
const PROJ_HAS_FUSE: int = 0x80             # PROJECTILE_BATCH weapon_slot bit7
# endregion

static var _lookup: PackedInt32Array = PackedInt32Array()


## CATALOGUE row index for a message id, or -1 when the id is unknown or reserved.
static func row_of(id: int) -> int:
	if id < 0 or id > 0xFF:
		return -1
	if _lookup.is_empty():
		_build_lookup()
	return _lookup[id]


static func is_known(id: int) -> bool:
	return row_of(id) >= 0


static func is_client_to_server(id: int) -> bool:
	return id >= 0 and id < SERVER_TO_CLIENT_MIN


## True for ids in the 04 s2.3 reserved ranges (0x0E-0x7F, 0x94-0xFF).
static func is_reserved(id: int) -> bool:
	return (id >= C2S_RESERVED_FIRST and id <= C2S_RESERVED_LAST) or \
			(id >= S2C_RESERVED_FIRST and id <= S2C_RESERVED_LAST)


## Channel a message travels on, or -1 for an unknown id.
static func channel_of(id: int) -> int:
	var r: int = row_of(id)
	return -1 if r < 0 else CATALOGUE[r * CATALOGUE_STRIDE + 1]


## Parser limit in bytes including the id byte, or 0 for an unknown id.
static func max_bytes(id: int) -> int:
	var r: int = row_of(id)
	return 0 if r < 0 else CATALOGUE[r * CATALOGUE_STRIDE + 2]


## Receivers drop a message that arrives on a channel other than its catalogue channel.
static func channel_allows(channel: int, id: int) -> bool:
	return channel >= 0 and channel_of(id) == channel


static func name_of(id: int) -> String:
	var r: int = row_of(id)
	return "" if r < 0 else NAMES[r]


static func message_count() -> int:
	return floori(float(CATALOGUE.size()) / float(CATALOGUE_STRIDE))


static func _build_lookup() -> void:
	var t: PackedInt32Array = PackedInt32Array()
	var _r: int = t.resize(256)
	t.fill(-1)
	for r: int in message_count():
		t[CATALOGUE[r * CATALOGUE_STRIDE]] = r
	_lookup = t
