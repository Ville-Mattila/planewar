extends GdUnitTestSuite
## 05 s11.2 landing scenarios SC-02..SC-08 (AI-09) on the flat datum (SC-05: a synthetic crater): LandingPilot
## (sim_ai) driving LandingController (sim/steer) through LandingScenario over a LandingWorld (R0 B.5 landing rule
## every tick in the pad volume, A-31). Every touchdown must meet R0 B.5 with the thrust axis within 10 degrees of
## the pad normal (05 AI-09). The world has no docking service yet (GD-15): a docked ship leaves after
## `service_ticks`.

const PAD_LAT: float = 40.0
const PAD_LON: float = 22.5
const TILT_MAX_DEG: float = 10.0
const R: float = Sphere.PLANET_RADIUS


static func pad_dir() -> Vector3:
	return Ai05Kit.geo(PAD_LAT, PAD_LON)


## The point `dist` m from `center` (unit) on bearing `az_deg` (0 = north, 90 = east) at `agl` m above the datum
## plus `ground`.
static func at(center: Vector3, dist: float, az_deg: float, agl: float, ground: float = 0.0) -> Vector3:
	var f: Basis = Sphere.tangent_frame(center)
	var az: float = deg_to_rad(az_deg)
	var b: Vector3 = f.y * cos(az) + f.x * sin(az)
	var d: Vector3 = center * cos(dist / R) + b * sin(dist / R)
	return d * (R + ground + agl)


## Unit tangent at `p` toward `to` rotated by `off_deg` about the local up.
static func heading(p: Vector3, to: Vector3, off_deg: float = 0.0) -> Vector3:
	var n: Vector3 = p.normalized()
	var t: Vector3 = (to - n * to.dot(n)).normalized()
	return t.rotated(n, deg_to_rad(off_deg))


func _touchdown_ok(sc: LandingScenario, i: int, what: String, vz_max: float = -1.0, vh_max: float = -1.0) -> void:
	var td: Vector4 = sc.world.touchdown[i]
	var c: FlightCommonDef = sc.world.common
	assert_int(sc.world.outcome[i]).override_failure_message(what).is_equal(LandingWorld.Outcome.LANDED)
	assert_int(sc.world.scrapes[i]).override_failure_message(what).is_equal(0)   # A-70: no terrain contact
	assert_float(td.x).override_failure_message(what).is_less_equal(vz_max if vz_max > 0.0 else c.landing_safe_v_vert)
	assert_float(td.y).override_failure_message(what).is_less_equal(vh_max if vh_max > 0.0 else c.landing_safe_v_hor)
	assert_float(td.z).override_failure_message(what).is_less_equal(TILT_MAX_DEG)


func _describe(sc: LandingScenario, i: int) -> String:
	return "outcome %d td %s gate->dock %.1f s go-arounds %d aborts [%s] hold %d ticks scrapes %d fuel %.2f" % [
		sc.world.outcome[i], sc.world.touchdown[i], sc.gate_to_dock_s(i), sc.go_arounds[i], ", ".join(sc.abort_log),
		sc.hold_ticks[i], sc.world.scrapes[i], sc.world.ss[i].fuel / sc.world.defs[i].fuel_s]


const MODELS: Array[StringName] = [RulesDef.LIFT_SPEED_SCALED, RulesDef.LIFT_DAMPING_ONLY]


## Asserted under the default lift model; the damping_only A/B variant is run and reported only (as AI-05's
## SC-09 / SC-10: FlightController's path tracking lags under damping_only, AI-05 PR).
static func asserted(model: StringName) -> bool:
	return model == RulesDef.LIFT_SPEED_SCALED


# SC-02 rtb_low_fuel: Dart 2,000 m from the pad at 24 % fuel. RETURN within 1 think; DOCKED within 90 s;
# touchdown sink <= 3 m/s, horizontal <= 5 m/s, thrust axis within 10 degrees of the pad normal.
func test_sc02_rtb_low_fuel() -> void:
	for model: StringName in MODELS:
		var sc: LandingScenario = LandingScenario.new(Terrain.new(), model)
		var pad: int = sc.world.add_pad(pad_dir())
		var p: Vector3 = at(pad_dir(), 2000.0, 200.0, 300.0)
		var dart: ShipDef = FlightTestKit.ship(&"dart")
		var _id: int = sc.add_ship(&"dart", p, heading(p, pad_dir(), 90.0), dart.v_cruise, pad, false)
		sc.world.ss[0].fuel = 0.24 * dart.fuel_s
		var ok: bool = sc.run(90 * 30)
		var what: String = "SC-02 %s: %s" % [model, _describe(sc, 0)]
		print(what)
		if not asserted(model):
			continue
		assert_int(sc.return_tick[0]).override_failure_message(what).is_between(0, sc.think_period)
		assert_bool(ok).override_failure_message(what).is_true()
		_touchdown_ok(sc, 0, what, 3.0, 5.0)


# SC-03 rtb_far_fuel_margin: Dart 9 km from the only pad at 30 % fuel. RETURN starts above 25 % (the distance
# term of the RTB rule); docks with fuel > 0.
func test_sc03_rtb_far_fuel_margin() -> void:
	for model: StringName in MODELS:
		var sc: LandingScenario = LandingScenario.new(Terrain.new(), model)
		var pad: int = sc.world.add_pad(pad_dir())
		var p: Vector3 = at(pad_dir(), 9000.0, 300.0, 300.0)
		var dart: ShipDef = FlightTestKit.ship(&"dart")
		var _id: int = sc.add_ship(&"dart", p, heading(p, pad_dir(), 120.0), dart.v_cruise, pad, false)
		sc.world.ss[0].fuel = 0.30 * dart.fuel_s
		var ok: bool = sc.run(240 * 30)
		var what: String = "SC-03 %s: return at tick %d, %s" % [model, sc.return_tick[0], _describe(sc, 0)]
		print(what)
		if not asserted(model):
			continue
		assert_int(sc.return_tick[0]).override_failure_message(what).is_between(0, sc.think_period)
		assert_bool(ok).override_failure_message(what).is_true()
		assert_float(sc.world.ss[0].fuel).override_failure_message(what).is_greater(0.0)
		_touchdown_ok(sc, 0, what)


# SC-04 landing_100_seeds: Dart RETURN from random positions 2-4 km out (random bearing, heading, 150-450 m),
# 100 seeds. >= 99 docks without damage; median gate-to-dock <= 35 s; at most 1 go-around per landing (flat pad); a
# terrain contact counts as a failed landing (R0 B.12 A-70).
func test_sc04_landing_100_seeds() -> void:
	for model: StringName in MODELS:
		var rng: Rng = Rng.new(904)
		var docked: int = 0
		var times: PackedFloat32Array = PackedFloat32Array()
		var max_ga: int = 0
		var worst: Vector4 = Vector4.ZERO
		var fails: PackedStringArray = PackedStringArray()
		var n: int = 100 if asserted(model) else 25
		for k: int in n:
			var sc: LandingScenario = LandingScenario.new(Terrain.new(), model)
			var pad: int = sc.world.add_pad(pad_dir())
			var p: Vector3 = at(pad_dir(), rng.range_f(2000.0, 4000.0), rng.range_f(0.0, 360.0), rng.range_f(150.0, 450.0))
			var dart: ShipDef = FlightTestKit.ship(&"dart")
			var _id: int = sc.add_ship(&"dart", p, heading(p, pad_dir(), rng.range_f(-180.0, 180.0)), dart.v_cruise,
				pad, true)
			var _ok: bool = sc.run(180 * 30)
			max_ga = maxi(max_ga, sc.go_arounds[0])
			var td: Vector4 = sc.world.touchdown[0]
			# A-70: any terrain contact (scrape) before the dock is a failed landing
			if sc.world.outcome[0] == LandingWorld.Outcome.LANDED and td.z <= TILT_MAX_DEG and sc.world.scrapes[0] == 0:
				docked += 1
				var _b: bool = times.push_back(sc.gate_to_dock_s(0))
				worst = Vector4(maxf(worst.x, td.x), maxf(worst.y, td.y), maxf(worst.z, td.z), maxf(worst.w, td.w))
			else:
				var _c: bool = fails.push_back("seed %d: %s" % [k, _describe(sc, 0)])
		times.sort()
		var median: float = times[times.size() / 2] if not times.is_empty() else INF
		var what: String = "SC-04 %s: docked %d/%d median gate->dock %.1f s (max %.1f) max go-arounds %d worst td %s; %s" % [
			model, docked, n, median, times[times.size() - 1] if not times.is_empty() else INF, max_ga, worst,
			"; ".join(fails)]
		print(what)
		if not asserted(model):
			continue
		assert_int(docked).override_failure_message(what).is_greater_equal(99)
		assert_float(median).override_failure_message(what).is_less_equal(35.0)
		assert_int(max_ga).override_failure_message(what).is_less_equal(1)


## SC-05 terrain: a crater of radius `crater_r` (rim crest) around `center`, flat floor at 0 m, a triangular rim
## `rim_h` high and `rim_w` wide on each side of the crest, flat outside.
class CraterTerrain extends Terrain:
	var center: Vector3 = Vector3.RIGHT
	var crater_r: float = 900.0
	var rim_h: float = 150.0
	var rim_w: float = 250.0

	func height_at(dir: Vector3) -> float:
		var r: float = center.angle_to(dir) * Sphere.PLANET_RADIUS
		return rim_h * maxf(0.0, 1.0 - absf(r - crater_r) / rim_w)

	func normal_at(dir: Vector3) -> Vector3:   # radial; contacts only matter as counts here
		return dir.normalized()


# SC-05 landing_crater_rim_pad: pad 300 m inside a crater rim 150 m high (crest 900 m from the crater centre, pad
# 600 m from it); the Dart comes from outside, across the rim. Docks in <= 2 attempts; the approach line (the
# chosen bearing, flown established in L2 and L4) never crosses the rim below 60 m clearance: every such tick over
# the rim band the ship is >= 60 m above the terrain, and the line itself (bearing choice) clears the rim by 60 m
# at the glide height. Elsewhere the ship flies under the terrain lift (h_req, 05 s5.3); that minimum is printed.
func test_sc05_landing_crater_rim_pad() -> void:
	for model: StringName in MODELS:
		var crater: CraterTerrain = CraterTerrain.new()
		crater.center = pad_dir()
		var pd: Vector3 = at(pad_dir(), crater.crater_r - 300.0, 0.0, 0.0).normalized()
		var sc: LandingScenario = LandingScenario.new(crater, model)
		var pad: int = sc.world.add_pad(pd)
		var p: Vector3 = at(pd, 3000.0, 10.0, 300.0)
		var _id: int = sc.add_ship(&"dart", p, heading(p, pd), 110.0, pad, true)
		var rim_min: Array[float] = [INF, INF]   # on the approach line, anywhere
		var line_short: Array[float] = [-INF]
		sc.on_tick = func(s: LandingScenario, _t: int) -> void:
			var q: Vector3 = s.world.ss[0].p
			var r: float = crater.center.angle_to(q) * R
			if absf(r - crater.crater_r) >= crater.rim_w:
				return
			var c: float = q.length() - R - crater.height_at(q) - s.world.defs[0].bounding_radius
			rim_min[1] = minf(rim_min[1], c)
			var sl: int = EntityId.slot(s.world.ids[0])
			var ph: int = s.phase(0)
			var b: Vector3 = s.st.land_bearing[sl]
			var pp: Vector3 = s.world.pos(pad)
			var along: float = (q.normalized() - pp.normalized()).dot(b) * R
			if (ph == LandingController.Phase.APPROACH or ph >= LandingController.Phase.TRANSITION) and along > 0.0 					and s.world.vel(s.world.ids[0]).dot(pp - q) > 0.0:
				rim_min[0] = minf(rim_min[0], c)
		var ok: bool = sc.run(180 * 30)
		var b: Vector3 = sc.st.land_bearing[EntityId.slot(sc.world.ids[0])]
		for j: int in 96:   # the chosen line, transition to gate, at the glide height, where it is over the rim
			var d: float = 250.0 + 950.0 * float(j + 1) / 96.0
			var dir: Vector3 = pd * cos(d / R) + b * sin(d / R)
			if absf(crater.center.angle_to(dir) * R - crater.crater_r) < crater.rim_w:
				line_short[0] = maxf(line_short[0], crater.height_at(dir) + 60.0 - d * tan(deg_to_rad(8.0)))
		var what: String = "SC-05 %s: rim clearance on the line %.1f m, anywhere %.1f m, line shortfall %.1f m, %s" % [
			model, rim_min[0], rim_min[1], line_short[0], _describe(sc, 0)]
		print(what)
		if not asserted(model):
			continue
		assert_bool(ok).override_failure_message(what).is_true()
		assert_int(sc.go_arounds[0]).override_failure_message(what).is_less_equal(1)
		assert_float(rim_min[0]).override_failure_message(what).is_greater_equal(60.0)
		assert_float(line_short[0]).override_failure_message(what).is_less_equal(0.0)
		_touchdown_ok(sc, 0, what)


# SC-06 landing_busy_pad_hold: 2 Darts RETURN to one pad 1 s apart. The second holds in orbit and docks after the
# first is serviced (service 20 s here, GD-15 stand-in); no collision (separation > both bounding radii + 10 m).
func test_sc06_landing_busy_pad_hold() -> void:
	for model: StringName in MODELS:
		var sc: LandingScenario = LandingScenario.new(Terrain.new(), model)
		sc.world.service_ticks = 20 * 30
		var pad: int = sc.world.add_pad(pad_dir())
		var p0: Vector3 = at(pad_dir(), 2000.0, 90.0, 300.0)
		var p1: Vector3 = at(pad_dir(), 2110.0, 92.0, 300.0)
		var _a: int = sc.add_ship(&"dart", p0, heading(p0, pad_dir()), 110.0, pad, true)
		var _b: int = sc.add_ship(&"dart", p1, heading(p1, pad_dir()), 110.0, pad, false)
		sc.on_tick = func(s: LandingScenario, t: int) -> void:
			if t == 30:
				s.start_return(1, pad)
		var ok: bool = sc.run(240 * 30)
		var dart: ShipDef = FlightTestKit.ship(&"dart")
		var what: String = "SC-06 %s: sep %.1f m, first %s | second %s, docked t %d / %d" % [model, sc.min_sep_m,
			_describe(sc, 0), _describe(sc, 1), sc.world.dock_tick[0], sc.world.dock_tick[1]]
		print(what)
		if not asserted(model):
			continue
		assert_bool(ok).override_failure_message(what).is_true()
		assert_int(sc.hold_ticks[1]).override_failure_message(what).is_greater(0)
		assert_int(sc.world.dock_tick[1]).override_failure_message(what).is_greater_equal(
			sc.world.dock_tick[0] + sc.world.service_ticks)
		assert_float(sc.min_sep_m).override_failure_message(what).is_greater(2.0 * dart.bounding_radius + 10.0)
		_touchdown_ok(sc, 0, what)
		_touchdown_ok(sc, 1, what)


# SC-07 landing_pad_destroyed_divert: Dart in L5 hover; the pad is destroyed by script. Aborts within 3 ticks
# (PAD_INVALID); selects the other pad (1,500 m away); docks there.
func test_sc07_landing_pad_destroyed_divert() -> void:
	for model: StringName in MODELS:
		var sc: LandingScenario = LandingScenario.new(Terrain.new(), model)
		var pad_a: int = sc.world.add_pad(pad_dir())
		var pad_b: int = sc.world.add_pad(at(pad_dir(), 1500.0, 135.0, 0.0).normalized())
		var p: Vector3 = at(pad_dir(), 2000.0, 300.0, 300.0)
		var _id: int = sc.add_ship(&"dart", p, heading(p, pad_dir()), 110.0, pad_a, true)
		var killed: Array[int] = [-1]
		sc.on_tick = func(s: LandingScenario, t: int) -> void:
			if killed[0] < 0 and s.phase(0) == LandingController.Phase.HOVER:
				s.world.pad_alive[s.world.pad_index(pad_a)] = 0
				killed[0] = t
		var ok: bool = sc.run(240 * 30)
		var first: PackedStringArray = sc.abort_log[0].split(" ") if not sc.abort_log.is_empty() else PackedStringArray()
		var what: String = "SC-07 %s: pad killed at %d, %s" % [model, killed[0], _describe(sc, 0)]
		print(what)
		if not asserted(model):
			continue
		assert_int(killed[0]).override_failure_message(what).is_greater(0)
		assert_int(first.size()).override_failure_message(what).is_equal(3)
		if first.size() == 3:
			assert_int(int(first[1]) - killed[0]).override_failure_message(what).is_less_equal(3)
			assert_int(int(first[2])).override_failure_message(what).is_equal(LandingController.Abort.PAD_INVALID)
		assert_bool(ok).override_failure_message(what).is_true()
		assert_int(sc.world.dock_pad[0]).override_failure_message(what).is_equal(pad_b)
		_touchdown_ok(sc, 0, what)


# SC-08 go_around_on_drift: a 25 m lateral offset injected in L5 below the abort height. L3 go-around
# (HORIZ_ERR); the second attempt succeeds.
func test_sc08_go_around_on_drift() -> void:
	for model: StringName in MODELS:
		var sc: LandingScenario = LandingScenario.new(Terrain.new(), model)
		var pad: int = sc.world.add_pad(pad_dir())
		var p: Vector3 = at(pad_dir(), 2500.0, 45.0, 300.0)
		var _id: int = sc.add_ship(&"dart", p, heading(p, pad_dir()), 110.0, pad, true)
		var pushed: Array[int] = [-1]
		sc.on_tick = func(s: LandingScenario, t: int) -> void:
			var q: ShipState = s.world.ss[0]
			var h: float = q.p.length() - R - s.world.defs[0].bounding_radius
			if pushed[0] < 0 and s.phase(0) == LandingController.Phase.HOVER and h < 14.0:
				var f: Basis = Sphere.tangent_frame(q.p.normalized())
				q.p += f.x * 25.0
				pushed[0] = t
		var ok: bool = sc.run(240 * 30)
		var what: String = "SC-08 %s: pushed at %d, %s" % [model, pushed[0], _describe(sc, 0)]
		print(what)
		if not asserted(model):
			continue
		assert_int(pushed[0]).override_failure_message(what).is_greater(0)
		assert_int(sc.go_arounds[0]).override_failure_message(what).is_equal(1)
		if not sc.abort_log.is_empty():
			assert_str(sc.abort_log[0].split(" ")[2]).override_failure_message(what).is_equal(
				str(LandingController.Abort.HORIZ_ERR))
		assert_bool(ok).override_failure_message(what).is_true()
		_touchdown_ok(sc, 0, what)
