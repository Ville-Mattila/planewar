extends GdUnitTestSuite
## AI-17 tower brain on a real SimWorld (05 s6.8, R0 C2-15; sim_ai/brains/MODULE.md TB1-TB7): the idle states and their
## tags (IDLE, OFFLINE for power, HOLD, under construction), tracking and firing inside the `towers.json` envelope, the
## ATTACK and GUARD orders, the x1.5 attacker mark from `AiHitLog`, ground contacts through Perception for the
## Autocannon only, the zero drive when a target is lost, no input while possessed. The sim does not slew a turret
## yet (GD-09): the driver is Ai17Kit's SlewDriver, which applies the brain's pitch / yaw drive to the muzzle.

const HZ: int = 30
const C0: Vector3 = Vector3(1, 0, 0)

var _w: SimWorld
var _d: Ai17Kit.SlewDriver
var _tw: int
var _brain: TowerBrain


# A world with team 0's power (a Core 90 degrees away) and one tower of `def` on team 0 under C0, its muzzle toward +east.
func _setup(def: StringName, power: bool = true, agl: float = 0.0) -> void:
	_w = Ai17Kit.world(11)
	_brain = Ai17Kit.brain()
	_d = Ai17Kit.driver(_w, true, 3, _brain)
	if power:
		var _core: int = Ai14Kit.core(_w, Vector3(-1, 0, 0), 0)
	_tw = Ai17Kit.tower(_w, def, 0, C0, DartKit.above(_w, DartKit.offset(C0, 500.0, 0.0), 0.0), agl)


func _foe(def: StringName, east: float, north: float, h_rel: float, tank: bool = false) -> int:
	var id: int = DartKit.spawn(_w, def, DartKit.FOE, Ai17Kit.rel(_w, _tw, east, north, h_rel), Vector3.ZERO, Vector3(0, 1, 0))
	if tank:
		_w.store().hp[EntityId.slot(id)] = 10000000.0   # survives the fight: a choice test, not a kill test
	return id


func _run(ticks: int) -> void:
	for _k: int in ticks:
		var _e: Array[SimEvent] = Ai17Kit.step(_w)


func _s() -> int:
	return EntityId.slot(_tw)


func _mode() -> int:
	return _d.state.mode[_s()]


func _target() -> int:
	return _d.state.target[_s()]


func test_a_tower_without_enemies_idles_and_drives_nothing() -> void:
	_setup(&"autocannon_turret")
	_run(2 * HZ)
	assert_int(_mode()).is_equal(AiTag.Tag.IDLE)
	assert_int(_w.view().ai_tag(_tw)).is_equal(AiTag.Tag.IDLE)
	assert_int(_target()).is_equal(0)
	assert_int(_brain.stats_acts).is_equal(0)
	assert_int(Ai17Kit.buttons(_w, _tw)).is_equal(0)
	assert_int(_d.state.bflags[_s()] & TowerBrain.B_DRIVEN).is_equal(0)   # an idle tower is never driven


func test_a_tower_tracks_slews_and_fires_at_a_target_inside_its_envelope() -> void:
	_setup(&"autocannon_turret")
	var dart: int = _foe(&"dart", 0.0, 400.0, 100.0)   # 90 degrees from the muzzle: the slew has to turn first
	_run(3 * HZ)
	assert_int(_mode()).is_equal(AiTag.Tag.TRACK)
	assert_int(_w.view().ai_tag(_tw)).is_equal(AiTag.Tag.TRACK)
	assert_int(_target()).is_equal(dart)
	var v: SimView = _w.view()
	var to: Vector3 = (v.pos(dart) - v.pos(_tw)).normalized()
	assert_float(rad_to_deg((-v.basis(_tw).z).angle_to(to))).is_less(8.0)
	assert_int(v.ammo(_tw)).is_less(300)   # the pool was spent: the sim fired along the slewed muzzle
	assert_int(_brain.stats_visible).is_equal(_brain.stats_acts)   # one visible_to per tracking act


func test_offline_tower_idles_with_the_offline_tag() -> void:
	_setup(&"autocannon_turret", false)
	var _dart: int = _foe(&"dart", 300.0, 0.0, 100.0)
	_run(2 * HZ)
	assert_float(_w.view().stockpile(0).z).is_less(Ai17Kit.content().economy.tower_offline_ratio)
	assert_int(_mode()).is_equal(AiTag.Tag.OFFLINE)
	assert_int(_w.view().ai_tag(_tw)).is_equal(AiTag.Tag.OFFLINE)
	assert_int(_target()).is_equal(0)
	assert_int(_w.view().ammo(_tw)).is_equal(300)
	assert_int(Ai17Kit.buttons(_w, _tw)).is_equal(0)


func test_hold_order_holds_fire_and_clears_the_target() -> void:
	_setup(&"autocannon_turret")
	var dart: int = _foe(&"dart", 300.0, 0.0, 100.0)
	_run(2 * HZ)
	assert_int(_target()).is_equal(dart)
	DartKit.order(_w, _tw, OrderSpec.make(OrderSpec.Kind.HOLD))
	_run(HZ)   # the next think (<= 10 ticks) sees the order
	assert_int(_mode()).is_equal(AiTag.Tag.HOLD)
	assert_int(_w.view().ai_tag(_tw)).is_equal(AiTag.Tag.HOLD)
	assert_int(_target()).is_equal(0)
	assert_int(Ai17Kit.buttons(_w, _tw)).is_equal(0)   # a zero drive followed the last driven act
	var ammo: int = _w.view().ammo(_tw)
	_run(2 * HZ)
	assert_int(_w.view().ammo(_tw)).is_equal(ammo)


func test_a_tower_under_construction_idles() -> void:
	_setup(&"autocannon_turret")
	_w.store().flags[_s()] |= EntityStore.F_BUILDING
	var _dart: int = _foe(&"dart", 300.0, 0.0, 100.0)
	_run(2 * HZ)
	assert_int(_mode()).is_equal(AiTag.Tag.IDLE)
	assert_int(_target()).is_equal(0)


func test_attack_order_takes_the_ordered_target_when_eligible_else_the_normal_choice() -> void:
	_setup(&"autocannon_turret")
	var bomber: int = _foe(&"bomber", 300.0, 0.0, 200.0)
	var dart: int = _foe(&"dart", 350.0, 100.0, 150.0)
	_run(2 * HZ)
	assert_int(_target()).is_equal(bomber)                      # priority: bomber 100 over dart 50
	DartKit.order(_w, _tw, OrderSpec.make(OrderSpec.Kind.ATTACK, dart))
	_run(HZ)
	assert_int(_target()).is_equal(dart)                        # the ordered target, eligible
	var high: int = _foe(&"scout", 300.0, -100.0, 500.0)        # above h_rel_max: never eligible
	DartKit.order(_w, _tw, OrderSpec.make(OrderSpec.Kind.ATTACK, high))
	_run(HZ)
	assert_int(_target()).is_equal(bomber)                      # not eligible: the normal choice


func test_guard_order_doubles_the_attackers_of_the_guarded_structure_and_the_mark_expires() -> void:
	_setup(&"autocannon_turret")
	var core: int = Ai14Kit.core(_w, DartKit.offset(C0, -300.0, 0.0), 0)
	var a: int = _foe(&"dart", 350.0, 0.0, 100.0, true)         # equal priority, equal slew: the earlier candidate wins
	var b: int = _foe(&"dart", 350.0, 40.0, 100.0, true)
	_run(2 * HZ)
	assert_int(_target()).is_equal(a)
	DartKit.order(_w, _tw, OrderSpec.make(OrderSpec.Kind.GUARD, core))
	_hit(b, core, _w.view().pos(core), 200)                      # b attacked the guarded Core 200 ticks ago: past 5 s
	_d.state.set_target(_s(), 0)
	_run(HZ)
	assert_int(_target()).is_equal(a)                            # the mark expired: no boost
	_hit(b, core, _w.view().pos(core), 0)                        # b attacks the guarded Core now
	_d.state.set_target(_s(), 0)
	_run(HZ)
	assert_int(_target()).is_equal(b)                            # attacker of the guarded thing: x2 (and x1.5)


func test_attacker_of_a_friendly_asset_near_the_tower_gets_the_attacking_mark() -> void:
	_setup(&"autocannon_turret")
	var a: int = _foe(&"dart", 350.0, 0.0, 100.0, true)
	var b: int = _foe(&"dart", 350.0, 40.0, 100.0, true)
	_run(2 * HZ)
	assert_int(_target()).is_equal(a)
	var far: Vector3 = _w.view().pos(_tw) + Sphere.tangent_frame(_w.view().pos(_tw).normalized()).x * 1500.0
	_hit(b, _tw, far, 0)                                         # b hit something 1.5 km away: not "within 600 m"
	_d.state.set_target(_s(), 0)
	_run(HZ)
	assert_int(_target()).is_equal(a)
	_hit(b, _tw, _w.view().pos(_tw), 0)                          # b hit a team-0 asset at the tower: within 600 m
	_d.state.set_target(_s(), 0)
	_run(HZ)
	assert_int(_target()).is_equal(b)


func _mast_and_harvester() -> int:
	var mast_p: Vector3 = Ai17Kit.rel(_w, _tw, -150.0, 0.0, 0.0)   # a Sensor Mast reveals ground units through the datum
	var _m: int = DartKit.spawn(_w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, Vector3(0, 1, 0)))
	return DartKit.spawn(_w, &"harvester", DartKit.FOE, Ai17Kit.rel(_w, _tw, 300.0, 0.0, 0.0), Vector3.ZERO, Vector3(0, 1, 0))


func test_the_autocannon_takes_ground_targets_from_perception_and_the_flak_does_not() -> void:
	_setup(&"autocannon_turret")
	var hv: int = _mast_and_harvester()
	_run(3 * HZ)                                                 # past a Perception refresh (1 Hz)
	assert_int(_target()).is_equal(hv)
	assert_int(_brain.stats_ground_builds).is_greater(0)
	var builds: int = _brain.stats_ground_builds
	_run(HZ)
	assert_int(_brain.stats_ground_builds - builds).is_less_equal(1)   # once per Perception refresh, not per think
	_setup(&"flak_battery")
	var hv2: int = _mast_and_harvester()
	_run(3 * HZ)
	assert_bool(_w.view().visible_to(0, hv2)).is_true()
	assert_int(_target()).is_equal(0)                            # target_kinds: ship only


func test_a_lost_target_ends_the_slew_and_the_trigger() -> void:
	_setup(&"autocannon_turret")
	var dart: int = _foe(&"dart", 300.0, 0.0, 100.0)
	_run(2 * HZ)
	assert_int(Ai17Kit.buttons(_w, _tw) & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)
	assert_int(_d.state.bflags[_s()] & TowerBrain.B_DRIVEN).is_equal(TowerBrain.B_DRIVEN)
	IntelKit.teleport(_w, dart, Ai17Kit.rel(_w, _tw, 9000.0, 0.0, 300.0))   # far outside the tower's sensors
	_run(2 * HZ)
	assert_int(_mode()).is_equal(AiTag.Tag.IDLE)
	assert_int(Ai17Kit.buttons(_w, _tw)).is_equal(0)
	assert_int(_d.state.bflags[_s()] & TowerBrain.B_DRIVEN).is_equal(0)


func test_a_possessed_tower_gets_no_input_and_resumes_on_release() -> void:
	_setup(&"autocannon_turret")
	var _dart: int = _foe(&"dart", 300.0, 0.0, 100.0)
	_run(2 * HZ)
	var res: CommandResult = _w.apply_command(Command.possess(0, _tw))
	assert_int(res.code).is_equal(CommandResult.Code.ACCEPTED)
	_run(HZ)
	var acts: int = _brain.stats_acts
	_run(HZ)
	assert_int(_brain.stats_acts).is_equal(acts)                 # the act does not run on a possessed tower
	var rel: CommandResult = _w.apply_command(Command.release(0))
	assert_int(rel.code).is_equal(CommandResult.Code.ACCEPTED)
	_run(2 * HZ)
	assert_int(_brain.stats_acts).is_greater(acts)


# A synthetic HIT event on the driver: `attacker` landed a hit on `victim` (a team-0 asset) at `at`.
func _hit(attacker: int, victim: int, at: Vector3, age_ticks: int) -> void:
	var ev: SimEvent = SimEvent.new()
	ev.kind = SimEvent.Kind.HIT
	ev.tick = _w.tick() - age_ticks
	ev.a = victim
	ev.b = attacker
	ev.pos = at
	ev.team = 0
	_d.on_event(ev)
