extends GdUnitTestSuite
## AI-16 contract tests (sim_ai/MODULE.md, sim_ai/brains/MODULE.md): AiState FORMAT 8 with the ground block (`AiGround`),
## `HarvesterParams` (the `ap_harvester` numbers, def tables), `HarvestPicker.pick_sticky` (05 s6.6 "sticky to the same field
## unless its U fell by more than 30 %"), `HarvestSites` geometry (mining spot, dock stop) and refinery / flee-site choice.

const R: float = Sphere.PLANET_RADIUS


func _id(slot: int) -> int:
	return EntityId.make(slot, 1)


func test_ai_state_format8_round_trips_the_ground_block_and_refuses_format7() -> void:
	assert_int(AiState.FORMAT).is_equal(8)
	var st: AiState = AiState.new(32)
	st.cls[5] = 1
	st.eid[5] = _id(5)
	var g: AiGround = st.ground
	g.idx[5] = 17
	g.req[5] = 400
	g.ver[5] = 9
	g.stuck_tick[5] = 123
	g.threat[5] = 456
	g.faces[5] = 0b101
	g.strikes[5] = 2
	g.brake_run[5] = 9
	g.stuck_pos[5] = Vector3(1.5, -2.5, 3.5)
	st.path[5] = PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
	var bytes: PackedByteArray = st.serialize()
	var r: AiState = AiState.new(32)
	assert_bool(r.deserialize(bytes)).is_true()
	assert_int(r.ground.idx[5]).is_equal(17)
	assert_int(r.ground.req[5]).is_equal(400)
	assert_int(r.ground.ver[5]).is_equal(9)
	assert_int(r.ground.stuck_tick[5]).is_equal(123)
	assert_int(r.ground.threat[5]).is_equal(456)
	assert_int(r.ground.faces[5]).is_equal(5)
	assert_int(r.ground.strikes[5]).is_equal(2)
	assert_int(r.ground.brake_run[5]).is_equal(9)
	assert_object(r.ground.stuck_pos[5]).is_equal(Vector3(1.5, -2.5, 3.5))
	assert_int((r.path[5] as PackedVector3Array).size()).is_equal(2)         # the route follows the ground block
	assert_bool(r.serialize() == bytes).is_true()
	r.clear_slot(5)
	assert_int(r.ground.strikes[5]).is_equal(0)
	assert_int(r.ground.threat[5]).is_equal(0)
	assert_object(r.ground.stuck_pos[5]).is_equal(Vector3.ZERO)
	var old: PackedByteArray = bytes.duplicate()
	old[0] = 7                                                                # a FORMAT 7 blob (AI-17) is refused, state cleared
	assert_bool(r.deserialize(old)).is_false()
	assert_int(r.registered_count()).is_equal(0)


func test_ai_ground_record_size_matches_the_bytes() -> void:
	var g: AiGround = AiGround.new()
	g.resize(4)
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	g.write(b, 2)
	assert_int(b.data_array.size()).is_equal(AiGround.RECORD_BYTES)


func _params() -> HarvesterParams:
	return HarvesterParams.from_content(Ai16Kit.content(), Ai16Kit.ap(), Ai16Kit.ground_def())


func test_harvester_params_read_the_autopilot_def_the_unit_def_and_economy() -> void:
	var c: ContentSet = Ai16Kit.content()
	var p: HarvesterParams = _params()
	assert_object(p).is_not_null()
	assert_float(p.flee_radius_m).is_equal(600.0)                            # 05 s6.6 flee_radius_m
	assert_int(p.quiet_ticks).is_equal(15 * c.rules.tick_hz)                 # quiet_s 15
	assert_int(p.hit_ticks).is_equal(3 * c.rules.tick_hz)                    # "HIT in the last 3 s"
	assert_float(p.assigned_weight).is_equal(0.5)
	assert_float(p.sticky_drop).is_equal(0.3)
	assert_float(p.queue_m).is_equal(20.0 * Ai16Kit.ground_def().ground_speed)   # queue_len x 20 s x 12 m/s
	assert_float(p.deliver_m).is_equal(c.economy.salvage_deliver_m)
	assert_float(p.cargo_ore).is_equal(300.0)
	assert_float(p.face_tol_rad).is_equal_approx(deg_to_rad(40.0) / 30.0, 0.000001)   # BUG-4: one tick of ground_turn_rate_dps
	assert_int(p.mask).is_equal(Pathing.mask_for(25.0))                      # the Harvester's max_slope_deg
	assert_int(p.vision_period).is_greater(0)
	assert_object(p.ground).is_not_null()


func test_harvester_params_refuse_a_missing_key_without_defaults() -> void:
	var c: ContentSet = Ai16Kit.content()
	for key: String in ["flee_radius_m", "quiet_s"]:
		var ap: Dictionary = Ai16Kit.ap().duplicate(true)
		var _e: bool = ap.erase(key)
		assert_object(HarvesterParams.from_content(c, ap, Ai16Kit.ground_def())).override_failure_message(key).is_null()
	for key: String in HarvesterParams.HARVEST_KEYS:
		var ap: Dictionary = Ai16Kit.ap().duplicate(true)
		var _e: bool = (ap["harvest"] as Dictionary).erase(key)
		assert_object(HarvesterParams.from_content(c, ap, Ai16Kit.ground_def())).override_failure_message(key).is_null()
	var ap2: Dictionary = Ai16Kit.ap().duplicate(true)
	var _e2: bool = ap2.erase("follow")
	assert_object(HarvesterParams.from_content(c, ap2, Ai16Kit.ground_def())).is_null()


func test_def_tables_refinery_tower_envelope_and_armed_ships() -> void:
	var c: ContentSet = Ai16Kit.content()
	var p: HarvesterParams = _params()
	var d: Callable = func(n: StringName) -> int: return c.entity_index[n]
	assert_bool(p.is_dock(d.call(&"refinery"))).is_true()
	assert_bool(p.is_dock(d.call(&"core"))).is_false()
	assert_bool(p.is_dock(d.call(&"autocannon_turret"))).is_false()
	assert_bool(p.is_armed(d.call(&"lancer"))).is_true()
	assert_bool(p.is_armed(d.call(&"dart"))).is_true()
	assert_bool(p.is_armed(d.call(&"hauler"))).is_false()
	assert_bool(p.is_armed(d.call(&"harvester"))).is_false()                 # not a ship def: never armed here
	# the Autocannon Tower covers a threat 200 m above it (h_rel -200..400), not 500 m above, and is not a Refinery
	var ac: int = d.call(&"autocannon_turret")
	assert_bool(p.covers(ac, 200.0, 200.0)).is_true()
	assert_bool(p.covers(ac, 500.0, 500.0)).is_false()
	assert_bool(p.covers(ac, -250.0, 0.0)).is_false()
	assert_bool(p.covers(d.call(&"refinery"), 0.0, 0.0)).is_false()          # not a tower


# --- HarvestPicker.pick_sticky ------------------------------------------------------------------------------------------

func _fields(n: int) -> Array:
	var dirs: PackedVector3Array = PackedVector3Array()
	var rem: PackedFloat32Array = PackedFloat32Array()
	var free: PackedInt32Array = PackedInt32Array()
	var asg: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		var _a: bool = dirs.push_back(Ai16Kit.dir_at(500.0 * float(i + 1)))
		var _b: bool = rem.push_back(1.0)
		var _c: bool = free.push_back(4)
		var _d: bool = asg.push_back(0)
	return [dirs, rem, free, asg]


func test_sticky_keeps_the_last_field_unless_its_utility_fell_by_more_than_the_drop() -> void:
	var f: Array = _fields(2)                                                # fields at 500 m and 1,000 m
	var dirs: PackedVector3Array = f[0]
	var rem: PackedFloat32Array = f[1]
	var free: PackedInt32Array = f[2]
	var asg: PackedInt32Array = f[3]
	var from: Vector3 = Ai16Kit.dir_at(0.0)
	# last = the far field: plain pick would take the near one (utility 1/1.5 vs 1/2); 0.5 / 0.667 = 0.75 >= 0.7: stays
	assert_int(HarvestPicker.pick(from, dirs, rem, free, asg, 0.5, -1)).is_equal(0)
	assert_int(HarvestPicker.pick_sticky(from, dirs, rem, free, asg, 0.5, -1, 1, 0.3)).is_equal(1)
	# the far field has half its Ore: 0.25 / 0.667 = 0.375 < 0.7: it is dropped
	rem[1] = 0.5
	assert_int(HarvestPicker.pick_sticky(from, dirs, rem, free, asg, 0.5, -1, 1, 0.3)).is_equal(0)
	# the last field is gone (no Ore, no slot, avoided): never kept
	rem[1] = 1.0
	free[1] = 0
	assert_int(HarvestPicker.pick_sticky(from, dirs, rem, free, asg, 0.5, -1, 1, 0.3)).is_equal(0)
	free[1] = 4
	assert_int(HarvestPicker.pick_sticky(from, dirs, rem, free, asg, 0.5, 1, 1, 0.3)).is_equal(0)
	rem[0] = 0.0
	rem[1] = 0.0
	assert_int(HarvestPicker.pick_sticky(from, dirs, rem, free, asg, 0.5, -1, 1, 0.3)).is_equal(-1)
	# no last field, or the best is the last: the plain pick
	rem[0] = 1.0
	rem[1] = 1.0
	assert_int(HarvestPicker.pick_sticky(from, dirs, rem, free, asg, 0.5, -1, -1, 0.3)).is_equal(0)
	assert_int(HarvestPicker.pick_sticky(from, dirs, rem, free, asg, 0.5, -1, 0, 0.3)).is_equal(0)


# --- HarvestSites -------------------------------------------------------------------------------------------------------

func _sites() -> Array:
	var w: SimWorld = Ai16Kit.world(3)
	var _a: int = Ai16Kit.field(w, 450.0)
	var _b: int = Ai16Kit.field(w, 1500.0, 0.0, 6000, 2.0, 100.0, 2)
	var b: HarvesterBrain = Ai16Kit.brain()
	b.bind_fields(w.economy().harvest.fields)
	return [w, b.sites, b]


func test_the_mining_spot_is_inside_the_field_at_spot_frac_of_the_radius_on_the_approach_side() -> void:
	var rig: Array = _sites()
	var sites: HarvestSites = rig[1]
	assert_int(sites.field_count()).is_equal(2)
	var centre: Vector3 = Ai16Kit.dir_at(450.0) * R
	for from: Vector3 in [Ai16Kit.dir_at(0.0) * R, Ai16Kit.dir_at(450.0, 600.0) * R, Ai16Kit.dir_at(1200.0, -300.0) * R]:
		var sp: Vector3 = sites.spot(0, from)
		assert_float(GroundFollower.flat(centre, sp)).is_equal_approx(75.0, 0.5)                  # 0.5 x 150 m
		var arc_c: float = acos(clampf(from.normalized().dot(centre.normalized()), -1.0, 1.0)) * R
		var arc_s: float = acos(clampf(from.normalized().dot(sp.normalized()), -1.0, 1.0)) * R
		assert_float(arc_s).is_equal_approx(arc_c - 75.0, 0.5)                                     # BUG-4: the near side
	var west: Vector3 = sites.spot(0, Ai16Kit.dir_at(0.0) * R)
	assert_float(west.distance_to(sites.spot(0, Ai16Kit.dir_at(100.0) * R))).is_less(0.01)    # same side: same spot
	assert_float(GroundFollower.flat(Ai16Kit.dir_at(1500.0) * R, sites.spot(1, Ai16Kit.dir_at(0.0) * R))).is_equal_approx(50.0, 0.5)
	var c2: Vector3 = Ai16Kit.dir_at(1500.0) * R
	assert_float(GroundFollower.flat(c2, sites.spot(1, c2))).is_equal_approx(50.0, 0.5)         # from the centre: any side, still inside


func test_nearest_field_of_a_point() -> void:
	var sites: HarvestSites = _sites()[1]
	assert_int(sites.nearest_field(Ai16Kit.dir_at(500.0, 30.0) * R)).is_equal(0)
	assert_int(sites.nearest_field(Ai16Kit.dir_at(1400.0, -30.0) * R)).is_equal(1)


func test_toward_places_a_point_at_the_arc_distance() -> void:
	var site: Vector3 = Ai16Kit.dir_at(0.0) * R
	var p: Vector3 = HarvestSites.toward(site, Ai16Kit.dir_at(300.0) * R, 40.0)
	assert_float(GroundFollower.flat(site, p)).is_equal_approx(40.0, 0.05)
	assert_float(p.y).is_greater(0.0)                                         # on the side it comes from
	var away: Vector3 = HarvestSites.toward(site, Ai16Kit.dir_at(300.0) * R, -40.0)
	assert_float(away.y).is_less(0.0)
	assert_float(HarvestSites.toward(site, site, 25.0).distance_to(site)).is_greater(24.0)   # same point: any side, still 25 m


func test_the_dock_stop_is_inside_the_sims_delivery_reach() -> void:
	var rig: Array = _sites()
	var w: SimWorld = rig[0]
	var sites: HarvestSites = rig[1]
	var ref: int = Ai16Kit.put(w, &"refinery", 0, 0.0)
	var from: Vector3 = Ai16Kit.dir_at(400.0) * R
	var stop: Vector3 = sites.dock_stop(w.view(), ref, from)
	var d: float = GroundFollower.flat(w.view().pos(ref), stop)
	var c: ContentSet = Ai16Kit.content()
	assert_float(d).is_greater(w.view().radius(ref))                          # outside the structure
	assert_float(d).is_less(w.view().radius(ref) + c.economy.salvage_deliver_m)   # inside radius + salvage_deliver_m (H5)


func test_best_refinery_weighs_distance_against_queue_and_skips_unfinished_and_enemy() -> void:
	var rig: Array = _sites()
	var w: SimWorld = rig[0]
	var sites: HarvestSites = rig[1]
	var near: int = Ai16Kit.put(w, &"refinery", 0, 200.0)
	var far: int = Ai16Kit.put(w, &"refinery", 0, 900.0)
	var _enemy: int = Ai16Kit.put(w, &"refinery", DartKit.FOE, 100.0)
	var p: Vector3 = w.view().pos(near)
	assert_int(sites.best_refinery(w.view(), 0, p, w.tick(), 0)).is_equal(near)
	assert_int(sites.best_refinery(w.view(), 0, p, w.tick(), near)).is_equal(far)    # avoid
	assert_int(sites.refineries(w.view(), 0, w.tick()).size()).is_equal(2)           # the enemy's is not on the team's list
	# an unfinished one (F_BUILDING) is never usable
	w.store().flags[EntityId.slot(near)] |= EntityStore.F_BUILDING
	assert_bool(sites.usable(w.view(), 0, near)).is_false()
	assert_int(sites.best_refinery(w.view(), 0, p, w.tick(), 0)).is_equal(far)


func test_flee_site_is_a_covering_tower_else_the_nearest_refinery() -> void:
	var rig: Array = _sites()
	var w: SimWorld = rig[0]
	var sites: HarvestSites = rig[1]
	var ref: int = Ai16Kit.put(w, &"refinery", 0, 100.0)
	var tower: int = Ai16Kit.put(w, &"autocannon_turret", 0, 800.0)
	var p: Vector3 = Ai16Kit.dir_at(450.0) * R
	var threat_low: Vector3 = Ai16Kit.dir_at(500.0) * (R + 200.0)             # 200 m up: the Autocannon covers it
	var threat_high: Vector3 = Ai16Kit.dir_at(500.0) * (R + 900.0)            # 900 m up: it does not
	assert_int(sites.flee_site(w.view(), 0, p, threat_low)).is_equal(tower)   # the tower, although the Refinery is nearer
	assert_int(sites.flee_site(w.view(), 0, p, threat_high)).is_equal(ref)
	var none: int = sites.flee_site(w.view(), 1, p, threat_low)               # team 1 owns neither
	assert_int(none).is_equal(0)
