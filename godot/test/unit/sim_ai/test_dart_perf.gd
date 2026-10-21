extends GdUnitTestSuite
## AI-13 perf note (05 s10: think row 25 us = 6 probes + 1 neighbour query + 1 choice point; act row 6 us per ship) for
## DartBrain on a real SimWorld populated like a match: FAR_SHIPS friendly Darts over many hash cells, 12 friendly Darts
## within ~300 m of the measured ones (the separation query's ring path has neighbours), and two enemy ships inside the
## intercept radius (the choice point scores candidates). Cases, timed per call with `think_one` / `act_batch`:
##   patrol    AUTO patrol thinks; the choice point runs every `choice_period_thinks` (6th) think, staggered by slot, the
##             separation refresh every `DartBrain.SEP_PHASES` (3rd) think (never on a choice think), so the mean is
##             the steady mix;
##   intercept the same Darts on an enemy Bomber 1.75 km out (DartCombat.think + the engaged re-evaluation);
##   act       back-to-back act_batch over the measured Darts (track_velocity, the PULL_UP check on every 3rd tick per
##             ship, staggered: one height sample + the 1.0 s re-sample, pull_up_loss only while sinking); engaged:
##             ENGAGE on a Bomber ~400 m ahead (in fire range: the per-tick lead, the burst).
## TeamPicture is asserted as its own line (per tick, all teams, once per Vision epoch), and deterministic counters
## (choice / refresh shares, exact pull_up_loss calls, picture builds per epoch) catch regressions without timer noise.
## Timing bounds are report-only on hosted runners (R0 B.17 A-97: PERF_REPORT lines; asserted with
## PLANEWAR_PINNED_RUNNER=1); the counters are hard everywhere. Statistics and host normalisation are AI-40's (test_escort_perf.gd): best batch mean, a frozen reference kernel timed
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
## R0 B.17 A-96 (the author never raises these): the 05 s10 act row is a fleet mean, priced at the engaged mix
## ENGAGED_MIX (one AI ship in four in a gun fight inside fire range on the same tick; OWNER default) as
## (1 - f) act_patrol + f act_engage < ACT_ROW_US x CI_FACTOR; act_engage alone has the interim ceiling
## ACT_ENGAGE_CEILING_US = 3 x the row until the pinned runner measures (A-62).
const ENGAGED_MIX: float = 0.25
const ACT_ENGAGE_CEILING_US: float = 3.0 * ACT_ROW_US


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
	# every SEP_PHASES-th think exactly (phase 1 mod 3 never meets a choice think, phase 0 mod 6; no closing pair here)
	assert_float(quiet["refresh_share"]).is_equal_approx(1.0 / float(DartBrain.SEP_PHASES), 1e-6)
	assert_float(quiet["shape_loss"]).is_equal(0.0)                      # level flight at the band: no sinking command
	assert_float(quiet["sink_cmds"]).is_equal(1.0)                       # descent case: every shaped think commands a sink
	assert_float(quiet["sink_loss"]).is_equal(1.0)                       # ... and its sink limit calls pull_up_loss exactly once
	assert_float(quiet["check_share"]).is_less_equal(1.0 / 3.0 + 0.001)   # the PULL_UP check on every 3rd tick per ship
	assert_float(quiet["check_loss"]).is_less_equal(1.0)
	assert_float(quiet["sinking_acts"]).is_greater(0.0)   # the harness ships sink (frozen state): the budget path runs
	assert_float(quiet["loss_per_sinking_act"]).is_equal_approx(1.0 / float(DartKit.params().check_ticks), 1e-6)   # A-96 counter
	assert_int(fight["builds"]).is_equal(fight["epochs"])                 # one picture per team per Vision epoch, exactly
	# timings against the 05 s10 rows x CI_FACTOR (AI-40 / AI-11 precedent; no other factor)
	assert_bool(_gate("test_dart_perf.quiet_think", qt.x, THINK_ROW_US * CI_FACTOR, host, "05 s10 / R0 A-96")).is_true()
	assert_bool(_gate("test_dart_perf.engaged_think", it.x, THINK_ROW_US * CI_FACTOR, host, "05 s10 / R0 A-96")).is_true()
	var mix: float = (1.0 - ENGAGED_MIX) * float(quiet["act"]) + ENGAGED_MIX * float(fight["act"])
	print("AI-13 act fleet mix (A-96, f %.2f): %.2f us (asserted %.2f < %.1f); act engage %.2f < %.1f" % [ENGAGED_MIX, mix,
		mix / host, ACT_ROW_US * CI_FACTOR, float(fight["act"]) / host, ACT_ENGAGE_CEILING_US])
	assert_bool(_gate("test_dart_perf.act_patrol", float(quiet["act"]), ACT_ROW_US * CI_FACTOR, host, "05 s10 / R0 A-96")).is_true()
	assert_bool(_gate("test_dart_perf.act_mix", mix, ACT_ROW_US * CI_FACTOR, host, "05 s10 / R0 A-96")).is_true()
	assert_bool(_gate("test_dart_perf.act_engage", float(fight["act"]), ACT_ENGAGE_CEILING_US, host, "05 s10 / R0 A-96")).is_true()
	assert_bool(_gate("test_dart_perf.team_picture_tick", pic_tick, PICTURE_CAP_US, host, "05 s10 / R0 A-96")).is_true()
	assert_float(fight["visible_per_engage_act"]).is_equal(1.0)   # A-97: one visible_to per ENGAGE act (the round-1 lever)


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
	out["sinking_acts"] = float(acts1[6] - acts0[6])
	out["loss_per_sinking_act"] = float(acts1[5] - acts0[5]) / float(maxi(acts1[6] - acts0[6], 1))
	if not enemies:
		_descent(w, brain, st, sink, ids, out)
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
	var e0: Vector2i = Vector2i(brain.modes.combat.stats_engage_acts, brain.modes.combat.stats_engage_visible)
	out["act"] = _acts(brain, v, st, sink, ids)
	var e1: Vector2i = Vector2i(brain.modes.combat.stats_engage_acts, brain.modes.combat.stats_engage_visible)
	out["visible_per_engage_act"] = float(e1.y - e0.y) / float(maxi(e1.x - e0.x, 1))
	var pic: float = INF
	for b: int in BATCHES:
		var t0: int = Time.get_ticks_usec()
		var _p: PackedInt32Array = brain.modes.picture.enemies(v, 0, 900000 + b * 1000)
		pic = minf(pic, float(Time.get_ticks_usec() - t0))
	var e: int = brain.modes.picture.epoch(0, 950000)
	var builds1: int = brain.modes.picture.builds
	for k: int in 3 * out["period"]:   # every tick of three epochs asks: one build per epoch
		var _q: PackedInt32Array = brain.modes.picture.enemies(v, 0, 950000 + k)
	out["builds"] = brain.modes.picture.builds - builds1
	out["epochs"] = brain.modes.picture.epoch(0, 950000 + 3 * out["period"] - 1) - e + 1
	out["picture_us"] = pic
	return out


# The sink limit's counter on commands that sink: each measured Dart gets a MOVE with FLAG_LOW (the 60 m deck band) from
# 300 m AGL; with the world frozen every think commands the same descent, so every shaped think runs sink_limited and its
# one pull_up_loss. Fills out["sink_cmds"] (share of shaped thinks whose command sinks) and out["sink_loss"].
func _descent(w: SimWorld, brain: DartBrain, st: AiState, sink: CommandSink, ids: PackedInt32Array, out: Dictionary) -> void:
	for i: int in MEASURED:
		var p: Vector3 = w.view().pos(ids[i])
		var to: Vector3 = DartKit.above(w, DartKit.offset(p.normalized(), 0.0, 3000.0), 60.0)
		DartKit.order(w, ids[i], OrderSpec.make(OrderSpec.Kind.MOVE, 0, to, OrderSpec.FLAG_LOW))
	w.step()
	var v: SimView = w.view()
	var c0: Array = _counters(brain)
	var sinking: int = 0
	for k: int in 60:
		for i: int in MEASURED:
			var s: int = EntityId.slot(ids[i])
			brain.think_one(ids[i], v, st, sink, 2000 + 10 * k)
			sinking += 1 if st.guidance_vel[s].dot(v.pos(ids[i]).normalized()) < 0.0 else 0
	var c1: Array = _counters(brain)
	var shaped: int = maxi(c1[2] - c0[2], 1)
	out["sink_cmds"] = float(sinking) / float(shaped)
	out["sink_loss"] = float(c1[3] - c0[3]) / float(shaped)


# [choices, refreshes, shaped thinks, shape exact losses, act checks, act exact losses, flight acts while sinking]
func _counters(b: DartBrain) -> Array:
	return [b.modes.stats_choices, b.stats_refreshes, b.stats_thinks, b.stats_shape_loss, b.stats_checks, b.stats_check_loss,
		b.stats_sinking_acts]


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

## R0 B.17 A-97 inline gate (until TEST-03's PerfGate): one PERF_REPORT line; the bound is asserted only on the pinned
## runner (PLANEWAR_PINNED_RUNNER == "1"); on hosted runners timing never fails a test.
static func _gate(name: String, us: float, bound_us: float, host: float, cite: String) -> bool:
	var pinned: bool = OS.get_environment("PLANEWAR_PINNED_RUNNER") == "1"
	print("PERF_REPORT name=%s us=%.2f bound_us=%.2f host=%.2f pinned=%d cite=%s" % [name, us, bound_us, host, 1 if pinned else 0, cite])
	return not pinned or us / host < bound_us
