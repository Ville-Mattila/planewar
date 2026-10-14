class_name ControlOrders extends RefCounted
## The order side of 05 s2.3 (AI-02): ORDER intake into the standing or pending queue (C1, C2 with the s3.4
## OVERRIDDEN echo, C3, C7), head completion and failure (C4, C5; called by the systems that judge them, AI-15),
## and the resume rule of every release (C9: pending wins if any pending order is valid; each order is revalidated
## and an invalid one is dropped with ORDER_FAILED(INVALID_ON_RESUME)). Owned by `ControlMachine`; stateless
## beyond the `OrderQueue` it writes. ORDER_FAILED: a = entity, b = the order's issuer, extra = [OrderFail, by].

var queue: OrderQueue
var rules: OrderRules = null                          ## null: every order counts as valid on resume

var _store: EntityStore
var _players: PlayerTable
var _events: SimEvents
var _hz: int = 1
var _spec: OrderSpec = OrderSpec.new()


func _init(store: EntityStore, q: OrderQueue, players: PlayerTable, events: SimEvents, tick_hz: int) -> void:
	_store = store
	queue = q
	_players = players
	_events = events
	_hz = maxi(tick_hz, 1)


## C3 guard: room for `flags` on slot `s` (a QUEUE append needs count < limit in the queue it lands in).
func room(s: int, flags: int) -> bool:
	if (flags & OrderSpec.FLAG_QUEUE) == 0:
		return true
	var which: int = OrderQueue.PENDING if _store.control_state[s] == ControlMachine.State.POSSESSED else OrderQueue.STANDING
	return queue.count(s, which) < queue.limit


## C1 / C2 / C3 / C7 for one validated ORDER on `ids` (issuer and tick already in `spec`).
func order(spec: OrderSpec, ids: PackedInt32Array) -> void:
	for id: int in ids:
		var s: int = EntityId.slot(id)
		if _store.control_state[s] == ControlMachine.State.POSSESSED:
			if queue.push(s, OrderQueue.PENDING, spec) == OrderQueue.Push.OK:          # C7
				var _e: SimEvent = _events.emit(SimEvent.Kind.ALERT, AlertKind.Kind.PENDING_ORDER, id, _store.pos[s],
					0.0, _store.team[s], _store.possessor[s])
			continue
		var had: bool = queue.count(s, OrderQueue.STANDING) > 0
		var prev_issuer: int = queue.head_issuer(s)
		var prev_tick: int = queue.head_tick(s)
		if queue.push(s, OrderQueue.STANDING, spec) != OrderQueue.Push.OK:
			continue
		_store.control_state[s] = ControlMachine.State.ORDERED                       # C1 / C3
		_store.dirty[s] |= EntityStore.DIRTY_CONTROL
		if had and (spec.flags & (OrderSpec.FLAG_QUEUE | OrderSpec.FLAG_PREPEND)) == 0:
			_echo(id, prev_issuer, prev_tick, spec.issuer)                          # C2


## C4: the standing head of `s` is complete: pop, ORDER_DONE (value = the kind), ORDERED or AUTO.
func complete_head(s: int) -> bool:
	if not queue.read(s, OrderQueue.STANDING, 0, _spec):
		return false
	var _p: bool = queue.pop_head(s, OrderQueue.STANDING)
	var _e: SimEvent = _events.emit(SimEvent.Kind.ORDER_DONE, _store.id_of(s), _spec.issuer, _store.pos[s],
		float(_spec.kind), _store.team[s])
	_settle(s)
	return true


## C5: the standing head of `s` is impossible (`reason`: an OrderFail): pop with ORDER_FAILED(reason); the
## following heads are revalidated (dropped with INVALID_TARGET) until a valid one leads, else AUTO.
func fail_head(s: int, reason: int) -> bool:
	if not queue.read(s, OrderQueue.STANDING, 0, _spec):
		return false
	var _p: bool = queue.pop_head(s, OrderQueue.STANDING)
	_fail(s, _spec.issuer, reason, -1)
	while queue.read(s, OrderQueue.STANDING, 0, _spec) and not valid(s, _spec):
		var _q: bool = queue.pop_head(s, OrderQueue.STANDING)
		_fail(s, _spec.issuer, ControlMachine.OrderFail.INVALID_TARGET, -1)
	_settle(s)
	return true


## C9 resume: the pending queue replaces the saved (standing) one when at least one pending order is valid;
## then every remaining order is revalidated and invalid ones are dropped with ORDER_FAILED(INVALID_ON_RESUME).
func resume(s: int) -> void:
	var n: int = queue.count(s, OrderQueue.PENDING)
	var any: bool = false
	for i: int in n:
		if queue.read(s, OrderQueue.PENDING, i, _spec) and valid(s, _spec):
			any = true
			break
	if any:
		var _c: bool = queue.commit_pending(s)
	else:
		_drop_invalid(s, OrderQueue.PENDING)
	_drop_invalid(s, OrderQueue.STANDING)


## Order validity on resume / after a failure: the class still accepts it (OrderRules) and its target lives.
func valid(s: int, spec: OrderSpec) -> bool:
	if spec.target != 0 and not _store.alive(spec.target):
		return false
	return rules == null or rules.validate(spec, _store.def_id[s], false) == OrderRules.Verdict.OK


# s3.4 echo: the replaced head came from a different human less than ECHO_WINDOW_S ago.
func _echo(id: int, prev_issuer: int, prev_tick: int, by: int) -> void:
	if prev_issuer < 0 or prev_issuer >= PlayerTable.SLOTS or prev_issuer == by:
		return
	if _players.kind[prev_issuer] != PlayerTable.KIND_HUMAN:
		return
	if _events.tick - prev_tick >= ControlMachine.ECHO_WINDOW_S * _hz:
		return
	_fail(EntityId.slot(id), prev_issuer, ControlMachine.OrderFail.OVERRIDDEN, by)


func _drop_invalid(s: int, which: int) -> void:
	var i: int = 0
	while queue.read(s, which, i, _spec):
		if valid(s, _spec):
			i += 1
			continue
		var _r: bool = queue.remove_at(s, which, i)
		_fail(s, _spec.issuer, ControlMachine.OrderFail.INVALID_ON_RESUME, -1)


func _fail(s: int, issuer: int, reason: int, by: int) -> void:
	var e: SimEvent = _events.emit(SimEvent.Kind.ORDER_FAILED, _store.id_of(s), issuer, _store.pos[s], 0.0,
		_store.team[s], reason)
	if by >= 0:
		var _a: bool = e.extra.push_back(by)


# Control state after a standing pop; a POSSESSED entity stays POSSESSED (its queue is the saved order).
func _settle(s: int) -> void:
	if _store.control_state[s] == ControlMachine.State.POSSESSED:
		return
	_store.control_state[s] = ControlMachine.State.ORDERED if queue.count(s, OrderQueue.STANDING) > 0 else ControlMachine.State.AUTO
	_store.dirty[s] |= EntityStore.DIRTY_CONTROL
