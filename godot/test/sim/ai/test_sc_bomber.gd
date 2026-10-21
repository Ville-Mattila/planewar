extends GdUnitTestSuite
## 05 s11.2 scenarios of the Bomber brain (AI-14) through SimWorld.step() with an AiDriver hook (Ai14Kit): SC-19
## (released mid-run 1,800 m out within 10 degrees of the target: the run-in continues, no new IP), SC-20 (released
## 60 degrees off: a new IP, the attack completes) and SC-21 (the pilot drops every bomb; on release the ATTACK is done,
## RETURN, the Bomber lands tail-down on the Core pad and docks). Flat datum. The target is an enemy Refinery; a
## friendly Sensor Mast 1 km from it gives the team the picture (vision only). Docking (GD-15) is not built: a touchdown
## inside the pad volume within the R0 B.5 safe limits is docked by the test (F_DOCKED + link), as GD-15 will.

const HZ: int = 30
const ME: int = 0   ## the possessing player (human, team 0)


## [world, driver, bomber, refinery, core]: the Core (home pad) 1 km behind the Bomber's start, the Bomber 4.5 km from
## the Refinery at 300 m AGL heading at it, ATTACK ordered.
func _setup(seed_value: int) -> Array:
	var w: SimWorld = Ai14Kit.world(seed_value)
	var d: AiDriver = Ai14Kit.driver(w)
	var tgt_dir: Vector3 = Vector3(1, 0, 0)
	var refinery: int = DartKit.spawn(w, &"refinery", DartKit.FOE, DartKit.above(w, tgt_dir, 0.0), Vector3.ZERO, Vector3(0, 1, 0))
	var mast_p: Vector3 = DartKit.above(w, DartKit.offset(tgt_dir, -1000.0, 0.0), 0.0)
	var _mast: int = DartKit.spawn(w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, Vector3(0, 1, 0)))
	var core: int = Ai14Kit.core(w, DartKit.offset(tgt_dir, -5500.0, 200.0), 0)   # the home pad (Ai14Kit.core: the RAM stand-in)
	var p0: Vector3 = DartKit.above(w, DartKit.offset(tgt_dir, -4500.0, 150.0), 300.0)
	var h0: Vector3 = DartKit.heading(p0, DartKit.above(w, tgt_dir, 300.0))
	var bomber: int = DartKit.spawn(w, &"bomber", 0, p0, h0 * 70.0, h0)
	for _k: int in 3:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
	assert_bool(w.view().visible_to(0, refinery)).is_true()
	DartKit.order(w, bomber, OrderSpec.make(OrderSpec.Kind.ATTACK, refinery))
	return [w, d, bomber, refinery, core]


# Runs until the Bomber is in R2 RUN_IN within `dist` m (ground) of the Refinery; false on timeout.
func _until_run_in(w: SimWorld, d: AiDriver, bomber: int, refinery: int, dist: float) -> bool:
	var s: int = EntityId.slot(bomber)
	for _k: int in 200 * HZ:
		var _e: Array[SimEvent] = Ai14Kit.step(w)
		if AttackRun.step_of(d.state, s) == AttackRun.Step.RUN_IN \
				and Guidance.ground_dist(w.view().pos(bomber), w.view().pos(refinery)) <= dist:
			return true
	return false


# The possessing pilot for one tick: level flight on the heading `off_deg` from the bearing to the Refinery, at the
# Bomber's cruise speed (FlightController.track_velocity with the Bomber's gains); FIRE2 when `bombs`.
func _pilot(w: SimWorld, bomber: int, refinery: int, off_deg: float, integ: Vector2, bombs: bool) -> Vector2:
	var v: SimView = w.view()
	var p: Vector3 = v.pos(bomber)
	var up: Vector3 = p.normalized()
	var h: Vector3 = DartKit.heading(p, v.pos(refinery)).rotated(up, deg_to_rad(off_deg))
	var inp: PilotInput = PilotInput.new()
	var out: Vector2 = FlightController.track_velocity(v.basis(bomber), v.vel(bomber), h * Ai14Kit.ship(&"bomber").v_cruise,
		up, DartKit.gains_of(&"bomber"), integ, inp)
	if bombs:
		inp.buttons |= PilotInput.FIRE2
	OverlayKit.ok(w, Command.pilot(ME, w.tick() + 1, inp))
	return out


# Bearing of the Refinery off the Bomber's horizontal velocity, degrees.
func _bearing(w: SimWorld, bomber: int, refinery: int) -> float:
	var v: SimView = w.view()
	var p: Vector3 = v.pos(bomber)
	var up: Vector3 = p.normalized()
	var vh: Vector3 = v.vel(bomber) - up * v.vel(bomber).dot(up)
	return rad_to_deg(vh.angle_to(DartKit.heading(p, v.pos(refinery))))


# Possess, fly `off_deg` off the target until the bearing is within 2 degrees of it and (for SC-19) the range is down to
# `release_m`; release. Returns [release tick, range at release, bearing at release].
func _possess_and_release(w: SimWorld, bomber: int, refinery: int, off_deg: float, release_m: float) -> Array:
	OverlayKit.ok(w, Command.possess(ME, bomber))
	var _e: Array[SimEvent] = Ai14Kit.step(w)
	assert_int(w.view().control_state(bomber)).is_equal(ControlMachine.State.POSSESSED)
	var integ: Vector2 = Vector2.ZERO
	for _k: int in 60 * HZ:
		integ = _pilot(w, bomber, refinery, off_deg, integ, false)
		var _x: Array[SimEvent] = Ai14Kit.step(w)
		var rng: float = Guidance.ground_dist(w.view().pos(bomber), w.view().pos(refinery))
		if absf(_bearing(w, bomber, refinery) - absf(off_deg)) < 2.0 and rng <= release_m:
			break
	var at: Array = [w.tick(), Guidance.ground_dist(w.view().pos(bomber), w.view().pos(refinery)), _bearing(w, bomber, refinery)]
	OverlayKit.ok(w, Command.release(ME))
	var _r: Array[SimEvent] = Ai14Kit.step(w)
	return at


# After the release: runs up to `ticks`, recording the AttackRun steps (in order, deduplicated), bomb impacts within
# 60 m of the Refinery, and its hull. Returns [steps, impacts near, refinery hp01, bombs left].
func _after_release(w: SimWorld, d: AiDriver, bomber: int, refinery: int, ticks: int) -> Array:
	var s: int = EntityId.slot(bomber)
	var steps: PackedInt32Array = PackedInt32Array()
	var near: int = 0
	for _k: int in ticks:
		for e: SimEvent in Ai14Kit.step(w):
			if e.kind == SimEvent.Kind.BOMB_IMPACT and w.view().alive(refinery) and e.pos.distance_to(w.view().pos(refinery)) < 60.0:
				near += 1
		var step: int = AttackRun.step_of(d.state, s)
		if steps.is_empty() or steps[steps.size() - 1] != step:
			var _a: bool = steps.push_back(step)
		if step == AttackRun.Step.EGRESS or step == AttackRun.Step.DONE or not w.view().alive(refinery):
			if w.view().bombs(bomber) == 0 or step == AttackRun.Step.DONE:
				break
	return [steps, near, w.view().hp01(refinery) if w.view().alive(refinery) else 0.0, w.view().bombs(bomber)]


# SC-19 release_mid_bomb_run_continue: Bomber ATTACK; possessed in R2, released 1,800 m out with the target 10 degrees
# off the nose. Pass: the run-in continues without an IP re-route (no ROUTE step after the release); bombs released;
# the target takes hits.
func test_sc19_release_mid_bomb_run_continue() -> void:
	var r: Array = _setup(19)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var bomber: int = r[2]
	var refinery: int = r[3]
	assert_bool(_until_run_in(w, d, bomber, refinery, 2000.0)).is_true()
	var at: Array = _possess_and_release(w, bomber, refinery, 10.0, 1800.0)
	var bombs0: int = w.view().bombs(bomber)
	var hp0: float = w.view().hp01(refinery)
	var res: Array = _after_release(w, d, bomber, refinery, 90 * HZ)
	var steps: PackedInt32Array = res[0]
	var what: String = "SC-19: released at %.0f m, bearing %.1f deg; steps after %s; bombs %d -> %d; impacts near %d; refinery hp %.2f -> %.2f" % [
		at[1], at[2], str(steps), bombs0, res[3], res[1], hp0, res[2]]
	print(what)
	assert_float(at[1]).override_failure_message(what).is_between(1700.0, 1800.0)
	assert_float(at[2]).override_failure_message(what).is_between(8.0, 12.0)
	var first_pass: PackedInt32Array = steps.slice(0, maxi(steps.find(AttackRun.Step.EGRESS), 0))
	assert_bool(first_pass.has(AttackRun.Step.ROUTE)).override_failure_message(what).is_false()   # no IP re-route
	assert_bool(first_pass.has(AttackRun.Step.RELEASE)).override_failure_message(what).is_true()
	assert_int(res[3]).override_failure_message(what).is_less(bombs0)
	assert_int(res[1]).override_failure_message(what).is_greater(0)
	assert_float(res[2]).override_failure_message(what).is_less(hp0)


# SC-20 release_mid_bomb_run_reroute: as SC-19 but released with the target 60 degrees off the nose. Pass: routes to a
# new IP (ROUTE after the release, before the next RUN_IN); completes the attack (bombs released, target hit).
func test_sc20_release_mid_bomb_run_reroute() -> void:
	var r: Array = _setup(20)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var bomber: int = r[2]
	var refinery: int = r[3]
	assert_bool(_until_run_in(w, d, bomber, refinery, 2000.0)).is_true()
	var at: Array = _possess_and_release(w, bomber, refinery, 60.0, 2500.0)
	var bombs0: int = w.view().bombs(bomber)
	var hp0: float = w.view().hp01(refinery)
	var res: Array = _after_release(w, d, bomber, refinery, 240 * HZ)
	var steps: PackedInt32Array = res[0]
	var what: String = "SC-20: released at %.0f m, bearing %.1f deg; steps after %s; bombs %d -> %d; impacts near %d; refinery hp %.2f -> %.2f" % [
		at[1], at[2], str(steps), bombs0, res[3], res[1], hp0, res[2]]
	print(what)
	assert_float(at[2]).override_failure_message(what).is_between(58.0, 62.0)
	assert_int(steps.find(AttackRun.Step.ROUTE)).override_failure_message(what).is_between(0, 1)
	assert_bool(steps.find(AttackRun.Step.RELEASE) > steps.find(AttackRun.Step.ROUTE)).override_failure_message(what).is_true()
	assert_int(res[3]).override_failure_message(what).is_less(bombs0)
	assert_int(res[1]).override_failure_message(what).is_greater(0)
	assert_float(res[2]).override_failure_message(what).is_less(hp0)


# SC-21 release_after_all_bombs: the possessing pilot drops all bombs; release. Pass: the ATTACK is complete (AttackRun
# DONE at the first think after the SAFETY overlay; 05 s2.5 "bombs = 0 -> order complete -> RETURN"); a system RETURN
# (issuer -1) heads the queue; the Bomber lands tail-down on the Core pad within the R0 B.5 limits and docks (DOCKED
# tag). Order completion itself (popping the ATTACK, C4) is the sim's path of AI-15 / A-61.
func test_sc21_release_after_all_bombs() -> void:
	var r: Array = _setup(21)
	var w: SimWorld = r[0]
	var d: AiDriver = r[1]
	var bomber: int = r[2]
	var refinery: int = r[3]
	var core: int = r[4]
	var s: int = EntityId.slot(bomber)
	assert_bool(_until_run_in(w, d, bomber, refinery, 2400.0)).is_true()
	OverlayKit.ok(w, Command.possess(ME, bomber))
	var _e: Array[SimEvent] = Ai14Kit.step(w)
	var integ: Vector2 = Vector2.ZERO
	for _k: int in 20 * HZ:
		integ = _pilot(w, bomber, refinery, 0.0, integ, true)
		var _x: Array[SimEvent] = Ai14Kit.step(w)
		if w.view().bombs(bomber) == 0:
			break
	assert_int(w.view().bombs(bomber)).is_equal(0)
	OverlayKit.ok(w, Command.release(ME))
	var _r: Array[SimEvent] = Ai14Kit.step(w)
	var t_rel: int = w.tick()
	var done_tick: int = -1
	var return_tick: int = -1
	var docked_tick: int = -1
	var td: Vector3 = Vector3(-1, -1, -1)
	var common: FlightCommonDef = Ai14Kit.content().flight_common
	for _k: int in 300 * HZ:
		var _y: Array[SimEvent] = Ai14Kit.step(w)
		var v: SimView = w.view()
		if done_tick < 0 and AttackRun.step_of(d.state, s) == AttackRun.Step.DONE:
			done_tick = w.tick()
		if return_tick < 0 and v.order_head(bomber) != null and v.order_head(bomber).kind == OrderSpec.Kind.RETURN:
			return_tick = w.tick()
		if docked_tick < 0 and return_tick >= 0:
			td = _touchdown(w, bomber, core)
			if td.x >= 0.0 and td.x <= common.landing_safe_v_vert and td.y <= common.landing_safe_v_hor \
					and td.z <= common.landing_safe_pitch_deg:
				_dock(w, bomber, core)   # GD-15 stand-in
				docked_tick = w.tick()
		if docked_tick >= 0 and w.tick() > docked_tick + 2 * d.think_period():
			break
	var what: String = "SC-21: release +%d, run done +%d, RETURN head +%d (issuer %d), docked +%d (touchdown vz %.2f vh %.2f tilt %.1f), tag %d, hp %.2f" % [
		0, done_tick - t_rel, return_tick - t_rel, w.view().order_issuer(bomber), docked_tick - t_rel, td.x, td.y, td.z,
		w.view().ai_tag(bomber), w.view().hp01(bomber)]
	print(what)
	assert_int(done_tick).override_failure_message(what).is_between(t_rel, t_rel + 4 * HZ)
	assert_int(return_tick).override_failure_message(what).is_between(t_rel, t_rel + 5 * HZ)
	assert_int(w.view().order_issuer(bomber)).override_failure_message(what).is_equal(-1)
	assert_int(docked_tick).override_failure_message(what).is_greater(0)
	assert_int(w.view().ai_tag(bomber)).override_failure_message(what).is_equal(AiTag.Tag.DOCKED)
	assert_float(w.view().hp01(bomber)).override_failure_message(what).is_equal(1.0)


# R0 B.5 / A-31 pad volume test of `ship` on `pad`: (descent speed along the pad normal, horizontal speed, tilt of the
# thrust axis from the normal, degrees) when inside the volume and in contact, else x = -1.
func _touchdown(w: SimWorld, ship: int, pad: int) -> Vector3:
	var v: SimView = w.view()
	var n: Vector3 = v.basis(pad).y
	var rel: Vector3 = v.pos(ship) - v.pos(pad)
	var h: float = rel.dot(n)
	var off: float = (rel - n * h).length()
	var radius: float = Ai14Kit.ship(&"bomber").bounding_radius
	if off > 12.0 or h > radius + 0.5:
		return Vector3(-1, -1, -1)
	var vel: Vector3 = v.vel(ship)
	var tilt: float = rad_to_deg((-v.basis(ship).z).angle_to(n))
	return Vector3(maxf(-vel.dot(n), 0.0), (vel - n * vel.dot(n)).length(), tilt)


func _dock(w: SimWorld, ship: int, pad: int) -> void:
	var s: int = EntityId.slot(ship)
	w.store().flags[s] |= EntityStore.F_DOCKED
	w.store().link[s] = pad
	w.store().vel[s] = Vector3.ZERO
