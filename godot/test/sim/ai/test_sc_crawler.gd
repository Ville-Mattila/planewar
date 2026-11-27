extends GdUnitTestSuite
## AI-18 scenarios on a real SimWorld on `tiny_test` (05 s6.7, AI-18 acceptance): the Siege Crawler attacks from
## 1,000-1,150 m, relocates after a near bomb, and holds with NO_AMMO after its 20 shells. The sim runs the real Pathing,
## GroundMotion, weapon fire (step 9) and Combat; the brain only drives (`Ai18Kit`). Layout (metres of arc along +Y from
## +X): an enemy Refinery at 0, a friendly Sensor Mast 950 m from it (its deck reveal, 1,200 m, is the team's eyes on the target: the Crawler's own sensor
## is 1,000 m), the Crawler at 2,600. AI-18b: the brain lays the barrel on the lofted solve, so every shell lands on the
## target (within `loft_tol_m`, with the spread off); the highest elevation that still lands inside the shell's lifetime
## is measured for GD-34 (R0 B.31 A-151).

const HZ: int = 30
const MAP: StringName = &"tiny_test"

var _w: SimWorld
var _d: AiDriver
var _b: CrawlerBrain
var _target: int
var _shots: Array[float] = []   ## Crawler-to-target distance at every shell spawn
var _miss: Array[float] = []    ## AI-18b: per ended shell, great-circle distance target - contact point (0 = struck the target)
var _land: Array[float] = []    ## AI-18b: per fired shell, great-circle distance target - its ballistic ground point
var _hits: int = 0              ## shells that struck the target's body
var _lost: int = 0              ## shells that ended without a contact (expired in the air)
var _elev: Array[float] = []    ## barrel elevation (rad) at every shell spawn
var _live: Dictionary = {}      ## shell projectile id -> true
var _aim: Vector3 = Vector3.ZERO     ## the target's position at setup (it stands)
var _hold_max: float = 0.0      ## the longest BRAKE hold the sim counted on the Crawler (s)


func _setup(crawler_east: float = 2600.0, defs: ContentSet = null, target_def: StringName = &"refinery") -> int:
	_w = Ai18Kit.world(defs, 5, MAP)
	_target = Ai16Kit.put(_w, target_def, DartKit.FOE, 0.0)
	_aim = _w.view().pos(_target)
	var _m: int = Ai16Kit.put(_w, &"sensor_mast", 0, 900.0, 300.0)
	var c: int = Ai16Kit.put(_w, &"siege_crawler", 0, crawler_east)
	_b = Ai18Kit.brain(_w.terrain())
	_d = Ai18Kit.driver(_w, _b)
	_shots.clear()
	_miss.clear()
	_land.clear()
	_hits = 0
	_elev.clear()
	_lost = 0
	_live.clear()
	_hold_max = 0.0
	return c


func _tag(id: int) -> int:
	return _w.view().ai_tag(id)


# One tick, recording every new shell (the Crawler's distance to the target, the barrel elevation), the contact point of
# every shell that ended (its miss from the target) or that it expired, the BRAKE hold.
func _tick(c: int) -> void:
	Ai16Kit.step(_w)
	var ps: ProjectileStore = _w.projectiles()
	for k: Variant in _live.keys():
		var pid: int = k
		var ci: int = Ai18Kit.contact(_w, pid)
		if ci >= 0:
			var col: Collision = _w.collision
			var struck: bool = col.c_kind[ci] == Collision.C_HIT and col.c_b[ci] == _target
			_hits += 1 if struck else 0
			_miss.append(0.0 if struck else _arc(col.c_point[ci]))
			var _e: bool = _live.erase(k)
		elif not ps.alive(pid):
			_lost += 1
			var _e2: bool = _live.erase(k)
	for i: int in Ai18Kit.shells(_w, 0):
		var pid: int = ps.id_of(i)
		if not _live.has(pid):
			_shots.append(_w.view().pos(c).distance_to(_w.view().pos(_target)))
			_elev.append(_w.view().barrel_elevation(c))
			_land.append(_arc(Ai18Kit.ground_point(_w, ps.pos[i], ps.vel[i])))
			_live[pid] = true
	_hold_max = maxf(_hold_max, _w.store().timer_b[EntityId.slot(c)])


# Great-circle metres from the target's position (last read: it may be dead) to the direction of `q`.
func _arc(q: Vector3) -> float:
	return q.normalized().angle_to(_aim) * Sphere.PLANET_RADIUS if q != Vector3.ZERO else INF


func _run(c: int, ticks: int) -> void:
	for _k: int in ticks:
		_tick(c)


func _until(c: int, tag: int, max_ticks: int) -> int:
	for k: int in max_ticks:
		_tick(c)
		if _tag(c) == tag:
			return k + 1
	return -1


func _attack(c: int) -> void:
	DartKit.order(_w, c, OrderSpec.make(OrderSpec.Kind.ATTACK, _target))


# AI-18 acceptance 1 + AI-18b: attacks from 1,000-1,150 m on tiny_test. Every shell leaves while the Crawler stands in
# the band with the barrel laid on the lofted solve; its ballistic landing point is within `loft_tol_m` of the target and
# it strikes the Refinery (bounding radius 39 m, so the contact is its near face, ~38 m from the centre). Spread off: the
# solve's accuracy, not the dice. The trigger is never held on the way; waiting never reaches the sim's reverse hold.
func test_attacks_from_1000_to_1150_m() -> void:
	var c: int = _setup(2600.0, BarrelTestKit.no_spread_content())
	_run(c, HZ)
	assert_int(_tag(c)).is_equal(AiTag.Tag.HOLD)                              # AUTO = HOLD (01 s4.3)
	_attack(c)
	assert_int(_until(c, AiTag.Tag.SIEGE, 2 * _d.think_period())).is_greater(0)
	var first: int = -1
	for k: int in 240 * HZ:
		_tick(c)
		if _miss.size() >= 3:
			first = k
			break
	assert_int(first).is_greater(0)
	_on_target(c)
	assert_int(_hits).is_equal(_miss.size())                                  # every ended shell struck the Refinery
	assert_float(_hold_max).is_less(0.5 - 0.5 / float(HZ))                   # BRAKE never held up to the reverse hold
	assert_int(_b.stats_gave_up).is_equal(0)
	print("AI-18b SC attack (Refinery): shells at %s m, elevation %.2f deg, ballistic landing %s m from the target, %d of %d struck it" % [
		str(_shots), rad_to_deg(_elev[0]), str(_land), _hits, _miss.size()])


# AI-18b on a small target: an enemy Harvester (bounding radius 4.5 m) standing 1,075 m out; every shell's contact point
# (a hit on it, or the ground) is within `loft_tol_m` of it until it dies.
func test_shells_land_within_loft_tol_of_a_small_target() -> void:
	var c: int = _setup(1075.0, BarrelTestKit.no_spread_content(), &"harvester")
	_attack(c)
	for _k: int in 60 * HZ:
		_tick(c)
		if _miss.size() >= 3 or not _w.view().alive(_target):
			break
	assert_int(_miss.size()).is_greater(0)
	_on_target(c)
	for m: float in _miss:
		assert_float(m).is_less_equal(_b.prm.loft_tol_m)
	print("AI-18b SC attack (Harvester): elevation %.2f deg, contacts %s m and ballistic landing %s m from it, %d struck it" % [
		rad_to_deg(_elev[0]), str(_miss), str(_land), _hits])


# Every shell left from the band, with the barrel on the solve, with its ballistic landing point within loft_tol_m of the
# target, and none expired in the air.
func _on_target(c: int) -> void:
	var s: int = EntityId.slot(c)
	for d: float in _shots:
		assert_float(d).is_between(1000.0, 1150.0)
	for e: float in _elev:
		assert_float(e).is_equal_approx(_d.state.tti[s], 1e-9)                    # fired only with the barrel laid
		assert_float(rad_to_deg(e)).is_between(5.0, 25.0)
	for m: float in _land:
		assert_float(m).is_less_equal(_b.prm.loft_tol_m)
	assert_int(_lost).is_equal(0)


# AI-18 acceptance 2: an enemy bomb within 60 m moves the Crawler along the ring away from it (RELOCATE), still inside the
# band, and it fires again from the new spot; a bomb 200 m away and a friendly bomb 30 m away move nothing.
func test_relocates_after_a_near_bomb() -> void:
	var c: int = _setup(1075.0)                                              # in the band already: it sieges where it stands
	_attack(c)
	_run(c, 2 * _d.think_period())
	assert_int(_tag(c)).is_equal(AiTag.Tag.SIEGE)
	var s: int = EntityId.slot(c)
	var p0: Vector3 = _w.view().pos(c)
	var _f: int = Ai18Kit.bomb(_w, Ai16Kit.dir_at(1075.0, 200.0), DartKit.FOE, 1, 0)
	var _g: int = Ai18Kit.bomb(_w, Ai16Kit.dir_at(1075.0, -30.0), 0, 0, 0)     # friendly
	_run(c, 3 * HZ)
	assert_int(_tag(c)).is_equal(AiTag.Tag.SIEGE)
	assert_int(_b.stats_relocations).is_equal(0)
	var n0: int = _shots.size()
	var impact: Vector3 = Ai16Kit.dir_at(1075.0, 40.0)
	var _h: int = Ai18Kit.bomb(_w, impact, DartKit.FOE, 1, 0)
	var k: int = _until(c, AiTag.Tag.RELOCATE, 3 * HZ)
	assert_int(k).is_between(1, 2 * HZ)                                      # the fall (~1.2 s) and one woken think
	assert_int(_b.stats_relocations).is_equal(1)
	var spot: Vector3 = _d.state.goal[s]
	var hit: Vector3 = impact * Sphere.PLANET_RADIUS
	assert_float(GroundFollower.flat(spot, hit)).is_greater(GroundFollower.flat(p0, hit) + 60.0)   # away from the impact
	assert_float(spot.distance_to(_w.view().pos(_target))).is_between(1000.0, 1150.0)
	assert_int(_until(c, AiTag.Tag.SIEGE, 60 * HZ)).is_greater(0)
	_run(c, 10 * HZ)
	assert_int(_shots.size()).is_greater(n0)                                 # firing again from the new spot
	assert_float(GroundFollower.flat(_w.view().pos(c), p0)).is_greater(100.0)
	for d: float in _shots:
		assert_float(d).is_between(1000.0, 1150.0)


# AI-18 acceptance 3: after its 20 shells the Crawler decides NO_AMMO and holds: no more shells, it stands, HOLD.
func test_no_ammo_after_20_shells() -> void:
	var c: int = _setup(1075.0)
	_attack(c)
	var empty: int = -1
	for k: int in 120 * HZ:
		_tick(c)
		if _w.view().ammo(c) == 0 and _tag(c) == AiTag.Tag.HOLD:
			empty = k
			break
	assert_int(empty).is_greater(0)
	assert_int(_shots.size()).is_equal(20)
	assert_int(_b.stats_no_ammo).is_equal(1)
	var p: Vector3 = _w.view().pos(c)
	_run(c, 20 * HZ)
	assert_int(_shots.size()).is_equal(20)
	assert_int(_tag(c)).is_equal(AiTag.Tag.HOLD)
	assert_float(_w.view().pos(c).distance_to(p)).is_less(0.01)
	assert_int(_b.stats_no_ammo).is_equal(1)                                  # decided once per empty magazine
	assert_int(_w.view().order_head(c).kind).is_equal(OrderSpec.Kind.ATTACK)  # ORDER_FAILED(NO_AMMO) needs a sink call
	print("AI-18 SC no_ammo: 20 shells in %.1f s; impacts %s m from the target (spread 1.5 deg)" % [float(empty) / float(HZ),
		str(_miss.slice(0, 5))])
