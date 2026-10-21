extends GdUnitTestSuite
## TA-65: S4 byte-exact mid-burst. Three Darts fire 0.6 s bursts with 0.3 s pauses (the Dart brain's cadence, 05
## s4.3) at three Lancers, driven the way the AI drives them (`SimAiHook.on_tick` -> `sink.drive`, FIRE1) or with
## one of them possessed (PILOT_INPUT commands, step 2); saved at 12 points with slugs in flight over 3 seeds,
## restored with a fresh hook, continued 600 ticks: identical bytes on reload, identical step-3 queries
## (`ids_near`, `projectiles_near`) right after the reload, identical events every tick, identical raw bytes every
## CHECK_EVERY ticks. Root cause guarded: slugs spawned in step 9 are not in the step-7 index and keep
## `hash_cell` 0 until the next step 7; a load that rebuilt the index put them in (and wrote their cells), so the
## reloaded bytes and the AI's next-tick projectile queries differed from the original's.

const SEEDS: PackedInt32Array = [41, 42, 43]
const SAVES: int = 12
const FIRST_SAVE: int = 31          ## the first burst opens on tick 2 of the shooters' life
const SAVE_STEP: int = 7            ## coprime with the 27-tick cycle: every phase of a burst gets a save point
const CONTINUE: int = 600
const CHECK_EVERY: int = 25
const CYCLE: int = 27               ## 0.9 s at 30 Hz: 18 ticks on, 9 off
const ON: int = 18
const PHASES: PackedInt32Array = [0, 5, 11]
const ALT: float = 1400.0           ## everyone falls together at `gravity`; the ground ends the fight inside the run
const QUERY_R: float = 300.0        ## inside ring 2 (~188 m) and beyond it: both ids_near paths
const MIN_STALE: int = 6          ## save points that must land on a tick that fired (the pre-fix failure)


## The AI's way of firing: every tick, FIRE1 on the burst cadence through `sink.drive` (a possessed Dart refuses).
class BurstHook extends SimAiHook:
	var ids: PackedInt32Array = PackedInt32Array()
	var _in: PilotInput = PilotInput.new()

	func on_tick(t: int, _v: SimView, sink: CommandSinkBase) -> void:
		for k: int in ids.size():
			_in.buttons = BurstHook.buttons_at(t, k)
			var _ok: bool = sink.drive(ids[k], _in)

	static func buttons_at(t: int, k: int) -> int:
		return PilotInput.FIRE1 if posmod(t + PHASES[k], CYCLE) < ON else 0

	func serialize() -> PackedByteArray:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.put_var(ids)
		return b.data_array

	func deserialize(bytes: PackedByteArray) -> void:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.data_array = bytes
		ids = b.get_var()


class Ref:
	var saves: Array[PackedByteArray] = []
	var save_ticks: PackedInt32Array = PackedInt32Array()
	var queries: Array[PackedInt32Array] = []
	var events: Dictionary = {}     ## tick -> event bytes of that tick
	var raw: Dictionary = {}        ## checkpoint tick -> SimSerialize.write_raw
	var stale_saves: int = 0        ## save points with a slug whose hash_cell is not its cell (fired in step 9)
	var min_live: int = 1 << 30
	var hits: int = 0


var _hits: int = 0   ## HIT events of the last _tick


func _at(alt: float, east: float, north: float) -> Vector3:
	return FireTestKit.at(alt, east, north)


# [world, darts]: three Darts (player 1, team 1) facing three Lancers (player 0) 500 m east; `possessed` = player 1
# possesses dart 0 and flies it with PILOT_INPUT commands.
func _setup(seed_value: int, possessed: bool) -> Array:
	var w: SimWorld = CombatTestKit.world(seed_value)
	var h: BurstHook = BurstHook.new()
	w.set_ai_hook(h)
	var darts: PackedInt32Array = PackedInt32Array()
	for k: int in 3:
		darts.push_back(CombatTestKit.spawn(w, &"dart", 1, 1, _at(ALT + 20.0 * k, -300.0, 30.0 * k)))
		var _t: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(ALT + 20.0 * k, 200.0, 30.0 * k))
	h.ids = darts
	if possessed:
		var _r: CommandResult = w.apply_command(Command.possess(1, darts[0]))
	return [w, darts]


# Step-3 inputs of the next tick: what an AI reads from the index right after a load.
func _queries(w: SimWorld, darts: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var v: SimView = w.view()
	for id: int in darts:
		var p: Vector3 = w.store().pos[EntityId.slot(id)]
		out.append_array(v.projectiles_near(p, QUERY_R, 3))
		out.append_array(v.ids_near(p, QUERY_R, Spatial.MASK_ALL))
		out.append_array(v.ids_near(p, 100.0, Spatial.MASK_PROJECTILE))
		out.push_back(-1)
	return out


func _stale(w: SimWorld) -> int:
	var ps: ProjectileStore = w.projectiles()
	var n: int = 0
	for i: int in ps.live:
		if ps.hash_cell[i] != Spatial.cell_of(ps.pos[i]):
			n += 1
	return n


# One tick: the possessed pilot's command (FIRE1 on dart 0's cadence), then step; returns the tick's event bytes.
func _tick(w: SimWorld, possessed: bool) -> PackedByteArray:
	if possessed:
		var inp: PilotInput = PilotInput.new()
		inp.buttons = BurstHook.buttons_at(w.tick() + 1, 0)
		var _r: CommandResult = w.apply_command(Command.pilot(1, w.tick() + 1, inp))
	w.step()
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	_hits = 0
	for e: SimEvent in w.drain_events():
		_hits += 1 if e.kind == SimEvent.Kind.HIT else 0
		b.put_var([e.kind, e.tick, e.a, e.b, e.pos, e.value, e.team, e.extra])
	return b.data_array


func _reference(seed_value: int, possessed: bool) -> Ref:
	var a: Array = _setup(seed_value, possessed)
	var w: SimWorld = a[0]
	var darts: PackedInt32Array = a[1]
	var ref: Ref = Ref.new()
	var t0: int = w.tick()
	var last_save: int = t0 + FIRST_SAVE + SAVE_STEP * (SAVES - 1)
	while w.tick() < last_save + CONTINUE:
		var eb: PackedByteArray = _tick(w, possessed)
		var t: int = w.tick()
		ref.events[t] = eb
		ref.hits += _hits
		if t % CHECK_EVERY == 0:
			ref.raw[t] = SimSerialize.write_raw(w)
		if t >= t0 + FIRST_SAVE and t <= last_save and (t - t0 - FIRST_SAVE) % SAVE_STEP == 0:
			ref.saves.append(w.serialize())
			ref.save_ticks.push_back(t)
			ref.queries.append(_queries(w, darts))
			ref.min_live = mini(ref.min_live, w.projectiles().live.size())
			ref.stale_saves += 1 if _stale(w) > 0 else 0
	ref.raw[w.tick()] = SimSerialize.write_raw(w)
	return ref


# "" when the world restored from save `k` reloads to the same bytes, answers the same queries and replays the
# reference byte for byte for CONTINUE ticks; else what diverged first.
func _replay(ref: Ref, k: int, darts: PackedInt32Array, possessed: bool) -> String:
	var w: SimWorld = SimWorld.deserialize(ref.saves[k], WorldTestKit.content(), BurstHook.new())
	if w == null:
		return "refused"
	if w.serialize() != ref.saves[k]:
		return "reload bytes"
	if _queries(w, darts) != ref.queries[k]:
		return "step-3 queries"
	for _n: int in CONTINUE:
		var t: int = w.tick() + 1
		var eb: PackedByteArray = _tick(w, possessed)
		if eb != ref.events[t]:
			var x: StreamPeerBuffer = StreamPeerBuffer.new()
			x.data_array = eb
			var y: StreamPeerBuffer = StreamPeerBuffer.new()
			y.data_array = ref.events[t]
			var sx: String = ""
			var sy: String = ""
			while x.get_available_bytes() > 0:
				sx += str(x.get_var())
			while y.get_available_bytes() > 0:
				sy += str(y.get_var())
			return "events at tick %d: %s VS ref %s" % [t, sx, sy]
		if ref.raw.has(t) and SimSerialize.write_raw(w) != ref.raw[t]:
			return "bytes at tick %d" % t
	return ""


func _run(possessed: bool) -> void:
	var bad: PackedStringArray = PackedStringArray()
	for seed_value: int in SEEDS:
		var ref: Ref = _reference(seed_value, possessed)
		var darts: PackedInt32Array = _setup(seed_value, possessed)[1]
		assert_int(ref.saves.size()).is_equal(SAVES)
		assert_int(ref.hits).is_greater(10)                    # the slugs land: damage rolls on the world Rng
		assert_int(ref.min_live).is_greater(0)                 # slugs in flight at every save point
		assert_int(ref.stale_saves).is_greater_equal(MIN_STALE)   # most saves land on a tick that fired
		for k: int in SAVES:
			var why: String = _replay(ref, k, darts, possessed)
			if why != "":
				bad.append("seed %d save tick %d: %s" % [seed_value, ref.save_ticks[k], why])
	assert_array(Array(bad)).is_empty()


func test_ai_driven_burst_fight_restores_byte_exact_at_12_save_points() -> void:
	_run(false)


func test_possessed_dart_in_the_burst_fight_restores_byte_exact() -> void:
	_run(true)


# A restore takes the saved step-7 index: a slug fired in step 9 is absent from it and keeps hash_cell 0.
func test_restore_keeps_the_step_7_index_and_cells() -> void:
	var a: Array = _setup(41, false)
	var w: SimWorld = a[0]
	while _stale(w) == 0:
		var _e: PackedByteArray = _tick(w, false)
	var w2: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), BurstHook.new())
	assert_int(_stale(w2)).is_equal(_stale(w))
	assert_bool(w2.projectiles().hash_cell == w.projectiles().hash_cell).is_true()
	var sa: StreamPeerBuffer = StreamPeerBuffer.new()
	var sb: StreamPeerBuffer = StreamPeerBuffer.new()
	w.spatial.write_state(sa)
	w2.spatial.write_state(sb)
	assert_bool(sa.data_array == sb.data_array).is_true()
	assert_int(w2.spatial.item_count).is_equal(w.spatial.item_count)
	assert_int(w2.spatial.touched_count).is_equal(w.spatial.touched_count)


# FORMAT 12 (GD-10 added the shield domes after the fire state; TA-65 had added the Spatial section): bytes stamped 11 are
# refused as OLD_FORMAT and do not load.
func test_format_12_refuses_format_11_bytes() -> void:
	assert_int(SimSerialize.FORMAT).is_equal(12)
	assert_str(SimSerialize.SECTIONS[SimSerialize.SECTIONS.size() - 1]).is_equal("spatial")
	var w: SimWorld = _setup(7, false)[0]
	var bytes: PackedByteArray = w.serialize()
	bytes.encode_u32(4, 11)
	assert_int(SimSerialize.check(bytes)).is_equal(SimSerialize.Status.OLD_FORMAT)
	assert_object(SimWorld.deserialize(bytes, WorldTestKit.content(), BurstHook.new())).is_null()
