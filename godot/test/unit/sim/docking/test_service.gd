extends GdUnitTestSuite
## GD-15 service (02 s2.3, 03 s6.4): every ship's refuel, rearm and repair time and cost reproduce the 02 s2.3 table
## (from the shipped `ships.json`, `weapons.json` rearm_ice and `economy.repair_ore_per_hp`), the timers run in parallel
## and scale with what is missing, a manual FAIR+ landing repairs in repair_time_s x 0.9, a short team pool pauses the
## timer it cannot pay (one ALERT WAITING_FOR_ICE / ORE) and resumes, SERVICED fires once with what was given, a ship
## whose pad dies is released, and SimView.service_progress reads the three fills.

const SHIPS: Array[StringName] = [&"dart", &"lancer", &"bomber", &"scout", &"hauler"]

var _w: SimWorld
var _pad: int
var _hz: int


func before_test() -> void:
	_w = WorldTestKit.world()
	_hz = WorldTestKit.content().rules.tick_hz
	_pad = DockingTestKit.pad(_w)
	var _e: Array[SimEvent] = _w.drain_events()


func _slot(id: int) -> int:
	return EntityId.slot(id)


func _sec_weapon(sd: ShipDef) -> WeaponDef:
	var c: ContentSet = WorldTestKit.content()
	var wd: int = c.weapon_index.get(sd.secondary_weapon, -1)
	return c.weapons[wd - DefRanges.WEAPON_BASE] if wd >= DefRanges.WEAPON_BASE else null


func _secondary(id: int, sd: ShipDef) -> int:
	var w: WeaponDef = _sec_weapon(sd)
	var s: int = _slot(id)
	return _w.store().bombs[s] if w != null and w.kind == &"bomb" else _w.store().rockets[s]


func _empty(id: int, hp_left: float) -> void:
	var s: int = _slot(id)
	_w.store().fuel[s] = 0.0
	_w.store().ammo[s] = 0
	_w.store().bombs[s] = 0
	_w.store().rockets[s] = 0
	_w.store().hp[s] = hp_left


## Steps until SERVICED for `id` (at most `limit` ticks); returns per timer the tick count to full: x fuel, y ammo,
## z hp, w SERVICED (-1 never).
func _run(id: int, sd: ShipDef, limit: int) -> Vector4i:
	var s: int = _slot(id)
	var done: Vector4i = Vector4i(-1, -1, -1, -1)
	var hm: float = float(sd.hp)
	for t: int in range(1, limit + 1):
		_w.step()
		if done.x < 0 and _w.store().fuel[s] >= sd.fuel_s:
			done.x = t
		if done.y < 0 and _w.store().ammo[s] >= sd.primary_ammo and _secondary(id, sd) >= sd.secondary_count:
			done.y = t
		if done.z < 0 and _w.store().hp[s] >= hm:
			done.z = t
		for e: SimEvent in DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.SERVICED):
			if e.a == id:
				done.w = t
		if done.w >= 0:
			break
	return done


func test_every_ship_reproduces_the_02_s2_3_service_time_and_cost() -> void:
	var c: ContentSet = WorldTestKit.content()
	var report: PackedStringArray = PackedStringArray()
	for def: StringName in SHIPS:
		before_test()
		var sd: ShipDef = DockingTestKit.ship_def(def)
		var id: int = DockingTestKit.ship_over(_w, def, 0, 0, _pad, DockingTestKit.HIGH)
		DockingTestKit.dock(_w, id, _pad)
		_empty(id, 1.0)                                                       # 1 HP left: repair of hp - 1
		var _d: Array[SimEvent] = _w.drain_events()
		var pool0: Vector2i = DockingTestKit.pool(_w, 0)
		var got: Vector4i = _run(id, sd, 120 * _hz)
		var spent: Vector2i = pool0 - DockingTestKit.pool(_w, 0)
		var sec: WeaponDef = _sec_weapon(sd)
		var want_ice: int = sd.refuel_ice + (sd.secondary_count * sec.rearm_ice if sec != null else 0)
		var want_ore: int = ceili((float(sd.hp) - 1.0) * c.economy.repair_ore_per_hp)
		var t_fuel: int = roundi(sd.refuel_time_s * float(_hz))
		var t_rearm: int = roundi(sd.rearm_time_s * float(_hz)) if sd.primary_ammo + sd.secondary_count > 0 else 1
		var t_rep: int = ceili(sd.repair_time_s * (float(sd.hp) - 1.0) / float(sd.hp) * float(_hz))
		var line: String = "%s: fuel %d/%d ticks, rearm %d/%d, repair %d/%d, serviced %d; Ice %d/%d, Ore %d/%d" % [def, got.x, t_fuel,
			got.y, t_rearm, got.z, t_rep, got.w, spent.y, want_ice, spent.x, want_ore]
		var _a: bool = report.push_back(line)
		assert_int(got.x).override_failure_message(line).is_equal(t_fuel)
		assert_int(got.y).override_failure_message(line).is_equal(t_rearm)
		assert_int(got.z).override_failure_message(line).is_between(t_rep - 1, t_rep)
		assert_int(got.w).override_failure_message(line).is_equal(maxi(t_fuel, maxi(t_rearm, got.z)))   # parallel timers
		assert_int(spent.y).override_failure_message(line).is_equal(want_ice)
		assert_int(spent.x).override_failure_message(line).is_equal(want_ore)
	print("GD-15 service table:\n  " + "\n  ".join(report))


func test_refuel_time_and_ice_scale_with_fuel_missing() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"dart")
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	_w.store().fuel[_slot(id)] = sd.fuel_s * 0.5
	var _d: Array[SimEvent] = _w.drain_events()
	var ice0: int = DockingTestKit.pool(_w, 0).y
	var got: Vector4i = _run(id, sd, 60 * _hz)
	assert_int(got.x).is_equal(roundi(sd.refuel_time_s * 0.5 * float(_hz)))
	assert_int(got.w).is_equal(got.x)                                         # nothing else was missing
	assert_int(ice0 - DockingTestKit.pool(_w, 0).y).is_equal(ceili(float(sd.refuel_ice) * 0.5))
	# 01 / 02: the Dart draws 2 Ice per second while refuelling
	assert_float(float(sd.refuel_ice) / sd.refuel_time_s).is_equal_approx(2.0, 1e-9)


func test_rearm_time_follows_the_most_missing_slot_and_charges_per_round() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"dart")
	var sec: WeaponDef = _sec_weapon(sd)
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	var s: int = _slot(id)
	_w.store().fuel[s] = sd.fuel_s                                            # the far parking burnt a little idle fuel
	_w.store().ammo[s] = roundi(float(sd.primary_ammo) * 0.5)                # gun half full, bombs full: half the time
	var _d: Array[SimEvent] = _w.drain_events()
	var ice0: int = DockingTestKit.pool(_w, 0).y
	var got: Vector4i = _run(id, sd, 60 * _hz)
	assert_int(got.y).is_equal(roundi(sd.rearm_time_s * 0.5 * float(_hz)))
	assert_int(ice0 - DockingTestKit.pool(_w, 0).y).is_equal(0)                # gun rounds are free
	_w.store().bombs[s] = 0                                                   # now the bombs: full time, rearm_ice each
	_w.economy().docking.service.begin(s)
	ice0 = DockingTestKit.pool(_w, 0).y
	var got2: Vector4i = _run(id, sd, 60 * _hz)
	assert_int(got2.y).is_equal(roundi(sd.rearm_time_s * float(_hz)))
	assert_int(ice0 - DockingTestKit.pool(_w, 0).y).is_equal(sd.secondary_count * sec.rearm_ice)


func test_a_manual_fair_or_better_landing_repairs_in_ninety_percent() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"lancer")
	var g: LandingGrade = _w.economy().docking.grade
	var times: PackedInt32Array = PackedInt32Array()
	for grade: int in [LandingGrade.Grade.HARD, LandingGrade.Grade.FAIR, LandingGrade.Grade.AUTO, LandingGrade.Grade.ACE]:
		before_test()
		var id: int = DockingTestKit.ship_over(_w, &"lancer", 0, 0, _pad, DockingTestKit.HIGH)
		DockingTestKit.dock(_w, id, _pad)
		_w.store().hp[_slot(id)] = float(sd.hp) * 0.5
		_w.economy().docking.landings.record(id, grade, 0.5)
		var _d: Array[SimEvent] = _w.drain_events()
		var _b: bool = times.push_back(_run(id, sd, 60 * _hz).z)
	var full: int = ceili(sd.repair_time_s * 0.5 * float(_hz))
	var fast: int = ceili(sd.repair_time_s * g.repair_time_mult * 0.5 * float(_hz))
	assert_array(Array(times)).is_equal([full, fast, full, fast])
	assert_int(fast).is_less(full)


## The pool pays each whole Ice / Ore as the missing amount crosses it (Economy E7's rule), so an empty pool stops a
## timer at its next whole unit (at most one unit's worth, e.g. 12 fuel-seconds of a Dart), and it stays there.
func test_a_short_pool_pauses_that_timer_alerts_once_and_resumes() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"dart")
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	var s: int = _slot(id)
	_empty(id, float(sd.hp) * 0.5)
	var pl: PlayerTable = _w._players
	pl.team_ice[0] = 0                                                         # no Ice: refuel and rearm stall
	var alerts: Array[SimEvent] = []
	var fuel_2s: float = -1.0
	for t: int in 3 * _hz:
		_w.step()
		fuel_2s = _w.store().fuel[s] if t == 2 * _hz else fuel_2s
		for e: SimEvent in DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.ALERT):
			alerts.append(e)
	var per_ice: float = sd.fuel_s / float(sd.refuel_ice)
	assert_float(_w.store().fuel[s]).is_equal(fuel_2s)                        # stalled
	assert_float(_w.store().fuel[s]).is_less_equal(per_ice)                   # at most one Ice worth, unpaid
	assert_int(_w.store().bombs[s]).is_equal(0)
	assert_int(pl.team_ice[0]).is_greater_equal(0)
	assert_float(_w.store().hp[s]).is_greater(float(sd.hp) * 0.5)             # repair (Ore) goes on
	assert_int(alerts.size()).is_equal(1)
	assert_int(alerts[0].a).is_equal(AlertKind.Kind.WAITING_FOR_ICE)
	assert_int(alerts[0].b).is_equal(id)
	assert_int(alerts[0].team).is_equal(0)
	var prog: Vector3 = _w.view().service_progress(id)
	assert_float(prog.y).is_less(0.5)                                         # the first bomb loads at half the line
	pl.team_ice[0] = 1000                                                      # Ice arrives: both resume
	var f0: float = _w.store().fuel[s]
	for _t: int in 3 * _hz:
		_w.step()
	assert_float(_w.store().fuel[s]).is_greater(f0)
	assert_int(_w.store().bombs[s]).is_greater(0)
	pl.team_ore[0] = 0                                                         # now no Ore: repair stalls
	var _d: Array[SimEvent] = _w.drain_events()
	var hp_2s: float = -1.0
	for t: int in 3 * _hz:
		_w.step()
		hp_2s = _w.store().hp[s] if t == 2 * _hz else hp_2s
	var ore_alerts: Array[SimEvent] = DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.ALERT)
	assert_float(_w.store().hp[s]).is_equal(hp_2s)
	assert_float(_w.store().hp[s]).is_less(float(sd.hp))
	assert_int(ore_alerts.size()).is_equal(1)
	assert_int(ore_alerts[0].a).is_equal(AlertKind.Kind.WAITING_FOR_ORE)


func test_serviced_fires_once_with_what_was_given() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"scout")
	var id: int = DockingTestKit.ship_over(_w, &"scout", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	_w.store().fuel[_slot(id)] = sd.fuel_s * 0.9
	var _d: Array[SimEvent] = _w.drain_events()
	var serviced: Array[SimEvent] = []
	for _t: int in 10 * _hz:
		_w.step()
		serviced.append_array(DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.SERVICED))
	assert_int(serviced.size()).is_equal(1)
	assert_int(serviced[0].a).is_equal(id)
	assert_int(serviced[0].b).is_equal(_pad)
	assert_int(serviced[0].extra[0]).is_equal(PadService.BIT_FUEL)            # only fuel was missing
	assert_vector(_w.view().service_progress(id)).is_equal(Vector3.ONE)


func test_a_serviced_ship_hit_on_the_pad_repairs_again_without_a_second_serviced() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"scout")
	var id: int = DockingTestKit.ship_over(_w, &"scout", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	_w.step()
	assert_int(DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.SERVICED).size()).is_equal(1)   # full: done at once
	var s: int = _slot(id)
	_w.store().hp[s] = float(sd.hp) * 0.5                                     # damage taken while DOCKED (D7: still served)
	var ore0: int = DockingTestKit.pool(_w, 0).x
	var serviced: int = 0
	for _t: int in ceili(sd.repair_time_s * 0.5 * float(_hz)) + 2:
		_w.step()
		serviced += DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.SERVICED).size()
	assert_float(_w.store().hp[s]).is_equal(float(sd.hp))
	assert_int(ore0 - DockingTestKit.pool(_w, 0).x).is_equal(ceili(float(sd.hp) * 0.5 * WorldTestKit.content().economy.repair_ore_per_hp))
	assert_int(serviced).is_equal(0)                                          # SERVICED once per stay (D9)


func test_a_ship_whose_pad_dies_is_released() -> void:
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	_w.step()
	var r: CommandResult = _w.apply_command(CommandPayload.debug_set(0, _pad, CommandPayload.SET_KILL, 0.0))
	assert_int(r.code).is_equal(CommandResult.Code.ACCEPTED)
	_w.step()
	_w.step()
	var s: int = _slot(id)
	assert_bool(_w.view().alive(id)).is_true()
	assert_int(_w.store().flags[s] & (EntityStore.F_DOCKED | EntityStore.F_LANDED)).is_equal(0)
	assert_int(_w.store().link[s]).is_equal(0)
	assert_vector(_w.view().service_progress(id)).is_equal(Vector3.ZERO)


func test_service_progress_reads_the_three_fills() -> void:
	var sd: ShipDef = DockingTestKit.ship_def(&"dart")
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	assert_vector(_w.view().service_progress(id)).is_equal(Vector3.ZERO)       # flying
	DockingTestKit.dock(_w, id, _pad)
	var s: int = _slot(id)
	_w.store().fuel[s] = sd.fuel_s * 0.25
	_w.store().hp[s] = float(sd.hp) * 0.75
	_w.store().bombs[s] = 1
	_w.store().timer_a[s] = 0.5
	assert_vector(_w.view().service_progress(id)).is_equal_approx(Vector3(0.25, 0.5, 0.75), Vector3.ONE * 1e-6)
	assert_vector(_w.view().service_progress(0)).is_equal(Vector3.ZERO)
	assert_vector(_w.view().service_progress(_pad)).is_equal(Vector3.ZERO)
	var yard: int = DockingTestKit.pad(_w, &"shipyard", 0, 0, 1500.0)
	var parked: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, yard, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, parked, yard)                                       # a launch pad never services
	assert_vector(_w.view().service_progress(parked)).is_equal(Vector3.ZERO)
