extends GdUnitTestSuite
## Unit tests for sim/steer/terrain_probe.gd (AI-07; 05 s5.3): TTI against closed-form cases over flat and sloped
## synthetic terrain, a triangular ridge against a dense reference, min clearance over the cradle crater rims
## against an independent Quaternion-based path, lift sanity, purity and determinism. Acceptance: TTI error < 0.1 s.

const MAP_CRADLE: String = "res://content/maps/cradle"
const TTI_TOL: float = 0.1
const R: float = Sphere.PLANET_RADIUS


## Analytic terrain: height = slope * R * (angle from `origin`), capped at `cap`; a negative `ridge_w` selects a
## triangular ridge of height `cap` centred `ridge_at` radians from `origin` with half-width `ridge_w` instead.
class SynTerrain extends Terrain:
	var origin: Vector3 = Vector3.RIGHT
	var slope: float = 0.0
	var ridge_h: float = 0.0
	var ridge_at: float = 0.0
	var ridge_w: float = 1.0

	func height_at(dir: Vector3) -> float:
		var a: float = origin.angle_to(dir.normalized())
		if ridge_h > 0.0:
			return ridge_h * maxf(0.0, 1.0 - absf(a - ridge_at) / ridge_w)
		return slope * R * a


func _probe() -> ProbeParams:
	return ProbeParams.make(25.0, 0.25, PackedFloat32Array([0.5, 1.0, 1.5, 2.0, 3.0, 4.0]), 6.0, 0.6, 0.5)


## Ship over `origin` at altitude `alt`, moving along +Y (tangent) at `ground` m/s with vertical speed `vr`.
func _ship(alt: float, ground: float, vr: float) -> Array[Vector3]:
	var n: Vector3 = Vector3.RIGHT
	return [n * (R + alt), Vector3(0.0, ground, 0.0) + n * vr]


# region flat and sloped closed forms
func test_flat_descent_matches_quadratic() -> void:
	var s: Array[Vector3] = _ship(100.0, 100.0, -40.0)
	var tti: float = TerrainProbe.time_to_impact(Terrain.new(), s[0], s[1], _probe())
	var exact: float = (-40.0 + sqrt(40.0 * 40.0 + 4.0 * 3.0 * 100.0)) / 6.0   # 3 t^2 + 40 t - 100 = 0
	assert_float(tti).is_between(exact - TTI_TOL, exact + TTI_TOL)


func test_flat_level_flight_falls_by_gravity() -> void:
	var s: Array[Vector3] = _ship(40.0, 100.0, 0.0)
	var tti: float = TerrainProbe.time_to_impact(Terrain.new(), s[0], s[1], _probe())
	assert_float(tti).is_between(sqrt(40.0 / 3.0) - TTI_TOL, sqrt(40.0 / 3.0) + TTI_TOL)


func test_flat_climbing_is_clear_and_infinite() -> void:
	var s: Array[Vector3] = _ship(100.0, 100.0, 30.0)
	assert_float(TerrainProbe.time_to_impact(Terrain.new(), s[0], s[1], _probe())).is_equal(INF)


func test_at_or_below_surface_is_zero() -> void:
	var s: Array[Vector3] = _ship(0.0, 100.0, 0.0)
	assert_float(TerrainProbe.time_to_impact(Terrain.new(), s[0], s[1], _probe())).is_equal(0.0)
	s = _ship(-5.0, 100.0, 0.0)
	assert_float(TerrainProbe.time_to_impact(Terrain.new(), s[0], s[1], _probe())).is_equal(0.0)


func test_sloped_terrain_matches_quadratic() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.slope = 0.2
	for ground: float in [80.0, 150.0, 200.0]:
		var s: Array[Vector3] = _ship(40.0, ground, 0.0)
		var r0: float = R + 40.0
		# r0 - 3 t^2 - R = slope * R * ground * t / r0
		var b: float = t.slope * R * ground / r0
		var exact: float = (-b + sqrt(b * b + 4.0 * 3.0 * 40.0)) / 6.0
		var tti: float = TerrainProbe.time_to_impact(t, s[0], s[1], _probe())
		assert_float(tti).is_between(exact - TTI_TOL, exact + TTI_TOL)


func test_ridge_tti_against_dense_reference() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.ridge_h = 700.0
	t.ridge_w = 600.0 / R
	t.ridge_at = 900.0 / R
	for alt: float in [200.0, 350.0, 500.0, 650.0]:
		var s: Array[Vector3] = _ship(alt, 160.0, 0.0)
		var tti: float = TerrainProbe.time_to_impact(t, s[0], s[1], _probe())
		var ref: float = _dense_tti(t, s[0], s[1], 6.0, 4.0)
		if is_inf(ref):
			assert_float(tti).is_equal(INF)
		else:
			assert_float(tti).is_between(ref - TTI_TOL, ref + TTI_TOL)


func test_vertical_and_stationary_ship_stay_over_one_point() -> void:
	var s: Array[Vector3] = _ship(50.0, 0.0, -20.0)
	var tti: float = TerrainProbe.time_to_impact(Terrain.new(), s[0], s[1], _probe())
	assert_float(tti).is_between(1.837, 2.037)   # 3 t^2 + 20 t - 50 = 0 -> 1.937 s
	assert_float(TerrainProbe.time_to_impact(Terrain.new(), s[0], Vector3.ZERO, _probe())).is_equal(INF)
# endregion


# region clearance and lift
func test_min_clearance_reports_worst_sample_and_time() -> void:
	var s: Array[Vector3] = _ship(100.0, 100.0, -20.0)
	var w: Vector2 = TerrainProbe.min_clearance(Terrain.new(), s[0], s[1], _probe())
	assert_float(w.y).is_equal(4.0)   # monotone descent: the last sample is the lowest
	assert_float(w.x).is_equal_approx(100.0 - 80.0 - 48.0, 0.05)


func test_lift_zero_when_clear_and_positive_when_low() -> void:
	var hi: Array[Vector3] = _ship(500.0, 100.0, 0.0)
	var lo: Array[Vector3] = _ship(40.0, 100.0, 0.0)
	var p: ProbeParams = _probe()
	var h_req: float = p.required_clearance(100.0)
	assert_float(h_req).is_equal(50.0)
	assert_float(TerrainProbe.terrain_lift(Terrain.new(), hi[0], hi[1], p, h_req)).is_equal(0.0)
	assert_float(TerrainProbe.terrain_lift(Terrain.new(), lo[0], lo[1], p, h_req)).is_greater(0.0)


func test_lift_formula_and_cap() -> void:
	var p: ProbeParams = _probe()
	var s: Array[Vector3] = _ship(100.0, 100.0, 0.0)
	# worst sample t = 4: c = 100 - 48 = 52; h_req 80 -> (80 - 52) / 4 = 7 m/s
	assert_float(TerrainProbe.terrain_lift(Terrain.new(), s[0], s[1], p, 80.0)).is_equal_approx(7.0, 0.05)
	# huge deficiency: capped at 0.6 u
	assert_float(TerrainProbe.terrain_lift(Terrain.new(), s[0], s[1], p, 5000.0)).is_equal_approx(0.6 * 100.0, 0.01)


func test_lift_uses_time_floor() -> void:
	var p: ProbeParams = ProbeParams.make(25.0, 0.25, PackedFloat32Array([0.1]), 6.0, 0.6, 0.5)
	var s: Array[Vector3] = _ship(10.0, 100.0, 0.0)
	# c(0.1) = 10 - 0.03; deficiency 20.03 / max(0.1, 0.5) = 40.06 (below the 60 cap)
	assert_float(TerrainProbe.terrain_lift(Terrain.new(), s[0], s[1], p, 30.0)).is_equal_approx(20.03 / 0.5, 0.05)


func test_lift_on_ridge_raises_with_clearance_deficit() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.ridge_h = 300.0
	t.ridge_w = 500.0 / R
	t.ridge_at = 600.0 / R
	var s: Array[Vector3] = _ship(280.0, 160.0, 0.0)
	var p: ProbeParams = _probe()
	var lift: float = TerrainProbe.terrain_lift(t, s[0], s[1], p, p.required_clearance(160.0))
	assert_float(lift).is_greater(10.0)
	assert_float(lift).is_less_equal(0.6 * 160.0)
# endregion


# region cradle crater rims
func _cradle() -> Terrain:
	var t: Terrain = Terrain.new()
	assert_int(t.load_map(MAP_CRADLE)).is_equal(OK)
	return t


func _crater_centre() -> Vector3:
	var f: FileAccess = FileAccess.open(MAP_CRADLE + "/features.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for ft: Dictionary in d["named_features"]:
		if ft["type"] == "crater" and ft["radius_m"] >= 1200.0:
			var a: Array = ft["dir"]
			return Vector3(a[0], a[1], a[2]).normalized()
	return Vector3.RIGHT


## Independent reference: rotate the start direction about n0 x tdir with a Quaternion.
func _ref_clearance(t: Terrain, p: Vector3, v: Vector3, g: float, time: float) -> float:
	var n0: Vector3 = p.normalized()
	var vt: Vector3 = v - n0 * v.dot(n0)
	var s: float = vt.length()
	var q: Quaternion = Quaternion(n0.cross(vt.normalized()).normalized(), s * time / p.length())
	var dir: Vector3 = q * n0
	return p.length() + v.dot(n0) * time - 0.5 * g * time * time - R - t.height_at(dir)


func _dense_tti(t: Terrain, p: Vector3, v: Vector3, g: float, horizon: float) -> float:
	var time: float = 0.0
	while time <= horizon:
		if _ref_clearance(t, p, v, g, time) <= 0.0:
			return time
		time += 0.001
	return INF


func test_cradle_crater_rim_min_clearance_matches_reference() -> void:
	var t: Terrain = _cradle()
	var c: Vector3 = _crater_centre()
	var tdir: Vector3 = Sphere.tangent_frame(c).x
	var p: ProbeParams = _probe()
	var checked: int = 0
	for k: int in 12:
		var a: float = (1700.0 - 250.0 * float(k)) / R   # sweep from outside the rim to the far side
		var start: Vector3 = c * cos(a) - tdir * sin(a)
		var heading: Vector3 = c * sin(a) + tdir * cos(a)
		var pos: Vector3 = start * (R + t.height_at(start) + 30.0)
		var vel: Vector3 = heading * 300.0
		var w: Vector2 = TerrainProbe.min_clearance(t, pos, vel, p)
		var ref: float = INF
		for ts: float in p.probe_times_s:
			ref = minf(ref, _ref_clearance(t, pos, vel, p.gravity, ts))
		assert_float(w.x).is_equal_approx(ref, 0.01)
		checked += 1
	assert_int(checked).is_equal(12)


func test_cradle_tti_matches_dense_reference_and_lift_clears() -> void:
	var t: Terrain = _cradle()
	var c: Vector3 = _crater_centre()
	var tdir: Vector3 = Sphere.tangent_frame(c).x
	var p: ProbeParams = _probe()
	var hits: int = 0
	for k: int in 16:
		var a: float = (1800.0 - 220.0 * float(k)) / R
		var start: Vector3 = c * cos(a) - tdir * sin(a)
		var heading: Vector3 = c * sin(a) + tdir * cos(a)
		var pos: Vector3 = start * (R + t.height_at(start) + 8.0)   # grazing the rim
		var vel: Vector3 = heading * 300.0
		var tti: float = TerrainProbe.time_to_impact(t, pos, vel, p)
		var ref: float = _dense_tti(t, pos, vel, p.gravity, 4.0)
		if is_inf(ref):
			assert_float(tti).is_equal(INF)
			continue
		hits += 1
		assert_float(tti).is_between(ref - TTI_TOL, ref + TTI_TOL)
		var lift: float = TerrainProbe.terrain_lift(t, pos, vel, p, p.required_clearance(300.0))
		assert_float(lift).is_greater(0.0)
	assert_int(hits).is_greater(0)
# endregion


# region purity and determinism
func test_pure_and_deterministic() -> void:
	var t: Terrain = _cradle()
	var p: ProbeParams = _probe()
	var pos: Vector3 = _crater_centre() * (R + 40.0)
	var vel: Vector3 = Vector3(10.0, 90.0, -15.0)
	var pos0: Vector3 = pos
	var vel0: Vector3 = vel
	var times0: PackedFloat32Array = p.probe_times_s.duplicate()
	var a1: float = TerrainProbe.time_to_impact(t, pos, vel, p)
	var a2: Vector2 = TerrainProbe.min_clearance(t, pos, vel, p)
	var a3: float = TerrainProbe.terrain_lift(t, pos, vel, p, 52.5)
	for i: int in 5:
		assert_float(TerrainProbe.time_to_impact(t, pos, vel, p)).is_equal(a1)
		assert_vector(TerrainProbe.min_clearance(t, pos, vel, p)).is_equal(a2)
		assert_float(TerrainProbe.terrain_lift(t, pos, vel, p, 52.5)).is_equal(a3)
	assert_vector(pos).is_equal(pos0)
	assert_vector(vel).is_equal(vel0)
	assert_array(p.probe_times_s).is_equal(times0)
	# a second terrain instance over the same bytes answers identically (S9)
	assert_float(TerrainProbe.time_to_impact(_cradle(), pos, vel, p)).is_equal(a1)


func test_source_has_no_state() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/sim/steer/terrain_probe.gd")
	assert_bool(src.contains("\nvar ")).is_false()
	for line: String in src.split("\n"):
		if line.begins_with("func "):
			fail("non-static func in TerrainProbe: " + line)
# endregion
