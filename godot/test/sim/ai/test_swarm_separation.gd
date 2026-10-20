extends GdUnitTestSuite
## AI-11 swarm test (05 s5.4, s11): 50 seeds of a mixed friendly swarm (Darts, Lancers, a Bomber) launched within ~400 m
## of each other toward their own destination on shared waypoint legs (a squad MOVE: each ship's destination is the leg
## point plus its own offset within `SPREAD_M`), flown by guidance velocity + `Separation.push` (SwarmWorld). Pass: no
## overlapping friendly pair (centres closer than the bounding radii) in any seed, at any tick.
## Start states are fair: ships point at their own first destination and no pair starts on a collision course
## (`MIN_START_GAP_M` now and at the closest approach within `START_HORIZON_S`). The stress variant sends every ship to
## the very same points (spread 0); the PR reports how often that still clips.

const SEEDS: int = 50
const TICKS: int = 30 * 40
const SPREAD_M: float = 250.0
const MIN_START_GAP_M: float = 60.0
const START_HORIZON_S: float = 4.0
const ARRIVE_M: float = 150.0
const FLIGHT_LEVEL_M: float = 300.0
const CLASSES: Array[StringName] = [&"dart", &"dart", &"dart", &"dart", &"dart", &"dart", &"lancer", &"lancer", &"lancer",
	&"dart", &"bomber", &"lancer"]


## Shared legs: ~1.2 km apart along the equator with a random lateral swing of up to 600 m.
func _legs(rng: RandomNumberGenerator) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var lon: float = 0.0
	for _k: int in 6:
		lon += 1200.0 / Sphere.PLANET_RADIUS
		var lat: float = rng.randf_range(-0.1, 0.1)
		var _b: bool = out.push_back(Vector3(cos(lon) * cos(lat), sin(lon) * cos(lat), sin(lat)) * (Sphere.PLANET_RADIUS + FLIGHT_LEVEL_M))
	return out


func _offset(rng: RandomNumberGenerator, at: Vector3, spread: float) -> Vector3:
	var up: Vector3 = at.normalized()
	var a: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	return (a - up * a.dot(up)).normalized() * spread * sqrt(rng.randf())


## A fair start for a ship of `def` heading for `dest`: inside the launch box, no collision course with the placed ships.
func _free_start(w: SwarmWorld, def: ShipDef, dest: Vector3, rng: RandomNumberGenerator) -> Array[Vector3]:
	while true:
		var p: Vector3 = Vector3(Sphere.PLANET_RADIUS + FLIGHT_LEVEL_M + rng.randf_range(-30.0, 30.0),
			rng.randf_range(-200.0, 200.0), rng.randf_range(-200.0, 200.0))
		var up: Vector3 = p.normalized()
		var to: Vector3 = dest - p
		var v: Vector3 = (to - up * to.dot(up)).normalized() * rng.randf_range(0.7, 1.0) * def.v_cruise
		var clear: bool = true
		for s: ShipState in w.ss:
			clear = clear and _gap_ok(p - s.p, v - s.v)
		if clear:
			return [p, v]
	return [Vector3.ZERO, Vector3.ZERO]


func _gap_ok(d: Vector3, vr: Vector3) -> bool:
	if d.length() < MIN_START_GAP_M:
		return false
	var t: float = clampf(-d.dot(vr) / maxf(vr.length_squared(), 0.01), 0.0, START_HORIZON_S)
	return (d + vr * t).length() >= MIN_START_GAP_M


## One seed: returns the world after TICKS (collisions counted every tick). `gain` >= 0 overrides `sep_gain`.
func _fly(sv: int, spread: float, gain: float = -1.0) -> SwarmWorld:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5000 + sv
	var w: SwarmWorld = SwarmWorld.new(FlightTestKit.common(), FormationKit.content().rules, FormationKit.params())
	if gain >= 0.0:
		w.prm.sep_gain = gain
	var legs: PackedVector3Array = _legs(rng)
	var offs: PackedVector3Array = PackedVector3Array()
	for cls: StringName in CLASSES:
		var def: ShipDef = FormationKit.ship(cls)
		var off: Vector3 = _offset(rng, legs[0], spread)
		var ps: Array[Vector3] = _free_start(w, def, legs[0] + off, rng)
		var s: ShipState = FlightTestKit.spawn(def, ps[0], ps[1].normalized(), ps[0].normalized(), ps[1])
		var _id: int = w.add_ship(def, FormationKit.gains(cls), s)
		var _o: bool = offs.push_back(off)
	for t: int in TICKS:
		if t % w.think_period == 0:
			for i: int in w.ids.size():
				while w.ss[i].p.distance_to(legs[w.leg[i] % legs.size()] + offs[i]) < ARRIVE_M:
					w.leg[i] += 1
				w.waypoint[i] = legs[w.leg[i] % legs.size()] + offs[i]
				w.think(i, w.defs[i].v_cruise)
			w.thinks += 1
		for i: int in w.ids.size():
			w.act_and_step(i)
		w.now += 1
		w.check_collisions()
	return w


func _count(spread: float, seeds: int, gain: float = -1.0) -> Array[int]:
	var bad: Array[int] = []
	for sv: int in seeds:
		if _fly(sv, spread, gain).collisions > 0:
			bad.append(sv)
	return bad


func test_zero_friendly_collisions_in_50_seeds() -> void:
	var worst: float = INF
	var bad: Array[int] = []
	for sv: int in SEEDS:
		var w: SwarmWorld = _fly(sv, SPREAD_M)
		worst = minf(worst, w.min_gap)
		if w.collisions > 0:
			bad.append(sv)
			print("seed %d first collision at tick %d: %s" % [sv, w.first_collision_tick, w.first_info])
	var what: String = "swarm: closest friendly gap %.1f m over %d seeds; seeds with a collision %s" % [worst, SEEDS, str(bad)]
	print(what)
	assert_array(bad).override_failure_message(what).is_empty()
	assert_float(worst).override_failure_message(what).is_greater(0.0)


## Control: the same swarm without separation does collide, so the test can fail.
func test_swarm_without_separation_collides() -> void:
	var bad: Array[int] = _count(SPREAD_M, 20, 0.0)
	print("swarm control without separation: %d of 20 seeds collide" % bad.size())
	assert_int(bad.size()).is_greater(0)


## Stress: every ship to the very same points. Separation must cut the collisions to a minority of what no separation gives.
func test_same_destination_stress_is_better_with_separation() -> void:
	var with_sep: Array[int] = _count(0.0, 30)
	var without: Array[int] = _count(0.0, 30, 0.0)
	print("swarm stress (same destinations): %d of 30 seeds collide with separation, %d without" % [with_sep.size(), without.size()])
	assert_int(with_sep.size()).is_less(without.size())
