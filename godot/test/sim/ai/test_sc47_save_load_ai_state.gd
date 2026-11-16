extends GdUnitTestSuite
## 05 s11.2 SC-47 save_load_ai_state (AI-33): a mixed skirmish on the AI-14 fixture (Darts, Lancer, Bomber, Scout on
## AUTO, both teams, per-team intel), saved through SimWorld.serialize() (S4: world + hook bytes) and restored into a
## world whose driver is configured as a session does (brains, overlays, class table, intel, before deserialize). Pass:
## the AI state round-trips (driver bytes equal), and the first 300 ticks after the load match a continuous run in
## modes and targets every tick, and in the full S4 bytes every second tick. Same machine (same Godot build).

const HZ: int = 30
const SAVE_TICKS: int = 20 * HZ
const AFTER_TICKS: int = 300
const FOE: int = DartKit.FOE


func _skirmish(seed_value: int) -> Array:
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
	for _k: int in SAVE_TICKS:
		var _ev: Array[SimEvent] = Ai14Kit.step(w)
	return [w, d]


func _restore(bytes: PackedByteArray, src: SimWorld) -> Array:
	var d2: AiDriver = Ai14Kit.make_driver(src.terrain())
	var w2: SimWorld = SimWorld.deserialize(bytes, Ai14Kit.content(), d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	return [w2, d2]


func _same_modes_targets(a: AiDriver, b: AiDriver) -> bool:
	return a.state.mode == b.state.mode and a.state.target == b.state.target and a.state.cls == b.state.cls


func test_sc47_save_load_ai_state() -> void:
	for seed_value: int in [1, 2, 3]:
		var r: Array = _skirmish(seed_value)
		var wa: SimWorld = r[0]
		var da: AiDriver = r[1]
		var bytes: PackedByteArray = wa.serialize()
		var regs: int = 0
		for s: int in da.state.cls.size():
			regs += 1 if da.state.cls[s] != AiState.NO_CLASS else 0
		assert_int(regs).is_greater(8)
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
