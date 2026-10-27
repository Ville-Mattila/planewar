extends GdUnitTestSuite
## GD-09 tower slew (R0 B.23 A-118, B.24 A-123; sim/MODULE.md step 5): `TurretSlew.slew` (the pure law) and
## `TurretSlew.step` through a real `SimWorld`. Azimuth about the site normal, elevation about the tangent right, the
## (pitch, yaw) pair clamped on the unit norm, the commanded rate in full in its tick, truncation at the pole, `right`
## re-projected onto the tangent plane every tick (no roll, no drift over a long match), a possessed offline tower slews
## and cannot fire.

const R: float = Sphere.PLANET_RADIUS
const HZ: float = 30.0
const DT: float = 1.0 / HZ

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _turn_rad_s(def: StringName) -> float:
	for sd: StructureDef in WorldTestKit.content().structures:
		if sd.id == def:
			return deg_to_rad(float(sd.tower.get("turret_turn_dps", 0.0)))
	return 0.0


# The mount's pose at elevation `el_deg` over the east tangent direction at site `pos`: (fwd, up = n).
func _pose(pos: Vector3, el_deg: float) -> Array[Vector3]:
	var n: Vector3 = pos.normalized()
	var east: Vector3 = Sphere.tangent_frame(n).x
	var right: Vector3 = east.cross(n)
	var f: Vector3 = (Quaternion(right, deg_to_rad(el_deg)) * east).normalized()
	return [f, n]


func _horizontal(v: Vector3, n: Vector3) -> Vector3:
	return (v - n * v.dot(n)).normalized()


func test_yaw_at_60_degrees_elevation_turns_the_azimuth_by_rate_times_dt_about_n() -> void:
	var pos: Vector3 = Vector3(R, 0.0, 0.0)
	var n: Vector3 = pos.normalized()
	var rate: float = _turn_rad_s(&"autocannon_turret")
	var pose: Array[Vector3] = _pose(pos, 60.0)
	var b: Basis = TurretSlew.slew(pos, pose[0], pose[1], 0.0, 1.0, rate * DT)
	var f1: Vector3 = -b.z
	assert_float(rad_to_deg(asin(f1.dot(n)))).is_equal_approx(60.0, 0.001)                  # elevation unchanged
	var az: float = _horizontal(pose[0], n).signed_angle_to(_horizontal(f1, n), n)
	assert_float(az).is_equal_approx(rate * DT, 0.0001)                                      # +yaw: left (counter-clockwise about n)
	assert_float(az).is_greater(0.0)


func test_pitch_raises_the_muzzle_and_the_diagonal_command_moves_at_the_cap() -> void:
	var pos: Vector3 = Vector3(R, 0.0, 0.0)
	var n: Vector3 = pos.normalized()
	var step: float = _turn_rad_s(&"flak_battery") * DT
	var pose: Array[Vector3] = _pose(pos, 0.0)
	var up_only: Vector3 = -TurretSlew.slew(pos, pose[0], pose[1], 1.0, 0.0, step).z
	assert_float(asin(up_only.dot(n))).is_equal_approx(step, 0.0001)
	var diag: Vector3 = -TurretSlew.slew(pos, pose[0], pose[1], 1.0, 1.0, step).z
	var moved: float = pose[0].angle_to(diag)
	assert_float(moved).is_equal_approx(step, 0.0001)                                        # at the cap, never sqrt(2) x
	assert_float(moved).is_less(step * 1.2)
	var big: Vector3 = -TurretSlew.slew(pos, pose[0], pose[1], 5.0, -5.0, step).z           # out-of-range axes clamp too
	assert_float(pose[0].angle_to(big)).is_equal_approx(step, 0.0001)
	var none: Vector3 = -TurretSlew.slew(pos, pose[0], pose[1], 0.0, 0.0, step).z
	assert_vector(none).is_equal_approx(pose[0], Vector3(1e-6, 1e-6, 1e-6))


func _walk(ticks: int, rate: float, start_el: float) -> Dictionary:
	var pos: Vector3 = Vector3(R * 0.6, R * 0.64, R * 0.48)
	var n: Vector3 = pos.normalized()
	var pose: Array[Vector3] = _pose(pos, start_el)
	var f: Vector3 = pose[0]
	var u: Vector3 = pose[1]
	var worst_tangent: float = 0.0
	var worst_ortho: float = 0.0
	_rng.seed = 12345
	for _k: int in ticks:
		var b: Basis = TurretSlew.slew(pos, f, u, _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), rate * DT)
		f = -b.z
		u = b.y
		worst_tangent = maxf(worst_tangent, absf(b.x.dot(n)))
		worst_ortho = maxf(worst_ortho, maxf(absf(b.x.length() - 1.0), maxf(absf(b.y.length() - 1.0), maxf(absf(b.x.dot(b.y)), maxf(absf(b.x.dot(f)), absf(b.y.dot(f)))))))
		# right is the one the reprojected basis reports, and equals fwd x up
		worst_ortho = maxf(worst_ortho, (f.cross(u) - b.x).length())
	return {"tangent": worst_tangent, "ortho": worst_ortho}


func test_1000_random_slew_ticks_keep_the_basis_orthonormal_and_right_tangent() -> void:
	var r: Dictionary = _walk(1000, _turn_rad_s(&"autocannon_turret") * 8.0, 20.0)
	assert_float(float(r["tangent"])).is_less(1e-5)
	assert_float(float(r["ortho"])).is_less(1e-5)


func test_100000_random_slew_ticks_do_not_accumulate_roll() -> void:
	var r: Dictionary = _walk(100000, _turn_rad_s(&"autocannon_turret") * 8.0, -30.0)
	assert_float(float(r["tangent"])).override_failure_message("right.dot(n) drifted: %s" % str(r)).is_less_equal(1e-6)
	assert_float(float(r["ortho"])).is_less(1e-5)


func test_a_command_past_the_zenith_stops_at_the_pole() -> void:
	var pos: Vector3 = Vector3(R, 0.0, 0.0)
	var n: Vector3 = pos.normalized()
	var pose: Array[Vector3] = _pose(pos, 80.0)
	var f: Vector3 = pose[0]
	var u: Vector3 = pose[1]
	for _k: int in 40:
		var b: Basis = TurretSlew.slew(pos, f, u, 1.0, 0.0, deg_to_rad(10.0))           # 10 deg a tick: 2 ticks reach the pole
		f = -b.z
		u = b.y
		assert_float(f.dot(n)).is_less_equal(1.0 + 1e-6)
	assert_float(f.dot(n)).is_greater(1.0 - 1e-5)
	assert_bool(f.is_finite() and u.is_finite()).is_true()
	var back: Basis = TurretSlew.slew(pos, f, u, -1.0, 0.0, deg_to_rad(10.0))           # and it comes back down
	assert_float(asin(clampf((-back.z).dot(n), -1.0, 1.0))).is_equal_approx(deg_to_rad(80.0), 0.001)


func test_a_command_below_the_nadir_stops_at_the_pole_too() -> void:
	var pos: Vector3 = Vector3(R, 0.0, 0.0)
	var n: Vector3 = pos.normalized()
	var pose: Array[Vector3] = _pose(pos, -80.0)
	var f: Vector3 = pose[0]
	var u: Vector3 = pose[1]
	for _k: int in 10:
		var b: Basis = TurretSlew.slew(pos, f, u, -1.0, 0.3, deg_to_rad(10.0))
		f = -b.z
		u = b.y
	assert_float(f.dot(n)).is_less(-1.0 + 1e-5)


func test_reproject_keeps_the_previous_right_inside_the_pole_guard() -> void:
	var n: Vector3 = Vector3(1, 0, 0)
	var prev: Vector3 = Vector3(0.001, 0, 1)                                              # a little off the tangent plane
	var b: Basis = TurretSlew.reproject(n, n, prev)                                       # muzzle exactly at the pole
	assert_float(b.x.dot(n)).is_equal_approx(0.0, 1e-6)
	assert_float(b.x.length()).is_equal_approx(1.0, 1e-6)
	assert_vector(b.x).is_equal_approx(Vector3(0, 0, 1), Vector3(1e-5, 1e-5, 1e-5))


# --- through SimWorld --------------------------------------------------------------------------------------------

func _pilot(yaw: float, pitch: float, buttons: int, w: SimWorld) -> void:
	var inp: PilotInput = PilotInput.new()
	inp.yaw = yaw
	inp.pitch = pitch
	inp.buttons = buttons
	assert_int(w.apply_command(Command.pilot(0, w.tick() + 1, inp)).code).is_equal(CommandResult.Code.ACCEPTED)


func test_a_possessed_offline_tower_slews_and_cannot_fire() -> void:
	var w: SimWorld = WorldTestKit.world()
	var tw: int = WorldTestKit.spawn(w, &"autocannon_turret", 0, 0, Vector3(R, 0.0, 0.0))   # no Core, no Reactor: power 0, offline
	var s: int = EntityId.slot(tw)
	assert_int(w.apply_command(Command.possess(0, tw)).code).is_equal(CommandResult.Code.ACCEPTED)
	w.step()
	assert_int(w.view().possessor(tw)).is_equal(0)
	var f0: Vector3 = -w.view().basis(tw).z
	var ammo0: int = w.view().ammo(tw)
	var rate: float = _turn_rad_s(&"autocannon_turret")
	for _k: int in 30:
		_pilot(1.0, 0.0, PilotInput.FIRE1, w)
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	var f1: Vector3 = -w.view().basis(tw).z
	assert_float(f0.angle_to(f1)).is_equal_approx(rate, 0.01)                              # one second at the cap
	assert_int(w.view().ammo(tw)).is_equal(ammo0)                                          # offline: no round left the barrel
	assert_int(FireTestKit.fired_by(w, tw).size()).is_equal(0)
	assert_float(absf((w.view().basis(tw).x).dot(w.store().pos[s].normalized()))).is_less(1e-5)


func test_a_building_tower_does_not_slew() -> void:
	var w: SimWorld = WorldTestKit.world()
	var tw: int = WorldTestKit.spawn(w, &"autocannon_turret", 0, 0, Vector3(R, 0.0, 0.0))
	var s: int = EntityId.slot(tw)
	w.store().flags[s] = w.store().flags[s] | EntityStore.F_BUILDING
	var f0: Vector3 = w.store().fwd[s]
	var inp: PilotInput = PilotInput.new()
	inp.yaw = 1.0
	w._inputs.set_entity(s, inp)
	w.step()
	assert_vector(w.store().fwd[s]).is_equal(f0)


func test_slew_marks_the_pose_dirty_and_a_zero_command_does_not() -> void:
	var w: SimWorld = WorldTestKit.world()
	var tw: int = WorldTestKit.spawn(w, &"flak_battery", 0, 0, Vector3(R, 0.0, 0.0))
	var s: int = EntityId.slot(tw)
	w.store().dirty[s] = 0
	w.step()
	assert_int(w.store().dirty[s] & EntityStore.DIRTY_POSE).is_equal(0)
	var inp: PilotInput = PilotInput.new()
	inp.pitch = 1.0
	w._inputs.set_entity(s, inp)
	w.step()
	assert_int(w.store().dirty[s] & EntityStore.DIRTY_POSE).is_equal(EntityStore.DIRTY_POSE)
	assert_float(asin((-w.view().basis(tw).z).dot(Vector3(1, 0, 0)))).is_equal_approx(_turn_rad_s(&"flak_battery") * DT, 0.0001)
