extends GdUnitTestSuite
## AI-16 scenarios on a real SimWorld (05 s11.2; R0 C1-05): SC-32 harvester_cycle, SC-33 harvester_flee_and_return,
## SC-34 harvester_repath_on_build. The sim runs the real Pathing (step 3b), GroundMotion (step 5) and Harvest (step 10);
## the brain only drives (`Ai16Kit`). Distances are metres of arc along +Y from +X on the flat datum.

const HZ: int = 30

var _w: SimWorld
var _d: AiDriver
var _brain: HarvesterBrain


# A Refinery at 0 m, a field `field_east` m away, one Harvester at the Refinery; returns the Harvester id.
func _cycle(field_east: float, with_brain: bool = true) -> int:
	_w = Ai16Kit.world(11)
	var _ref: int = Ai16Kit.put(_w, &"refinery", 0, 0.0)
	var _f: int = Ai16Kit.field(_w, field_east)
	var h: int = Ai16Kit.put(_w, &"harvester", 0, 60.0)
	if with_brain:
		_brain = Ai16Kit.brain()
		_d = Ai16Kit.driver(_w, _brain)
	return h


func _tag(h: int) -> int:
	return _w.view().ai_tag(h)


func _run(ticks: int) -> void:
	Ai16Kit.step(_w, ticks)


# SC-32 harvester_cycle: 1 Harvester, 1 field, 1 Refinery -> >= 3 full deliveries in 10 sim-min; never idle > 20 s.
func test_sc32_harvester_cycle() -> void:
	var h: int = _cycle(450.0)
	var idle: int = 0
	var worst: int = 0
	var drops: int = 0
	var cargo: float = 0.0
	var last: Vector3 = _w.view().pos(h)
	for _k: int in 10 * 60 * HZ:
		Ai16Kit.step(_w)
		var p: Vector3 = _w.view().pos(h)
		var t: int = _tag(h)
		# "idle" = standing still outside the stops the sim itself makes it wait at (mining, unloading, queueing)
		var waits: bool = t == AiTag.Tag.MINE or t == AiTag.Tag.UNLOAD or t == AiTag.Tag.QUEUE
		idle = idle + 1 if (p.distance_to(last) < 0.001 and not waits) else 0
		worst = maxi(worst, idle)
		last = p
		drops += 1 if cargo >= 300.0 and _w.view().cargo(h) == 0.0 else 0   # a full load (cargo_ore 300) unloaded
		cargo = _w.view().cargo(h)
	assert_int(drops).is_greater_equal(3)
	assert_int(worst).is_less(20 * HZ)


# Runs until `tag` shows on `h` (up to `max_ticks`); returns the ticks it took, -1 when it never did.
func _until(h: int, tag: int, max_ticks: int) -> int:
	for k: int in max_ticks:
		Ai16Kit.step(_w)
		if _tag(h) == tag:
			return k + 1
	return -1


# A frozen enemy Lancer `north` m of the field at 200 m AGL (no brain, so it only has to be visible and armed); pinned
# in place each tick by `_hold`.
func _lancer(field_east: float, north: float) -> int:
	var lp: Vector3 = DartKit.above(_w, Ai16Kit.dir_at(field_east, north), 200.0)
	var id: int = Ai17Kit.spawn_many(_w, &"lancer", DartKit.FOE, lp, Vector3.ZERO, DartKit.heading(lp, Ai16Kit.dir_at(field_east, 0.0) * Ai16Kit.R))
	_w.store().hp[EntityId.slot(id)] = 10000000.0
	return id


func _hold(id: int, at: Vector3) -> void:
	var s: int = EntityId.slot(id)
	_w.store().pos[s] = at
	_w.store().vel[s] = Vector3.ZERO


# SC-33 harvester_flee_and_return: an enemy Lancer attacks a mining Harvester, a friendly Autocannon 800 m away -> it flees
# toward the tower within one think of the threat being seen (+ the Vision epoch), and resumes the cycle 15 s after the
# threat is dead.
func test_sc33_harvester_flee_and_return() -> void:
	var h: int = _cycle(600.0)
	var tower: int = Ai16Kit.put(_w, &"autocannon_turret", 0, 600.0, 800.0)
	assert_int(_until(h, AiTag.Tag.MINE, 120 * HZ)).is_greater(0)
	var hs: int = EntityId.slot(h)
	var lancer: int = _lancer(600.0, -300.0)
	var lp: Vector3 = _w.view().pos(lancer)
	var d0: float = Ai16Kit.apart(_w, h, tower)
	var seen: int = 0
	for k: int in 60:
		_hold(lancer, lp)
		Ai16Kit.step(_w)
		if _tag(h) == AiTag.Tag.FLEE:
			seen = k + 1
			break
	var one_think: int = _d.think_period() + _brain.prm.vision_period + 2   # a think, the Vision epoch, the Lancer's first sight
	assert_int(seen).is_between(1, one_think)
	assert_int(_d.state.target[hs]).is_equal(tower)                         # the tower covers the Lancer's band
	for _k: int in 5 * HZ:
		_hold(lancer, lp)
		Ai16Kit.step(_w)
	assert_float(Ai16Kit.apart(_w, h, tower)).is_less(d0 - 30.0)            # toward it
	assert_int(_tag(h)).is_equal(AiTag.Tag.FLEE)
	_w._applier.kill(EntityId.slot(lancer))
	Ai16Kit.step(_w, 2)
	assert_bool(_w.view().alive(lancer)).is_false()
	var dead: int = _w.tick()
	Ai16Kit.step(_w, 14 * HZ)
	assert_int(_tag(h)).is_equal(AiTag.Tag.FLEE)                            # not before the quiet time is up
	Ai16Kit.step(_w, 2 * HZ + _d.think_period())
	assert_int(_tag(h)).is_not_equal(AiTag.Tag.FLEE)                        # 15 s after the threat died (+ a think)
	assert_int(_w.tick() - dead).is_greater_equal(15 * HZ)
	assert_int(_until(h, AiTag.Tag.MINE, 150 * HZ)).is_greater(0)           # back to mining


# The other trigger: a hull loss within `hit_window_s` flees with no enemy in sight (HIT in the last 3 s).
func test_a_hit_flees_with_no_enemy_visible() -> void:
	var h: int = _cycle(450.0)
	assert_int(_until(h, AiTag.Tag.MINE, 120 * HZ)).is_greater(0)
	_w.store().hp[EntityId.slot(h)] *= 0.8
	var k: int = _until(h, AiTag.Tag.FLEE, 30)
	assert_int(k).is_between(1, _d.think_period() + 1)
	assert_int(_until(h, AiTag.Tag.MINE, 150 * HZ)).is_greater(0)           # no more hits: quiet_s later it is back
	assert_int(_brain.stats_flees).is_equal(1)


# SC-34 harvester_repath_on_build: a wall of blocked path cells (what a structure's footprint does) across the route of a
# Harvester on its way to a far field -> it repaths within one think, arrives, and no stuck strike is ever counted.
func test_sc34_harvester_repath_on_build() -> void:
	var h: int = _cycle(1200.0)
	var hs: int = EntityId.slot(h)
	Ai16Kit.step(_w, 5 * HZ)
	assert_int(_tag(h)).is_equal(AiTag.Tag.TO_FIELD)
	assert_bool(_d.state.path.has(hs)).is_true()
	var pa: Pathing = _w._pathing
	var r0: int = pa.requests
	var cell_m: float = Sphere.PLANET_RADIUS * PI * 0.5 / float(PathGrid.N)
	for k: int in range(-26, 27):                                           # 13 cells = 480 m wide, across the route at 700 m, 3 columns thick
		for e: float in [690.0, 700.0, 710.0]:                              # sampled at a quarter cell so the wall has no gap
			pa.set_weight(PathGrid.cell_of(Ai16Kit.dir_at(e, float(k) * cell_m * 0.25)), PathGrid.W_BLOCKED)
	var again: int = 0
	for k: int in 3 * _d.think_period():
		Ai16Kit.step(_w)
		if pa.requests > r0:
			again = k + 1
			break
	assert_int(again).is_between(1, _d.think_period() + 1)                  # a think later, not after a stuck window
	var detour: float = 0.0
	var arrived: int = -1
	for k: int in 200 * HZ:
		Ai16Kit.step(_w)
		detour = maxf(detour, absf(_w.view().pos(h).z))
		if _tag(h) == AiTag.Tag.MINE:
			arrived = k
			break
	assert_int(arrived).is_greater_equal(0)                                  # arrived ...
	assert_float(detour).is_greater(6.0 * cell_m)                            # ... around the wall, not through it
	assert_int(_brain.stats_strikes).is_equal(0)
	assert_int(_brain.stats_gave_up).is_equal(0)
