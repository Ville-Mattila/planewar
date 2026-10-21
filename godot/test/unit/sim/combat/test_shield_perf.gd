extends GdUnitTestSuite
## GD-10 perf note (03 s4.2 row 9, combat 1.2 ms p95): the shield pass in a scene where the domes actually absorb, not an
## empty world. 8 Cores and 16 Projectors (two teams, power ratio 0.67 so every Projector is up), 300 bombs and rockets
## entering enemy domes every call; the hard counters (absorbed, active domes, Ice paid) are asserted exactly, the timing
## goes through PerfGate (report-only on a hosted runner, A-97).

const R: float = Sphere.PLANET_RADIUS
const PROJECTILES: int = 300
const CALLS: int = 100


func _put(w: SimWorld, def: StringName, owner: int, dir: Vector3) -> int:
	return w._applier.spawn(WorldTestKit.def_id(def), owner, 0 if owner < 4 else 1, dir * R, Vector3.ZERO, dir.cross(Vector3.BACK), 0)


# 8 bases on a ring of the equator; each a Core and two Projectors 600 m aside. Returns the dome slots.
func _scene() -> Dictionary:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(-1.0, -1.0, true))
	for s: int in range(3, 8):
		w.add_player(s, 0 if s < 4 else 1, &"", PlayerTable.KIND_BOT)
	var domes: PackedInt32Array = PackedInt32Array()
	for p: int in 8:
		var ang: float = float(p) * TAU / 8.0
		var c: Vector3 = Vector3(cos(ang), sin(ang), 0.0)
		var side: Vector3 = c.cross(Vector3.BACK)
		var a: float = 600.0 / R
		for k: int in 3:
			var dir: Vector3 = c if k == 0 else (c * cos(a) + side * (sin(a) if k == 1 else -sin(a))).normalized()
			var s: int = _put(w, &"core" if k == 0 else &"shield_projector", p, dir)
			assert(s >= 0)
			var _p: bool = domes.push_back(s)
	w.step()
	return {"w": w, "domes": domes}


# One projectile entering each dome (cycling) from an enemy owner: bombs and rockets alternate.
func _inject(w: SimWorld, domes: PackedInt32Array) -> void:
	for n: int in PROJECTILES:
		var s: int = domes[n % domes.size()]
		var enemy: int = 4 if w.store().team[s] == 0 else 0
		var c: Vector3 = w.store().pos[s]
		var r: float = w.shields().dome_radius(s)
		var bomb: bool = n % 2 == 0
		var id: int = CombatTestKit.shot(w, &"bomb" if bomb else &"rocket", &"bomb" if bomb else &"rocket_lancer", c + c.normalized() * (r - 3.0), enemy, 0 if enemy < 4 else 1)
		w.projectiles().prev_pos[w.projectiles().index_of(id)] = c + c.normalized() * (r + 3.0)


func test_absorb_and_recharge_with_24_domes_and_300_projectiles_entering_per_call() -> void:
	var sc: Dictionary = _scene()
	var w: SimWorld = sc["w"]
	var domes: PackedInt32Array = sc["domes"]
	var sh: ShieldDomes = w.shields()
	var us_absorb: int = 0
	var absorbed: int = 0
	for _i: int in CALLS:
		for s: int in domes:
			sh._charge[s] = 1.0e9                                                     # never empty: every shot is absorbed
		_inject(w, domes)
		var t0: int = Time.get_ticks_usec()
		absorbed += sh.absorb(w.tick())
		us_absorb += Time.get_ticks_usec() - t0
	assert_int(absorbed).is_equal(CALLS * PROJECTILES)                                # hard counter: all absorbed
	assert_int(sh._a_n).is_equal(24)                                                  # 8 Cores + 16 Projectors active
	assert_int(w.projectiles().live_count()).is_equal(0)
	var per_call: float = float(us_absorb) / float(CALLS)
	assert_bool(PerfGate.check("shield_absorb_300_proj_24_domes", per_call, 400.0, "03 s4.2 row 9 combat 1.2 ms p95")).is_true()
	for s: int in domes:
		sh._charge[s] = 0.0
		sh._last_hit[s] = ShieldDomes.NEVER
	var ice0: int = w.economy().economy.stockpile(0).y + w.economy().economy.stockpile(1).y
	var us_step: int = 0
	for i: int in CALLS:
		var t1: int = Time.get_ticks_usec()
		sh.step(w.tick() + 1 + i)
		us_step += Time.get_ticks_usec() - t1
	var ice1: int = w.economy().economy.stockpile(0).y + w.economy().economy.stockpile(1).y
	assert_int(ice0 - ice1).is_greater(0)                                             # hard counter: the recharge paid Ice
	assert_float(sh.charge_of(domes[1])).is_greater(0.0)
	assert_bool(PerfGate.check("shield_step_24_domes_recharging", float(us_step) / float(CALLS), 100.0, "03 s4.2 row 10 economy 0.8 ms p95")).is_true()


# The S-SIM-1 shape: 2,000 live projectiles, 1,898 of them slugs, 100 bombs and rockets in flight outside every dome and
# two entering enemy domes this call.
func test_s_sim_1_load_2000_projectiles_100_absorbable_2_entering() -> void:
	var sc: Dictionary = _scene()
	var w: SimWorld = sc["w"]
	var domes: PackedInt32Array = sc["domes"]
	var sh: ShieldDomes = w.shields()
	var far: Vector3 = Vector3(0.0, 0.0, R + 800.0)                                    # over the pole, away from every base
	var us: int = 0
	var absorbed: int = 0
	for _i: int in CALLS:
		for s: int in domes:
			sh._charge[s] = 1.0e9
		for n: int in 1898:
			var _a: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", far + Vector3(float(n), 0.0, 0.0), 4, 1)
		for n: int in 100:
			var _b: int = CombatTestKit.shot(w, &"bomb" if n % 2 == 0 else &"rocket", &"bomb" if n % 2 == 0 else &"rocket_lancer", far + Vector3(0.0, float(n), 0.0), 4, 1)
		var enemy_dome: int = domes[3 + _i % 20]
		var c: Vector3 = w.store().pos[enemy_dome]
		var team: int = 1 if w.store().team[enemy_dome] == 0 else 0
		for k: int in 2:
			var id: int = CombatTestKit.shot(w, &"bomb", &"bomb", c + c.normalized() * (sh.dome_radius(enemy_dome) - 3.0), 4 * team, team)
			w.projectiles().prev_pos[w.projectiles().index_of(id)] = c + c.normalized() * (sh.dome_radius(enemy_dome) + 3.0)
		var t0: int = Time.get_ticks_usec()
		absorbed += sh.absorb(w.tick())
		us += Time.get_ticks_usec() - t0
		for i: int in w.projectiles().live.duplicate():
			var _f: bool = w.projectiles().free_slot(i, w.tick())
	assert_int(absorbed).is_equal(2 * CALLS)                                           # hard counter: exactly the two entering
	assert_bool(PerfGate.check("shield_absorb_2000_proj_2_entering", float(us) / float(CALLS), 250.0, "03 s4.2 row 9 combat 1.2 ms p95")).is_true()


func test_a_world_without_domes_pays_only_the_sync_check() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(-1.0, -1.0, true))
	w.step()
	var sh: ShieldDomes = w.shields()
	var t0: int = Time.get_ticks_usec()
	for i: int in 1000:
		var _n: int = sh.absorb(w.tick() + i)
	var per_call: float = float(Time.get_ticks_usec() - t0) / 1000.0
	assert_int(sh._a_n).is_equal(0)                                                   # hard counter: nothing active
	assert_bool(PerfGate.check("shield_absorb_no_domes", per_call, 20.0, "03 s4.2 row 9 combat 1.2 ms p95")).is_true()
