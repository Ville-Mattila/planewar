extends GdUnitTestSuite
## GD-19 W6-W8 (sim/salvage/MODULE.md): tow slots (Hauler 1, Foundry 2), the hook rules and the order-driven auto-hook,
## release when the Hauler dies, delivery to a friendly Refinery with its Ore credit and events.

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")
const FAR: float = 2000.0
const HOVER_EAST: float = 60.0   ## clear of a Refinery's collision radius, inside radius + reach


func _reach(w: SimWorld) -> float:
	return w.economy().salvage.reach_m()


# A Hauler of `owner` hovering `alt` m above the datum at `east`; a wreck on the ground below it.
func _pair(w: SimWorld, owner: int = 0, east: float = 3000.0, alt: float = 20.0) -> Vector2i:
	var h: int = K.put(w, &"hauler", owner, 0, alt, east)
	var wr: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, east))
	return Vector2i(h, wr)


func test_reach_is_the_tether_length_plus_its_drop() -> void:
	var w: SimWorld = K.world()
	var c: FlightCommonDef = WorldTestKit.content().flight_common
	assert_float(_reach(w)).is_equal(c.tether_len_m + c.tether_drop_m)


func test_a_hauler_has_one_slot_and_a_foundry_hauler_two() -> void:
	var w: SimWorld = K.world()
	var base: int = K.put(w, &"hauler", 0, 0, 40.0)
	var foundry: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 40.0, 400.0)
	var dart: int = K.put(w, &"dart", 0, 0, 40.0, 800.0)
	var sal: Salvage = w.economy().salvage
	assert_int(sal.tow_slots_of(base)).is_equal(1)
	assert_int(sal.tow_slots_of(foundry)).is_equal(2)
	assert_int(sal.tow_slots_of(dart)).is_equal(0)
	assert_int(sal.tow_slots_of(0)).is_equal(0)


func test_try_attach_links_both_ends_and_refuses_a_second_wreck() -> void:
	var w: SimWorld = K.world()
	var p: Vector2i = _pair(w)
	var spare: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	var sal: Salvage = w.economy().salvage
	assert_int(sal.try_attach(p.x, p.y)).is_equal(Salvage.Hook.OK)
	assert_int(w.store().link[p.y]).is_equal(w.store().id_of(p.x))
	assert_bool(K.tethered(w, p.x) and K.tethered(w, p.y)).is_true()
	assert_int(sal.towed_count(p.x)).is_equal(1)
	assert_int(w.store().dirty[p.y] & EntityStore.DIRTY_CONTROL).is_equal(EntityStore.DIRTY_CONTROL)
	assert_int(sal.try_attach(p.x, spare)).is_equal(Salvage.Hook.NO_SLOT)
	assert_bool(K.tethered(w, spare)).is_false()
	assert_int(w.store().link[spare]).is_equal(0)


func test_a_foundry_hauler_tows_two_and_refuses_a_third() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, 3000.0)
	var a: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	var b: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3004.0))
	var c: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3008.0))
	var sal: Salvage = w.economy().salvage
	assert_int(sal.try_attach(h, a)).is_equal(Salvage.Hook.OK)
	assert_int(sal.try_attach(h, b)).is_equal(Salvage.Hook.OK)
	assert_int(sal.try_attach(h, c)).is_equal(Salvage.Hook.NO_SLOT)
	assert_int(sal.towed_count(h)).is_equal(2)
	assert_bool(K.tethered(w, a) and K.tethered(w, b) and not K.tethered(w, c)).is_true()


func test_try_attach_failure_order_and_no_side_effects() -> void:
	var w: SimWorld = K.world()
	var p: Vector2i = _pair(w)
	var far: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0 + FAR))
	var dart: int = K.put(w, &"dart", 0, 0, 20.0, 5000.0)
	var sal: Salvage = w.economy().salvage
	assert_int(sal.try_attach(dart, p.y)).is_equal(Salvage.Hook.NOT_HAULER)
	assert_int(sal.try_attach(p.x, far)).is_equal(Salvage.Hook.TOO_FAR)
	assert_int(sal.try_attach(p.x, 0)).is_equal(Salvage.Hook.BAD_WRECK)
	assert_int(sal.try_attach(p.x, dart)).is_equal(Salvage.Hook.BAD_WRECK)       # not a wreck
	assert_bool(K.tethered(w, p.x) or K.tethered(w, far) or K.tethered(w, p.y)).is_false()
	assert_int(sal.try_attach(p.x, p.y)).is_equal(Salvage.Hook.OK)
	assert_int(sal.try_attach(p.x, p.y)).is_equal(Salvage.Hook.NO_SLOT)         # slots are checked before the wreck
	var other: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	assert_int(sal.try_attach(other, p.y)).is_equal(Salvage.Hook.BAD_WRECK)      # already towed


func test_reach_is_a_centre_distance_and_a_docked_ship_cannot_hook() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var sal: Salvage = w.economy().salvage
	var d: float = sal.reach_m()
	var up: Vector3 = w.store().pos[h].normalized()
	var near: int = K.wreck_at(w, &"dart", 60.0, w.store().pos[h] + Vector3(0, d * 0.99, 0))
	var out: int = K.wreck_at(w, &"dart", 60.0, w.store().pos[h] + Vector3(0, d * 1.01, 0))
	assert_vector(up).is_not_equal(Vector3.ZERO)
	assert_int(sal.try_attach(h, out)).is_equal(Salvage.Hook.TOO_FAR)
	w.store().flags[h] |= EntityStore.F_DOCKED
	assert_int(sal.try_attach(h, near)).is_equal(Salvage.Hook.NOT_HAULER)
	w.store().flags[h] &= ~EntityStore.F_DOCKED
	assert_int(sal.try_attach(h, near)).is_equal(Salvage.Hook.OK)


func test_a_tow_order_hooks_its_target_in_step_10() -> void:
	var w: SimWorld = K.world()
	var p: Vector2i = _pair(w)
	K.haul(w, p.x, OrderSpec.HaulMode.TOW, w.store().id_of(p.y))
	var _ev: Array[SimEvent] = K.steps(w, 1)
	assert_bool(K.tethered(w, p.x) and K.tethered(w, p.y)).is_true()
	assert_int(w.store().link[p.y]).is_equal(w.store().id_of(p.x))


func test_nothing_hooks_without_a_tow_order_in_reach() -> void:
	var w: SimWorld = K.world()
	var p: Vector2i = _pair(w)
	var _a: Array[SimEvent] = K.steps(w, 2)                                      # no order at all
	assert_bool(K.tethered(w, p.y)).is_false()
	K.haul(w, p.x, OrderSpec.HaulMode.FERRY, w.store().id_of(p.y))              # wrong mode
	var _b: Array[SimEvent] = K.steps(w, 2)
	assert_bool(K.tethered(w, p.y)).is_false()
	var far: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0 + FAR))
	K.haul(w, p.x, OrderSpec.HaulMode.TOW, w.store().id_of(far))                 # target out of reach: no greedy first hook
	var _c: Array[SimEvent] = K.steps(w, 2)
	assert_bool(K.tethered(w, p.y) or K.tethered(w, far)).is_false()


func test_the_second_slot_takes_a_neighbouring_wreck_and_the_first_does_not() -> void:
	var w: SimWorld = K.world()
	var base: Vector2i = _pair(w, 0, 3000.0)
	var base_next: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3004.0))
	K.haul(w, base.x, OrderSpec.HaulMode.TOW, w.store().id_of(base.y))
	var _a: Array[SimEvent] = K.steps(w, 3)
	assert_bool(K.tethered(w, base.y)).is_true()
	assert_bool(K.tethered(w, base_next)).is_false()                             # one slot, full
	var f: Vector2i = _pair(w, K.FOUNDRY_SLOT, 5000.0)
	var f_next: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 5004.0))
	var f_third: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 5008.0))
	K.haul(w, f.x, OrderSpec.HaulMode.TOW, w.store().id_of(f.y))
	var _b: Array[SimEvent] = K.steps(w, 3)
	assert_bool(K.tethered(w, f.y) and K.tethered(w, f_next)).is_true()
	assert_bool(K.tethered(w, f_third)).is_false()
	assert_int(w.economy().salvage.towed_count(f.x)).is_equal(2)


func test_a_dead_hauler_releases_its_wreck_where_it_lies() -> void:
	var w: SimWorld = K.world()
	var p: Vector2i = _pair(w)
	assert_int(w.economy().salvage.try_attach(p.x, p.y)).is_equal(Salvage.Hook.OK)
	var at: Vector3 = w.store().pos[p.y]
	var _ev: Array[SimEvent] = K.kill(w, p.x)
	assert_bool(K.tethered(w, p.y)).is_false()
	assert_int(w.store().link[p.y]).is_equal(0)
	assert_vector(w.store().pos[p.y]).is_equal(at)
	assert_bool((w.store().flags[p.y] & EntityStore.F_ALIVE) != 0).is_true()
	assert_bool(w.economy().salvage.try_attach(K.put(w, &"hauler", 0, 0, 20.0, 3000.0), p.y) == Salvage.Hook.OK).is_true()


func test_drop_releases_every_wreck_and_clears_the_haulers_flag() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, 3000.0)
	var a: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	var b: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3004.0))
	var sal: Salvage = w.economy().salvage
	assert_int(sal.try_attach(h, a)).is_equal(Salvage.Hook.OK)
	assert_int(sal.try_attach(h, b)).is_equal(Salvage.Hook.OK)
	assert_int(sal.drop(h)).is_equal(2)
	assert_int(sal.towed_count(h)).is_equal(0)
	assert_bool(K.tethered(w, h) or K.tethered(w, a) or K.tethered(w, b)).is_false()
	assert_int(sal.drop(h)).is_equal(0)


# Refinery for team 0 on the ground at `east`; returns its slot.
func _refinery(w: SimWorld, east: float, team: int = 0, owner: int = 0) -> int:
	return K.put(w, &"refinery", owner, team, 0.0, east)


# A Hauler hovering HOVER_EAST m beside `east` (a ship rams a structure it overlaps) towing a wreck of `wreck_ore`.
func _tow(w: SimWorld, east: float, wreck_ore: float = 60.0, owner: int = 0) -> Vector2i:
	var h: int = K.put(w, &"hauler", owner, 0, 20.0, east + HOVER_EAST)
	var wr: int = K.wreck_at(w, &"dart", wreck_ore, K.at(0.0, east + HOVER_EAST))
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.OK)
	return Vector2i(h, wr)


func test_delivery_credits_the_ore_frees_the_wreck_and_reports() -> void:
	var w: SimWorld = K.world()
	var ref: int = _refinery(w, 3000.0)
	var p: Vector2i = _tow(w, 3000.0, 80.0)
	w._players.team_ore[0] = 0
	var wreck_id: int = w.store().id_of(p.y)
	var hauler_id: int = w.store().id_of(p.x)
	var ledger: int = w.economy().build.delivered_ore[0]
	var ev: Array[SimEvent] = K.steps(w, 1)
	assert_int(EconomyTestKit.ore(w)).is_equal(80)
	assert_int(w.economy().build.delivered_ore[0]).is_equal(ledger + 80)
	assert_bool(w.store().alive(wreck_id)).is_false()
	assert_bool(K.tethered(w, p.x)).is_false()
	var salvaged: Array[SimEvent] = K.of_kind(ev, SimEvent.Kind.WRECK_SALVAGED)
	var delivered: Array[SimEvent] = K.of_kind(ev, SimEvent.Kind.SALVAGE_DELIVERED)
	assert_int(salvaged.size()).is_equal(1)
	assert_int(delivered.size()).is_equal(1)
	assert_int(salvaged[0].a).is_equal(wreck_id)
	assert_int(salvaged[0].b).is_equal(hauler_id)
	assert_float(salvaged[0].value).is_equal(80.0)
	assert_int(delivered[0].a).is_equal(hauler_id)
	assert_int(delivered[0].b).is_equal(w.store().id_of(ref))
	assert_float(delivered[0].value).is_equal(80.0)
	assert_int(delivered[0].team).is_equal(0)
	assert_int(K.of_kind(ev, SimEvent.Kind.DEATH).size()).is_equal(0)


func test_two_wrecks_of_a_foundry_hauler_are_delivered_in_slot_order() -> void:
	var w: SimWorld = K.world()
	var _ref: int = _refinery(w, 3000.0)
	var h: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, 3000.0 + HOVER_EAST)
	var a: int = K.wreck_at(w, &"shipyard", 80.0, K.at(0.0, 3000.0 + HOVER_EAST))
	var b: int = K.wreck_at(w, &"shipyard", 80.0, K.at(0.0, 3004.0 + HOVER_EAST))
	assert_int(w.economy().salvage.try_attach(h, b)).is_equal(Salvage.Hook.OK)
	assert_int(w.economy().salvage.try_attach(h, a)).is_equal(Salvage.Hook.OK)
	w._players.team_ore[0] = 0
	var ev: Array[SimEvent] = K.steps(w, 1)
	assert_int(EconomyTestKit.ore(w)).is_equal(160)
	var salvaged: Array[SimEvent] = K.of_kind(ev, SimEvent.Kind.WRECK_SALVAGED)
	assert_int(salvaged.size()).is_equal(2)
	assert_bool(EntityId.slot(salvaged[0].a) < EntityId.slot(salvaged[1].a)).is_true()
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(K.of_kind(ev, SimEvent.Kind.SALVAGE_DELIVERED).size()).is_equal(2)


func test_the_credit_is_clamped_to_storage_but_the_event_reports_the_value() -> void:
	var w: SimWorld = K.world()
	var _ref: int = _refinery(w, 3000.0)
	var cap: int = w.economy().economy.caps(0).x
	w._players.team_ore[0] = cap - 10
	var _p: Vector2i = _tow(w, 3000.0, 80.0)
	var ev: Array[SimEvent] = K.steps(w, 1)
	assert_int(EconomyTestKit.ore(w)).is_equal(cap)
	assert_float(K.of_kind(ev, SimEvent.Kind.SALVAGE_DELIVERED)[0].value).is_equal(80.0)


func test_only_a_finished_friendly_refinery_in_reach_takes_a_wreck() -> void:
	# [def, owner, team, is a site]: an enemy Refinery, our own site, a structure without docks
	for c: Array in [[&"refinery", 1, 1, false], [&"refinery", 0, 0, true], [&"shipyard", 0, 0, false]]:
		var w: SimWorld = K.world()
		var other: int = K.put(w, c[0], c[1], c[2], 0.0, 3000.0)
		if c[3]:
			w.store().flags[other] |= EntityStore.F_BUILDING
		var p: Vector2i = _tow(w, 3000.0)
		var ev: Array[SimEvent] = K.steps(w, 3)
		assert_int(K.of_kind(ev, SimEvent.Kind.SALVAGE_DELIVERED).size()).override_failure_message(String(c[0])).is_equal(0)
		assert_bool(K.tethered(w, p.y)).is_true()


func test_a_friendly_refinery_out_of_reach_takes_nothing() -> void:
	var w: SimWorld = K.world()
	var _good: int = _refinery(w, 3000.0)
	var far: Vector2i = _tow(w, 3000.0 + 4000.0)
	var ev: Array[SimEvent] = K.steps(w, 3)
	assert_int(K.of_kind(ev, SimEvent.Kind.SALVAGE_DELIVERED).size()).is_equal(0)
	assert_bool(K.tethered(w, far.y)).is_true()


func test_a_tow_reaches_a_refinery_by_its_radius_plus_the_reach() -> void:
	var w: SimWorld = K.world()
	var ref: int = _refinery(w, 3000.0)
	var d: float = w.store().radius[ref] + w.economy().salvage.reach_m()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var wr: int = K.wreck_at(w, &"dart", 60.0, w.store().pos[h])
	assert_int(w.economy().salvage.try_attach(h, wr)).is_equal(Salvage.Hook.OK)
	w.store().pos[h] = w.store().pos[ref] + Vector3(0, d * 1.02, 0)
	var out: Array[SimEvent] = K.steps(w, 1)
	assert_int(K.of_kind(out, SimEvent.Kind.SALVAGE_DELIVERED).size()).is_equal(0)
	w.store().pos[h] = w.store().pos[ref] + Vector3(0, d * 0.98, 0)
	var inside: Array[SimEvent] = K.steps(w, 1)
	assert_int(K.of_kind(inside, SimEvent.Kind.SALVAGE_DELIVERED).size()).is_equal(1)


func test_a_refinery_built_after_the_first_pass_is_found() -> void:
	var w: SimWorld = K.world()
	var _p: Vector2i = _tow(w, 3000.0)
	var _a: Array[SimEvent] = K.steps(w, 2)                                      # list built with no Refinery
	w._players.team_ore[0] = 0
	var _ref: int = _refinery(w, 3000.0)
	var _b: Array[SimEvent] = K.steps(w, 1)                                       # its step 10 finds the new Refinery and delivers
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(EconomyTestKit.ore(w)).is_equal(60)


func test_a_destroyed_refinery_takes_nothing_the_same_tick() -> void:
	var w: SimWorld = K.world()
	var ref: int = _refinery(w, 3000.0)
	var _a: Array[SimEvent] = K.steps(w, 1)
	var p: Vector2i = _tow(w, 3000.0)
	var ev: Array[SimEvent] = K.kill(w, ref)
	assert_int(K.of_kind(ev, SimEvent.Kind.SALVAGE_DELIVERED).size()).is_equal(0)
	assert_bool(K.tethered(w, p.y)).is_true()
