extends GdUnitTestSuite
## AI-18b measurement for GD-34 (R0 B.31 A-151, A-155): the highest barrel elevation at which a siege shell still reaches
## the ground inside `siege_shell.lifetime_s`, on the flat datum and on cradle relief, and what happens above it. The
## ceiling is bisected on `Ballistics.predict_impact` at the sim's own step (one tick, as many steps as the shell lives),
## then confirmed in the sim: a shell fired 0.1 deg under it lands (Collision GROUND), one fired 0.1 deg over it ends in
## the air at its lifetime with no contact (no blast, no damage: `ProjectileMotion` frees it). Spread off.

const HZ: int = 30
const MARGIN_DEG: float = 0.1
const HEADINGS: int = 4


func _shell() -> ProjectileDef:
	return BarrelTestKit.shell()


# True when a shell fired by the Crawler in slot `s` at elevation `e` hits the ground inside its lifetime (predicted).
func _lands(w: SimWorld, s: int, e: float) -> bool:
	var p: Vector3 = w.store().pos[s]
	var dir: Vector3 = BarrelSlew.muzzle_dir(p, w.store().fwd[s], e)
	var steps: int = floori(_shell().lifetime_s * float(HZ))
	var dt: float = 1.0 / float(HZ)
	var r: Vector4 = Ballistics.predict_impact(p + dir * w.store().radius[s], dir * _shell().speed_mps, _shell(),
		WorldTestKit.content().rules, w.terrain(), dt, dt, 0.0, steps, ProjectileState.new())
	return Ballistics.has_impact(r)


# Bisection between 0 (lands) and the barrel's 45 deg (does not on the datum) for the highest elevation that lands.
func _ceiling(w: SimWorld, s: int) -> float:
	var lo: float = 0.0
	var hi: float = deg_to_rad(45.0)
	if _lands(w, s, hi):
		return hi
	for _i: int in 30:
		var mid: float = 0.5 * (lo + hi)
		if _lands(w, s, mid):
			lo = mid
		else:
			hi = mid
	return lo


# The sim's own answer at elevation `e`: [landed, reach m, flight ticks].
func _fire(w: SimWorld, id: int, e: float) -> Array:
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, false)
	var _k: int = BarrelTestKit.slew_to(w, p, e, BarrelTestKit.rate())
	var shot: BarrelTestKit.Shot = BarrelTestKit.fire_one(w, p)
	var n: Vector3 = w.store().pos[EntityId.slot(id)].normalized()
	return [shot.landed, n.angle_to(shot.impact) * Sphere.PLANET_RADIUS if shot.landed else 0.0, shot.ticks]


# One spot and heading: the predicted ceiling, then the sim under and over it.
func _measure(map_id: StringName, dir: Vector3, turn: float) -> Array:
	var c: ContentSet = BarrelTestKit.no_spread_content()
	var out: Array = []
	for over: bool in [false, true]:
		var w: SimWorld = BarrelTestKit.world(c, map_id)
		var id: int = BarrelTestKit.crawler(w, dir)
		var s: int = EntityId.slot(id)
		var n: Vector3 = w.store().pos[s].normalized()
		w.store().fwd[s] = Quaternion(n, turn) * w.store().fwd[s]
		var top: float = _ceiling(w, s)
		var e: float = top + deg_to_rad(MARGIN_DEG if over else -MARGIN_DEG)
		var r: Array = _fire(w, id, e)
		out.append_array([rad_to_deg(top), r[0], r[1], r[2]])
	return out


func test_flat_datum_ceiling_is_about_19_degrees_and_a_higher_shell_ends_in_the_air() -> void:
	var r: Array = _measure(&"", Vector3(1, 0, 0), 0.0)
	assert_float(float(r[0])).is_between(18.5, 20.5)                       # arithmetic (A-151): asin(12 x 6 / 220) = 19.1
	assert_bool(bool(r[1])).is_true()                                       # under: lands
	assert_bool(bool(r[5])).is_false()                                      # over: no contact, freed at its lifetime
	assert_int(int(r[7])).is_equal(0)
	print("AI-18b ceiling, flat datum: %.2f deg; at -0.1 deg the shell lands %.0f m out after %d ticks; at +0.1 deg it ends in the air at %.0f s with no contact" % [
		float(r[0]), float(r[2]), int(r[3]), _shell().lifetime_s])


func test_cradle_ceiling_per_heading() -> void:
	var lines: PackedStringArray = PackedStringArray()
	var lo: float = INF
	var hi: float = -INF
	for k: int in HEADINGS:
		var turn: float = TAU * float(k) / float(HEADINGS)
		var r: Array = _measure(&"cradle", Sphere.from_lat_lon(0.1, 0.2, 1.0), turn)
		assert_bool(bool(r[1])).is_true()
		assert_bool(bool(r[5])).is_false()
		lo = minf(lo, float(r[0]))
		hi = maxf(hi, float(r[0]))
		var _a: bool = lines.push_back("heading +%d deg: %.2f deg (lands %.0f m out)" % [roundi(rad_to_deg(turn)), float(r[0]),
			float(r[2])])
	assert_float(lo).is_greater(10.0)
	print("AI-18b ceiling, cradle (lat 0.1, lon 0.2): %.2f-%.2f deg; %s" % [lo, hi, ", ".join(lines)])
