extends GdUnitTestSuite
## 05 s11.2 SC-47 save_load_ai_state (AI-33): a mixed skirmish on the AI-14 fixture (Darts, Lancer, Bomber, Scout on
## AUTO, both teams, per-team intel), saved through SimWorld.serialize() (S4: world + hook bytes) and restored into a
## world whose driver is configured as a session does (brains, overlays, class table, intel, before deserialize). Pass:
## the AI state round-trips (driver bytes equal), and the first 300 ticks after the load match a continuous run in
## modes and targets every tick, and in the full S4 bytes every second tick. Same machine (same Godot build).

const HZ: int = 30
const SAVE_TICKS: int = 20 * HZ
const SAVE_TEN_MIN: int = 600 * HZ   ## SC-47's "save at 10:00"
const AFTER_TICKS: int = 300
const FOE: int = DartKit.FOE


func _skirmish(seed_value: int, ticks: int = SAVE_TICKS) -> Array:
	var w: SimWorld = Ai14Kit.world(seed_value)
	var d: AiDriver = Ai14Kit.driver(w)
	var _core0: int = Ai14Kit.core(w, Vector3(1, 0, 0), 0)
	var _core1: int = Ai14Kit.core(w, DartKit.geo(0.0, 40.0), FOE)
	var rng: Rng = Rng.new(4700 + seed_value)
	var defs: Array[StringName] = [&"dart", &"dart", &"lancer", &"bomber", &"scout"]
	for def: StringName in defs:
		for team: int in [0, FOE]:
			var base: Vector3 = DartKit.geo(0.0, 20.0 if team == 0 else 24.0)
			var dir: Vector3 = DartKit.offset(base, rng.range_f(-1500.0, 1500.0), rng.range_f(-1500.0, 1500.0))
			var p: Vector3 = DartKit.above(w, dir, 300.0)
			var h: Vector3 = DartKit.heading(p, Vector3(0, 1, 0)).rotated(p.normalized(), rng.range_f(0.0, TAU))
			var _id: int = DartKit.spawn(w, def, team, p, h * 100.0, h)
	var deaths: int = 0
	for _k: int in ticks:
		for e: SimEvent in Ai14Kit.step(w):
			deaths += 1 if e.kind == SimEvent.Kind.DEATH else 0
	return [w, d, deaths]


## Slots whose AI state is not default: landing phase or aux id set, a target held, a mode entered after the spawn.
func _nondefault(d: AiDriver) -> Dictionary:
	var n: Dictionary = {"land": 0, "aux": 0, "target": 0}
	for s: int in d.state.cls.size():
		if d.state.cls[s] == AiState.NO_CLASS:
			continue
		n["land"] += 1 if d.state.land_phase[s] != 0 else 0
		n["aux"] += 1 if d.state.aux_id[s] != 0 else 0
		n["target"] += 1 if d.state.target[s] != 0 else 0
	return n


func _restore(bytes: PackedByteArray, src: SimWorld) -> Array:
	var d2: AiDriver = Ai14Kit.make_driver(src.terrain())
	var w2: SimWorld = SimWorld.deserialize(bytes, Ai14Kit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	return [w2, d2]


func _same_modes_targets(a: AiDriver, b: AiDriver) -> bool:
	return a.state.mode == b.state.mode and a.state.target == b.state.target and a.state.aux_id == b.state.aux_id and a.state.land_phase == b.state.land_phase and a.state.cls == b.state.cls


func test_sc47_save_load_ai_state() -> void:
	for save_ticks: int in [SAVE_TICKS, SAVE_TEN_MIN]:
		for seed_value: int in [1, 2, 3]:
			_check_skirmish(seed_value, save_ticks)


func _check_skirmish(seed_value: int, save_ticks: int) -> void:
	if true:
		var r: Array = _skirmish(seed_value, save_ticks)
		var wa: SimWorld = r[0]
		var da: AiDriver = r[1]
		var bytes: PackedByteArray = wa.serialize()
		var regs: int = 0
		for s: int in da.state.cls.size():
			regs += 1 if da.state.cls[s] != AiState.NO_CLASS else 0
		assert_int(regs).is_greater(2)
		# The save point must hold non-default AI state, else a field left out of the bytes would go unseen.
		var nd: Dictionary = _nondefault(da)
		var held: int = int(nd["aux"]) + int(nd["land"])
		assert_int(held).override_failure_message("seed %d @%d: no aux_id / land_phase set at the save" % [seed_value, save_ticks]).is_greater(0)
		if save_ticks == SAVE_TEN_MIN:
			assert_int(int(r[2])).override_failure_message("seed %d: no unit died by 10:00" % seed_value).is_greater(0)
			assert_int(int(nd["aux"]) + int(nd["land"])).override_failure_message("seed %d: too little state at 10:00" % seed_value).is_greater(1)
		var r2: Array = _restore(bytes, wa)
		var w2: SimWorld = r2[0]
		var d2: AiDriver = r2[1]
		assert_bool(d2.serialize() == da.serialize()).override_failure_message("seed %d: AI bytes do not round-trip" % seed_value).is_true()
		assert_bool(w2.serialize() == bytes).is_true()
		var engaged: int = 0
		for k: int in AFTER_TICKS:
			wa.step()
			w2.step()
			var _x: Array[SimEvent] = wa.drain_events()
			var _y: Array[SimEvent] = w2.drain_events()
			assert_bool(_same_modes_targets(da, d2)).override_failure_message("seed %d: modes / targets diverge at +%d" % [seed_value, k]).is_true()
			if k % 2 == 0:
				assert_bool(w2.serialize() == wa.serialize()).override_failure_message("seed %d: S4 bytes diverge at +%d" % [seed_value, k]).is_true()
			for s: int in da.state.cls.size():
				engaged += 1 if da.state.cls[s] != AiState.NO_CLASS and da.state.target[s] != 0 else 0
		if save_ticks == SAVE_TICKS:   # by 10:00 the fights are over: the state held there is aux_id / land_phase (asserted above)
			assert_int(engaged).override_failure_message("seed %d: no target was ever held, the run proves nothing" % seed_value).is_greater(0)
		assert_bool(w2.serialize() == wa.serialize()).is_true()


# The economy half of a skirmish: three Harvesters mid-cycle (ground record, path, brake run, stuck ladder, field
# choice) saved at three points of their cycle; each restore matches the continuous run tick by tick in modes and
# targets (aux_id = the chosen field too) and in the S4 bytes at the end.
func test_sc47_economy_save_points() -> void:
	for save_at: int in [15 * HZ, 40 * HZ, 75 * HZ]:
		var w: SimWorld = Ai16Kit.world(11)
		var _r: int = Ai16Kit.put(w, &"refinery", 0, 0.0)
		for e: float in [450.0, 900.0]:
			var _f: int = Ai16Kit.field(w, e, 0.0, 6000, 2.0, 150.0, 2)
		for e: float in [60.0, 90.0, 120.0]:
			var _h: int = Ai16Kit.put(w, &"harvester", 0, e)
		var d: AiDriver = Ai16Kit.driver(w)
		Ai16Kit.step(w, save_at)
		var bytes: PackedByteArray = w.serialize()
		var d2: AiDriver = AiDriver.new(Rng.new(3))
		var b2: HarvesterBrain = Ai16Kit.brain()
		var c: ContentSet = Ai16Kit.content()
		d2.set_class_table(AiClassTable.from_content(c))
		d2.set_brain(Ai16Kit.cls(), b2)
		d2.set_overlay_params(Ai16Kit.cls(), OverlayParams.for_ground(Ai16Kit.ap(), c.rules, c.rules.tick_hz))
		var w2: SimWorld = SimWorld.deserialize(bytes, c, d2)
		assert_object(w2).is_not_null()
		d2.set_terrain(w2.terrain())
		b2.bind_fields(w2.economy().harvest.fields)
		var cycling: int = 0
		for sl: int in d.state.cls.size():
			cycling += 1 if d.state.cls[sl] != AiState.NO_CLASS and d.state.aux_id[sl] != 0 and d.state.path_ticket.size() > sl else 0
		assert_int(cycling).override_failure_message("save at %d: no Harvester has a field chosen" % save_at).is_greater(0)
		assert_bool(d2.serialize() == d.serialize()).override_failure_message("save at %d: AI bytes do not round-trip" % save_at).is_true()
		for k: int in AFTER_TICKS:
			w.step()
			w2.step()
			var _x: Array[SimEvent] = w.drain_events()
			var _y: Array[SimEvent] = w2.drain_events()
			var same: bool = _same_modes_targets(d, d2) and d.state.aux_id == d2.state.aux_id
			assert_bool(same).override_failure_message("save at %d: diverge at +%d" % [save_at, k]).is_true()
		assert_bool(w2.serialize() == w.serialize()).override_failure_message("save at %d: S4 bytes diverge" % save_at).is_true()


# Negative control: the comparison sees a single flipped mode, so a restore that lost a field could not pass unnoticed.
func test_sc47_comparison_detects_a_difference() -> void:
	var r: Array = _skirmish(1)
	var da: AiDriver = r[1]
	var d2: AiDriver = _restore((r[0] as SimWorld).serialize(), r[0])[1]
	assert_bool(_same_modes_targets(da, d2)).is_true()
	for s: int in d2.state.cls.size():
		if d2.state.cls[s] != AiState.NO_CLASS:
			d2.state.mode[s] += 1
			break
	assert_bool(_same_modes_targets(da, d2)).is_false()
	assert_bool(d2.serialize() == da.serialize()).is_false()
