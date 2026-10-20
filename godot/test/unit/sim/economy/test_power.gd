extends GdUnitTestSuite
## Power (GD-13; 02 s8.4, C-12, O-4): ratio math, the solar factor at latitudes -1, 0, +0.25, +1 degrees and on the
## Plateau, the moving sun's path, the low-power effects (production speed, tower rate of fire and offline, Shield
## Projector recharge, construction unaffected), the LOW_POWER wire round trip, S4 and determinism.

const K := preload("res://test/unit/sim/economy_test_kit.gd")
const R: float = Sphere.PLANET_RADIUS

var _band: float = 0.0


func before_test() -> void:
	_band = WorldTestKit.content().economy.solar_band_deg


## Up vector at latitude `lat_deg` on the meridian of the +X axis (the sun is +Z, so elevation = latitude).
func _lat(lat_deg: float) -> Vector3:
	var a: float = deg_to_rad(lat_deg)
	return Vector3(cos(a), 0.0, sin(a))


func _factor(lat_deg: float, plateau: bool = false) -> float:
	return Economy.solar_factor(_lat(lat_deg), Vector3.BACK, plateau, _band, WorldTestKit.content().economy.solar_plateau_mult)


# --- solar factor ----------------------------------------------------------------------------------------------

func test_solar_factor_at_minus_one_zero_quarter_and_plus_one_degrees() -> void:
	assert_float(_factor(-1.0)).is_equal_approx(0.0, 0.001)
	assert_float(_factor(0.0)).is_equal_approx(0.5, 0.001)
	assert_float(_factor(0.25)).is_equal_approx(0.75, 0.001)       # (0.25 + 0.5) / 1.0
	assert_float(_factor(1.0)).is_equal_approx(1.0, 0.001)


func test_solar_factor_on_the_plateau_is_multiplied() -> void:
	var mult: float = WorldTestKit.content().economy.solar_plateau_mult
	assert_float(_factor(1.0, true)).is_equal_approx(mult, 0.001)
	assert_float(_factor(0.0, true)).is_equal_approx(0.5 * mult, 0.001)
	assert_float(_factor(-1.0, true)).is_equal_approx(0.0, 0.001)    # night stays dark


func test_plateau_membership_uses_the_arc_radius() -> void:
	var radius: float = WorldTestKit.content().economy.solar_plateau_radius_m
	var centres: PackedVector3Array = [Vector3.BACK]
	assert_bool(SunPath.on_plateau(Vector3.BACK, centres, radius)).is_true()
	assert_bool(SunPath.on_plateau(_lat(90.0 - rad_to_deg((radius - 10.0) / R)), centres, radius)).is_true()
	assert_bool(SunPath.on_plateau(_lat(90.0 - rad_to_deg((radius + 10.0) / R)), centres, radius)).is_false()
	assert_bool(SunPath.on_plateau(Vector3.BACK, PackedVector3Array(), radius)).is_false()


func test_plateau_raises_a_solar_array_supply_in_the_world() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	var _a: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, Vector3(0.0, R, 0.0))
	var _a2: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, Vector3(0.0, R, 200.0))      # demand 20 + 20
	var _b: int = WorldTestKit.spawn(w, &"solar_array", 0, 0, Vector3(0.0, 0.0, R))      # north pole: factor 1
	assert_float(e.power_ratio(0)).is_equal_approx(32.0 / 40.0, 0.0001)                  # 0.8 without the Plateau
	e.set_plateaus(PackedVector3Array([Vector3.BACK]))
	assert_float(e.power_ratio(0)).is_equal_approx((20.0 + 12.0 * 1.5) / 40.0, 0.0001)   # 0.95 on it
	e.set_plateaus(PackedVector3Array([Vector3.FORWARD]))                                # a Plateau elsewhere: back to 0.8
	assert_float(e.power_ratio(0)).is_equal_approx(32.0 / 40.0, 0.0001)


# --- moving sun ------------------------------------------------------------------------------------------------

func test_sun_path_fixed_and_moving() -> void:
	assert_vector(SunPath.dir_at(0.0, 500.0)).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.0001)
	assert_vector(SunPath.dir_at(100.0, 0.0)).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.0001)
	assert_vector(SunPath.dir_at(100.0, 25.0)).is_equal_approx(Vector3.UP, Vector3.ONE * 0.0001)
	assert_vector(SunPath.dir_at(100.0, 50.0)).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 0.0001)
	assert_vector(SunPath.dir_at(100.0, 100.0)).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.0001)


func test_solar_factor_follows_the_moving_sun_and_arrays_fade_at_night() -> void:
	var r: MatchRules = WorldTestKit.rules()
	r.sun_period_s = 120.0
	var w: SimWorld = K.solo_world(true, 7, r)
	var e: Economy = w.economy().economy
	var hz: int = r.tick_hz
	var _a: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, Vector3(0.0, R, 0.0))        # demand 30 vs supply 20 + 12 f
	var _b: int = WorldTestKit.spawn(w, &"solar_array", 0, 0, Vector3(0.0, 0.0, R))    # under the sun at t = 0
	var _x: Array[SimEvent] = K.run(w, hz)
	assert_float(e.power_ratio(0)).is_equal_approx(1.0, 0.001)                          # noon: f = 1
	var _y: Array[SimEvent] = K.run(w, 30 * hz - hz)                                    # t = 30 s: sun on the horizon
	assert_float(e.power_ratio(0)).is_equal_approx((20.0 + 12.0 * 0.5) / 30.0, 0.01)
	var _z: Array[SimEvent] = K.run(w, 30 * hz)                                         # t = 60 s: night
	assert_float(e.power_ratio(0)).is_equal_approx(20.0 / 30.0, 0.001)


# --- effects ---------------------------------------------------------------------------------------------------

func _starve(w: SimWorld, team: int, owner: int, shipyards: int) -> void:
	for i: int in shipyards:
		var _id: int = WorldTestKit.spawn(w, &"shipyard", owner, team, Vector3(0.0, R, float(i) * 100.0))


func test_ratio_math_min_one_and_zero_demand() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	assert_float(e.power_ratio(0)).is_equal(1.0)
	assert_float(e.power_ratio(3)).is_equal(1.0)                    # no structures: zero demand
	assert_float(e.power_ratio(-1)).is_equal(1.0)
	_starve(w, 0, 0, 2)                                             # supply 20, demand 20 + 20 + 0
	assert_float(e.power_ratio(0)).is_equal_approx(0.5, 0.001)
	assert_float(e.production_speed(0)).is_equal_approx(0.5, 0.001)
	_starve(w, 0, 0, 8)
	assert_float(e.power_ratio(0)).is_less(0.2)
	assert_float(e.production_speed(0)).is_equal_approx(WorldTestKit.content().economy.production_min_speed, 0.0001)


func test_low_power_rates_for_towers_and_shields() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	var off: float = WorldTestKit.content().economy.tower_offline_ratio
	_starve(w, 0, 0, 1)                                             # 20 / 30
	assert_float(e.tower_rates()[0]).is_equal_approx(20.0 / 30.0, 0.001)
	assert_float(e.shield_recharge_mult(0)).is_equal_approx(20.0 / 30.0, 0.001)
	_starve(w, 0, 0, 2)                                             # 20 / 50 = 0.4 < tower_offline_ratio
	assert_float(e.power_ratio(0)).is_less(off)
	assert_float(e.tower_rates()[0]).is_equal(0.0)
	assert_float(e.shield_recharge_mult(0)).is_equal(0.0)           # dome down
	assert_float(e.tower_rates()[1]).is_equal(1.0)


## C-12 (tower half): a team at ratio ~0.45 fires nothing; at ~0.74 it fires, slower than at full power.
func test_c12_towers_fire_zero_at_ratio_045_and_scale_above_half() -> void:
	var shots: PackedInt32Array = PackedInt32Array()
	for yards: int in [0, 5, 9]:
		var w: SimWorld = CombatTestKit.world()
		CombatTestKit.power(w, 1, 1)                                  # Reactor +40, the Outpost root +5
		var gun: int = CombatTestKit.spawn(w, &"autocannon_turret", 1, 1, CombatTestKit.R * Vector3.RIGHT + Vector3(0.0, 0.0, 0.0))
		var _root: int = CombatTestKit.feed(w, 1, 1, CombatTestKit.R * Vector3.RIGHT)   # GD-18: supplied, +5 power
		for i: int in yards:
			var _id: int = WorldTestKit.spawn(w, &"shipyard", 1, 1, Vector3(0.0, R, float(i) * 100.0))
		if yards == 9:
			var _rf: int = WorldTestKit.spawn(w, &"refinery", 1, 1, Vector3(0.0, -R, 0.0))
		FireTestKit.hook(w).hold(gun, PilotInput.FIRE1)
		var ratio: float = w.economy().economy.power_ratio(1)
		if yards == 9:
			assert_float(ratio).is_equal_approx(45.0 / 98.0, 0.001)       # 0.459
		var s: PackedInt32Array = FireTestKit.shot_ticks(w, gun, 216)
		shots.push_back(s.size())
	assert_int(shots[0]).is_equal(30)                                 # 6 bursts of 5 at full power
	assert_int(shots[1]).is_between(1, 29)                            # ratio 0.74
	assert_int(shots[2]).is_equal(0)                                  # offline


## C-12 (production and construction halves): production time scales with the ratio, construction does not.
func test_c12_production_scales_and_construction_does_not() -> void:
	var full: SimWorld = K.solo_world()
	var low: SimWorld = K.solo_world()
	var _id: int = WorldTestKit.spawn(low, &"shipyard", 0, 0, Vector3(0.0, R, 0.0))
	var _id2: int = WorldTestKit.spawn(low, &"shipyard", 0, 0, Vector3(0.0, R, 200.0))
	var _id3: int = WorldTestKit.spawn(low, &"shipyard", 0, 0, Vector3(0.0, R, 400.0))   # 20 / 50 = 0.4
	assert_float(low.economy().economy.power_ratio(0)).is_less(0.5)
	assert_float(low.economy().economy.production_speed(0)).is_equal_approx(0.4, 0.001)
	assert_float(full.economy().economy.production_speed(0)).is_equal(1.0)
	var done: PackedInt32Array = PackedInt32Array()
	for w: SimWorld in [full, low]:
		assert_int(K.code(w, Command.build(0, K.def(&"solar_array"), K.cell_west(250.0), 0))).is_equal(CommandResult.Code.ACCEPTED)
		done.push_back(K.count_kind(K.run(w, 480), SimEvent.Kind.BUILD_DONE))
	assert_int(done[0]).is_equal(1)
	assert_int(done[1]).is_equal(1)                                   # construction speed is never affected (02 s6.3)


# --- events, S4, determinism -----------------------------------------------------------------------------------

func test_low_power_wire_round_trip() -> void:
	var w: SimWorld = K.solo_world()
	assert_int(WorldTestKit.queue_spawn(w, &"shipyard", 0, 0, Vector3(0.0, R, 0.0))).is_equal(CommandResult.Code.ACCEPTED)
	var events: Array[SimEvent] = K.run(w, 2)
	var aud: EventAudience = EventAudience.new(Roster.new())
	aud.unfiltered = true
	aud.player = 0
	aud.team = 0
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [aud]
	router.route(w.tick(), events, auds)
	var out: Array[WireEvent] = []
	for p: PackedByteArray in aud.outbox:
		assert_int(EventCodec.decode(p, out)).is_greater_equal(0)
	var seen: int = 0
	for we: WireEvent in out:
		if we.kind == SimEvent.Kind.LOW_POWER:
			seen += 1
			assert_int(we.v[0]).is_equal(0)                           # team
			assert_int(we.v[1]).is_equal(roundi(20.0 / 30.0 * 255.0))   # ratio as u8 (04 s3.6)
	assert_int(seen).is_equal(1)


func test_s4_round_trip_with_a_moving_sun_and_determinism() -> void:
	var r: MatchRules = WorldTestKit.rules()
	r.sun_period_s = 120.0                                            # sun on the horizon at t = 30 s (tick 900)
	var hz: int = r.tick_hz
	var a: SimWorld = K.solo_world(true, 7, r)
	var b: SimWorld = K.solo_world(true, 7, r)
	for w: SimWorld in [a, b]:
		var _s: int = WorldTestKit.spawn(w, &"solar_array", 0, 0, Vector3(0.0, 0.0, R))
		var _y: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, Vector3(0.0, R, 0.0))   # demand 30
	var _x1: Array[SimEvent] = K.run(a, 25 * hz - a.tick())
	var _x2: Array[SimEvent] = K.run(b, 25 * hz - b.tick())
	assert_bool(a.serialize() == b.serialize()).is_true()
	var copy: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null)
	assert_bool(copy.serialize() == a.serialize()).is_true()          # snapshot before the terminator crossing
	for w: SimWorld in [a, b, copy]:
		var _x3: Array[SimEvent] = K.run(w, 30 * hz - 1 - w.tick())
		assert_float(w.economy().economy.power_ratio(0)).is_equal_approx(1.0, 0.0001)   # still lit one tick before
		var _x4: Array[SimEvent] = K.run(w, 1)
		assert_float(w.economy().economy.power_ratio(0)).is_equal_approx((20.0 + 12.0 * 0.5) / 30.0, 0.01)   # crossing tick
	var _x5: Array[SimEvent] = K.run(a, 300)
	var _x6: Array[SimEvent] = K.run(b, 300)
	var _x7: Array[SimEvent] = K.run(copy, 300)
	assert_bool(a.serialize() == b.serialize()).is_true()
	assert_bool(copy.serialize() == a.serialize()).is_true()
