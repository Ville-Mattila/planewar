extends GdUnitTestSuite
## 05 s11.2 SC-38 scout_explores_and_flees (AI-14) through SimWorld.step() with an AiDriver hook (Ai14Kit: the Scout
## and Dart brains, per-team intel for teams 0 and 1). Flat datum. Team 0: a Core (home pad, sensors) and one Scout on
## AUTO (SEARCH) above it; team 1: one Dart on its AUTO patrol (no pad: round its spawn point, 2-3 km from the Scout's
## home on a seeded bearing, so its 1,200 m circle and 2 km intercept radius cover the Scout's first search rings). Pass:
## the Scout's position visits >= 12 distinct interest cells in 3 min in every seed 0-9; it survives the first contact
## (the first tick the Dart is within `CONTACT_M`, the Scout's sensor radius: alive `SURVIVE_S` later, or at the end of
## the 3 min if sooner; 05 s11.2 "survives" = not destroyed) in >= 7 / 10 seeds, with contact in >= 7 / 10. Hull loss
## in that window is reported (unhurt count).

const HZ: int = 30
const CONTACT_M: float = 2000.0
const SURVIVE_S: int = 30
const PATROL_MIN_M: float = 2000.0   ## the enemy Dart patrols its 1,200 m AUTO circle round a point this far from home
const PATROL_MAX_M: float = 3000.0


# One seed over 3 min: [distinct cells, contact tick or -1, survived contact, flees, world, scout].
func _run(seed_value: int) -> Array:
	var rng: Rng = Rng.new(3800 + seed_value)
	var w: SimWorld = Ai14Kit.world(seed_value)
	var d: AiDriver = Ai14Kit.driver(w)
	var home: Vector3 = Vector3(1, 0, 0)
	var _core: int = Ai14Kit.core(w, home, 0)
	var a: float = rng.range_f(0.0, TAU)
	var r: float = rng.range_f(PATROL_MIN_M, PATROL_MAX_M)
	var pd: Vector3 = DartKit.above(w, DartKit.offset(home, r * cos(a), r * sin(a)), 300.0)   # its patrol centre (no pad)
	var hd: Vector3 = DartKit.heading(pd, home)
	var dart: int = DartKit.spawn(w, &"dart", DartKit.FOE, pd, hd * 110.0, hd)
	var ps: Vector3 = DartKit.above(w, home, 500.0)
	var hs: Vector3 = DartKit.heading(ps, Vector3(0, 1, 0)).rotated(home, rng.range_f(0.0, TAU))
	var scout: int = DartKit.spawn(w, &"scout", 0, ps, hs * 140.0, hs)
	var cells: Dictionary = {}
	var contact: int = -1
	var survived: bool = true
	var min_d: float = INF
	var unhurt: bool = true
	var killer: int = 0
	for _k: int in 180 * HZ:
		var ev: Array[SimEvent] = Ai14Kit.step(w)
		for e: SimEvent in ev:
			if e.kind == SimEvent.Kind.DEATH and e.a == scout:
				killer = e.b
		var v: SimView = w.view()
		var in_window: bool = contact < 0 or w.tick() <= contact + SURVIVE_S * HZ
		if not v.alive(scout):
			survived = survived and not in_window
			break
		cells[Sphere.cell_of(v.pos(scout), Sphere.GRID_INTEREST)] = true
		if v.alive(dart):
			min_d = minf(min_d, v.pos(scout).distance_to(v.pos(dart)))
		if in_window and contact >= 0 and v.hp01(scout) < 1.0:
			unhurt = false
		if contact < 0 and v.alive(dart) and v.pos(scout).distance_to(v.pos(dart)) < CONTACT_M:
			contact = w.tick()
	var brain: ScoutBrain = Ai14Kit.brain_of(d, &"scout") as ScoutBrain
	return [cells.size(), contact, survived, brain.stats_flees, w, scout, brain.stats_scans, min_d, killer == dart, unhurt]


func test_sc38_scout_explores_and_flees() -> void:
	var survived: int = 0
	var unhurt: int = 0
	var contacts: int = 0
	var min_cells: int = 1 << 30
	var lines: PackedStringArray = PackedStringArray()
	for seed_value: int in 10:
		var r: Array = _run(seed_value)
		var w: SimWorld = r[4]
		var cells: int = r[0]
		min_cells = mini(min_cells, cells)
		contacts += 1 if r[1] >= 0 else 0
		survived += 1 if r[2] else 0
		unhurt += 1 if r[2] and r[9] else 0
		var _a: bool = lines.push_back("seed %d: cells %d, contact %s, %s, flees %d, scans %d, closest %.0f m, scout alive %s hp %.2f%s" % [
			seed_value, cells, ("at %.1f s" % (float(r[1]) / float(HZ))) if r[1] >= 0 else "none",
			"survived" if r[2] else "LOST", r[3], r[6], r[7], w.view().alive(r[5]), w.view().hp01(r[5]),
			" (killed by the Dart)" if r[8] else ""])
	var what: String = "SC-38: min cells %d, survived %d / 10 (unhurt %d), contacts %d / 10\n  %s" % [min_cells, survived, unhurt, contacts,
		"\n  ".join(lines)]
	print(what)
	assert_int(min_cells).override_failure_message(what).is_greater_equal(12)
	assert_int(contacts).override_failure_message(what).is_greater_equal(7)   # the flee rule is exercised
	assert_int(survived).override_failure_message(what).is_greater_equal(7)
