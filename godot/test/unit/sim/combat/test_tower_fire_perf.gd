extends GdUnitTestSuite
## GD-09 perf note (03 s4.2 row 9, combat 1.2 ms p95, fire share 0.6 ms = 150 firings x 4 us; R0 B.26 A-137): `fire.step`
## p95 at the canonical entity count (400 ships, 200 ground, 480 structures, 120 wrecks, the S-SIM-1 mix of perf_tick
## --full) with FIRE1 held on gun towers at the far pole: (a) 32 firing towers with 20 hostile Darts in the envelope,
## (b) 32 idle-held towers (20 Bombers in range above the ceiling: the contract worst case, one scan per tower per tick),
## (c) 8 idle-held towers (the player cap, the realistic sustained worst case). Gate: (c) under 0.6 ms; (a) and (b) are
## reported. Timing goes through PerfGate (report-only on a hosted runner, R0 B.17 A-97); the work counters (`scans`, rounds
## spent) are hard everywhere. `fire.step` is called directly on the frozen world, the projectiles it spawns freed untimed.

const R: float = Sphere.PLANET_RADIUS
const SAMPLES: int = 400
const FOES: int = 20
const BOUND_IDLE8_US: float = 600.0   ## 03 s4.2 row 9 fire share (gate, case c)
const BOUND_A_US: float = 1200.0      ## case (a): reported; the whole combat row as a ceiling on a pinned runner
const BOUND_B_US: float = 3000.0      ## case (b): reported; about 2x the dev-laptop figure, a runaway guard


func _put(pw: PerfTickWorld, def: StringName, team: int, p: Vector3) -> int:
	var s: int = pw._put(def, team, 0.0, 0.0)
	var st: EntityStore = pw.world.store()
	st.pos[s] = p
	st.up[s] = p.normalized()
	st.fwd[s] = Sphere.tangent_frame(p).y
	st.vel[s] = Vector3.ZERO
	st.hp[s] = 1.0e9
	return s


# Towers on a grid at the +Z pole, hostiles `foe_alt` m up (beyond range of every filler entity on the equator).
func _build(towers: int, foe: StringName, foe_alt: float) -> Array:
	var pw: PerfTickWorld = PerfTickWorld.new(400, 200, 480, 120, 0, &"")
	var w: SimWorld = pw.world
	var hook: FireTestKit.TriggerHook = FireTestKit.TriggerHook.new()
	w.set_ai_hook(hook)
	var ids: PackedInt32Array = PackedInt32Array()
	var _root: int = _put(pw, &"reactor", 1, Vector3(0.0, 0.0, -R))
	var _out: int = _put(pw, &"outpost", 1, Vector3(0.0, 0.0, R))
	for k: int in towers:
		var s: int = _put(pw, &"autocannon_turret", 1, Vector3(float(k % 8) * 20.0, float(k / 8) * 20.0 - 40.0, R))
		w.store().ammo[s] = 1000000
		var id: int = w.store().id_of(s)
		hook.hold(id, PilotInput.FIRE1)
		var _p: bool = ids.push_back(s)
	for k: int in FOES:
		var a: float = TAU * float(k) / float(FOES)
		var _f: int = _put(pw, foe, 0, Vector3(300.0 * cos(a), 300.0 * sin(a), R + foe_alt))
	for _k: int in 3:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	return [w, ids]


# p95 in us of `fire.step` over SAMPLES calls; returns [p95, scans, rounds].
func _measure(w: SimWorld, ids: PackedInt32Array) -> Array:
	var fire: WeaponFire = w._combat.fire
	var st: EntityStore = w.store()
	var ps: ProjectileStore = w.projectiles()
	var us: PackedFloat32Array = PackedFloat32Array()
	var _r: int = us.resize(SAMPLES)
	var before: int = 0
	for s: int in ids:
		before += st.ammo[s]
	fire.scans = 0
	for k: int in SAMPLES:
		var t0: int = Time.get_ticks_usec()
		fire.step(w.tick() + k, w.rng)
		us[k] = float(Time.get_ticks_usec() - t0)
		for i: int in ps.live.duplicate():
			var _f: bool = ps.free_slot(i, w.tick() + k)
	var after: int = 0
	for s: int in ids:
		after += st.ammo[s]
	us.sort()
	return [us[int(float(SAMPLES) * 0.95)], fire.scans, before - after]


func test_32_firing_towers() -> void:
	var a: Array = _build(32, &"dart", 100.0)
	var m: Array = _measure(a[0], a[1])
	assert_int(m[2]).override_failure_message("rounds spent").is_greater(0)
	assert_bool(PerfGate.check("fire_step_32_firing_towers", m[0], BOUND_A_US, "03 s4.2 row 9 fire share; A-137 case (a), reported")).is_true()


func test_32_idle_held_towers() -> void:
	var hi: float = _ceiling()
	var a: Array = _build(32, &"bomber", 1.5 * hi)
	var m: Array = _measure(a[0], a[1])
	assert_int(m[2]).is_equal(0)
	assert_int(m[1]).override_failure_message("one scan per tower per tick").is_equal(32 * SAMPLES)
	assert_bool(PerfGate.check("fire_step_32_idle_held_towers", m[0], BOUND_B_US, "03 s4.2 row 9 fire share; A-137 case (b), reported")).is_true()


func test_8_idle_held_towers_under_the_fire_share() -> void:
	var hi: float = _ceiling()
	var a: Array = _build(8, &"bomber", 1.5 * hi)
	var m: Array = _measure(a[0], a[1])
	assert_int(m[2]).is_equal(0)
	assert_int(m[1]).is_equal(8 * SAMPLES)
	assert_bool(PerfGate.check("fire_step_8_idle_held_towers", m[0], BOUND_IDLE8_US, "03 s4.2 row 9 fire share 0.6 ms; A-137 case (c)")) \
			.override_failure_message("p95 %.1f us" % m[0]).is_true()


func _ceiling() -> float:
	for sd: StructureDef in WorldTestKit.content().structures:
		if sd.id == &"autocannon_turret":
			return float(sd.tower.get("h_rel_max", 0.0))
	return 0.0
