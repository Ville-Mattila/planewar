class_name AiDriver extends SimAiHook
## The AI's tick-order step 3 (05 s4.3, R0 B.5): schedules class-batched autopilot thinks and per-tick acts, plus the
## staggered Commander bot thinks, and the overlays SAFETY / RECOVER_CEILING (AI-08, `Overlays`): a per-tick check of
## the possessed entities sees the POSSESSED -> released edge, the overlay runs after the class's act (its input
## wins) and the entity does not think until it ends; then it is woken. Think: entity thinks when `(tick + stagger) % P == 0`; `stagger` is a per-entity
## round-robin number, so every phase holds an equal share. Event wake: `wake` forces a think on the next `on_tick`, at most
## once per `WAKE_MIN_GAP` ticks per entity. Act: every tick over the whole class batch. No per-entity objects, no
## allocation per tick (budget: 03 s4.2 "AI think + act", 6.0 ms; this class is the scheduling share of it).
## Periods are constructor arguments whose defaults mirror `autopilots.json` (10, cut-ladder rung 1: 15) and
## `bot_profiles.json` (90/30/30/30); the session reads the defs and passes them (A-43 pattern).

const MAX_CLASSES: int = 16
const WAKE_MIN_GAP: int = 5
const BOT_STAGGER: int = 4              ## 05 s7: bot k thinks when (tick + 4k) % P == 0
const FORMAT: int = 1

var state: AiState = AiState.new()

var _sink: CommandSink = CommandSink.new()
var _rng: Rng = null
var _base_period: int = 10
var _cut_period: int = 15
var _bot_periods: PackedInt32Array = PackedInt32Array([90, 30, 30, 30])
var _offline: bool = false
var _rung1: bool = false
var _reg_counter: int = 0
var _batches: Array[AiBatch] = []
var _brains: Array[AiBrain] = []
var _bot_slot: PackedInt32Array = PackedInt32Array()
var _bot_tier: PackedInt32Array = PackedInt32Array()
var _bot_brain: AiBrain = null
var _class_table: PackedByteArray = PackedByteArray()   ## def id -> class (AiClassTable); empty: SPAWN registers nothing
var _dead: PackedInt32Array = PackedInt32Array()
var _stats_thinks: int = 0
var _stats_bot_thinks: int = 0
var _stats_us: int = 0
var _stats_ticks: int = 0
var _stats_overlay_ticks: int = 0
var _ov_params: Array[OverlayParams] = []
var _terrain: Terrain = Terrain.new()   ## the flat datum until the session passes the map's terrain
var _ov_ids: PackedInt32Array = PackedInt32Array()
var _probe: ProbeResult = ProbeResult.new()
var _ov_in: PilotInput = PilotInput.new()


func _init(rng: Rng = null, think_period_ticks: int = 10, cut_period_ticks: int = 15,
		bot_periods: PackedInt32Array = PackedInt32Array([90, 30, 30, 30])) -> void:
	_rng = (rng if rng != null else Rng.new(0)).fork(&"ai")
	_base_period = maxi(think_period_ticks, 1)
	_cut_period = maxi(cut_period_ticks, 1)
	_bot_periods = bot_periods
	for c: int in MAX_CLASSES:
		_batches.append(AiBatch.new())
		_brains.append(null)
		_ov_params.append(null)


## Autopilot think period P in ticks: the cut period offline (Lite) or under cut-ladder rung 1, else the default.
func think_period() -> int:
	return _cut_period if (_offline or _rung1) else _base_period


## Offline web/mobile (05 s10, R0 C1-01): every class thinks every `cut_period_ticks` (15).
func set_offline_profile(lite: bool) -> void:
	_offline = lite


## 03 s4.3 cut-ladder rung 1 (default `sim_budget_profile` [1, 2]): autopilot think every `cut_period_ticks`.
func set_cut_rung1(on: bool) -> void:
	_rung1 = on


## The deterministic AI sub-stream, `Rng.fork(&"ai")`.
func ai_rng() -> Rng:
	return _rng


## Brain for class `cls` (null = none). Also receives `think_bot` for bots when set with `bot = true`.
func set_brain(cls: int, brain: AiBrain, bot: bool = false) -> void:
	_brains[cls] = brain
	if brain != null:
		brain.bind_rng(_rng)
	if bot:
		_bot_brain = brain


## Overlay parameters of class `cls` (null: that class runs no overlays). The session builds them with
## `OverlayParams.for_ship` / `for_ground` from the class's autopilot def.
func set_overlay_params(cls: int, p: OverlayParams) -> void:
	_ov_params[cls] = p


## The terrain the overlays probe: the session passes `SimWorld.terrain()` after `load_map` (read-only, public map
## data, not a vision cheat). Default: the flat datum.
func set_terrain(t: Terrain) -> void:
	_terrain = t


## Registers entity `id` in class batch `cls`; false if invalid or already registered (slot taken).
func register(id: int, cls: int) -> bool:
	var s: int = EntityId.slot(id)
	if cls < 0 or cls >= MAX_CLASSES or s <= 0 or s >= state.capacity or state.cls[s] != AiState.NO_CLASS:
		return false
	var _ok: bool = _batches[cls].add(id)
	state.cls[s] = cls
	state.eid[s] = id
	state.stagger[s] = _reg_counter
	_reg_counter = (_reg_counter + 1) & 0x3FFFFFFF
	return true


## Drops entity `id` and resets its AI state; false if it was not registered under that id.
func unregister(id: int) -> bool:
	var s: int = EntityId.slot(id)
	if s <= 0 or s >= state.capacity or state.cls[s] == AiState.NO_CLASS or state.eid[s] != id:
		return false
	var _ok: bool = _batches[state.cls[s]].remove(id)
	state.clear_slot(s)
	return true


## Event wake: forces a think at the next `on_tick`. Rate-limited to one accepted wake per `WAKE_MIN_GAP` ticks per
## entity; returns whether it was accepted.
func wake(id: int, tick: int) -> bool:
	var s: int = EntityId.slot(id)
	if s <= 0 or s >= state.capacity or state.cls[s] == AiState.NO_CLASS or state.eid[s] != id:
		return false
	if tick - state.last_wake[s] < WAKE_MIN_GAP:
		return false
	state.last_wake[s] = tick
	state.wake_pending[s] = 1
	return true


## The def -> class table SPAWN registration reads (`AiClassTable.from_content`); the session sets it after `load_map`.
## Empty (the default): SPAWN registers nothing, rigs call `register` themselves.
func set_class_table(table: PackedByteArray) -> void:
	_class_table = table


## Feeds one drained sim event: SPAWN of an AI-driven def registers it in that def's class (A-71, AI-37); HIT on an AI
## entity wakes it; DEATH unregisters the dead and wakes whoever targeted it;
## POSSESSED marks the entity for the per-tick release check (AI-08) and drops a running overlay.
func on_event(ev: SimEvent) -> void:
	if ev.kind == SimEvent.Kind.SPAWN:
		var c: int = AiClassTable.class_of(_class_table, ev.b)
		if c != AiClassTable.NONE:
			var _r: bool = register(ev.a, c)
	elif ev.kind == SimEvent.Kind.HIT:
		var _w: bool = wake(ev.a, ev.tick)
	elif ev.kind == SimEvent.Kind.POSSESSED:
		var s: int = EntityId.slot(ev.a)
		if s > 0 and s < state.capacity and state.cls[s] != AiState.NO_CLASS and state.eid[s] == ev.a:
			Overlays.clear(state, s)
			state.ov_flags[s] = state.ov_flags[s] | AiState.OV_POSSESSED
	elif ev.kind == SimEvent.Kind.DEATH:
		var _u: bool = unregister(ev.a)
		for b: AiBatch in _batches:
			for id: int in b.ids:
				if state.target[EntityId.slot(id)] == ev.a:
					var _w2: bool = wake(id, ev.tick)


## Schedules Commander bot (or Adjutant) `slot` of difficulty tier 0..3 (easy, normal, hard, brutal).
func schedule_bot(slot: int, tier: int) -> void:
	var i: int = _bot_slot.find(slot)
	if i >= 0:
		_bot_tier[i] = tier
		return
	var _a: bool = _bot_slot.append(slot)
	var _b: bool = _bot_tier.append(tier)


func unschedule_bot(slot: int) -> void:
	var i: int = _bot_slot.find(slot)
	if i >= 0:
		_bot_slot.remove_at(i)
		_bot_tier.remove_at(i)


## Whether bot `slot` of `tier` thinks on `tick`: (tick + 4 * slot) % P == 0, P = 90 / 30 / 30 / 30.
func bot_due(slot: int, tier: int, tick: int) -> bool:
	return (tick + BOT_STAGGER * slot) % _bot_periods[tier] == 0


func on_tick(tick: int, view: SimView, sink: CommandSinkBase) -> void:
	var t0: int = Time.get_ticks_usec()
	_sink.bind(sink)
	_sink.reset_counters()
	var p: int = think_period()
	for c: int in MAX_CLASSES:
		var brain: AiBrain = _brains[c]
		var b: AiBatch = _batches[c]
		var op: OverlayParams = _ov_params[c]
		if b.ids.is_empty() or (brain == null and op == null):
			continue
		var nov: int = _scan_overlays(b, view, tick, p, op) if op != null else 0
		if brain != null:
			var n: int = _collect_due(b, tick, p, view)
			if n > 0:
				brain.think_batch(b.due, n, view, state, _sink, tick)
			brain.act_batch(b.ids, view, state, _sink)
		for i: int in nov:
			if Overlays.run(_ov_ids[i], view, state, op, _terrain, _sink, tick, _probe, _ov_in):
				_sink.end_overlay(_ov_ids[i])
				var _w: bool = wake(_ov_ids[i], tick)
		_stats_overlay_ticks += nov
	_bots(tick, view)
	_stats_us += Time.get_ticks_usec() - t0
	_stats_ticks += 1


## Fills `b.due` with the ids that think this tick; clears wake flags; drops dead ones. Returns the count.
func _collect_due(b: AiBatch, tick: int, p: int, view: SimView) -> int:
	var n: int = 0
	var dead: int = 0
	for id: int in b.ids:
		var s: int = EntityId.slot(id)
		if (tick + state.stagger[s]) % p != 0 and state.wake_pending[s] == 0:
			continue
		state.wake_pending[s] = 0
		if not view.alive(id):
			if _dead.size() <= dead:
				var _e: int = _dead.resize(dead + 1)
			_dead[dead] = id
			dead += 1
		elif view.control_state(id) != ControlMachine.State.POSSESSED and state.overlay[s] == Overlays.NONE:
			b.due[n] = id
			n += 1
	for i: int in dead:
		var _u: bool = unregister(_dead[i])
	_stats_thinks += n
	return n


## AI-08 release edge. The control state is read every tick for entities marked possessed (OV_POSSESSED) or in an
## overlay, and on the entity's think phase `(tick + stagger) % p == 0` otherwise (1/p of the roster per tick), so a
## possession is noticed within p ticks or at once through `on_event(POSSESSED)`. POSSESSED marks the entity (and
## drops a running overlay); the first tick a marked live entity is not POSSESSED starts the overlay (no latency).
## Fills `_ov_ids` with the entities in an overlay, in batch (slot) order; returns the count.
func _scan_overlays(b: AiBatch, view: SimView, tick: int, p: int, op: OverlayParams) -> int:
	var n: int = 0
	var flags: PackedByteArray = state.ov_flags
	var ov: PackedByteArray = state.overlay
	var stag: PackedInt32Array = state.stagger
	for id: int in b.ids:
		var s: int = EntityId.slot(id)
		var f: int = flags[s]
		if f == 0 and ov[s] == 0 and (tick + stag[s]) % p != 0:
			continue
		if view.control_state(id) == ControlMachine.State.POSSESSED:
			if state.overlay[s] != Overlays.NONE:
				Overlays.clear(state, s)
			state.ov_flags[s] = state.ov_flags[s] | AiState.OV_POSSESSED
			continue
		if (f & AiState.OV_POSSESSED) != 0:
			state.ov_flags[s] = f & ~AiState.OV_POSSESSED
			if view.alive(id):
				Overlays.enter(id, view, state, op, tick)
		if state.overlay[s] != Overlays.NONE and view.alive(id):
			if _ov_ids.size() <= n:
				var _e: int = _ov_ids.resize(n + 1)
			_ov_ids[n] = id
			n += 1
	return n


func _bots(tick: int, view: SimView) -> void:
	if _bot_brain == null:
		return
	for i: int in _bot_slot.size():
		if bot_due(_bot_slot[i], _bot_tier[i], tick):
			_bot_brain.think_bot(_bot_slot[i], _bot_tier[i], tick, view, _sink)
			_stats_bot_thinks += 1


## Counters for perf tests: autopilot thinks, bot thinks, ticks, total and mean µs per tick, last-tick sink counters.
func stats() -> Dictionary:
	return {"thinks": _stats_thinks, "bot_thinks": _stats_bot_thinks, "ticks": _stats_ticks, "us": _stats_us,
		"us_per_tick": float(_stats_us) / float(maxi(_stats_ticks, 1)), "submits": _sink.submits, "drives": _sink.drives,
		"registered": state.registered_count(), "overlay_ticks": _stats_overlay_ticks}


func reset_stats() -> void:
	_stats_thinks = 0
	_stats_bot_thinks = 0
	_stats_us = 0
	_stats_ticks = 0
	_stats_overlay_ticks = 0


## S4 bytes: FORMAT, flags, reg counter, bots, rng state, then the AiState blob (length-prefixed).
func serialize() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(FORMAT)
	b.put_u8((1 if _offline else 0) | (2 if _rung1 else 0))
	b.put_32(_reg_counter)
	b.put_u32(_bot_slot.size())
	for i: int in _bot_slot.size():
		b.put_32(_bot_slot[i])
		b.put_u8(_bot_tier[i])
	var _e1: Error = b.put_data(_rng.state())
	var st: PackedByteArray = state.serialize()
	b.put_u32(st.size())
	var _e2: Error = b.put_data(st)
	return b.data_array


## Restores `serialize` bytes (config such as periods and brains stays as constructed). Empty or bad bytes reset to empty.
func deserialize(bytes: PackedByteArray) -> void:
	for b: AiBatch in _batches:
		b.ids.clear()
		b.due.clear()
	_bot_slot.clear()
	_bot_tier.clear()
	var _cleared: bool = state.deserialize(PackedByteArray())
	if bytes.size() < 6:
		return
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	if b.get_u8() != FORMAT:
		return
	var flags: int = b.get_u8()
	_offline = (flags & 1) != 0
	_rung1 = (flags & 2) != 0
	_reg_counter = b.get_32()
	var nb: int = b.get_u32()
	for i: int in nb:
		var _a: bool = _bot_slot.append(b.get_32())
		var _b: bool = _bot_tier.append(b.get_u8())
	var pos: int = b.get_position()
	if pos + Rng.STATE_BYTES + 4 > bytes.size():
		return
	_rng = Rng.from_state(bytes.slice(pos, pos + Rng.STATE_BYTES))
	for br: AiBrain in _brains:
		if br != null:
			br.bind_rng(_rng)
	b.seek(pos + Rng.STATE_BYTES)
	var len_st: int = b.get_u32()
	pos = b.get_position()
	if not state.deserialize(bytes.slice(pos, pos + len_st)):
		return
	for s: int in state.capacity:
		if state.cls[s] != AiState.NO_CLASS:
			var _ok: bool = _batches[state.cls[s]].add(state.eid[s])
