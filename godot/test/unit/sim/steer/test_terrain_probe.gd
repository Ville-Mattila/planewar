extends GdUnitTestSuite
## Unit tests for sim/steer/terrain_probe.gd (AI-07; 05 s5.3): TTI against closed-form cases over flat and sloped
## synthetic terrain, a triangular ridge against a dense reference, min clearance over the cradle crater rims
## against an independent Quaternion-based path, lift sanity, purity and determinism. Acceptance: TTI error < 0.1 s.

const MAP_CRADLE: String = "res://content/maps/cradle"
const TTI_TOL: float = 0.1
const ROUGH_TTI_TOL: float = 0.5
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


var _out: ProbeResult = ProbeResult.new()


func _tti(t: Terrain, p: Vector3, v: Vector3, probe: ProbeParams) -> float:
	TerrainProbe.probe(t, p, v, probe, 0.0, _out)
	return _out.tti_s


func _minc(t: Terrain, p: Vector3, v: Vector3, probe: ProbeParams) -> Vector2:
	TerrainProbe.probe(t, p, v, probe, 0.0, _out)
	return Vector2(_out.min_clearance_m, _out.worst_t_s)


func _lift(t: Terrain, p: Vector3, v: Vector3, probe: ProbeParams, h_req: float) -> float:
	TerrainProbe.probe(t, p, v, probe, h_req, _out)
	return _out.lift_mps


func _probe() -> ProbeParams:
	return ProbeParams.make(25.0, 0.25, PackedFloat32Array([0.5, 1.0, 1.5, 2.0, 3.0, 4.0]), 6.0, 0.6, 0.5)


## Ship over `origin` at altitude `alt`, moving along +Y (tangent) at `ground` m/s with vertical speed `vr`.
func _ship(alt: float, ground: float, vr: float) -> Array[Vector3]:
	var n: Vector3 = Vector3.RIGHT
	return [n * (R + alt), Vector3(0.0, ground, 0.0) + n * vr]


# region flat and sloped closed forms
func test_flat_descent_matches_quadratic() -> void:
	var s: Array[Vector3] = _ship(100.0, 100.0, -40.0)
	var tti: float = _tti(Terrain.new(), s[0], s[1], _probe())
	var exact: float = (-40.0 + sqrt(40.0 * 40.0 + 4.0 * 3.0 * 100.0)) / 6.0   # 3 t^2 + 40 t - 100 = 0
	assert_float(tti).is_between(exact - TTI_TOL, exact + TTI_TOL)


func test_flat_level_flight_falls_by_gravity() -> void:
	var s: Array[Vector3] = _ship(40.0, 100.0, 0.0)
	var tti: float = _tti(Terrain.new(), s[0], s[1], _probe())
	assert_float(tti).is_between(sqrt(40.0 / 3.0) - TTI_TOL, sqrt(40.0 / 3.0) + TTI_TOL)


func test_flat_climbing_is_clear_and_infinite() -> void:
	var s: Array[Vector3] = _ship(100.0, 100.0, 30.0)
	assert_float(_tti(Terrain.new(), s[0], s[1], _probe())).is_equal(INF)


func test_at_or_below_surface_is_within_first_sample() -> void:
	var p: ProbeParams = _probe()
	for alt: float in [0.0, -5.0, -40.0]:
		var s: Array[Vector3] = _ship(alt, 100.0, 0.0)
		var tti: float = _tti(Terrain.new(), s[0], s[1], p)
		assert_float(tti).is_between(0.0, p.probe_times_s[0])


func test_sloped_terrain_matches_quadratic() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.slope = 0.2
	for ground: float in [80.0, 150.0, 200.0]:
		var s: Array[Vector3] = _ship(40.0, ground, 0.0)
		var r0: float = R + 40.0
		# r0 - 3 t^2 - R = slope * R * ground * t / r0
		var b: float = t.slope * R * ground / r0
		var exact: float = (-b + sqrt(b * b + 4.0 * 3.0 * 40.0)) / 6.0
		var tti: float = _tti(t, s[0], s[1], _probe())
		assert_float(tti).is_between(exact - TTI_TOL, exact + TTI_TOL)


func test_ridge_tti_against_dense_reference() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.ridge_h = 700.0
	t.ridge_w = 600.0 / R
	t.ridge_at = 900.0 / R
	for alt: float in [200.0, 350.0, 500.0, 650.0]:
		var s: Array[Vector3] = _ship(alt, 160.0, 0.0)
		var tti: float = _tti(t, s[0], s[1], _probe())
		var ref: float = _dense_tti(t, s[0], s[1], 6.0, 4.0)
		if is_inf(ref):
			assert_float(tti).is_equal(INF)
		else:
			assert_float(tti).is_between(ref - TTI_TOL, ref + TTI_TOL)


func test_vertical_and_stationary_ship_stay_over_one_point() -> void:
	var s: Array[Vector3] = _ship(50.0, 0.0, -20.0)
	var tti: float = _tti(Terrain.new(), s[0], s[1], _probe())
	assert_float(tti).is_between(1.837, 2.037)   # 3 t^2 + 20 t - 50 = 0 -> 1.937 s
	assert_float(_tti(Terrain.new(), s[0], Vector3.ZERO, _probe())).is_equal(INF)
# endregion


# region clearance and lift
func test_min_clearance_reports_worst_sample_and_time() -> void:
	var s: Array[Vector3] = _ship(100.0, 100.0, -20.0)
	var w: Vector2 = _minc(Terrain.new(), s[0], s[1], _probe())
	assert_float(w.y).is_equal(4.0)   # monotone descent: the last sample is the lowest
	assert_float(w.x).is_equal_approx(100.0 - 80.0 - 48.0, 0.05)


func test_lift_zero_when_clear_and_positive_when_low() -> void:
	var hi: Array[Vector3] = _ship(500.0, 100.0, 0.0)
	var lo: Array[Vector3] = _ship(40.0, 100.0, 0.0)
	var p: ProbeParams = _probe()
	var h_req: float = p.required_clearance(100.0)
	assert_float(h_req).is_equal(50.0)
	assert_float(_lift(Terrain.new(), hi[0], hi[1], p, h_req)).is_equal(0.0)
	assert_float(_lift(Terrain.new(), lo[0], lo[1], p, h_req)).is_greater(0.0)


func test_lift_formula_and_cap() -> void:
	var p: ProbeParams = _probe()
	var s: Array[Vector3] = _ship(100.0, 100.0, 0.0)
	# worst sample t = 4: c = 100 - 48 = 52; h_req 80 -> (80 - 52) / 4 = 7 m/s
	assert_float(_lift(Terrain.new(), s[0], s[1], p, 80.0)).is_equal_approx(7.0, 0.05)
	# huge deficiency: capped at 0.6 u
	assert_float(_lift(Terrain.new(), s[0], s[1], p, 5000.0)).is_equal_approx(0.6 * 100.0, 0.01)


func test_lift_uses_time_floor() -> void:
	var p: ProbeParams = ProbeParams.make(25.0, 0.25, PackedFloat32Array([0.1]), 6.0, 0.6, 0.5)
	var s: Array[Vector3] = _ship(10.0, 100.0, 0.0)
	# c(0.1) = 10 - 0.03; deficiency 20.03 / max(0.1, 0.5) = 40.06 (below the 60 cap)
	assert_float(_lift(Terrain.new(), s[0], s[1], p, 30.0)).is_equal_approx(20.03 / 0.5, 0.05)


func test_lift_on_ridge_raises_with_clearance_deficit() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.ridge_h = 300.0
	t.ridge_w = 500.0 / R
	t.ridge_at = 600.0 / R
	var s: Array[Vector3] = _ship(280.0, 160.0, 0.0)
	var p: ProbeParams = _probe()
	var lift: float = _lift(t, s[0], s[1], p, p.required_clearance(160.0))
	assert_float(lift).is_greater(10.0)
	assert_float(lift).is_less_equal(0.6 * 160.0)


# ST3 (AI-13): climb_need_mps = max over samples of (h_req - c'_k) / max(t_k, lift_min_time_s), c'_k the drop-free
# clearance, against an independent recomputation through `_ref_clearance`; when the binding sample is not the worst
# ballistic one the need exceeds the A-69 lift of the worst sample; over open ground it is negative.
func test_climb_need_is_the_drop_free_requirement_over_every_sample() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.slope = -0.3                                    # ground falling away as fast as the ship sinks: the ballistic
	var p: ProbeParams = _probe()                     # worst sample is the last (gravity drop), the binding one the first
	var s: Array[Vector3] = _ship(30.0, 100.0, -30.0)
	var h_req: float = p.required_clearance(s[1].length())
	TerrainProbe.probe(t, s[0], s[1], p, h_req, _out)
	var ref: float = -INF
	for time: float in p.probe_times_s:
		var c_free: float = _ref_clearance(t, s[0], s[1], p.gravity, time) + 0.5 * p.gravity * time * time
		ref = maxf(ref, (h_req - c_free) / maxf(time, p.lift_min_time_s))
	assert_float(_out.climb_need_mps).is_equal_approx(ref, 1e-3)
	assert_float(_out.climb_need_mps).is_greater(TerrainProbe.drop_free_lift(_out, p, h_req, s[1].length()))
	var flat: Array[Vector3] = _ship(400.0, 110.0, 0.0)
	TerrainProbe.probe(Terrain.new(), flat[0], flat[1], p, p.required_clearance(110.0), _out)
	assert_float(_out.climb_need_mps).is_less(0.0)
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
		var w: Vector2 = _minc(t, pos, vel, p)
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
		var tti: float = _tti(t, pos, vel, p)
		var ref: float = _dense_tti(t, pos, vel, p.gravity, 4.0)
		if is_inf(ref):
			assert_float(tti).is_equal(INF)
			continue
		hits += 1
		assert_float(tti).is_between(ref - ROUGH_TTI_TOL, ref + ROUGH_TTI_TOL)   # linear refinement on rough rims: measured <= 0.5 s
		var lift: float = _lift(t, pos, vel, p, p.required_clearance(300.0))
		assert_float(lift).is_greater(0.0)
	assert_int(hits).is_greater(0)
# endregion


# region purity and determinism
class CountingTerrain extends Terrain:
	var calls: int = 0

	func height_at(dir: Vector3) -> float:
		calls += 1
		return super.height_at(dir)


func test_probe_costs_exactly_the_probe_times() -> void:
	var t: CountingTerrain = CountingTerrain.new()
	var s: Array[Vector3] = _ship(10.0, 100.0, -30.0)   # hit case
	TerrainProbe.probe(t, s[0], s[1], _probe(), 50.0, _out)
	assert_int(t.calls).is_equal(6)
	t.calls = 0
	s = _ship(900.0, 100.0, 0.0)   # clear case
	TerrainProbe.probe(t, s[0], s[1], _probe(), 50.0, _out)
	assert_int(t.calls).is_equal(6)
	t.calls = 0
	var c: float = TerrainProbe.sample_clearance(t, s[0], s[1], 6.0, 1.0)
	assert_int(t.calls).is_equal(1)
	assert_float(c).is_equal_approx(900.0 - 3.0, 0.01)


func test_dip_between_samples_is_missed_by_design() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.ridge_h = 700.0
	t.ridge_w = 30.0 / R
	t.ridge_at = 225.0 / R   # 0.75 s at 300 m/s: between the 0.5 s (150 m) and 1.0 s (300 m) samples
	var s: Array[Vector3] = _ship(300.0, 300.0, 0.0)
	assert_float(_tti(t, s[0], s[1], _probe())).is_equal(INF)
	assert_float(_dense_tti(t, s[0], s[1], 6.0, 1.5)).is_less(1.0)   # the true path does hit it


func test_sample_clearance_matches_probe_sample() -> void:
	var t: SynTerrain = SynTerrain.new()
	t.slope = 0.1
	var s: Array[Vector3] = _ship(150.0, 120.0, -10.0)
	var p: ProbeParams = _probe()
	TerrainProbe.probe(t, s[0], s[1], p, 0.0, _out)
	var worst: float = INF
	for ts: float in p.probe_times_s:
		worst = minf(worst, TerrainProbe.sample_clearance(t, s[0], s[1], p.gravity, ts))
	assert_float(_out.min_clearance_m).is_equal(worst)


func test_pure_and_deterministic() -> void:
	var t: Terrain = _cradle()
	var p: ProbeParams = _probe()
	var pos: Vector3 = _crater_centre() * (R + 40.0)
	var vel: Vector3 = Vector3(10.0, 90.0, -15.0)
	var pos0: Vector3 = pos
	var vel0: Vector3 = vel
	var times0: PackedFloat32Array = p.probe_times_s.duplicate()
	var a1: float = _tti(t, pos, vel, p)
	var a2: Vector2 = _minc(t, pos, vel, p)
	var a3: float = _lift(t, pos, vel, p, 52.5)
	for i: int in 5:
		assert_float(_tti(t, pos, vel, p)).is_equal(a1)
		assert_vector(_minc(t, pos, vel, p)).is_equal(a2)
		assert_float(_lift(t, pos, vel, p, 52.5)).is_equal(a3)
	assert_vector(pos).is_equal(pos0)
	assert_vector(vel).is_equal(vel0)
	assert_array(p.probe_times_s).is_equal(times0)
	# a second terrain instance over the same bytes answers identically (S9)
	assert_float(_tti(_cradle(), pos, vel, p)).is_equal(a1)


func test_source_has_no_state() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/sim/steer/terrain_probe.gd")
	assert_bool(src.contains("\nvar ")).is_false()
	for line: String in src.split("\n"):
		if line.begins_with("func "):
			fail("non-static func in TerrainProbe: " + line)
# endregion
