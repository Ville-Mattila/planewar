extends GdUnitTestSuite
## GD-50 BarrelSlew (sim/ground/MODULE.md B1-B5): 06 s3.2 "pitch = barrel" for a ground unit's mounted weapon, slewed at
## the def's `barrel_slew_dps` within `barrel_min_deg` / `barrel_max_deg`, from the input slot alone (possessed and AUTO).

const EPS: float = 1e-9         ## f64 scalars (elevation, input slots)
const VEC_EPS: float = 1e-5     ## Vector3 components are float32


func _crawler_def() -> GroundUnitDef:
	var c: ContentSet = WorldTestKit.content()
	return c.ground_units[WorldTestKit.def_id(&"siege_crawler") - DefRanges.GROUND_BASE]


func _deg(name: String) -> float:
	return deg_to_rad(Def.num(_crawler_def().raw.get(name, 0.0)))


# --- defs -------------------------------------------------------------------------------------------------------

func test_the_crawler_def_carries_a_barrel_and_the_harvester_none() -> void:
	var b: BarrelSlew = BarrelSlew.new(EntityStore.new(), InputSlots.new(), WorldDefs.new(WorldTestKit.content()))
	assert_bool(b.has_barrel(WorldTestKit.def_id(&"siege_crawler"))).is_true()
	assert_bool(b.has_barrel(WorldTestKit.def_id(&"harvester"))).is_false()
	assert_bool(b.has_barrel(WorldTestKit.def_id(&"dart"))).is_false()
	assert_bool(b.has_barrel(WorldTestKit.def_id(&"autocannon_turret"))).is_false()
	assert_bool(b.has_barrel(-1)).is_false()
	assert_float(_deg("barrel_slew_dps")).is_greater(0.0)
	assert_float(_deg("barrel_max_deg")).is_greater(_deg("barrel_min_deg"))
	assert_float(b.rest(WorldTestKit.def_id(&"siege_crawler"))).is_equal(clampf(0.0, _deg("barrel_min_deg"), _deg("barrel_max_deg")))


func test_the_lofted_band_lies_inside_the_def_limits() -> void:
	# 05 s6.7: 1,000-1,150 m needs about 0.5 asin(g d / v^2) on a flat world, less on the curved one; both inside the limits.
	var g: float = WorldTestKit.content().rules.gravity
	var v: float = BarrelTestKit.shell().speed_mps
	for d: float in [1000.0, 1150.0]:
		var flat: float = 0.5 * asin(g * d / (v * v))
		assert_float(flat).is_less(_deg("barrel_max_deg"))
		assert_float(flat).is_greater(_deg("barrel_min_deg"))


# --- slew law (B1, B2) ------------------------------------------------------------------------------------------

func _slew_case(possessed: bool) -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = BarrelTestKit.crawler(w)
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, possessed)
	var rate: float = _deg("barrel_slew_dps")
	var dt: float = 1.0 / float(WorldTestKit.content().rules.tick_hz)
	assert_float(w.view().barrel_elevation(id)).is_equal(0.0)          # rest = level
	p.input.pitch = 1.0
	for k: int in 30:
		p.tick(w)
		assert_float(w.view().barrel_elevation(id)).is_equal_approx(minf(float(k + 1) * rate * dt, _deg("barrel_max_deg")), EPS)
	p.input.pitch = 0.0
	var held: float = w.view().barrel_elevation(id)
	for _k: int in 10:
		p.tick(w)
	assert_float(w.view().barrel_elevation(id)).is_equal(held)        # pitch 0 holds
	p.input.pitch = -0.5
	p.tick(w)
	assert_float(w.view().barrel_elevation(id)).is_equal_approx(held - 0.5 * rate * dt, EPS)


func test_auto_pitch_slews_at_the_def_rate_and_zero_holds() -> void:
	_slew_case(false)


func test_possessed_pitch_slews_at_the_def_rate_and_zero_holds() -> void:
	_slew_case(true)


func test_the_barrel_stops_at_the_def_limits_and_pitch_is_clamped_to_one() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = BarrelTestKit.crawler(w)
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, false)
	var rate: float = _deg("barrel_slew_dps")
	var dt: float = 1.0 / float(WorldTestKit.content().rules.tick_hz)
	p.input.pitch = 4.0                                                 # beyond the stick: one full-rate step
	p.tick(w)
	assert_float(w.view().barrel_elevation(id)).is_equal_approx(rate * dt, EPS)
	var to_max: int = ceili(_deg("barrel_max_deg") / (rate * dt)) + 5
	for _k: int in to_max:
		p.tick(w)
	assert_float(w.view().barrel_elevation(id)).is_equal(_deg("barrel_max_deg"))
	p.input.pitch = -1.0
	for _k: int in to_max:
		p.tick(w)
	assert_float(w.view().barrel_elevation(id)).is_equal(_deg("barrel_min_deg"))


func test_the_autopilot_cannot_slew_a_possessed_barrel() -> void:
	# S11: drive is refused for a POSSESSED unit, so the player's pitch is the only source.
	var w: SimWorld = WorldTestKit.world()
	var id: int = BarrelTestKit.crawler(w)
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, true)
	p.possessed = false                                                 # the hook now tries to drive; no PILOT_INPUT
	p.input.pitch = 1.0
	for _k: int in 10:
		p.tick(w)
	assert_bool(p.drive_ok).is_false()
	assert_float(w.view().barrel_elevation(id)).is_equal(0.0)


func test_dead_beat_slew_reaches_an_exact_elevation() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = BarrelTestKit.crawler(w)
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, false)
	var want: float = deg_to_rad(16.25)
	var used: int = BarrelTestKit.slew_to(w, p, want, _deg("barrel_slew_dps"))
	assert_int(used).is_less(300)
	assert_float(w.view().barrel_elevation(id)).is_equal_approx(want, 1e-12)


func test_a_unit_without_a_barrel_ignores_pitch_and_reads_zero() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = BarrelTestKit.crawler(w, Vector3(1, 0, 0), &"harvester")
	var p: BarrelTestKit.Pilot = BarrelTestKit.pilot(w, id, false)
	p.input.pitch = 1.0
	for _k: int in 30:
		p.tick(w)
	assert_float(w.view().barrel_elevation(id)).is_equal(0.0)
	assert_float(w.view().barrel_elevation(EntityId.make(EntityId.slot(id), 77))).is_equal(0.0)   # stale id


# --- slot reuse (B3) --------------------------------------------------------------------------------------------

func test_a_reused_slot_starts_at_rest_not_at_the_dead_units_elevation() -> void:
	var st: EntityStore = EntityStore.new(0)
	var inp: InputSlots = InputSlots.new()
	var b: BarrelSlew = BarrelSlew.new(st, inp, WorldDefs.new(WorldTestKit.content()))
	var id: int = st.alloc(EntityStore.K_GROUND, 1)
	var s: int = EntityId.slot(id)
	st.def_id[s] = WorldTestKit.def_id(&"siege_crawler")
	inp.e_pitch[s] = 1.0
	for _k: int in 20:
		b.step(1.0 / 30.0)
	assert_float(b.elevation_of(s)).is_greater(0.0)
	assert_bool(st.free_slot(s, 2)).is_true()
	var id2: int = st.alloc(EntityStore.K_GROUND, 3)
	assert_int(EntityId.slot(id2)).is_equal(s)
	st.def_id[s] = WorldTestKit.def_id(&"siege_crawler")
	assert_float(b.elevation_of(s)).is_equal(0.0)                     # rest, before any step
	inp.e_pitch[s] = 0.0
	b.step(1.0 / 30.0)
	assert_float(b.elevation_of(s)).is_equal(0.0)
	assert_int(b.bound[s]).is_equal(id2)


# --- frame (B4) -------------------------------------------------------------------------------------------------

func test_muzzle_dir_and_up_are_an_orthonormal_pair_at_the_elevation() -> void:
	var p: Vector3 = Sphere.from_lat_lon(0.3, 1.1, 1.0) * (Sphere.PLANET_RADIUS + 40.0)
	var n: Vector3 = p.normalized()
	var f: Vector3 = (Vector3(0.2, 0.9, -0.4) - n * Vector3(0.2, 0.9, -0.4).dot(n)).normalized()
	var tilted: Vector3 = (f + n * 0.3).normalized()                  # a non-tangent heading is made tangent first
	for e: float in [0.0, 0.1, 0.3, 0.785]:
		var d: Vector3 = BarrelSlew.muzzle_dir(p, tilted, e)
		var u: Vector3 = BarrelSlew.muzzle_up(p, tilted, e)
		assert_float(d.length()).is_equal_approx(1.0, VEC_EPS)
		assert_float(u.length()).is_equal_approx(1.0, VEC_EPS)
		assert_float(d.dot(u)).is_equal_approx(0.0, VEC_EPS)
		assert_float(asin(d.dot(n))).is_equal_approx(e, VEC_EPS)             # elevation above the local horizontal
		assert_float(d.cross(u).dot(n)).is_equal_approx(f.cross(n).dot(n), VEC_EPS)   # right stays horizontal
		assert_float((d - n * d.dot(n)).normalized().dot(f)).is_equal_approx(1.0, VEC_EPS)   # on the heading


func test_frame_of_a_unit_without_a_barrel_is_its_fwd_and_up() -> void:
	var st: EntityStore = EntityStore.new()
	var b: BarrelSlew = BarrelSlew.new(st, InputSlots.new(), WorldDefs.new(WorldTestKit.content()))
	var s: int = EntityId.slot(st.alloc(EntityStore.K_GROUND, 1))
	st.def_id[s] = WorldTestKit.def_id(&"harvester")
	var f: Vector3 = Vector3(0, 1, 0)
	var u: Vector3 = Vector3(0.9, 0, 0.1).normalized()
	assert_vector(b.frame(s, Vector3(Sphere.PLANET_RADIUS, 0, 0), f, u)).is_equal(f)
	assert_vector(b.frame_up).is_equal(u)


# --- state (B5) -------------------------------------------------------------------------------------------------

func test_read_state_round_trips_and_refuses_bad_sizes_and_non_finite_elevations() -> void:
	var st: EntityStore = EntityStore.new()
	var defs: WorldDefs = WorldDefs.new(WorldTestKit.content())
	var a: BarrelSlew = BarrelSlew.new(st, InputSlots.new(), defs)
	a.elevation[7] = 0.25
	a.bound[7] = 1234
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	a.write_state(buf)
	var b: BarrelSlew = BarrelSlew.new(st, InputSlots.new(), defs)
	buf.seek(0)
	assert_bool(b.read_state(buf)).is_true()
	assert_float(b.elevation[7]).is_equal(0.25)
	assert_int(b.bound[7]).is_equal(1234)
	a.elevation[3] = NAN
	var bad: StreamPeerBuffer = StreamPeerBuffer.new()
	a.write_state(bad)
	bad.seek(0)
	assert_bool(BarrelSlew.new(st, InputSlots.new(), defs).read_state(bad)).is_false()
	a.elevation[3] = 0.0
	var _r: int = a.bound.resize(9)
	var short: StreamPeerBuffer = StreamPeerBuffer.new()
	a.write_state(short)
	short.seek(0)
	assert_bool(BarrelSlew.new(st, InputSlots.new(), defs).read_state(short)).is_false()
