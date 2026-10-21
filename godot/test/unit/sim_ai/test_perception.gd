extends GdUnitTestSuite
## AI-22 Perception (05 s7.1 rule 2, s7.2, s7.8): contacts only from the team's vision, own vision, reaction delay,
## ghosts kept by memory and forgotten when their spot is seen empty, the work counters of a refresh, the profile
## parse (and its mirror of bot_promises.json reaction_s), and S4 bytes with the digest rebuilt bit for bit.

const HOME: Vector3 = Vector3(1, 0, 0)
const VISION_TICKS: int = 8          # > one Vision period at 5 Hz (6 ticks): every team has passed


func _world() -> SimWorld:
	return DartKit.world(11)


func _team() -> Perception:
	return Perception.new(0, -1, IntelKit.profile("team"), IntelKit.tables())


func test_profiles_parse_and_mirror_the_promises() -> void:
	var memory: Dictionary = {"easy": 10, "normal": 30, "hard": 60, "brutal": 90}
	for pd: BotPromiseDef in DartKit.content().bot_promises:
		var tier: String = str(pd.id)
		var d: Dictionary = IntelKit.raw()["perception"][tier]
		assert_float(TargetParams.num(d, "reaction_delay_s", -1.0)).override_failure_message(tier).is_equal(pd.reaction_s)
		var p: PerceptionParams = IntelKit.profile(tier)
		assert_bool(p.own_vision).is_equal(tier == "easy")
		assert_int(p.memory_ticks).is_equal(int(memory[tier]) * 30)
		assert_int(p.delay_ticks).is_equal(roundi(pd.reaction_s * 30.0))
	for k: String in PerceptionParams.KEYS:
		var d: Dictionary = (IntelKit.raw()["perception"]["normal"] as Dictionary).duplicate()
		d.erase(k)
		assert_object(PerceptionParams.from_dict(d, 30)).override_failure_message(k).is_null()
	assert_object(PerceptionParams.from_dict({"vision": "all", "ghost_memory_s": 1, "reaction_delay_s": 0}, 30)).is_null()


func test_contacts_come_from_team_vision_only() -> void:
	var w: SimWorld = _world()
	var own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var near: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	var far: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 0.0, 5000.0))
	var base: int = IntelKit.spawn(w, &"refinery", 1, 1, DartKit.above(w, DartKit.geo(0.0, 90.0), 0.0))
	IntelKit.run(w, VISION_TICKS)
	var v: SimView = w.view()
	var p: Perception = _team()
	p.refresh(v, w.tick())
	assert_int(p.n_known).is_equal(1)
	assert_bool(p.knows(near, w.tick())).is_true()
	assert_bool(p.knows(far, w.tick())).is_false()
	assert_bool(p.knows(base, w.tick())).is_false()
	for i: int in p.n_known:
		assert_bool(v.visible_to(0, p.k_id[p.known[i]])).is_true()
	assert_vector(p.k_pos[EntityId.slot(near)]).is_equal(v.pos(near))
	assert_int(p.k_cell[EntityId.slot(near)]).is_equal(IntelKit.cell(v.pos(near)))
	assert_int(p.n_own).is_equal(1)
	assert_int(p.own_id[0]).is_equal(own)
	assert_int(p.n_ghosts).is_equal(0)


func test_reaction_delay_postpones_a_new_contact() -> void:
	var w: SimWorld = _world()
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var tur: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	IntelKit.run(w, VISION_TICKS)
	var p: Perception = Perception.new(0, -1, IntelKit.profile("normal"), IntelKit.tables())   # 2 s
	var m: ThreatMap = ThreatMap.new(IntelKit.tables())
	var t0: int = w.tick()
	p.refresh(w.view(), t0)
	m.update(w.view(), p, t0)
	assert_bool(p.knows(tur, t0)).is_false()
	assert_float(m.threat_at(IntelKit.cell(w.view().pos(tur)), ThreatMap.AIR_DECK)).is_equal(0.0)
	assert_int(p.n_fresh_keys).is_equal(0)
	assert_bool(p.knows(tur, t0 + 59)).is_false()
	assert_bool(p.knows(tur, t0 + 60)).is_true()
	p.refresh(w.view(), t0 + 60)
	m.update(w.view(), p, t0 + 60)
	assert_float(m.threat_at(IntelKit.cell(w.view().pos(tur)), ThreatMap.AIR_DECK)).is_greater(0.0)
	assert_int(p.k_first[EntityId.slot(tur)]).is_equal(t0)   # re-seen: the first sight is kept


func test_ghost_is_kept_for_its_memory_when_unobserved() -> void:
	var w: SimWorld = _world()
	var own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var tur: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	IntelKit.run(w, VISION_TICKS)
	var prm: PerceptionParams = PerceptionParams.from_dict({"vision": "team", "ghost_memory_s": 1.5, "reaction_delay_s": 0}, 30)
	var p: Perception = Perception.new(0, -1, prm, IntelKit.tables())
	var t0: int = w.tick()
	p.refresh(w.view(), t0)
	IntelKit.teleport(w, own, DartKit.above(w, DartKit.geo(0.0, 90.0), 300.0))   # the only sensor leaves
	IntelKit.run(w, VISION_TICKS)
	assert_bool(w.view().visible_to(0, tur)).is_false()
	p.refresh(w.view(), t0 + 45)
	assert_bool(p.knows(tur, t0 + 45)).is_true()
	assert_int(p.n_ghosts).is_equal(1)
	assert_int(p.k_seen[EntityId.slot(tur)]).is_equal(t0)
	p.refresh(w.view(), t0 + 46)
	assert_bool(p.knows(tur, t0 + 46)).is_false()
	assert_int(p.n_known).is_equal(0)


func test_ghost_is_forgotten_when_its_spot_is_seen_empty() -> void:
	var w: SimWorld = _world()
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var foe: int = IntelKit.spawn(w, &"dart", 1, 1, IntelKit.at(w, HOME, 700.0, 0.0, 300.0))
	IntelKit.run(w, VISION_TICKS)
	var p: Perception = _team()
	p.refresh(w.view(), w.tick())
	assert_bool(p.knows(foe, w.tick())).is_true()
	IntelKit.teleport(w, foe, DartKit.above(w, DartKit.geo(0.0, 90.0), 300.0))
	IntelKit.run(w, VISION_TICKS)
	p.refresh(w.view(), w.tick())
	assert_int(p.n_known).is_equal(0)   # its last spot is inside our sensor and the team does not see it there


func test_own_vision_keeps_only_the_slots_contacts() -> void:
	var w: SimWorld = _world()
	var _mine: int = IntelKit.spawn(w, &"dart", 2, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var _mate: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 4000.0, 300.0))
	var a: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	var b: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 4000.0))
	IntelKit.run(w, VISION_TICKS)
	var team: Perception = _team()
	var easy: Perception = Perception.new(0, 2, IntelKit.profile("easy"), IntelKit.tables())
	var t: int = w.tick()
	team.refresh(w.view(), t)
	easy.refresh(w.view(), t)
	assert_bool(team.knows(a, t) and team.knows(b, t)).is_true()
	assert_int(easy.n_known).is_equal(1)
	assert_bool(easy.knows(a, t)).is_false()          # 6 s reaction delay
	assert_bool(easy.knows(a, t + 180)).is_true()
	assert_bool(easy.knows(b, t + 180)).is_false()    # only the teammate's sensor sees b


func test_refresh_work_counters() -> void:
	var w: SimWorld = _world()
	var _own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var _core: int = IntelKit.spawn(w, &"refinery", 0, 0, IntelKit.at(w, HOME, 300.0, 0.0))
	var _foe: int = IntelKit.spawn(w, &"dart", 1, 1, IntelKit.at(w, HOME, 700.0, 0.0, 300.0))
	var _tur: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	IntelKit.run(w, VISION_TICKS)
	var p: Perception = _team()
	p.refresh(w.view(), w.tick())
	assert_int(p.stats_view_calls).is_equal(1 + 2 * 4 + 2 + 2)   # visible_ids; def + team per new id; pos per ship and per new structure
	var c0: int = p.stats_view_calls
	p.refresh(w.view(), w.tick() + 1)
	assert_int(p.stats_view_calls - c0).is_equal(1 + 2)          # cached: visible_ids + one pos per ship
	assert_int(p.n_known).is_equal(2)
	assert_int(p.n_own).is_equal(2)


func test_random_world_never_knows_an_unseen_entity() -> void:
	var w: SimWorld = _world()
	var rng: Rng = Rng.new(5)
	for k: int in 4:   # moving sensors: a contact that leaves vision keeps a ghost once its spot is uncovered
		var q0: Vector3 = IntelKit.at(w, HOME, rng.range_f(-1500.0, 1500.0), rng.range_f(-1500.0, 1500.0), 300.0)
		var _o: int = IntelKit.spawn(w, &"dart", 0, 0, q0, Sphere.tangent_frame(q0).x.rotated(q0.normalized(), rng.range_f(0.0, TAU)) * 200.0)
	var foes: PackedInt32Array = PackedInt32Array()
	for k: int in 24:
		var p0: Vector3 = IntelKit.at(w, HOME, rng.range_f(-4000.0, 4000.0), rng.range_f(-4000.0, 4000.0), rng.range_f(100.0, 900.0))
		var v0: Vector3 = Sphere.tangent_frame(p0).x.rotated(p0.normalized(), rng.range_f(0.0, TAU)) * 150.0
		var _a: bool = foes.push_back(IntelKit.spawn(w, &"dart", 1, 1, p0, v0))
	var ever: Dictionary = {}
	var p: Perception = Perception.new(0, -1, IntelKit.profile("brutal"), IntelKit.tables())
	var max_ghosts: int = 0
	for step: int in 240:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		for id: int in foes:
			if w.view().visible_to(0, id):
				ever[id] = true
		if step % 10 == 0:
			p.refresh(w.view(), w.tick())
			max_ghosts = maxi(max_ghosts, p.n_ghosts)
			for i: int in p.n_known:
				var s: int = p.known[i]
				assert_bool(ever.has(p.k_id[s])).is_true()
				if p.k_seen[s] == w.tick():
					assert_bool(w.view().visible_to(0, p.k_id[s])).is_true()
	assert_int(ever.size()).is_greater(0)
	assert_int(ever.size()).is_less(foes.size())
	assert_int(max_ghosts).is_greater(0)


func test_s4_bytes_round_trip_with_the_digest() -> void:
	var w: SimWorld = _world()
	var own: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, HOME, 0.0, 0.0, 300.0))
	var _t1: int = IntelKit.spawn(w, &"autocannon_turret", 1, 1, IntelKit.at(w, HOME, 800.0, 0.0))
	var _t2: int = IntelKit.spawn(w, &"flak_battery", 1, 1, IntelKit.at(w, HOME, -900.0, 200.0))
	var _f: int = IntelKit.spawn(w, &"lancer", 1, 1, IntelKit.at(w, HOME, 0.0, 900.0, 400.0))
	IntelKit.run(w, VISION_TICKS)
	var p: Perception = _team()
	p.refresh(w.view(), w.tick())
	IntelKit.teleport(w, own, IntelKit.at(w, HOME, 0.0, 1400.0, 300.0))   # the flak and turret become ghosts
	IntelKit.run(w, VISION_TICKS)
	p.refresh(w.view(), w.tick())
	assert_int(p.n_ghosts).is_greater(0)
	assert_int(p.n_fresh_keys).is_greater(0)
	var bytes: PackedByteArray = p.serialize()
	var q: Perception = _team()
	assert_bool(q.deserialize(bytes)).is_true()
	assert_bool(q.serialize() == bytes).is_true()
	assert_int(q.n_ghosts).is_equal(p.n_ghosts)
	assert_bool(q.ghosts.slice(0, q.n_ghosts) == p.ghosts.slice(0, p.n_ghosts)).is_true()
	assert_bool(q.fresh_keys.slice(0, q.n_fresh_keys) == p.fresh_keys.slice(0, p.n_fresh_keys)).is_true()
	assert_bool(q.fresh_bin == p.fresh_bin and q.fresh_val == p.fresh_val).is_true()
	var bad: PackedByteArray = bytes.duplicate()
	bad[0] = Perception.FORMAT + 1
	assert_bool(q.deserialize(bad)).is_false()
	assert_int(q.n_known).is_equal(0)
	assert_int(q.n_fresh_keys).is_equal(0)
