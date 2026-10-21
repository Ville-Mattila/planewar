extends GdUnitTestSuite
## GD-10 perf note (03 s4.2 row 9, combat 1.2 ms p95): the shield pass in a scene where the domes actually absorb, not an
## empty world. 8 Cores and 16 Projectors (two teams), all charged through the recharge, every call restores that saved
## world and injects bombs / rockets entering enemy domes; the hard counters (absorbed, domes up, Ice paid) are asserted
## exactly, the timing goes through PerfGate (report-only on a hosted runner, A-97). Bounds are shares of the combat row:
## the pass may use 25 % of it (300 us) under the stress load (60 absorbed per tick, the worst a bomber wing drops in one
## tick) and 12.5 % (150 us) under the S-SIM-1 load.

# Why 60 absorbed shots per tick is the worst case: a ship releases at most one absorbable shot per tick (one bomb, one
# rocket or one shell per weapon, rate of fire <= 10 per s at 30 Hz), a dome takes 3 bombs (Projector 1,200 / 400) or 6
# (Core 2,400 / 400) before it collapses and stops absorbing, and at S-SIM-1 scale (<= 80 units per player, a wing per
# base) a tick in which 60 shots enter domes is a bomber wing hitting a fortress. Cost is linear in absorbed shots,
# about 3.3-4.4 us each (CI and dev box), so the 300 us bound leaves room for ~70.
const R: float = Sphere.PLANET_RADIUS
const STRESS: int = 60
const CALLS: int = 12
const BOUND_STRESS_US: float = 300.0     ## 25 % of the 1.2 ms combat row
const BOUND_SSIM_US: float = 150.0       ## 12.5 % of the 1.2 ms combat row


static var _saved: PackedByteArray = PackedByteArray()
static var _domes: PackedInt32Array = PackedInt32Array()


# 8 bases on a ring of the equator; each a Core and two Projectors 600 m aside, spawned through DEBUG_SPAWN, then
# charged by stepping (the Cores start full). Saved once; every call restores it.
func _build() -> void:
	if not _saved.is_empty():
		return
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(-1.0, -1.0, true))
	for s: int in range(3, 8):
		w.add_player(s, 0 if s < 4 else 1, &"", PlayerTable.KIND_BOT)
	var ids: PackedInt32Array = PackedInt32Array()
	for p: int in 8:
		var ang: float = float(p) * TAU / 8.0
		var c: Vector3 = Vector3(cos(ang), sin(ang), 0.0)
		var side: Vector3 = c.cross(Vector3.BACK)
		var a: float = 600.0 / R
		for k: int in 3:
			var dir: Vector3 = c if k == 0 else (c * cos(a) + side * (sin(a) if k == 1 else -sin(a))).normalized()
			var id: int = WorldTestKit.spawn(w, &"core" if k == 0 else &"shield_projector", p, 0 if p < 4 else 1, dir * R)
			assert(id != 0)
			var _p: bool = ids.push_back(EntityId.slot(id))
	for _t: int in 3400:                                                          # ratio 0.67: 90 s to fill
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
	_domes = ids
	_saved = w.serialize()


func _world() -> SimWorld:
	_build()
	var w: SimWorld = SimWorld.deserialize(_saved, WorldTestKit.content(), null)
	assert_object(w).is_not_null()
	return w


# One projectile entering each dome (cycling) from an enemy owner: bombs and rockets alternate (bombs 400, rockets 40).
func _inject(w: SimWorld, n: int, first: int) -> void:
	for k: int in n:
		var s: int = _domes[(first + k) % _domes.size()]
		var enemy: int = 4 if w.store().team[s] == 0 else 0
		var c: Vector3 = w.store().pos[s]
		var r: float = w.shields().dome_radius(s)
		var bomb: bool = k % 3 == 0
		var id: int = CombatTestKit.shot(w, &"bomb" if bomb else &"rocket", &"bomb" if bomb else &"rocket_lancer", c + c.normalized() * (r - 3.0), enemy, 0 if enemy < 4 else 1)
		w.projectiles().prev_pos[w.projectiles().index_of(id)] = c + c.normalized() * (r + 3.0)


func test_absorb_and_recharge_with_24_domes_and_60_shots_entering_per_call() -> void:
	var us: int = 0
	var absorbed: int = 0
	var w: SimWorld = null
	for i: int in CALLS:
		w = _world()
		var up: int = 0
		for s: int in _domes:
			up += 1 if w.shields().is_up(s, w.tick()) and w.shields().charge_of(s) > 0.0 else 0
		assert_int(up).is_equal(24)                                                   # hard counter: 8 Cores + 16 Projectors charged and up
		_inject(w, STRESS, i)
		var t0: int = Time.get_ticks_usec()
		absorbed += w.shields().absorb(w.tick())
		us += Time.get_ticks_usec() - t0
	assert_int(absorbed).is_equal(CALLS * STRESS)                                     # hard counter: every shot absorbed
	assert_int(w.projectiles().live_count()).is_equal(0)
	var per_call: float = float(us) / float(CALLS)
	assert_bool(PerfGate.check("shield_absorb_60_shots_24_domes", per_call, BOUND_STRESS_US, "03 s4.2 row 9 combat 1.2 ms p95, 25 % share")) \
			.override_failure_message("measured %.1f us" % per_call).is_true()
	# Recharge: every dome hit once, 5 s later the pass recharges and pays Ice.
	w = _world()
	_inject(w, 24, 0)
	assert_int(w.shields().absorb(w.tick())).is_equal(24)
	var ice0: int = w.economy().economy.stockpile(0).y + w.economy().economy.stockpile(1).y
	var charge0: float = w.shields().charge_of(_domes[1])
	for _t: int in 150:
		w.step()
	var t1: int = Time.get_ticks_usec()
	for _i: int in 100:
		w.shields().step(w.tick())
	var us_step: int = Time.get_ticks_usec() - t1
	var ice1: int = w.economy().economy.stockpile(0).y + w.economy().economy.stockpile(1).y
	assert_int(ice0 - ice1).is_greater(0)                                             # hard counter: the recharge paid Ice
	assert_float(w.shields().charge_of(_domes[1])).is_greater(charge0)
	assert_bool(PerfGate.check("shield_step_24_domes_recharging", float(us_step) / 100.0, 100.0, "03 s4.2 row 10 economy 0.8 ms p95, 12 % share")).is_true()


# The S-SIM-1 shape: 2,000 live projectiles, 1,898 slugs and 100 bombs and rockets in flight outside every dome, and two
# entering enemy domes this call.
func test_s_sim_1_load_2000_projectiles_100_absorbable_2_entering() -> void:
	var us: int = 0
	var absorbed: int = 0
	var far: Vector3 = Vector3(0.0, 0.0, R + 800.0)                                    # over the pole, away from every base
	for i: int in CALLS:
		var w: SimWorld = _world()
		for n: int in 1898:
			var _a: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", far + Vector3(float(n), 0.0, 0.0), 4, 1)
		for n: int in 100:
			var _b: int = CombatTestKit.shot(w, &"bomb" if n % 2 == 0 else &"rocket", &"bomb" if n % 2 == 0 else &"rocket_lancer", far + Vector3(0.0, float(n), 0.0), 4, 1)
		_inject(w, 2, i)
		var t0: int = Time.get_ticks_usec()
		absorbed += w.shields().absorb(w.tick())
		us += Time.get_ticks_usec() - t0
	assert_int(absorbed).is_equal(2 * CALLS)                                           # hard counter: exactly the two entering
	assert_bool(PerfGate.check("shield_absorb_2000_proj_2_entering", float(us) / float(CALLS), BOUND_SSIM_US, "03 s4.2 row 9 combat 1.2 ms p95, 12.5 % share")).is_true()


func test_a_world_without_domes_pays_only_the_sync_check() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(-1.0, -1.0, true))
	w.step()
	var sh: ShieldDomes = w.shields()
	var t0: int = Time.get_ticks_usec()
	var total: int = 0
	for i: int in 1000:
		total += sh.absorb(w.tick() + i)
	var per_call: float = float(Time.get_ticks_usec() - t0) / 1000.0
	assert_int(total).is_equal(0)                                                     # hard counter: nothing to absorb
	assert_int(sh.absorbed_total).is_equal(0)
	assert_bool(PerfGate.check("shield_absorb_no_domes", per_call, 20.0, "03 s4.2 row 9 combat 1.2 ms p95")).is_true()
