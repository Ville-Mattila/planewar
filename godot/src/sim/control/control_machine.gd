class_name ControlMachine extends RefCounted
## The control-state machine of 05 s2 (AI-02; R0 C2-08, B.3; A-44, A-45): every transition C1-C18 of 05 s2.3, the
## C6r / V-REQ rejection codes, the single `ReleaseReason` enum and the events of each row. One per `SimWorld`.
## Commands reach it in tick step 1 (`apply`, `order`), the silent-pilot rule runs in step 2 (`step_inputs`), the
## control check (ceiling, invalidation, request expiry) at the start of step 3 (`control_check`), deaths at the end
## of step 9 (`on_death`). It *sets* overlays; `sim_ai` executes SAFETY / RECOVER_CEILING, `Assist.link_bridge`
## executes LINK_BRIDGE (05 s1.3). Guards (`check_*`) are pure: `CommandValidator` calls them at intake and again in
## step 1, so a command that turned invalid in between has no effect (S10). Order validity on resume and the
## C4 / C5 queue pops live in `ControlOrders`. No allocation per tick: per-player loops over 8 slots only.

enum State { AUTO, ORDERED, POSSESSED }
enum Overlay { NONE, SAFETY, RECOVER_CEILING, LINK_BRIDGE }
enum ReleaseReason { PLAYER, DEATH, CEILING, HANDOVER, DISCONNECT, MATCH, INVALID, ADMIN }
enum OrderFail { INVALID_TARGET, UNREACHABLE, STUCK, OVERRIDDEN, INVALID_ON_RESUME, NO_PAD, NO_AMMO }

## 05 C13 silent-pilot window: mirrors net's `InputBuffer.DECAY_TICKS` (R0 B.10 A-45; NET-19 `handoff_test` pins both).
const DECAY_TICKS: int = 10
## A-44: stick axes halve per silent tick; thrust, BOOST and BRAKE are held, every momentary button is cleared.
const DECAY_FACTOR: float = 0.5
const KEEP_BUTTONS: int = PilotInput.BOOST | PilotInput.BRAKE
## 05 s2.1 / C17 / V-REQ: a hand-over request lives 10 s. Documented default of `rules.request_ttl_s` (`configure`).
const REQUEST_TTL_S: int = 10
## 05 s3.4: the OVERRIDDEN echo fires when the replaced head is younger than 10 s. Default of `rules.override_echo_s`.
const ECHO_WINDOW_S: int = 10
## 05 C6r: REJECTED_UPLINK at altitude >= ceiling_hard_m - 50 m (1,950 m). Default of `rules.uplink_margin_m`.
const UPLINK_MARGIN_M: int = 50
const _STATE: PackedStringArray = ["_request_from", "_request_tick", "_last_input", "_silent", "_fresh", "_admin", "_team_out"]

var orders: ControlOrders                             ## C1-C5, C7 and the resume rules of C9

var _store: EntityStore
var _players: PlayerTable
var _inputs: InputSlots
var _events: SimEvents
var _hz: int = 1
var _request_ttl_s: int = REQUEST_TTL_S
var _uplink_r: float = 0.0
var _ceiling_r: float = 0.0
var _request_from: PackedByteArray = PackedByteArray()   # per main-range slot: requesting player or NONE_U8
var _request_tick: PackedInt32Array = PackedInt32Array()
var _last_input: PackedInt32Array = PackedInt32Array()   # per player: tick of the last fresh PilotInput (05 s2.1)
var _silent: PackedInt32Array = PackedInt32Array()       # per player: ticks without input since possession (-1 = possessed this tick)
var _fresh: PackedByteArray = PackedByteArray()          # per player: a PILOT_INPUT was stored since the last step 2
var _admin: PackedByteArray = PackedByteArray()          # per player: ADMIN release queued for the next step 1
var _team_out: PackedByteArray = PackedByteArray()       # per team: lost its last Core; members are spectators


func _init(store: EntityStore, queue: OrderQueue, players: PlayerTable, inputs: InputSlots, events: SimEvents,
		ceiling_hard_m: float, tick_hz: int) -> void:
	_store = store
	_players = players
	_inputs = inputs
	_events = events
	_hz = maxi(tick_hz, 1)
	_ceiling_r = Sphere.PLANET_RADIUS + ceiling_hard_m
	_uplink_r = _ceiling_r - float(UPLINK_MARGIN_M)
	orders = ControlOrders.new(store, queue, players, events, _hz)
	var n: int = InputSlots.ENTITY_SLOTS
	var m: int = PlayerTable.SLOTS
	var e: int = _request_from.resize(n) | _request_tick.resize(n) | _last_input.resize(m) | _silent.resize(m)
	e |= _fresh.resize(m) | _admin.resize(m) | _team_out.resize(PlayerTable.TEAMS)
	assert(e == OK)
	_request_from.fill(EntityStore.NONE_U8)
	_request_tick.fill(0)
	_last_input.fill(-1)
	_silent.fill(0)
	_fresh.fill(0)
	_admin.fill(0)
	_team_out.fill(0)


## R0 B.11 A-51: the uplink margin, request TTL and echo window come from `rules`; the consts are the defaults.
func configure(rules: RulesDef) -> void:
	_uplink_r = _ceiling_r - float(rules.uplink_margin_m)
	_request_ttl_s = rules.request_ttl_s
	orders.echo_window_s = rules.override_echo_s


# --- guards (pure) -------------------------------------------------------------------------------------------------

## 05 C6 / C6r in the table's order; `claimed`: another POSSESS of `t` was accepted since the last step 1.
func check_possess(p: int, t: int, claimed: bool) -> int:
	if not _store.alive(t) or EntityId.is_wreck(t):
		return CommandResult.Code.REJECTED_DEAD
	var s: int = EntityId.slot(t)
	if _store.team[s] != _players.team[p]:
		return CommandResult.Code.REJECTED_NOT_OWNER
	if (_store.flags[s] & EntityStore.F_POSSESSABLE) == 0 or (_store.flags[s] & EntityStore.F_BUILDING) != 0:
		return CommandResult.Code.REJECTED_NOT_POSSESSABLE
	if _store.possessor[s] != EntityStore.NONE_U8 or claimed:
		return CommandResult.Code.REJECTED_ALREADY_POSSESSED
	if spectator(p):
		return CommandResult.Code.REJECTED_NO_RIGHTS
	if _store.pos[s].length() >= _uplink_r:
		return CommandResult.Code.REJECTED_UPLINK
	return CommandResult.Code.ACCEPTED


## C9 guard: `p` possesses a live entity; `t` is 0 (whatever it is) or that entity.
func check_release(p: int, t: int) -> int:
	var cur: int = _players.possessed[p]
	if cur == 0 or not _store.alive(cur):
		return CommandResult.Code.REJECTED_DEAD
	return CommandResult.Code.ACCEPTED if t == 0 or t == cur else CommandResult.Code.REJECTED_NOT_OWNER


## C8 / C10 guards (04 V-REQ: a failed request or hand-over is REJECTED_NO_RIGHTS).
func check_request(cmd: Command) -> int:
	var t: int = cmd.target
	if not _store.alive(t) or EntityId.is_wreck(t):
		return CommandResult.Code.REJECTED_DEAD
	var s: int = EntityId.slot(t)
	var p: int = cmd.player
	if _store.team[s] != _players.team[p]:
		return CommandResult.Code.REJECTED_NOT_OWNER
	var who: int = _store.possessor[s]
	if cmd.kind == Command.Kind.REQUEST_POSSESS:
		if not cmd.payload.is_empty():
			return CommandResult.Code.REJECTED_MALFORMED
		if who == EntityStore.NONE_U8 or who == p or spectator(p):
			return CommandResult.Code.REJECTED_NO_RIGHTS
		var other: int = request_from(t)
		return CommandResult.Code.ACCEPTED if other < 0 or other == p else CommandResult.Code.REJECTED_NO_RIGHTS
	if cmd.payload.size() != 1:
		return CommandResult.Code.REJECTED_MALFORMED
	if who != p:
		return CommandResult.Code.REJECTED_NOT_OWNER
	var q: int = cmd.payload.decode_u8(0)
	if not _players.is_active(q) or _players.connected[q] == 0 or _players.team[q] != _players.team[p]:
		return CommandResult.Code.REJECTED_NO_RIGHTS
	return CommandResult.Code.ACCEPTED if request_from(t) == q else CommandResult.Code.REJECTED_NO_RIGHTS


## True when `p` may not pilot: an open slot, or a player whose team lost its last Core (05 C6 "spectator").
func spectator(p: int) -> bool:
	var tm: int = _players.team[p]
	return _players.kind[p] == PlayerTable.KIND_OPEN or tm < 0 or tm >= PlayerTable.TEAMS or _team_out[tm] != 0


## Live hand-over requester of entity `id` (C8, expires per C17), or -1.
func request_from(id: int) -> int:
	if not _store.alive(id) or EntityId.slot(id) >= InputSlots.ENTITY_SLOTS:
		return -1
	var s: int = EntityId.slot(id)
	var q: int = _request_from[s]
	if q == EntityStore.NONE_U8 or _events.tick - _request_tick[s] > _request_ttl_s * _hz:
		return -1
	return q


## Ticks `p`'s pilot has been silent (05 C13); 0 right after a fresh input.
func silent_ticks(p: int) -> int:
	return maxi(_silent[p], 0)


func last_input_tick(p: int) -> int:
	return _last_input[p]


# --- step 1: commands ----------------------------------------------------------------------------------------------

## Applies POSSESS, RELEASE, REQUEST_POSSESS or HANDOVER that passed its guard in step 1.
func apply(cmd: Command) -> void:
	var p: int = cmd.player
	var s: int = EntityId.slot(cmd.target)
	match cmd.kind:
		Command.Kind.POSSESS:
			possess(p, s)
		Command.Kind.RELEASE:
			release_player(p, ReleaseReason.PLAYER)
		Command.Kind.REQUEST_POSSESS:
			_request(p, s)
		Command.Kind.HANDOVER:
			_handover(p, s, cmd.payload.decode_u8(0))


## 05 C6: `p` takes slot `s`; `p`'s previous possession is released first (C9) in the same tick; the standing
## queue stays as the saved order, the pending queue is cleared, the pilot starts with a neutral input.
func possess(p: int, s: int) -> void:
	release_player(p, ReleaseReason.PLAYER)
	var id: int = _store.id_of(s)
	_store.possessor[s] = p
	_store.control_state[s] = State.POSSESSED
	_store.overlay[s] = Overlay.NONE
	_store.dirty[s] |= EntityStore.DIRTY_CONTROL
	orders.queue.clear(s, OrderQueue.PENDING)
	_clear_request(s)
	_inputs.clear_entity(s)
	_inputs.clear_player(p)
	_players.possessed[p] = id
	_silent[p] = -1
	_fresh[p] = 0
	var _e: SimEvent = _events.emit(SimEvent.Kind.POSSESSED, id, p, _store.pos[s], 0.0, _store.team[s])


## Releases whatever `p` possesses with `reason` (C9 PLAYER, C11 CEILING, C12 DISCONNECT, C15 DEATH, C16 MATCH,
## C18 INVALID / ADMIN); a no-op when `p` possesses nothing. RELEASED (+ CEILING_RELEASE) first, then the resume.
func release_player(p: int, reason: int) -> void:
	var id: int = _players.possessed[p]
	if id == 0:
		return
	_players.possessed[p] = 0
	_inputs.clear_player(p)
	_silent[p] = 0
	if not _store.alive(id):
		return
	var s: int = EntityId.slot(id)
	_store.possessor[s] = EntityStore.NONE_U8
	_clear_request(s)
	_inputs.clear_entity(s)
	_store.dirty[s] |= EntityStore.DIRTY_CONTROL
	var tm: int = _store.team[s]
	var _e: SimEvent = _events.emit(SimEvent.Kind.RELEASED, id, p, _store.pos[s], 0.0, tm, reason)
	if reason == ReleaseReason.CEILING:
		var _c: SimEvent = _events.emit(SimEvent.Kind.CEILING_RELEASE, id, p, _store.pos[s], 0.0, tm)
	if reason == ReleaseReason.DEATH:
		_store.control_state[s] = State.AUTO
		_store.overlay[s] = Overlay.NONE
		return
	if reason == ReleaseReason.MATCH:
		orders.queue.clear_slot(s)
	else:
		orders.resume(s)
	_store.control_state[s] = State.ORDERED if orders.queue.count(s, OrderQueue.STANDING) > 0 else State.AUTO
	_store.overlay[s] = _release_overlay(s, reason)


## Step 1, after the commands: C12 for players whose transport is gone (`SimWorld.remove_player`), then queued C18
## ADMIN releases (`SimWorld.admin_release`).
func step_releases() -> void:
	for p: int in PlayerTable.SLOTS:
		if _players.possessed[p] != 0 and _players.connected[p] == 0:
			release_player(p, ReleaseReason.DISCONNECT)
		if _admin[p] != 0:
			_admin[p] = 0
			release_player(p, ReleaseReason.ADMIN)


## Queues an admin release of `p`'s possession (C18 ADMIN) for step 1 of the next tick (S1: no mutation here).
func admin_release(p: int) -> void:
	if p >= 0 and p < PlayerTable.SLOTS:
		_admin[p] = 1


## C16 at match end: every possession, reason MATCH.
func release_all(reason: int) -> void:
	for p: int in PlayerTable.SLOTS:
		release_player(p, reason)


## C16 when team `t` loses its last Core (Economy / scoring calls it): its pilots are released (MATCH) and its
## members become spectators (later POSSESS: REJECTED_NO_RIGHTS). A commander-only elimination never calls this.
func release_team(t: int) -> void:
	if t < 0 or t >= PlayerTable.TEAMS:
		return
	_team_out[t] = 1
	for p: int in PlayerTable.SLOTS:
		if _players.is_active(p) and _players.team[p] == t:
			release_player(p, ReleaseReason.MATCH)


## A PILOT_INPUT from `p` was stored into its slot (C14 / C13 bookkeeping for the next step 2).
func note_input(p: int) -> void:
	_fresh[p] = 1


# --- step 2: inputs (C13, C14) -------------------------------------------------------------------------------------

## Each possessing player's input becomes its entity's input. A silent tick reuses the last input decayed (A-44)
## for DECAY_TICKS ticks, then LINK_BRIDGE is set with one ALERT(LINK_WEAK) (C13); a fresh input clears it (C14).
func step_inputs(tick: int) -> void:
	for p: int in PlayerTable.SLOTS:
		var fresh: bool = _fresh[p] != 0
		_fresh[p] = 0
		var id: int = _players.possessed[p]
		if id == 0 or not _store.alive(id) or EntityId.slot(id) >= InputSlots.ENTITY_SLOTS:
			continue
		var s: int = EntityId.slot(id)
		if fresh:
			_silent[p] = 0
			_last_input[p] = tick
			if _store.overlay[s] == Overlay.LINK_BRIDGE:
				_store.overlay[s] = Overlay.NONE
				_store.dirty[s] |= EntityStore.DIRTY_CONTROL
		else:
			_silent[p] = mini(_silent[p] + 1, DECAY_TICKS + 2)
			if _silent[p] > 0:
				_decay(p)
			if _silent[p] == DECAY_TICKS + 1 and _store.overlay[s] != Overlay.LINK_BRIDGE:
				_store.overlay[s] = Overlay.LINK_BRIDGE
				_store.dirty[s] |= EntityStore.DIRTY_CONTROL
				var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.LINK_WEAK, id, _store.pos[s], 0.0,
					_store.team[s], p)
		_inputs.copy_player_to_entity(p, s)


# --- step 3: control check (C11, C17, C18) -------------------------------------------------------------------------

## Start of step 3, before the AI hook: ceiling release (C11), server-side invalidation (C18 INVALID: the entity
## changed team or is no longer possessable), then expiry of hand-over requests older than 10 s (C17).
func control_check() -> void:
	for p: int in PlayerTable.SLOTS:
		var id: int = _players.possessed[p]
		if id == 0 or not _store.alive(id):
			continue
		var s: int = EntityId.slot(id)
		if _store.pos[s].length() >= _ceiling_r:
			release_player(p, ReleaseReason.CEILING)
		elif _store.team[s] != _players.team[p] or (_store.flags[s] & EntityStore.F_POSSESSABLE) == 0:
			release_player(p, ReleaseReason.INVALID)
		elif _request_from[s] != EntityStore.NONE_U8 and request_from(id) < 0:
			_clear_request(s)


# --- step 9: death (C15) -------------------------------------------------------------------------------------------

## C15, before the DEATH event: a possessed entity is released (RELEASED reason DEATH), control fields cleared.
func on_death(s: int) -> void:
	var who: int = _store.possessor[s]
	if who != EntityStore.NONE_U8 and who < PlayerTable.SLOTS:
		release_player(who, ReleaseReason.DEATH)
	if s < InputSlots.ENTITY_SLOTS:
		_clear_request(s)
	_store.possessor[s] = EntityStore.NONE_U8
	_store.control_state[s] = State.AUTO
	_store.overlay[s] = Overlay.NONE


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE):
		return false
	return StateIO.sizes_ok(self, ["_request_from", "_request_tick"], InputSlots.ENTITY_SLOTS) 		and StateIO.sizes_ok(self, ["_last_input", "_silent", "_fresh", "_admin"], PlayerTable.SLOTS) 		and StateIO.sizes_ok(self, ["_team_out"], PlayerTable.TEAMS)


# --- private -------------------------------------------------------------------------------------------------------

# C8: `q` asks the pilot of `s` for the entity; POSSESS_REQUESTED + ALERT(HANDOVER_REQUEST) to the pilot.
func _request(q: int, s: int) -> void:
	var id: int = _store.id_of(s)
	var p: int = _store.possessor[s]
	_request_from[s] = q
	_request_tick[s] = _events.tick
	var tm: int = _store.team[s]
	var _e: SimEvent = _events.emit(SimEvent.Kind.POSSESS_REQUESTED, id, q, _store.pos[s], 0.0, tm, p)
	var _a: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.HANDOVER_REQUEST, id, _store.pos[s], 0.0, tm, p)


# C10: `p` hands `s` to `q`; q's own possession ends first; LINK_BRIDGE until q's first input; p's input is
# never replayed (both player slots and the entity slot start neutral).
func _handover(p: int, s: int, q: int) -> void:
	release_player(q, ReleaseReason.PLAYER)
	var id: int = _store.id_of(s)
	var tm: int = _store.team[s]
	_players.possessed[p] = 0
	_players.possessed[q] = id
	_inputs.clear_player(p)
	_inputs.clear_player(q)
	_inputs.clear_entity(s)
	_silent[p] = 0
	_silent[q] = DECAY_TICKS + 1
	_fresh[q] = 0
	_store.possessor[s] = q
	_store.overlay[s] = Overlay.LINK_BRIDGE
	_store.dirty[s] |= EntityStore.DIRTY_CONTROL
	_clear_request(s)
	var r: SimEvent = _events.emit(SimEvent.Kind.RELEASED, id, p, _store.pos[s], 0.0, tm, ReleaseReason.HANDOVER)
	var _x: bool = r.extra.push_back(q)
	var _h: SimEvent = _events.emit(SimEvent.Kind.HANDOVER, id, q, _store.pos[s], 0.0, tm, p)
	var _e: SimEvent = _events.emit(SimEvent.Kind.POSSESSED, id, q, _store.pos[s], 0.0, tm)


func _clear_request(s: int) -> void:
	if s < InputSlots.ENTITY_SLOTS:
		_request_from[s] = EntityStore.NONE_U8
		_request_tick[s] = 0


# A-44: stick axes halve, thrust held, BOOST / BRAKE held, FLIP / DOCK / RELEASE / FIRE1 / FIRE2 cleared.
func _decay(p: int) -> void:
	_inputs.p_pitch[p] = _inputs.p_pitch[p] * DECAY_FACTOR
	_inputs.p_yaw[p] = _inputs.p_yaw[p] * DECAY_FACTOR
	_inputs.p_roll[p] = _inputs.p_roll[p] * DECAY_FACTOR
	_inputs.p_buttons[p] = _inputs.p_buttons[p] & KEEP_BUTTONS


# 05 s2.4: SAFETY on every release, RECOVER_CEILING for C11; structures (towers, production) get no overlay.
func _release_overlay(s: int, reason: int) -> int:
	if _store.kind[s] == EntityStore.K_STRUCTURE:
		return Overlay.NONE
	return Overlay.RECOVER_CEILING if reason == ReleaseReason.CEILING else Overlay.SAFETY
