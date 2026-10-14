class_name CommandValidator extends RefCounted
## S10 / S12 for `SimWorld.apply_command` (03 s3.5; 04's protocol-level class is `ProtocolValidator`). `validate`
## runs the rate limit (04 s11.3 token bucket per player, C2-27) and then `check`, the state rules: ownership,
## rights, caps, cost, phase, shape; placement is `Build.can_place`'s (TA-19). `check` is pure and runs again when
## step 1 applies the command, so a command made invalid by an earlier one in the same tick has no effect.
## The bucket counts every command that passes the rate check, accepted or not; PILOT_INPUT is exempt (04 0x04).

## 04 s11.3 "COMMAND 10/s sustained, burst 30" (the one command-rate rule): documented defaults of `rules.json`
## `command_rate_per_s` / `command_burst` (R0 B.11 A-51), which `_init` reads.
const RATE_PER_S: int = 10
const BURST: int = 30
## sim/MODULE.md "Data owned": pending command queue <= 256 per tick; overflow rejects with REJECTED_RATE.
const QUEUE_MAX: int = 256
const _STATE: PackedStringArray = ["_tokens", "_last", "_claimed"]

var order_rules: OrderRules = null                    ## null: every ORDER is REJECTED_INVALID_ORDER
var build: Build = null                               ## set by EconomyHub: BUILD runs `can_place`, PRODUCE the early share lock
var production: Production = null                     ## set by EconomyHub: queue room, item owners (S12, S13)
var economy: Economy = null                           ## set by EconomyHub (reserved for pool reads)
var last_reject: int = 0                              ## `Build.Reject` of the last `check` that returned REJECTED_PLACEMENT

var _store: EntityStore
var _players: PlayerTable
var _defs: WorldDefs
var _rules: MatchRules
var _rate: int = RATE_PER_S
var _burst: int = BURST
var _control: ControlMachine
var _tokens: PackedInt32Array = PackedInt32Array()   ## per player, in 1 / tick_hz commands
var _last: PackedInt32Array = PackedInt32Array()     ## tick of the last refill
var _claimed: PackedInt32Array = PackedInt32Array()  ## POSSESS targets accepted since the last step 1
var _spec: OrderSpec = OrderSpec.new()
var _ids: PackedInt32Array = PackedInt32Array()


func _init(store: EntityStore, players: PlayerTable, defs: WorldDefs, rules: MatchRules, control: ControlMachine) -> void:
	_store = store
	_players = players
	_defs = defs
	_rules = rules
	_control = control
	if defs.rules != null:
		_rate = defs.rules.command_rate_per_s
		_burst = defs.rules.command_burst
	var e: int = _tokens.resize(PlayerTable.SLOTS) | _last.resize(PlayerTable.SLOTS)
	assert(e == OK)
	_tokens.fill(_burst * rules.tick_hz)
	_last.fill(0)


## Full S10 verdict for `cmd` arriving at `tick` with `queued` commands already pending; charges the bucket.
func validate(cmd: Command, tick: int, ended: bool, queued: int) -> CommandResult:
	var r: CommandResult = CommandResult.new()
	var p: int = cmd.player
	if p < 0 or p >= PlayerTable.SLOTS or not _players.is_active(p):
		r.code = CommandResult.Code.REJECTED_MALFORMED
		return r
	if cmd.kind != Command.Kind.PILOT_INPUT:
		if queued >= QUEUE_MAX or not _take_token(p, tick):
			r.code = CommandResult.Code.REJECTED_RATE
			return r
	if ended:
		r.code = CommandResult.Code.REJECTED_PHASE
		return r
	r.code = check(cmd) as CommandResult.Code
	if r.code == CommandResult.Code.REJECTED_PLACEMENT:
		r.reject = last_reject
	if r.code == CommandResult.Code.ACCEPTED and cmd.kind == Command.Kind.POSSESS:
		var _a: bool = _claimed.push_back(cmd.target)
	return r


## Step 1 of every tick, before applying: POSSESS claims of the previous intake no longer hold.
func begin_tick() -> void:
	var _r: int = _claimed.resize(0)


## The state rules of S10 / S12 for `cmd` (no rate, no phase); a CommandResult.Code.
func check(cmd: Command) -> int:
	var p: int = cmd.player
	if cmd.kind >= Command.Kind.DEBUG_SPAWN and not _rules.debug_commands:
		return CommandResult.Code.REJECTED_NO_RIGHTS
	match cmd.kind:
		Command.Kind.ORDER:
			return _check_order(cmd)
		Command.Kind.BUILD:
			return _check_build(cmd)
		Command.Kind.PRODUCE:
			return _check_produce(cmd)
		Command.Kind.CANCEL_BUILD, Command.Kind.CANCEL_PRODUCE:
			return _check_cancel(cmd)
		Command.Kind.SET_RALLY, Command.Kind.TOGGLE_AUTO_REPLENISH:
			return _check_own_structure(cmd)
		Command.Kind.POSSESS:
			return _control.check_possess(p, cmd.target, _claimed.has(cmd.target))
		Command.Kind.RELEASE:
			return _control.check_release(p, cmd.target)
		Command.Kind.REQUEST_POSSESS, Command.Kind.HANDOVER:
			return _control.check_request(cmd)
		Command.Kind.PILOT_INPUT:
			return CommandResult.Code.ACCEPTED if cmd.payload.size() == CommandPayload.PILOT_BYTES else CommandResult.Code.REJECTED_MALFORMED
		Command.Kind.SURRENDER:
			return CommandResult.Code.ACCEPTED if cmd.target == 0 else CommandResult.Code.REJECTED_MALFORMED
		Command.Kind.SET_ADJUTANT:
			return _check_adjutant(cmd)
		Command.Kind.DEBUG_SPAWN:
			return _check_debug_spawn(cmd)
		Command.Kind.DEBUG_SET:
			if not _store.alive(cmd.target):
				return CommandResult.Code.REJECTED_DEAD
			var f: int = CommandPayload.u8_at(cmd, 0)
			var ok: bool = cmd.payload.size() == CommandPayload.DEBUG_SET_BYTES and f >= 0 and f <= CommandPayload.SET_KILL
			return CommandResult.Code.ACCEPTED if ok else CommandResult.Code.REJECTED_MALFORMED
	return CommandResult.Code.REJECTED_MALFORMED


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and _tokens.size() == PlayerTable.SLOTS and _last.size() == PlayerTable.SLOTS


func _take_token(p: int, tick: int) -> bool:
	var cap: int = _burst * _rules.tick_hz
	var t: int = mini(cap, _tokens[p] + maxi(tick - _last[p], 0) * _rate)
	_last[p] = tick
	if t < _rules.tick_hz:
		_tokens[p] = t
		return false
	_tokens[p] = t - _rules.tick_hz
	return true


func _commander(p: int) -> bool:
	return _players.eliminated[p] == 0


func _check_order(cmd: Command) -> int:
	if not CommandPayload.read_order(cmd, _spec, _ids):
		return CommandResult.Code.REJECTED_MALFORMED
	if not _commander(cmd.player):
		return CommandResult.Code.REJECTED_NO_RIGHTS
	if order_rules == null:
		return CommandResult.Code.REJECTED_INVALID_ORDER
	var tm: int = _players.team[cmd.player]
	for id: int in _ids:
		if not _store.alive(id) or EntityId.is_wreck(id):
			return CommandResult.Code.REJECTED_DEAD
		var s: int = EntityId.slot(id)
		if _store.team[s] != tm:
			return CommandResult.Code.REJECTED_NOT_OWNER
		var v: OrderRules.Verdict = order_rules.validate(_spec, _store.def_id[s], true)
		if v != OrderRules.Verdict.OK:
			return CommandResult.Code.REJECTED_MALFORMED if OrderRules.malformed(v) else CommandResult.Code.REJECTED_INVALID_ORDER
		if not _control.orders.room(s, _spec.flags):
			return CommandResult.Code.REJECTED_CAP                               # 05 C3 guard: queue < 8
	if _spec.target != 0 and not _store.alive(_spec.target):
		return CommandResult.Code.REJECTED_INVALID_ORDER
	return CommandResult.Code.ACCEPTED


func _check_build(cmd: Command) -> int:
	var d: int = CommandPayload.u16_at(cmd, 0)
	var rot: int = CommandPayload.u8_at(cmd, 6)
	if cmd.payload.size() != 7 or _defs.entity_kind(d) != EntityStore.K_STRUCTURE or rot > 3:
		return CommandResult.Code.REJECTED_MALFORMED
	if not _commander(cmd.player):
		return CommandResult.Code.REJECTED_NO_RIGHTS
	if TeamStats.count_owned(_store, cmd.player, _store.structures) >= _rules.caps.structures:
		return CommandResult.Code.REJECTED_CAP
	var a: int = _afford(cmd.player, d, 1)
	if a != CommandResult.Code.ACCEPTED or build == null:
		return a
	last_reject = build.can_place(cmd.player, d, CommandPayload.u32_at(cmd, 2), rot)
	return CommandResult.Code.ACCEPTED if last_reject == Build.Reject.OK else CommandResult.Code.REJECTED_PLACEMENT


func _check_produce(cmd: Command) -> int:
	var d: int = CommandPayload.u16_at(cmd, 0)
	var n: int = CommandPayload.u8_at(cmd, 2)
	var k: int = _defs.entity_kind(d)
	var qmax: int = _defs.economy.queue_max if _defs.economy != null else 0
	if cmd.payload.size() != 3 or (k != EntityStore.K_SHIP and k != EntityStore.K_GROUND) or n < 1 or n > qmax:
		return CommandResult.Code.REJECTED_MALFORMED
	var own: int = _check_team_factory(cmd, d)
	if own != CommandResult.Code.ACCEPTED:
		return own
	if not _commander(cmd.player):
		return CommandResult.Code.REJECTED_NO_RIGHTS
	if not TeamStats.tech_available(_store, _defs, _players.team[cmd.player], d):
		return CommandResult.Code.REJECTED_NO_RIGHTS
	var units: int = TeamStats.count_owned(_store, cmd.player, _store.ships) + TeamStats.count_owned(_store, cmd.player, _store.ground)
	if units + n > _rules.caps.units or (production != null and production.length(EntityId.slot(cmd.target)) + n > qmax):
		return CommandResult.Code.REJECTED_CAP   # S13: queue_max items per queue
	var a: int = _afford(cmd.player, d, n)
	if a == CommandResult.Code.ACCEPTED and build != null and build.lock_blocks(cmd.player, _defs.cost(cmd.player, d).x * n):
		return CommandResult.Code.REJECTED_LOCKED
	return a


## S12 (R0 C3-08): the player who queued / placed the item, or a teammate when that player is disconnected,
## eliminated or a bot. A queue item belongs to the player who queued it (`Production.queuer`), a site to its placer.
func _check_cancel(cmd: Command) -> int:
	var t: int = cmd.target
	if not _store.alive(t) or EntityId.is_wreck(t):
		return CommandResult.Code.REJECTED_DEAD
	var s: int = EntityId.slot(t)
	if _store.kind[s] != EntityStore.K_STRUCTURE:
		return CommandResult.Code.REJECTED_MALFORMED
	if cmd.kind == Command.Kind.CANCEL_BUILD and (_store.flags[s] & EntityStore.F_BUILDING) == 0:
		return CommandResult.Code.REJECTED_MALFORMED
	if cmd.kind == Command.Kind.CANCEL_PRODUCE and cmd.payload.size() != 1:
		return CommandResult.Code.REJECTED_MALFORMED
	var o: int = _store.owner[s]
	if cmd.kind == Command.Kind.CANCEL_PRODUCE and production != null:
		o = production.queuer(s, CommandPayload.u8_at(cmd, 0))
		if o < 0:
			return CommandResult.Code.REJECTED_DEAD   # no such queue item
	if o == cmd.player:
		return CommandResult.Code.ACCEPTED
	if _store.team[s] == _players.team[cmd.player] and _players.cancel_delegable(o):
		return CommandResult.Code.ACCEPTED
	return CommandResult.Code.REJECTED_NOT_OWNER


## PRODUCE: any teammate may queue at a finished friendly factory that makes `unit` (02 s6.4: queues are team-shared).
func _check_team_factory(cmd: Command, unit: int) -> int:
	var t: int = cmd.target
	if not _store.alive(t) or EntityId.is_wreck(t):
		return CommandResult.Code.REJECTED_DEAD
	var s: int = EntityId.slot(t)
	if _store.kind[s] != EntityStore.K_STRUCTURE:
		return CommandResult.Code.REJECTED_MALFORMED
	if _store.team[s] != _players.team[cmd.player]:
		return CommandResult.Code.REJECTED_NOT_OWNER
	if (_store.flags[s] & EntityStore.F_BUILDING) != 0 or (production != null and not production.can_make(_store.def_id[s], unit)):
		return CommandResult.Code.REJECTED_MALFORMED
	return CommandResult.Code.ACCEPTED


func _check_own_structure(cmd: Command) -> int:
	var t: int = cmd.target
	if not _store.alive(t) or EntityId.is_wreck(t):
		return CommandResult.Code.REJECTED_DEAD
	var s: int = EntityId.slot(t)
	if _store.kind[s] != EntityStore.K_STRUCTURE:
		return CommandResult.Code.REJECTED_MALFORMED
	return CommandResult.Code.ACCEPTED if _store.owner[s] == cmd.player else CommandResult.Code.REJECTED_NOT_OWNER


func _check_adjutant(cmd: Command) -> int:
	var prof: int = CommandPayload.u8_at(cmd, 1)
	if cmd.payload.size() != 3 or prof > 2:
		return CommandResult.Code.REJECTED_MALFORMED
	var enabled: bool = cmd.payload[0] != 0
	if enabled and (_rules.ranked or _rules.adjutant_allowed == &"off"):
		return CommandResult.Code.REJECTED_NO_RIGHTS
	if enabled and _rules.adjutant_allowed == &"economy" and prof != 2:
		return CommandResult.Code.REJECTED_NO_RIGHTS
	return CommandResult.Code.ACCEPTED


func _check_debug_spawn(cmd: Command) -> int:
	var d: int = CommandPayload.u16_at(cmd, 0)
	var o: int = CommandPayload.u8_at(cmd, 2)
	if cmd.payload.size() != CommandPayload.DEBUG_SPAWN_BYTES or _defs.entity_kind(d) < 0:
		return CommandResult.Code.REJECTED_MALFORMED
	return CommandResult.Code.ACCEPTED if o == EntityStore.NONE_U8 or o < PlayerTable.SLOTS else CommandResult.Code.REJECTED_MALFORMED


func _afford(p: int, d: int, n: int) -> int:
	var c: Vector2i = _defs.cost(p, d) * n
	var t: int = _players.team[p]
	if t < 0 or t >= PlayerTable.TEAMS or c.x > _players.team_ore[t] or c.y > _players.team_ice[t]:
		return CommandResult.Code.REJECTED_COST
	return CommandResult.Code.ACCEPTED
