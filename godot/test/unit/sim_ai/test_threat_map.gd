extends GdUnitTestSuite
## AI-22 ThreatMap (05 s7.4): tower bands by envelope, fighters at half DPS, ground attackers, the ring rule against a
## brute force, ghost decay by half-life, values, own defence, last_seen, route_risk, hottest_own_cell, the update work
## counters, and determinism of the channels.

const HOME: Vector3 = Vector3(1, 0, 0)
const VISION_TICKS: int = 8


func _seen(w: SimWorld) -> Array:
	IntelKit.run(w, VISION_TICKS)
	var p: Perception = Perception.new(0, -1, IntelKit.profile("team"), IntelKit.tables())
	var m: ThreatMap = ThreatMap.new(IntelKit.tables())
	p.refresh(w.view(), w.tick())
	m.update(w.view(), p, w.tick())
	return [p, m]


func _dps(weapon: StringName) -> float:
	return ThreatParams.sustained_dps(IntelKit.weapon(weapon))


func test_sustained_dps_of_each_weapon_shape() -> void:
	assert_float(_dps(&"gun_dart")).is_equal_approx(100.0, 1e-3)                        # 10 x 10 / s
	assert_float(_dps(&"gun_turret")).is_equal_approx(10.0 * 5.0 / (5.0 / 12.0 + 1.2), 1e-3)   # bursts of 5
	assert_float(_dps(&"flak_gun")).is_equal_approx(30.0, 1e-3)                         # salvo 2 / 2 s
	assert_float(ThreatParams.sustained_dps(null)).is_equal(0.0)


func test_tower_bands_follow_the_envelope() -> void:
	var w: SimWorld = DartKit.world(3)
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var gun: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	var r: Array = _seen(w)
	var m: ThreatMap = r[1]
	var c: int = IntelKit.cell(w.view().pos(gun))
	var g: float = _dps(&"gun_turret")
	assert_float(m.threat_at(c, ThreatMap.AIR_DECK)).is_equal_approx(g, 1e-3)    # h_rel -200..400: Deck 60, Low 250
	assert_float(m.threat_at(c, ThreatMap.AIR_LOW)).is_equal_approx(g, 1e-3)
	assert_float(m.threat_at(c, ThreatMap.AIR_HIGH)).is_equal(0.0)               # High 600 is above the envelope
	assert_float(m.threat_at(c, ThreatMap.GROUND)).is_equal_approx(g, 1e-3)      # target_kinds ship + ground
	assert_float(m.ch[ThreatMap.ENEMY_VALUE * ThreatMap.CELLS + c]).is_equal(200.0)
	var w2: SimWorld = DartKit.world(3)
	var _own2: int = IntelKit.spawn(w2, &"dart", 0, 0, IntelKit.at(w2, HOME, 0.0, 0.0, 300.0))
	var flak: int = IntelKit.spawn(w2, &"flak_battery", 1, 1, IntelKit.at(w2, HOME, 800.0, 0.0))
	var m2: ThreatMap = _seen(w2)[1]
	var c2: int = IntelKit.cell(w2.view().pos(flak))
	assert_float(m2.threat_at(c2, ThreatMap.AIR_DECK)).is_equal(0.0)             # h_rel 150..1500
	assert_float(m2.threat_at(c2, ThreatMap.AIR_HIGH)).is_equal_approx(_dps(&"flak_gun"), 1e-3)
	assert_float(m2.threat_at(c2, ThreatMap.GROUND)).is_equal(0.0)


func test_fighters_at_half_dps_and_lancers_on_ground() -> void:
	var w: SimWorld = DartKit.world(3)
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var dart: int = IntelKit.spawn(w, &"dart", 1, 1, IntelKit.at(w, HOME, 700.0, 0.0, 400.0))
	var m: ThreatMap = _seen(w)[1]
	var c: int = IntelKit.cell(w.view().pos(dart))
	assert_float(m.threat_at(c, ThreatMap.AIR_HIGH)).is_equal_approx(0.5 * _dps(&"gun_dart"), 1e-3)
	assert_float(m.threat_at(c, ThreatMap.GROUND)).is_equal(0.0)
	var w2: SimWorld = DartKit.world(3)
	var _own2: int = IntelKit.spawn(w2, &"dart", 0, 0, IntelKit.at(w2, HOME, 0.0, 0.0, 300.0))
	var lancer: int = IntelKit.spawn(w2, &"lancer", 1, 1, IntelKit.at(w2, HOME, 700.0, 0.0, 400.0))
	var m2: ThreatMap = _seen(w2)[1]
	var c2: int = IntelKit.cell(w2.view().pos(lancer))
	assert_float(m2.threat_at(c2, ThreatMap.GROUND)).is_equal_approx(0.5 * _dps(&"gun_lancer"), 1e-3)


func test_rings_match_the_brute_force_rule() -> void:
	var t: ThreatParams = IntelKit.tables()
	assert_int(t.classes).is_greater(2)
	for k: int in range(1, t.classes):
		var reach: float = -1.0
		for p: int in range(1, t.profiles):
			if t.prof_class[p] == k:
				reach = _range_of(t, p)
		for c: int in range(0, ThreatParams.CELLS, 7):
			var got: Dictionary = {}
			var base: int = k * (ThreatParams.CELLS + 1) + c
			for j: int in range(t.ring_start[base], t.ring_start[base + 1]):
				got[t.ring_cell[j]] = t.ring_w[j]
			for h: int in ThreatParams.CELLS:
				var d: float = maxf(t.centre[c].angle_to(t.centre[h]) * Sphere.PLANET_RADIUS - t.circ_m[c], 0.0)
				var want: float = 1.0 if d <= reach else clampf(1.0 - (d - reach) / t.margin_m, 0.0, 1.0)
				var have: float = float(got.get(h, 0.0))
				assert_float(have).override_failure_message("class %d c %d h %d" % [k, c, h]).is_equal_approx(want, 1e-4)


# The range of profile p (its class ring was built from it): recovered from the defs.
func _range_of(t: ThreatParams, p: int) -> float:
	var c: ContentSet = DartKit.content()
	var fr: float = TargetParams.num(IntelKit.threat_block(), "fighter_radius_m", 0.0)
	for sd: StructureDef in c.structures:
		if t.profile_by_def[DartKit.def_id(sd.id)] == p:
			return IntelKit.weapon(StringName(str(sd.tower.get("weapon", "")))).range_m
	for gd: GroundUnitDef in c.ground_units:
		if t.profile_by_def[DartKit.def_id(gd.id)] == p:
			return IntelKit.weapon(gd.weapon).range_m
	return fr


func test_ghost_decays_with_its_half_life() -> void:
	var w: SimWorld = DartKit.world(3)
	var own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var gun: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	var r: Array = _seen(w)
	var p: Perception = r[0]
	var m: ThreatMap = r[1]
	var t0: int = w.tick()
	var c: int = IntelKit.cell(w.view().pos(gun))
	IntelKit.teleport(w, own, DartKit.above(w, DartKit.geo(0.0, 90.0), 300.0))
	IntelKit.run(w, VISION_TICKS)
	p.refresh(w.view(), t0 + 1800)      # 60 s later: one half-life (memory 90 s keeps it)
	m.update(w.view(), p, t0 + 1800)
	assert_int(p.n_ghosts).is_equal(1)
	assert_float(m.ch[ThreatMap.ENEMY_VALUE * ThreatMap.CELLS + c]).is_equal_approx(100.0, 1e-2)
	assert_float(m.threat_at(c, ThreatMap.AIR_DECK)).is_equal_approx(0.5 * _dps(&"gun_turret"), 1e-3)


func test_own_value_defence_and_last_seen() -> void:
	var w: SimWorld = DartKit.world(3)
	var tur: int = IntelKit.spawn(w, &"autocannon_turret", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0))
	var m: ThreatMap = _seen(w)[1]
	var c: int = IntelKit.cell(w.view().pos(tur))
	var g: float = _dps(&"gun_turret")
	assert_float(m.ch[ThreatMap.OWN_VALUE * ThreatMap.CELLS + c]).is_equal(200.0)
	assert_float(m.ch[ThreatMap.OWN_DEFENCE * ThreatMap.CELLS + c]).is_equal_approx(2.0 * g, 1e-3)   # max air band + ground
	assert_int(m.last_seen[c]).is_equal(w.tick())
	assert_int(m.last_seen[IntelKit.cell(DartKit.geo(0.0, 90.0))]).is_equal(-1)
	for ch: int in 4:
		assert_float(m.threat_at(c, ch)).is_equal(0.0)


func test_route_risk_and_hottest_own_cell() -> void:
	var w: SimWorld = DartKit.world(3)
	var ref_a: int = IntelKit.spawn(w, &"refinery", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0))
	var _ref_b: int = IntelKit.spawn(w, &"refinery", 0, 0, IntelKit.at(w, HOME, 0.0, -6000.0))
	var _own_b: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, -6000.0, 300.0))
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var gun: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 600.0, 0.0))
	var m: ThreatMap = _seen(w)[1]
	assert_int(m.hottest_own_cell()).is_equal(IntelKit.cell(w.view().pos(ref_a)))
	var through: float = m.route_risk(IntelKit.at(w, HOME, -3000.0, 0.0), IntelKit.at(w, HOME, 3000.0, 0.0), ThreatMap.AIR_DECK)
	var away: float = m.route_risk(IntelKit.at(w, HOME, -3000.0, 9000.0), IntelKit.at(w, HOME, 3000.0, 9000.0), ThreatMap.AIR_DECK)
	assert_float(through).is_greater_equal(m.threat_at(IntelKit.cell(w.view().pos(gun)), ThreatMap.AIR_DECK))
	assert_float(away).is_equal(0.0)
	var empty: ThreatMap = ThreatMap.new(IntelKit.tables())
	assert_int(empty.hottest_own_cell()).is_equal(-1)


func test_update_counters_are_bins_times_rings_and_deterministic() -> void:
	var w: SimWorld = DartKit.world(3)
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var a: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	var _b: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 820.0, 30.0))   # same cell, same class: one bin
	var _f: int = IntelKit.spawn(w, &"flak_battery", 1, 1, IntelKit.at(w, HOME, -800.0, 0.0))
	var r: Array = _seen(w)
	var p: Perception = r[0]
	var m: ThreatMap = r[1]
	var t: ThreatParams = IntelKit.tables()
	var want_bins: Dictionary = {}
	var want_cells: int = 0
	for i: int in p.n_known:
		var s: int = p.known[i]
		var key: int = p.k_cell[s] * t.classes + t.prof_class[t.profile_by_def[p.k_def[s]]]
		if not want_bins.has(key):
			want_bins[key] = true
			var base: int = (key % t.classes) * (ThreatParams.CELLS + 1) + MathX.floori_div(key, t.classes)
			want_cells += t.ring_start[base + 1] - t.ring_start[base]
	var own_bins: int = 0
	for i: int in p.n_own:
		if t.profile_by_def[p.own_def[i]] != 0:
			own_bins += 1
	assert_int(m.stats_bins).is_equal(want_bins.size() + own_bins)
	assert_int(m.stats_bins - own_bins).is_equal(2)
	assert_bool(m.stats_cells >= want_cells).is_true()
	var before: PackedFloat32Array = m.ch.duplicate()
	m.update(w.view(), p, w.tick())
	assert_bool(m.ch == before).is_true()
	var bytes: PackedByteArray = m.serialize()
	var m2: ThreatMap = ThreatMap.new(t)
	assert_bool(m2.deserialize(bytes)).is_true()
	m2.update(null, p, m2.updated)
	assert_bool(m2.ch == m.ch and m2.last_seen == m.last_seen).is_true()
	assert_bool(m2.serialize() == bytes).is_true()
	var bad: PackedByteArray = bytes.duplicate()
	bad[0] = ThreatMap.FORMAT + 1
	assert_bool(m2.deserialize(bad)).is_false()
	assert_float(m.threat_at(IntelKit.cell(w.view().pos(a)), ThreatMap.AIR_DECK)).is_equal_approx(2.0 * _dps(&"gun_turret"), 1e-3)
