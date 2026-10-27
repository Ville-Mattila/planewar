extends GdUnitTestSuite
## GD-09 sim-side fire gates (02 s4.4, R0 B.23 A-118 (e)): a tower's seeker honours `h_rel_min` / `h_rel_max`,
## `target_agl_min` and the datum horizon for AI and possessed towers alike (C-03), a guided rocket loses its target
## permanently below the projectile's `lock_break_agl_m` or when the target starts a flip with the rocket inside the
## `lock_break_flip_*_m` window (C-04). Every number is read from the defs.

const R: float = Sphere.PLANET_RADIUS
const HZ: int = 30


func _tower(def: StringName) -> Dictionary:
	for sd: StructureDef in WorldTestKit.content().structures:
		if sd.id == def:
			return sd.tower
	return {}


func _rocket() -> ProjectileDef:
	var c: ContentSet = WorldTestKit.content()
	return c.projectiles[int(c.projectile_index[&"rocket"]) - DefRanges.PROJECTILE_BASE]


func _num(d: Dictionary, k: String) -> float:
	return float(d.get(k, 0.0))


# Steps `ticks` times keeping `id` pinned at `p` (ships fall); returns the number of LOCK_ACQUIRED events.
func _pinned_locks(w: SimWorld, id: int, p: Vector3, ticks: int) -> int:
	var n: int = 0
	for _k: int in ticks:
		CombatTestKit.move(w, id, p)
		w.step()
		for e: SimEvent in w.drain_events():
			if e.kind == SimEvent.Kind.LOCK_ACQUIRED:
				n += 1
	return n


# The point `alt` m above the datum (|p| = R + alt) `east` m along the tangent from under (R, 0, 0) (the surface curves away).
func _at(alt: float, east: float) -> Vector3:
	return Vector3(R + alt, east, 0.0).normalized() * (R + alt)


# --- SeekerScan.in_envelope ---------------------------------------------------------------------------------------

func test_in_envelope_h_rel_band_is_inclusive_and_agl_needs_a_terrain() -> void:
	var t: Terrain = Terrain.new()
	var p: Vector3 = Vector3(R + 100.0, 0.0, 0.0)
	assert_bool(SeekerScan.in_envelope(p, Vector3(R + 100.0 + 399.0, 50.0, 0.0), -200.0, 400.0, 0.0, null)).is_true()
	assert_bool(SeekerScan.in_envelope(p, Vector3(R + 100.0 + 402.0, 50.0, 0.0), -200.0, 400.0, 0.0, null)).is_false()
	assert_bool(SeekerScan.in_envelope(p, Vector3(R + 100.0 - 199.0, 50.0, 0.0), -200.0, 400.0, 0.0, null)).is_true()
	assert_bool(SeekerScan.in_envelope(p, Vector3(R + 100.0 - 202.0, 50.0, 0.0), -200.0, 400.0, 0.0, null)).is_false()
	assert_bool(SeekerScan.in_envelope(p, _at(30.0, 50.0), -INF, INF, 40.0, t)).is_false()   # 30 m AGL < 40
	assert_bool(SeekerScan.in_envelope(p, _at(41.0, 50.0), -INF, INF, 40.0, t)).is_true()
	assert_bool(SeekerScan.in_envelope(p, _at(30.0, 50.0), -INF, INF, 40.0, null)).is_true()  # no terrain: no AGL floor


# --- C-03: the Missile Tower's seeker ----------------------------------------------------------------------------

func test_c03_no_lock_under_the_agl_floor_in_ten_seconds_and_a_lock_above_it() -> void:
	var floor_agl: float = _num(_tower(&"missile_tower"), "target_agl_min")
	assert_float(floor_agl).is_greater(0.0)
	var w: SimWorld = CombatTestKit.world()
	CombatTestKit.power(w, 1, 1)
	var mt: int = CombatTestKit.spawn(w, &"missile_tower", 1, 1, Vector3(R, 0.0, 0.0))
	var low: Vector3 = _at(0.75 * floor_agl, 600.0)             # 30 m AGL, 600 m out
	var lancer: int = CombatTestKit.spawn(w, &"lancer", 0, 0, low)
	FireTestKit.hook(w).hold(mt, PilotInput.FIRE1)
	assert_int(_pinned_locks(w, lancer, low, 10 * HZ)).is_equal(0)
	assert_int(FireTestKit.fired_by(w, mt).size()).is_equal(0)
	assert_int(w.view().ammo(mt)).is_equal(int(_num(_tower(&"missile_tower"), "ammo_pool")))
	assert_int(_pinned_locks(w, lancer, _at(2.5 * floor_agl, 600.0), 3 * HZ)).is_equal(1)
	assert_int(w.view().ammo(mt)).is_less(int(_num(_tower(&"missile_tower"), "ammo_pool")))   # the salvo left


func test_the_h_rel_band_gates_the_lock_of_a_held_trigger() -> void:
	var lo: float = _num(_tower(&"missile_tower"), "h_rel_min")
	assert_float(lo).is_less(0.0)
	var w: SimWorld = CombatTestKit.world()
	CombatTestKit.power(w, 1, 1)
	var site: Vector3 = Vector3(R + 1000.0, 0.0, 0.0)                      # a tower raised 1,000 m: the target can be below it
	var mt: int = CombatTestKit.spawn(w, &"missile_tower", 1, 1, site)
	var tgt: int = CombatTestKit.spawn(w, &"bomber", 0, 0, _at(1000.0 + 1.2 * lo, 500.0))
	FireTestKit.hook(w).hold(mt, PilotInput.FIRE1)
	assert_int(_pinned_locks(w, tgt, _at(1000.0 + 1.2 * lo, 500.0), 3 * HZ)).is_equal(0)   # 20 % under h_rel_min
	assert_int(_pinned_locks(w, tgt, _at(1000.0 + 0.5 * lo, 500.0), 3 * HZ)).is_equal(1)


# --- C-04: in-flight lock loss -------------------------------------------------------------------------------------

# A guided rocket of team 1 `dist` m east of a Dart of team 0 at `agl` m AGL, flying at it; the Dart's flip is ready.
func _flip_world(dist: float, agl: float) -> Array:
	var w: SimWorld = CombatTestKit.world()
	var dart: int = CombatTestKit.spawn(w, &"dart", 0, 0, Vector3(R + agl, 0.0, 0.0))
	w.store().flip_time[EntityId.slot(dart)] = -100.0
	var c: ContentSet = WorldTestKit.content()
	var pl: int = int(c.projectile_index[&"rocket"]) - DefRanges.PROJECTILE_BASE
	var wl: int = int(c.weapon_index[&"rocket_lancer"]) - DefRanges.WEAPON_BASE
	var id: int = w.projectiles().spawn(ProjectileStore.ROCKET, w.tick(), Vector3(R + agl, dist, 0.0), Vector3(0, -250.0, 0),
		6.0, pl, wl, 1, 1, 0, dart, ProjectileStore.F_GUIDED)
	return [w, dart, id]


func _guided_after_flip(dist: float) -> bool:
	var a: Array = _flip_world(dist, 300.0)
	var w: SimWorld = a[0]
	FireTestKit.hook(w).hold(a[1], PilotInput.FLIP)
	w.step()
	var i: int = w.projectiles().index_of(a[2])
	return i >= 0 and (w.projectiles().flags[i] & ProjectileStore.F_GUIDED) != 0


func test_c04_flip_breaks_the_lock_inside_the_window_only() -> void:
	var rk: ProjectileDef = _rocket()
	var lo: float = float(rk.raw.get("lock_break_flip_min_m", 0.0))
	var hi: float = float(rk.raw.get("lock_break_flip_max_m", 0.0))
	assert_float(lo).is_greater(0.0)
	assert_float(hi).is_greater(lo)
	assert_bool(_guided_after_flip(0.5 * (lo + hi))).is_false()               # 300 m: lock broken
	assert_bool(_guided_after_flip(lo + 5.0)).is_false()                      # just inside the near edge
	assert_bool(_guided_after_flip(hi - 5.0)).is_false()                      # just inside the far edge
	assert_bool(_guided_after_flip(0.5 * lo)).is_true()                       # 50 m: too close, not broken
	assert_bool(_guided_after_flip(hi * 1.4)).is_true()                       # 700 m: too far, not broken


func test_a_rocket_that_lost_its_lock_flies_straight_and_forgets_the_target() -> void:
	var a: Array = _flip_world(300.0, 300.0)
	var w: SimWorld = a[0]
	FireTestKit.hook(w).hold(a[1], PilotInput.FLIP)
	w.step()
	var i: int = w.projectiles().index_of(a[2])
	assert_int(w.projectiles().target[i]).is_equal(0)
	var v0: Vector3 = w.projectiles().vel[i]
	for _k: int in 4:
		w.step()
	var v1: Vector3 = w.projectiles().vel[w.projectiles().index_of(a[2])]
	assert_vector(v1.normalized()).is_equal_approx(v0.normalized(), Vector3(0.03, 0.03, 0.03))   # parallel transport turns it with the surface, nothing re-aims it


func test_no_flip_means_no_break_and_a_flip_started_outside_the_window_never_breaks_it_later() -> void:
	var a: Array = _flip_world(450.0, 300.0)
	var w: SimWorld = a[0]
	for _k: int in 3:
		w.step()
	var i: int = w.projectiles().index_of(a[2])
	assert_int(w.projectiles().flags[i] & ProjectileStore.F_GUIDED).is_equal(ProjectileStore.F_GUIDED)   # nobody flipped
	var b: Array = _flip_world(600.0, 300.0)
	var w2: SimWorld = b[0]
	var h: FireTestKit.TriggerHook = FireTestKit.hook(w2)
	h.hold(b[1], PilotInput.FLIP)
	w2.step()                                                                  # the flip starts at 600 m
	h.hold(b[1], 0)
	for _k: int in 12:
		w2.step()                                                              # the rocket crosses 500 m while the flip runs
	var j: int = w2.projectiles().index_of(b[2])
	assert_int(w2.projectiles().flags[j] & ProjectileStore.F_GUIDED).is_equal(ProjectileStore.F_GUIDED)


func test_a_target_under_the_rockets_agl_floor_is_lost() -> void:
	var floor_agl: float = float(_rocket().raw.get("lock_break_agl_m", 0.0))
	assert_float(floor_agl).is_greater(0.0)
	var a: Array = _flip_world(600.0, 0.75 * floor_agl)
	var w: SimWorld = a[0]
	w.step()
	var i: int = w.projectiles().index_of(a[2])
	assert_int(w.projectiles().flags[i] & ProjectileStore.F_GUIDED).is_equal(0)
	assert_int(w.projectiles().target[i]).is_equal(0)
	var b: Array = _flip_world(600.0, 2.0 * floor_agl)
	b[0].step()
	var j: int = b[0].projectiles().index_of(b[2])
	assert_int(b[0].projectiles().flags[j] & ProjectileStore.F_GUIDED).is_equal(ProjectileStore.F_GUIDED)


func test_the_agl_rule_spares_a_rocket_chasing_a_ground_unit() -> void:
	var w: SimWorld = CombatTestKit.world()
	var gnd: int = CombatTestKit.spawn(w, &"harvester", 0, 0, Vector3(R, 0.0, 0.0))        # AGL 0 on the datum, far under 40 m
	var c: ContentSet = WorldTestKit.content()
	var pl: int = int(c.projectile_index[&"rocket"]) - DefRanges.PROJECTILE_BASE
	var wl: int = int(c.weapon_index[&"rocket_lancer"]) - DefRanges.WEAPON_BASE
	var id: int = w.projectiles().spawn(ProjectileStore.ROCKET, w.tick(), Vector3(R + 100.0, 600.0, 0.0), Vector3(0, -250.0, 0),
		6.0, pl, wl, 1, 1, 0, gnd, ProjectileStore.F_GUIDED)
	w.step()
	var i: int = w.projectiles().index_of(id)
	assert_int(w.projectiles().flags[i] & ProjectileStore.F_GUIDED).is_equal(ProjectileStore.F_GUIDED)
	assert_int(w.projectiles().target[i]).is_equal(gnd)
