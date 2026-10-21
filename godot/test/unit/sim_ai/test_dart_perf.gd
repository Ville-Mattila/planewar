extends GdUnitTestSuite
## AI-13 perf note (05 s10: think row 25 us = 6 probes + 1 neighbour query + 1 choice point; act row 6 us per ship) for
## DartBrain on a real SimWorld populated like a match: FAR_SHIPS friendly Darts over many hash cells, 12 friendly Darts
## within ~300 m of the measured ones (the separation query's ring path has neighbours), and two enemy ships inside the
## intercept radius (the choice point scores candidates). Cases, timed per call with `think_one` / `act_batch`:
##   patrol    AUTO patrol thinks; the choice point runs every `choice_period_thinks` (6th) think, staggered by slot, the
##             separation refresh every 2nd (never on a choice think), so the mean is the steady mix;
##   intercept the same Darts on an enemy Bomber 1.75 km out (DartCombat.think + the engaged re-evaluation);
##   act       back-to-back act_batch over the measured Darts (track_velocity, the PULL_UP check on every 3rd tick per
##             ship, staggered: one height sample + the 1.0 s re-sample, pull_up_loss only while sinking); engaged:
##             ENGAGE on a Bomber ~400 m ahead (in fire range: the per-tick lead, the burst).
## TeamPicture is asserted as its own line (per tick, all teams, once per Vision epoch), and deterministic counters
## (choice / refresh shares, exact pull_up_loss calls, picture builds per epoch) catch regressions without timer noise.
## Statistics and host normalisation are AI-40's (test_escort_perf.gd): best batch mean, a frozen reference kernel timed
## before and after, figures divided by host = clamp(ref / REF_ANCHOR_US, 1, MAX_HOST); CI bound = row x CI_FACTOR.

const CALLS: int = 600
const BATCHES: int = 6
const ACT_LOOPS: int = 30
const FAR_SHIPS: int = 240
const MEASURED: int = 6           ## consecutive slots: the act-time PULL_UP check ((tick + slot) % 3) hits exactly a third of them
const THINK_ROW_US: float = 25.0
const ACT_ROW_US: float = 6.0
const CI_FACTOR: float = 2.0
const REF_ANCHOR_US: float = 1.25
const MAX_HOST: float = 1.5
## TeamPicture: one ships() pass per team per Vision epoch; its per-tick share at PlayerTable.TEAMS teams is asserted
## against a stated part of the 05 s10 think slice (1.8 ms): a quarter.
const PICTURE_CAP_US: float = 450.0


func _world(enemies: bool = true) -> Array:
	var w: SimWorld = DartKit.world(31, &"", DartKit.rules(2000))
	var dart: int = DartKit.def_id(&"dart")
	for k: int in FAR_SHIPS:
		var lat: float = deg_to_rad(-60.0 + 120.0 * float(k % 20) / 19.0)
		var lon: float = deg_to_rad(8.0 + 340.0 * float(k) / float(FAR_SHIPS))
		var pos: Vector3 = Sphere.from_lat_lon(lat, lon, Sphere.PLANET_RADIUS + 300.0)
		var code: int = CommandResult.Code.REJECTED_RATE
		while code == CommandResult.Code.REJECTED_RATE:
			code = w.apply_command(CommandPayload.debug_spawn(1, dart, 0, 0, pos, Vector3.ZERO, Vector3(0, 1, 0))).code
			w.step()
	var _old: Array[SimEvent] = w.drain_events()
	var home: Vector3 = Vector3(1, 0, 0)
	var _core: int = DartKit.spawn(w, &"core", 0, DartKit.above(w, home, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	# the formation and the two enemies spawn in one tick (one step for all), so the friendlies fly parallel: no closing
	# pair from staggered spawns (AI-11's harness rule); player 0 issues them all (owner 1 for the enemies)
	for k: int in MEASURED + 12:
		var p: Vector3 = DartKit.above(w, DartKit.offset(home, -45.0 * float(k % 4), 1200.0 + 60.0 * float(MathX.floori_div(k, 4))), 300.0)
		_queue(w, 0, &"dart", 0, p, Vector3(0, 110, 0))
	var far: float = 0.0 if enemies else 4000.0   # quiet case: the enemies out of every sensor and the radius
	_queue(w, 1, &"bomber", DartKit.FOE, DartKit.above(w, DartKit.offset(home, 900.0 + far, 1500.0), 400.0), Vector3(0, 70, 0))
	_queue(w, 1, &"scout", DartKit.FOE, DartKit.above(w, DartKit.offset(home, -600.0 - far, 400.0), 250.0), Vector3(0, 60, 0))
	_queue(w, 1, &"bomber", DartKit.FOE, DartKit.above(w, DartKit.offset(home, -70.0 + far, 1700.0), 330.0), Vector3(0, 110, 0))
	w.step()
	var ids: PackedInt32Array = PackedInt32Array()
	var bombers: PackedInt32Array = PackedInt32Array()
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN and e.b == dart:
			var _a: bool = ids.push_back(e.a)
		elif e.kind == SimEvent.Kind.SPAWN and e.b == DartKit.def_id(&"bomber"):
			var _b: bool = bombers.push_back(e.a)
	assert(ids.size() == MEASURED + 12 and bombers.size() == 2, "perf world spawns")
	for _k: int in 6:   # past a Vision pass (rules.vision_hz): the team sees the two enemies
		w.step()
	return [w, ids, bombers[0], bombers[1]]


func _queue(w: SimWorld, owner: int, def: StringName, team: int, p: Vector3, v: Vector3) -> void:
	var code: int = w.apply_command(CommandPayload.debug_spawn(0, DartKit.def_id(def), owner, team, p, v, Vector3(0, 1, 0))).code
	assert(code == CommandResult.Code.ACCEPTED, "spawn %s: %d" % [def, code])


func _stats(us: PackedFloat32Array) -> Vector3:
	var a: PackedFloat32Array = us.duplicate()
	a.sort()
	var sum: float = 0.0
	for x: float in us:
		sum += x
	return Vector3(sum / float(us.size()), a[MathX.floori_div(a.size(), 2)], a[int(float(a.size()) * 0.95)])


func _best(a: Vector3, b: Vector3) -> Vector3:
	return b if b.x < a.x else a


# Per-call think timings over the measured Darts; `tick` advances one think period per round so the choice point
# phase rotates as in play.
func _thinks(brain: DartBrain, v: SimView, st: AiState, sink: CommandSink, ids: PackedInt32Array) -> Vector3:
	var best: Vector3 = Vector3(INF, 0.0, 0.0)
	var period: int = DartKit.params().think_ticks
	for b: int in BATCHES:
		var us: PackedFloat32Array = PackedFloat32Array()
		var _r: int = us.resize(CALLS)
		for k: int in CALLS:
			var id: int = ids[k % MEASURED]
			var tick: int = 1000 + period * MathX.floori_div(k, MEASURED) + 100000 * b
			var _pic: PackedInt32Array = brain.modes.picture.enemies(v, 0, tick)   # the tick's shared picture: timed apart
			var t0: int = Time.get_ticks_usec()
			brain.think_one(id, v, st, sink, tick)
			us[k] = float(Time.get_ticks_usec() - t0)
		best = _best(best, _stats(us))
	return best


func _acts(brain: DartBrain, v: SimView, st: AiState, sink: CommandSink, ids: PackedInt32Array) -> float:
	var batch: PackedInt32Array = ids.slice(0, MEASURED)
	var best: float = INF
	for b: int in ACT_LOOPS + 1:
		var t0: int = Time.get_ticks_usec()
		for k: int in MathX.floori_div(CALLS, MEASURED):
			brain.act_batch(batch, v, st, sink)
		var us: float = float(Time.get_ticks_usec() - t0) / float(CALLS)
		if b > 0:
			best = minf(best, us)
	return best


func test_perf_think_and_act() -> void:
	var ref0: float = _ref_us()
	var quiet: Dictionary = _case(false)
	var fight: Dictionary = _case(true)
	var ref: float = minf(ref0, _ref_us())
	var host: float = clampf(ref / REF_ANCHOR_US, 1.0, MAX_HOST)
	var qt: Vector3 = quiet["think"]
	var it: Vector3 = fight["intercept"]
	var pic_tick: float = float(fight["picture_us"]) * float(PlayerTable.TEAMS) / float(fight["period"])
	print("AI-13 perf (%d far ships, 12 friendly neighbours; best of %d batches of %d per-call thinks): quiet patrol think mean %.1f / median %.1f / p95 %.1f us (choice share %.3f, separation refresh share %.2f, exact pull_up_loss per shaped think %.2f); engaged (INTERCEPT, three enemies near) think mean %.1f / median %.1f / p95 %.1f us (row %.0f); act patrol %.2f, act engage in fire range %.2f us/ship (row %.0f; PULL_UP checks per act %.3f, exact loss per check %.2f); TeamPicture build %.1f us for %d ships, once per team per Vision epoch (%d ticks): %.1f us/tick at %d teams (cap %.0f)" % [
		FAR_SHIPS, BATCHES, CALLS, qt.x, qt.y, qt.z, quiet["choice_share"], quiet["refresh_share"], quiet["shape_loss"],
		it.x, it.y, it.z, THINK_ROW_US, quiet["act"], fight["act"], ACT_ROW_US, quiet["check_share"], quiet["check_loss"],
		fight["picture_us"], FAR_SHIPS + MEASURED + 12 + 3, fight["period"], pic_tick, PlayerTable.TEAMS, PICTURE_CAP_US])
	print("AI-13 host: reference kernel %.3f us (anchor %.3f), scale %.2f; asserted quiet %.1f, engaged %.1f, act %.2f / %.2f, picture %.1f us/tick" % [
		ref, REF_ANCHOR_US, host, qt.x / host, it.x / host, float(quiet["act"]) / host, float(fight["act"]) / host, pic_tick / host])
	# deterministic counters (no timer noise)
	assert_float(quiet["choice_share"]).is_between(0.15, 0.18)           # every 6th think
	assert_float(quiet["refresh_share"]).is_less_equal(0.51)             # every 2nd think, none on a choice think (no closing pair)
	assert_float(quiet["shape_loss"]).is_less_equal(1.0)                 # at most one exact loss per shaped think
	assert_float(quiet["check_share"]).is_less_equal(1.0 / 3.0 + 0.001)   # the PULL_UP check on every 3rd tick per ship
	assert_float(quiet["check_loss"]).is_less_equal(1.0)
	assert_int(fight["builds_per_epoch"]).is_equal(1)                     # one picture per team per Vision epoch
	# timings against the 05 s10 rows x CI_FACTOR (AI-40 / AI-11 precedent; no other factor)
	assert_float(qt.x / host).is_less(THINK_ROW_US * CI_FACTOR)
	assert_float(it.x / host).is_less(THINK_ROW_US * CI_FACTOR)
	assert_float(float(quiet["act"]) / host).is_less(ACT_ROW_US * CI_FACTOR)
	assert_float(float(fight["act"]) / host).is_less(ACT_ROW_US * CI_FACTOR)
	assert_float(pic_tick / host).is_less(PICTURE_CAP_US)


# The timings and counters of one world: quiet (no enemy in reach) or fight (two enemies near, a Bomber in gun range).
func _case(enemies: bool) -> Dictionary:
	var r: Array = _world(enemies)
	var w: SimWorld = r[0]
	var ids: PackedInt32Array = r[1]
	var bomber: int = r[2]
	var close: int = r[3]
	var v: SimView = w.view()
	var brain: DartBrain = DartKit.brain(w)
	brain.bind_rng(Rng.new(7).fork(&"ai"))
	var st: AiState = AiState.new()
	for id: int in ids:
		st.cls[EntityId.slot(id)] = DartKit.CLS_DART
		st.eid[EntityId.slot(id)] = id
	var sink: CommandSink = CommandSink.new()
	for id: int in ids:   # first thinks: home, PATROL
		brain.think_one(id, v, st, sink, 990)
	var reach: int = brain.modes.picture.near(v, 0, 990, st.home[EntityId.slot(ids[0])], brain.prm.intercept_radius)
	assert_int(reach).is_equal(3 if enemies else 0)   # quiet: no visible enemy inside the intercept radius (far ones may be seen)
	var out: Dictionary = {"period": brain.modes.picture.period}
	var c0: Array = _counters(brain)
	out["think"] = _thinks(brain, v, st, sink, ids)
	var c1: Array = _counters(brain)
	var n: float = float(BATCHES * CALLS)
	out["choice_share"] = float(c1[0] - c0[0]) / n
	out["refresh_share"] = float(c1[1] - c0[1]) / float(maxi(c1[2] - c0[2], 1))
	out["shape_loss"] = float(c1[3] - c0[3]) / float(maxi(c1[2] - c0[2], 1))
	var acts0: Array = _counters(brain)
	out["act"] = _acts(brain, v, st, sink, ids)
	var acts1: Array = _counters(brain)
	out["check_share"] = float(acts1[4] - acts0[4]) / float((ACT_LOOPS + 1) * MathX.floori_div(CALLS, MEASURED) * MEASURED)
	out["check_loss"] = float(acts1[5] - acts0[5]) / float(maxi(acts1[4] - acts0[4], 1))
	if not enemies:
		return out
	for i: int in MEASURED:   # every measured Dart on the Bomber 1.75 km out
		var s: int = EntityId.slot(ids[i])
		st.set_target(s, bomber)
		st.seen_tick[s] = 1000
		st.mode[s] = AiTag.Tag.INTERCEPT
	out["intercept"] = _thinks(brain, v, st, sink, ids)
	for i: int in MEASURED:   # ENGAGE on the Bomber ~400 m ahead: in fire range, the per-tick lead and the burst logic
		var s: int = EntityId.slot(ids[i])
		st.set_target(s, close)
		st.goal[s] = v.pos(close)
		st.aim_lead[s] = v.pos(close)
		st.mode[s] = AiTag.Tag.ENGAGE
		assert_float(v.pos(ids[i]).distance_to(v.pos(close))).is_less(brain.prm.fire_range)
	out["act"] = _acts(brain, v, st, sink, ids)
	var pic: float = INF
	for b: int in BATCHES:
		var t0: int = Time.get_ticks_usec()
		var _p: PackedInt32Array = brain.modes.picture.enemies(v, 0, 900000 + b * 1000)
		pic = minf(pic, float(Time.get_ticks_usec() - t0))
	var e: int = brain.modes.picture.epoch(0, 950000)
	var builds1: int = brain.modes.picture.builds
	for k: int in 3 * out["period"]:   # every tick of three epochs asks: one build per epoch
		var _q: PackedInt32Array = brain.modes.picture.enemies(v, 0, 950000 + k)
	out["builds_per_epoch"] = float(brain.modes.picture.builds - builds1) / float(brain.modes.picture.epoch(0, 950000 + 3 * out["period"] - 1) - e + 1)
	out["builds_per_epoch"] = roundi(out["builds_per_epoch"])
	out["picture_us"] = pic
	return out


# [choices, refreshes, shaped thinks, shape exact losses, act checks, act exact losses]
func _counters(b: DartBrain) -> Array:
	return [b.modes.stats_choices, b.stats_refreshes, b.stats_thinks, b.stats_shape_loss, b.stats_checks, b.stats_check_loss]


## AI-40's host-speed reference: one untimed warm-up loop, then the minimum mean over ACT_LOOPS loops of 1000 steps.
func _ref_us() -> float:
	var pts: PackedVector3Array = PackedVector3Array()
	var _r: int = pts.resize(64)
	for i: int in 64:
		pts[i] = Vector3(sin(float(i)), cos(float(i) * 1.3), float(i % 7) - 3.0)
	var best: float = INF
	var acc: float = 0.0
	for b: int in ACT_LOOPS + 1:
		var t0: int = Time.get_ticks_usec()
		for k: int in 1000:
			acc += _ref_step(pts, k)
		var us: float = float(Time.get_ticks_usec() - t0) / 1000.0
		if b > 0:
			best = minf(best, us)
	assert_bool(is_finite(acc)).is_true()
	return best


## The AI-40 reference kernel (test_escort_perf.gd `_ref_step`), unchanged: no project code.
static func _ref_step(pts: PackedVector3Array, k: int) -> float:
	var a: Vector3 = pts[k & 63]
	var b: Vector3 = pts[(k * 7 + 3) & 63]
	var c: Vector3 = a.cross(b)
	var acc: float = 0.0
	for j: int in 8:
		c = (c + a * 0.5).normalized()
		acc += c.dot(b) + atan2(c.y, c.x) + (1.0 if c.z > 0.0 else -1.0)
	return acc
