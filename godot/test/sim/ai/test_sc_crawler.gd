extends GdUnitTestSuite
## AI-18 scenarios on a real SimWorld on `tiny_test` (05 s6.7, AI-18 acceptance): the Siege Crawler attacks from
## 1,000-1,150 m, relocates after a near bomb, and holds with NO_AMMO after its 20 shells. The sim runs the real Pathing,
## GroundMotion, weapon fire (step 9) and Combat; the brain only drives (`Ai18Kit`). Layout (metres of arc along +Y from
## +X): an enemy Refinery at 0, a friendly Sensor Mast 950 m from it (its deck reveal, 1,200 m, is the team's eyes on the target: the Crawler's own sensor
## is 1,000 m), the Crawler at 2,600.

const HZ: int = 30
const MAP: StringName = &"tiny_test"

var _w: SimWorld
var _d: AiDriver
var _b: CrawlerBrain
var _target: int
var _shots: Array[float] = []   ## Crawler-to-target distance at every shell spawn
var _reach: Array[float] = []   ## muzzle-to-last-position distance of every shell that ended (REPORT: needs sim)
var _live: Dictionary = {}      ## shell index -> [spawn position, last position]
var _hold_max: float = 0.0      ## the longest BRAKE hold the sim counted on the Crawler (s)


func _setup(crawler_east: float = 2600.0) -> int:
	_w = Ai16Kit.world(5, MAP)
	_target = Ai16Kit.put(_w, &"refinery", DartKit.FOE, 0.0)
	var _m: int = Ai16Kit.put(_w, &"sensor_mast", 0, 900.0, 300.0)
	var c: int = Ai16Kit.put(_w, &"siege_crawler", 0, crawler_east)
	_b = Ai18Kit.brain(_w.terrain())
	_d = Ai18Kit.driver(_w, _b)
	_shots.clear()
	_reach.clear()
	_live.clear()
	_hold_max = 0.0
	return c


func _tag(id: int) -> int:
	return _w.view().ai_tag(id)


# One tick, recording every new shell (the Crawler's distance to the target), every shell that ended, the BRAKE hold.
func _tick(c: int) -> void:
	Ai16Kit.step(_w)
	var ps: ProjectileStore = _w.projectiles()
	var now: PackedInt32Array = Ai18Kit.shells(_w, 0)
	for i: int in now:
		if not _live.has(i):
			_shots.append(_w.view().pos(c).distance_to(_w.view().pos(_target)))
			_live[i] = [ps.pos[i], ps.pos[i]]
		else:
			(_live[i] as Array)[1] = ps.pos[i]
	for k: Variant in _live.keys():
		if not now.has(k as int):
			var rec: Array = _live[k]
			_reach.append(GroundFollower.flat(rec[0] as Vector3, rec[1] as Vector3))
			var _e: bool = _live.erase(k)
	_hold_max = maxf(_hold_max, _w.store().timer_b[EntityId.slot(c)])


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


# AI-18 acceptance 1: attacks from 1,000-1,150 m on tiny_test. Every shell leaves while the Crawler stands in the band;
# the trigger is never held on the way; waiting never reaches the sim's reverse hold.
func test_attacks_from_1000_to_1150_m_on_tiny_test() -> void:
	var c: int = _setup()
	_run(c, HZ)
	assert_int(_tag(c)).is_equal(AiTag.Tag.HOLD)                              # AUTO = HOLD (01 s4.3)
	_attack(c)
	assert_int(_until(c, AiTag.Tag.SIEGE, 2 * _d.think_period())).is_greater(0)
	var first: int = -1
	for k: int in 240 * HZ:
		_tick(c)
		if _shots.size() >= 3:
			first = k
			break
	assert_int(first).is_greater(0)
	for d: float in _shots:
		assert_float(d).is_between(1000.0, 1150.0)
	assert_float(_hold_max).is_less(0.5 - 0.5 / float(HZ))                   # BRAKE never held up to the reverse hold
	assert_int(_b.stats_gave_up).is_equal(0)
	print("AI-18 SC attack: first 3 shells at %s m; shell reach so far %s m" % [str(_shots), str(_reach)])


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
	print("AI-18 SC no_ammo: 20 shells in %.1f s; shell reach %s m" % [float(empty) / float(HZ), str(_reach.slice(0, 5))])
