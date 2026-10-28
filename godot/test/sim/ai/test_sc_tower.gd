extends GdUnitTestSuite
## AI-17 scenarios on a real SimWorld (05 s11.2, s6.8; R0 C2-15): SC-30 tower_priority and SC-31 flak_min_elevation, the
## Missile Tower's lock hold (`lock_time_s`, AGL floor), vision fairness of the trigger, the unsupplied rate (GD-18) with
## the brain unchanged, and a byte-exact S4 restore in mid-fight (AiState FORMAT 7 with a live hit record). Every
## envelope number is read from towers.json through the def (no literal): the scenarios place targets relative to
## `h_rel_min` / `h_rel_max`. The turret slew is the sim's own (GD-09).

const HZ: int = 30
const C0: Vector3 = Vector3(1, 0, 0)

var _w: SimWorld
var _d: AiDriver
var _brain: TowerBrain
var _tw: int


func _setup(def: StringName, agl: float = 0.0) -> void:
	_w = Ai17Kit.world(11)
	_brain = Ai17Kit.brain()
	_d = Ai17Kit.driver(_w, true, 3, _brain)
	var _core: int = Ai14Kit.core(_w, Vector3(-1, 0, 0), 0)   # team 0's power
	_tw = Ai17Kit.tower(_w, def, 0, C0, DartKit.above(_w, DartKit.offset(C0, 500.0, 0.0), 0.0), agl)


func _tower_block(def: StringName) -> Dictionary:
	for sd: StructureDef in Ai17Kit.content().structures:
		if sd.id == def:
			return sd.tower
	return {}


func _foe(def: StringName, east: float, north: float, h_rel: float) -> int:
	var id: int = DartKit.spawn(_w, def, DartKit.FOE, Ai17Kit.rel(_w, _tw, east, north, h_rel), Vector3.ZERO, Vector3(0, 1, 0))
	_w.store().hp[EntityId.slot(id)] = 10000000.0   # a choice scenario, not a kill scenario
	return id


func _run(ticks: int) -> void:
	for _k: int in ticks:
		var _e: Array[SimEvent] = Ai17Kit.step(_w)


func _target() -> int:
	return _d.state.target[EntityId.slot(_tw)]


# SC-30 tower_priority: Autocannon, Bomber and Dart both in the envelope -> Bomber first; a Dart 150 m below the tower is
# engaged (h_rel_min -200); a ship above h_rel_max (400 m) is never targeted, whatever its priority.
func test_sc30_tower_priority() -> void:
	var blk: Dictionary = _tower_block(&"autocannon_turret")
	var lo: float = TargetParams.num(blk, "h_rel_min", 0.0)
	var hi: float = TargetParams.num(blk, "h_rel_max", 0.0)
	_setup(&"autocannon_turret")
	var bomber: int = _foe(&"bomber", 450.0, 0.0, 0.5 * hi)
	var dart: int = _foe(&"dart", 350.0, 100.0, 0.25 * hi)
	_run(3 * HZ)
	assert_bool(_w.view().visible_to(0, bomber) and _w.view().visible_to(0, dart)).is_true()
	assert_int(_target()).is_equal(bomber)                      # priority 100 over 50
	assert_int(_w.view().ai_tag(_tw)).is_equal(AiTag.Tag.TRACK)
	# the low Dart: 150 m below the tower's own height (lo = -200), the tower raised 300 m over the datum
	_setup(&"autocannon_turret", 300.0)
	var low: int = _foe(&"dart", 400.0, 0.0, 0.75 * lo)
	_run(3 * HZ)
	assert_float(_w.view().pos(low).length() - _w.view().pos(_tw).length()).is_between(lo, 0.0)
	assert_int(_target()).is_equal(low)
	# above h_rel_max: never targeted; the Dart inside the envelope is taken although a Bomber outranks it
	_setup(&"autocannon_turret")
	var high_bomber: int = _foe(&"bomber", 300.0, 0.0, 1.5 * hi)
	_run(3 * HZ)
	assert_int(_target()).is_equal(0)
	assert_int(_w.view().ai_tag(_tw)).is_equal(AiTag.Tag.IDLE)
	assert_int(Ai17Kit.buttons(_w, _tw)).is_equal(0)
	var mid: int = _foe(&"dart", 350.0, 0.0, 0.5 * hi)
	_run(3 * HZ)
	assert_int(_target()).is_equal(mid)
	assert_bool(_w.view().alive(high_bomber)).is_true()
	assert_int(_target()).is_not_equal(high_bomber)


# SC-31 flak_min_elevation: a Dart 50 m below h_rel_min is neither targeted nor fired at; it is once it is 100 m above.
func test_sc31_flak_min_elevation() -> void:
	var lo: float = TargetParams.num(_tower_block(&"flak_battery"), "h_rel_min", 0.0)
	_setup(&"flak_battery")
	var pool: int = _w.view().ammo(_tw)
	var dart: int = _foe(&"dart", 500.0, 0.0, lo - 50.0)
	var fired: bool = false
	for _k: int in 5 * HZ:
		var _e: Array[SimEvent] = Ai17Kit.step(_w)
		fired = fired or (Ai17Kit.buttons(_w, _tw) & PilotInput.FIRE1) != 0
	assert_bool(_w.view().visible_to(0, dart)).is_true()
	assert_bool(fired).is_false()
	assert_int(_target()).is_equal(0)
	assert_int(_w.view().ammo(_tw)).is_equal(pool)
	assert_int(Ai17Kit.shots_of(_w, _tw)).is_equal(0)
	IntelKit.teleport(_w, dart, Ai17Kit.rel(_w, _tw, 500.0, 0.0, lo + 100.0))   # climbs to 100 m above h_rel_min
	for _k: int in 5 * HZ:
		var _e: Array[SimEvent] = Ai17Kit.step(_w)
		fired = fired or (Ai17Kit.buttons(_w, _tw) & PilotInput.FIRE1) != 0
	assert_bool(fired).is_true()
	assert_int(_target()).is_equal(dart)
	assert_int(_w.view().ammo(_tw)).is_less(pool)


# The Missile Tower holds the trigger through the seeker's lock_time_s: the first rocket leaves `lock_ticks` after the
# hold began (`lock_tick`), and a Dart under its target_agl_min is never locked.
func test_missile_tower_holds_the_lock_and_respects_the_agl_floor() -> void:
	var blk: Dictionary = _tower_block(&"missile_tower")
	var floor_agl: float = TargetParams.num(blk, "target_agl_min", 0.0)
	_setup(&"missile_tower")
	var mast_p: Vector3 = Ai17Kit.rel(_w, _tw, -150.0, 0.0, 0.0)   # a Sensor Mast reveals ships hugging the deck
	var _m: int = DartKit.spawn(_w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, Vector3(0, 1, 0)))
	var low: int = _foe(&"dart", 600.0, 0.0, 0.5 * floor_agl)
	_run(4 * HZ)
	assert_bool(_w.view().visible_to(0, low)).is_true()
	assert_int(_target()).is_equal(0)                           # AGL under target_agl_min: no target, no lock
	assert_int(Ai17Kit.buttons(_w, _tw)).is_equal(0)
	var bomber: int = _foe(&"bomber", 700.0, 0.0, 4.0 * floor_agl)
	var s: int = EntityId.slot(_tw)
	var lock_ticks: int = _brain.prm.lock_ticks[_w.view().def_id(_tw) - DefRanges.STRUCTURE_BASE]
	assert_int(lock_ticks).is_greater(0)
	var first: int = 0
	var started: int = 0
	var target_at_launch: int = 0
	var pr: ProjectileStore = _w.projectiles()
	for _k: int in 8 * HZ:
		var _e: Array[SimEvent] = Ai17Kit.step(_w)
		if started == 0:
			started = _d.state.lock_tick[s]
		if first == 0:
			for i: int in pr.live:
				if pr.shooter[i] == _tw and pr.kind[i] == ProjectileStore.ROCKET:
					first = _w.tick()
					target_at_launch = _target()
	assert_int(first).is_not_equal(0)
	assert_int(target_at_launch).is_equal(bomber)
	assert_int(_brain.stats_lock_starts).is_greater(0)
	assert_int(first - started).override_failure_message("rocket at %d, lock began %d, lock_ticks %d" % [first, started, lock_ticks]).is_between(lock_ticks - 1, lock_ticks + 2)


# Vision fairness: a trigger is held only while the target is visible to the team (the visibility the act read: the
# bits of the previous tick's Vision pass), over a Bomber flying through two towers' fields from outside the sensors.
func test_the_trigger_is_never_held_on_a_target_the_team_cannot_see() -> void:
	_setup(&"autocannon_turret")
	var flak: int = Ai17Kit.tower(_w, &"flak_battery", 0, DartKit.offset(C0, 0.0, 60.0), Vector3(0, 1, 0))
	var cb: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(&"bomber"), _w.terrain())
	cb.speed = 70.0
	cb.agl = 250.0
	_d.set_brain(DartKit.class_of(&"bomber"), cb)
	var p0: Vector3 = DartKit.above(_w, DartKit.offset(C0, -4500.0, 200.0), 250.0)
	var bomber: int = DartKit.spawn(_w, &"bomber", DartKit.FOE, p0, DartKit.heading(p0, C0) * 70.0, DartKit.heading(p0, C0))
	cb.heading[bomber] = DartKit.heading(p0, DartKit.above(_w, DartKit.offset(C0, 4000.0, 200.0), 0.0))
	_w.store().hp[EntityId.slot(bomber)] = 10000000.0
	var trigger_ticks: int = 0
	var first_seen: int = -1
	var first_target: int = -1
	for _k: int in 90 * HZ:
		var v: SimView = _w.view()
		var seen_before: bool = v.alive(bomber) and v.visible_to(0, bomber)
		if seen_before and first_seen < 0:
			first_seen = _w.tick()
		var _e: Array[SimEvent] = Ai17Kit.step(_w)
		for t: int in [_tw, flak]:
			if (Ai17Kit.buttons(_w, t) & PilotInput.FIRE1) != 0:
				trigger_ticks += 1
				assert_bool(seen_before).override_failure_message("trigger held at tick %d on an unseen target" % _w.tick()).is_true()
		if first_target < 0 and (_d.state.target[EntityId.slot(_tw)] != 0 or _d.state.target[EntityId.slot(flak)] != 0):
			first_target = _w.tick()
	assert_int(trigger_ticks).is_greater(0)                     # the fight happened
	assert_int(first_seen).is_greater(0)
	assert_int(first_target).is_greater_equal(first_seen)        # no target before the team saw the Bomber


# Kill the Sensor Mast: a Dart on the deck is seen only through the Mast's reveal. When the Mast is gone the team no
# longer sees it, and the very next act must release the trigger although the think that clears the target has not
# run yet. Deleting the act's `visible_to` gate fails this test (stale ticks with FIRE1 held).
func test_the_act_gate_releases_the_trigger_when_the_sensor_mast_dies() -> void:
	_setup(&"autocannon_turret")
	var mast_p: Vector3 = Ai17Kit.rel(_w, _tw, -150.0, 0.0, 0.0)
	var mast: int = DartKit.spawn(_w, &"sensor_mast", 0, mast_p, Vector3.ZERO, DartKit.heading(mast_p, Vector3(0, 1, 0)))
	var dart_p: Vector3 = Ai17Kit.rel(_w, _tw, 600.0, 0.0, 0.01 * TargetParams.num(_tower_block(&"autocannon_turret"), "h_rel_max", 0.0))   # on the deck, in range, under the datum horizon of the tower
	var dart: int = DartKit.spawn(_w, &"dart", DartKit.FOE, dart_p, Vector3.ZERO, Vector3(0, 1, 0))
	_w.store().hp[EntityId.slot(dart)] = 10000000.0
	var fired: bool = false
	for _k: int in 3 * HZ:
		IntelKit.teleport(_w, dart, dart_p)
		var _e: Array[SimEvent] = Ai17Kit.step(_w)
		fired = fired or (Ai17Kit.buttons(_w, _tw) & PilotInput.FIRE1) != 0
	assert_bool(_w.view().visible_to(0, dart)).is_true()
	assert_bool(fired).override_failure_message("the tower never fired through the Mast's reveal").is_true()
	IntelKit.teleport(_w, mast, Ai17Kit.rel(_w, _tw, -9000.0, 0.0, 0.0))   # the Mast is gone (its reveal leaves with it)
	var stale: int = 0
	for _k: int in 3 * HZ:
		IntelKit.teleport(_w, dart, dart_p)
		var before: bool = _w.view().visible_to(0, dart)
		var _e: Array[SimEvent] = Ai17Kit.step(_w)
		var held: bool = (Ai17Kit.buttons(_w, _tw) & PilotInput.FIRE1) != 0
		var still_target: bool = _target() == dart and _d.state.mode[EntityId.slot(_tw)] == AiTag.Tag.TRACK
		if not before and still_target:
			stale += 1
			assert_bool(held).override_failure_message("FIRE1 held on an unseen target at tick %d" % _w.tick()).is_false()
	assert_bool(_w.view().visible_to(0, dart)).is_false()
	assert_int(stale).override_failure_message("no tick had an unseen target before the next think: the gate is untested").is_greater(0)


# GD-18: a tower outside the supply network fires at unsupplied_rate_mult; the brain is the same (it tracks and holds the
# trigger identically), so the HIT rate on an identical tanked target is about half.
func test_unsupplied_tower_fires_at_the_sim_rate_with_the_same_brain() -> void:
	_setup(&"autocannon_turret")
	var _supply: int = Ai14Kit.core(_w, DartKit.offset(C0, -300.0, 0.0), 0)   # inside the Core's build radius: supplied
	var mult: float = TargetParams.as_num(Ai17Kit.content().economy.raw.get("unsupplied_rate_mult"), -1.0)
	assert_float(mult).is_greater(0.0)
	var far_dir: Vector3 = DartKit.offset(C0, 0.0, 4000.0)
	var far: int = Ai17Kit.tower(_w, &"autocannon_turret", 0, far_dir, DartKit.above(_w, DartKit.offset(far_dir, 500.0, 0.0), 0.0))
	var near_foe: int = _foe(&"dart", 300.0, 0.0, 100.0)
	var far_p: Vector3 = Ai17Kit.rel(_w, far, 300.0, 0.0, 100.0)
	var far_foe: int = DartKit.spawn(_w, &"dart", DartKit.FOE, far_p, Vector3.ZERO, Vector3(0, 1, 0))
	_w.store().hp[EntityId.slot(far_foe)] = 10000000.0
	_w.store().hp[EntityId.slot(near_foe)] = 10000000.0
	var near_p: Vector3 = _w.view().pos(near_foe)
	_run(3 * HZ)
	assert_int(_w.economy().supply.unsupplied[EntityId.slot(far)]).is_equal(1)
	assert_int(_w.economy().supply.unsupplied[EntityId.slot(_tw)]).is_equal(0)
	var hits_near: int = 0
	var hits_far: int = 0
	for _k: int in 20 * HZ:
		IntelKit.teleport(_w, near_foe, near_p)                  # the targets hover (ships fall): an identical shooting gallery
		IntelKit.teleport(_w, far_foe, far_p)
		for e: SimEvent in Ai17Kit.step(_w):
			if e.kind == SimEvent.Kind.HIT:
				hits_near += 1 if e.b == _tw else 0
				hits_far += 1 if e.b == far else 0
	assert_int(_d.state.target[EntityId.slot(far)]).is_equal(far_foe)
	assert_int(hits_near).is_greater(20)
	var ratio: float = float(hits_far) / float(hits_near)
	assert_float(ratio).override_failure_message("far %d near %d ratio %.2f want ~%.2f" % [hits_far, hits_near, ratio, mult]).is_between(mult - 0.15, mult + 0.15)


# S4: saved mid-fight (towers tracking a flying Bomber, a live hit record) and restored into a world whose driver is
# configured before SimWorld.deserialize, both runs stay byte-identical.
func test_restore_mid_fight_is_byte_exact() -> void:
	var a: Array = _fight(5)
	var b: Array = _fight(5)
	var wa: SimWorld = a[0]
	var wb: SimWorld = b[0]
	assert_bool(wa.serialize() == wb.serialize()).is_true()    # the same seed twice: the same bytes
	var da: AiDriver = a[1]
	assert_int(da.state.target[EntityId.slot(a[3] as int)]).is_not_equal(0)   # mid-fight: the tower is tracking
	var bytes: PackedByteArray = wa.serialize()
	var d2: AiDriver = Ai17Kit.make_driver(null)
	var ca: DartKit.CruiseBrain = a[2]
	var c2: DartKit.CruiseBrain = DartKit.CruiseBrain.new(ca.gains, Terrain.new())
	c2.speed = ca.speed
	c2.agl = ca.agl
	c2.heading = ca.heading.duplicate()
	d2.set_brain(DartKit.class_of(&"bomber"), c2)
	var w2: SimWorld = SimWorld.deserialize(bytes, Ai17Kit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	c2.terrain = w2.terrain()
	assert_bool(w2.serialize() == bytes).is_true()
	assert_bool(d2.state.hits.tick == da.state.hits.tick).is_true()
	var tw: int = a[3]
	var ammo0: int = wa.view().ammo(tw)
	for k: int in 6 * HZ:
		wa.step()
		w2.step()
		var _x: Array[SimEvent] = wa.drain_events()
		var _y: Array[SimEvent] = w2.drain_events()
		if k % 15 == 0:
			assert_bool(w2.serialize() == wa.serialize()).override_failure_message("diverged at +%d" % k).is_true()
	assert_int(wa.view().ammo(tw)).is_not_equal(ammo0)           # the fight went on after the save point
	assert_bool(w2.serialize() == wa.serialize()).is_true()


func _fight(seed_value: int) -> Array:
	var w: SimWorld = Ai17Kit.world(seed_value)
	var brain: TowerBrain = Ai17Kit.brain()
	var d: AiDriver = Ai17Kit.driver(w, true, 3, brain)
	var cb: DartKit.CruiseBrain = DartKit.CruiseBrain.new(DartKit.gains_of(&"bomber"), w.terrain())
	cb.speed = 60.0
	cb.agl = 250.0
	d.set_brain(DartKit.class_of(&"bomber"), cb)
	var _core: int = Ai14Kit.core(w, Vector3(-1, 0, 0), 0)
	var tw: int = Ai17Kit.tower(w, &"autocannon_turret", 0, C0, Vector3(0, 1, 0))
	var _mt: int = Ai17Kit.tower(w, &"missile_tower", 0, DartKit.offset(C0, 80.0, 0.0), Vector3(0, 1, 0))
	var p0: Vector3 = DartKit.above(w, DartKit.offset(C0, -1500.0, 100.0), 250.0)
	var h: Vector3 = DartKit.heading(p0, DartKit.above(w, DartKit.offset(C0, 3000.0, 100.0), 0.0))
	var bomber: int = DartKit.spawn(w, &"bomber", DartKit.FOE, p0, h * 60.0, h)
	cb.heading[bomber] = h
	w.store().hp[EntityId.slot(bomber)] = 10000000.0
	for _k: int in 600:
		var _e: Array[SimEvent] = Ai17Kit.step(w)
		if d.state.target[EntityId.slot(tw)] != 0 and w.view().ammo(tw) < 280:
			break
	var ev: SimEvent = SimEvent.new()                           # a live hit record: the Bomber hit the tower just now
	ev.kind = SimEvent.Kind.HIT
	ev.tick = w.tick()
	ev.a = tw
	ev.b = bomber
	ev.pos = w.view().pos(tw)
	ev.team = 0
	d.on_event(ev)
	return [w, d, cb, tw]
