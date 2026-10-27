extends GdUnitTestSuite
## GD-09 acceptance scenarios on a real SimWorld with the tower brain and the sim's own slew and fire gates (02 s18.3
## C-01, C-02): the envelopes are read from `towers.json` (no literal), the targets are held in place so a scenario
## is a choice test. C-03 and C-04 are `test/unit/sim/combat/test_tower_gates.gd`.

const HZ: int = 30
const C0: Vector3 = Vector3(1, 0, 0)

var _w: SimWorld
var _d: AiDriver
var _tw: int


func _block(def: StringName) -> Dictionary:
	for sd: StructureDef in Ai17Kit.content().structures:
		if sd.id == def:
			return sd.tower
	return {}


func _setup(def: StringName) -> void:
	_w = Ai17Kit.world(11)
	_d = Ai17Kit.driver(_w, true, 3, Ai17Kit.brain())
	var _core: int = Ai14Kit.core(_w, DartKit.offset(C0, -300.0, 0.0), 0)       # supply and power
	_tw = Ai17Kit.tower(_w, def, 0, C0, DartKit.above(_w, DartKit.offset(C0, 500.0, 0.0), 0.0))


# A Dart of the foe pinned `h_rel` m over the tower and `east` m out for `ticks`; the shots the tower fired.
func _hold_foe(h_rel: float, east: float, ticks: int) -> int:
	var id: int = DartKit.spawn(_w, &"dart", DartKit.FOE, Ai17Kit.rel(_w, _tw, east, 0.0, h_rel), Vector3.ZERO, Vector3(0, 1, 0))
	_w.store().hp[EntityId.slot(id)] = 10000000.0
	var p: Vector3 = _w.view().pos(id)
	var shots: int = 0
	for _k: int in ticks:
		IntelKit.teleport(_w, id, p)
		var _e: Array[SimEvent] = Ai17Kit.step(_w)
		shots += 1 if (Ai17Kit.buttons(_w, _tw) & PilotInput.FIRE1) != 0 else 0
		shots = maxi(shots, Ai17Kit.shots_of(_w, _tw))
	assert_bool(_w.view().visible_to(0, id)).override_failure_message("the scenario target must be seen").is_true()
	return shots


func test_c01_a_bomber_level_above_h_rel_max_draws_no_autocannon_fire() -> void:
	var hi: float = float(_block(&"autocannon_turret").get("h_rel_max", 0.0))
	_setup(&"autocannon_turret")
	var pool: int = _w.view().ammo(_tw)
	var id: int = DartKit.spawn(_w, &"bomber", DartKit.FOE, Ai17Kit.rel(_w, _tw, 300.0, 0.0, 1.5 * hi), Vector3.ZERO, Vector3(0, 1, 0))   # 600 m rel
	_w.store().hp[EntityId.slot(id)] = 10000000.0
	var p: Vector3 = _w.view().pos(id)
	for _k: int in 20 * HZ:
		IntelKit.teleport(_w, id, p)
		var _e: Array[SimEvent] = Ai17Kit.step(_w)
	assert_float(p.length() - _w.view().pos(_tw).length()).is_equal_approx(1.5 * hi, 1.0)
	assert_bool(_w.view().visible_to(0, id)).is_true()
	assert_int(_w.view().ammo(_tw)).is_equal(pool)
	assert_int(Ai17Kit.shots_of(_w, _tw)).is_equal(0)


func test_c02_a_dart_below_the_flak_floor_for_twenty_seconds_draws_no_shell() -> void:
	var lo: float = float(_block(&"flak_battery").get("h_rel_min", 0.0))
	_setup(&"flak_battery")
	var pool: int = _w.view().ammo(_tw)
	var shots: int = _hold_foe(0.66 * lo, 800.0, 20 * HZ)                   # 100 m rel, inside 1,000 m
	assert_int(shots).is_equal(0)
	assert_int(_w.view().ammo(_tw)).is_equal(pool)


func test_c02_control_the_same_dart_above_the_floor_draws_fire() -> void:
	var lo: float = float(_block(&"flak_battery").get("h_rel_min", 0.0))
	_setup(&"flak_battery")
	var shots: int = _hold_foe(1.5 * lo, 800.0, 10 * HZ)
	assert_int(shots).is_greater(0)
