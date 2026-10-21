extends GdUnitTestSuite
## AI-14 contract tests (sim_ai/MODULE.md public API and invariants): AiState FORMAT 6 (`lock_tick`) round trip and
## the refusal of FORMAT 5 bytes, `AiBrain.bind_intel` reaching the brains through `AiDriver` (`set_brain` and
## `set_intel`), the three class brains building from their autopilot dictionaries and refusing a missing key, the
## separation-only `FormationParams`, the `structure_building` target weight, and AiTag.Tag ordinals of the words the
## new brains write (no new ordinal: A-94's reserved words).


func test_ai_state_format6_round_trips_lock_tick_and_refuses_format5() -> void:
	assert_int(AiState.FORMAT).is_equal(6)
	var st: AiState = AiState.new(32)
	st.cls[5] = 1
	st.eid[5] = EntityId.make(5, 1)
	st.lock_tick[5] = 1234
	st.order_tick[5] = 77
	var bytes: PackedByteArray = st.serialize()
	var r: AiState = AiState.new(32)
	assert_bool(r.deserialize(bytes)).is_true()
	assert_int(r.lock_tick[5]).is_equal(1234)
	assert_int(r.order_tick[5]).is_equal(77)
	assert_bool(r.serialize() == bytes).is_true()
	r.clear_slot(5)
	assert_int(r.lock_tick[5]).is_equal(0)
	var old: PackedByteArray = bytes.duplicate()
	old[0] = 5   # a FORMAT 5 blob (AI-13) is refused, state cleared
	assert_bool(r.deserialize(old)).is_false()
	assert_int(r.registered_count()).is_equal(0)


class IntelProbe extends AiBrain:
	var bound: Array[TeamIntel] = []

	func bind_intel(intel: TeamIntel) -> void:
		bound.append(intel)


func test_bind_intel_reaches_brains_on_set_brain_and_set_intel() -> void:
	var base: AiBrain = AiBrain.new()
	base.bind_intel(null)   # the base is a no-op
	var d: AiDriver = AiDriver.new(Rng.new(1))
	var probe: IntelProbe = IntelProbe.new()
	d.set_brain(3, probe)
	assert_int(probe.bound.size()).is_equal(1)
	assert_object(probe.bound[0]).is_null()
	var intel: TeamIntel = IntelKit.intel()
	d.set_intel(intel)
	assert_int(probe.bound.size()).is_equal(2)
	assert_object(probe.bound[1]).is_same(intel)
	var later: IntelProbe = IntelProbe.new()
	d.set_brain(4, later)
	assert_object(later.bound[0]).is_same(intel)


func test_class_brains_build_and_refuse_a_missing_key() -> void:
	var c: ContentSet = Ai14Kit.content()
	var t: Terrain = Terrain.new()
	assert_object(Ai14Kit.lancer(t)).is_not_null()
	assert_object(Ai14Kit.bomber(t)).is_not_null()
	assert_object(Ai14Kit.scout(t)).is_not_null()
	var cases: Array = [
		[&"lancer", "", "guard_cluster_m"], [&"lancer", "rocket", "lock_range_m"], [&"lancer", "rocket", "bomber_reserve"],
		[&"lancer", "rocket", "bomber_known_m"], [&"lancer", "rocket", "breakaway_m"], [&"lancer", "attack_run", "ip_dist_m"],
		[&"lancer", "gun", "fire_range_m"], [&"lancer", "formation", "k_form"], [&"lancer", "", "target_weights"],
		[&"bomber", "bomb", "release_tolerance_m"], [&"bomber", "attack_run", "max_passes"], [&"bomber", "guidance", "kp_alt"],
		[&"bomber", "intercept", "choice_period_thinks"], [&"scout", "", "flee_radius_m"], [&"scout", "search", "agl_m"],
		[&"scout", "search", "flee_s"], [&"scout", "search", "flee_clear_m"], [&"scout", "guidance", "deck_speed_mps"],
		[&"scout", "separation", "radius_m"]]
	for k: Array in cases:
		var def: StringName = k[0]
		var ap: Dictionary = Ai14Kit.ap(def).duplicate(true)
		var blk: String = k[1]
		var d: Dictionary = ap if blk == "" else ap[blk] as Dictionary
		var _e: bool = d.erase(k[2])
		var built: AiBrain = null
		if def == &"lancer":
			built = LancerBrain.create(c, ap, Ai14Kit.ship(def), t)
		elif def == &"bomber":
			built = BomberBrain.create(c, ap, Ai14Kit.ship(def), t)
		else:
			built = ScoutBrain.create(c, ap, Ai14Kit.ship(def), t)
		assert_object(built).override_failure_message("%s %s.%s" % [def, blk, k[2]]).is_null()
	# blocks a class does not use may be absent (A-93: optional elsewhere): no gun / evade / formation on the Bomber
	var bap: Dictionary = Ai14Kit.ap(&"bomber").duplicate(true)
	assert_bool(bap.has("gun") or bap.has("evade") or bap.has("formation") or bap.has("target_weights")).is_false()
	var p: DartParams = DartParams.from_content(bap, Ai14Kit.ship(&"bomber"), c)
	assert_bool(p.has_bombs and not p.has_gun and not p.has_rockets).is_true()
	var sp: DartParams = DartParams.from_content(Ai14Kit.ap(&"scout"), Ai14Kit.ship(&"scout"), c)
	assert_bool(sp.has_bombs or sp.has_gun or sp.has_rockets).is_false()
	var lpar: DartParams = DartParams.from_content(Ai14Kit.ap(&"lancer"), Ai14Kit.ship(&"lancer"), c)
	assert_bool(lpar.has_gun and lpar.has_rockets and not lpar.has_bombs).is_true()


func test_formation_params_separation_only_without_a_formation_block() -> void:
	var sep: Dictionary = Ai14Kit.ap(&"bomber")["separation"]
	var p: FormationParams = FormationParams.from_dict(sep, {}, null, 1600.0, 1000.0, 187.9)
	assert_object(p).is_not_null()
	assert_int(p.slot_count(false)).is_equal(0)
	assert_float(p.query_radius_m).is_equal_approx(180.0, 1e-4)
	assert_float(p.sep_push_mps).is_equal(20.0)
	var bad: Dictionary = (Ai14Kit.ap(&"lancer")["formation"] as Dictionary).duplicate(true)
	var _e: bool = bad.erase("k_form")
	assert_object(FormationParams.from_dict(sep, bad, null, 1600.0, 1000.0)).is_null()


func test_structure_building_weight() -> void:
	var tp: TargetParams = TargetParams.from_dict(Ai14Kit.ap(&"lancer"))
	tp.bind(Ai14Kit.content().entity_index)
	var refinery: int = DartKit.def_id(&"refinery")
	assert_float(tp.w_building).is_equal(0.8)
	assert_float(tp.weight(refinery, false)).is_equal(0.0)
	assert_float(tp.weight(refinery, false, true)).is_equal(0.8)
	assert_float(tp.weight(DartKit.def_id(&"harvester"), false, false)).is_equal(1.0)
	var dart: TargetParams = TargetParams.from_dict(Ai14Kit.ap(&"dart"))
	dart.bind(Ai14Kit.content().entity_index)
	assert_float(dart.weight(refinery, false, true)).is_equal(0.0)


func test_new_brains_write_reserved_ai_tag_words() -> void:
	assert_int(AiTag.Tag.FLEE).is_equal(16)
	assert_int(AiTag.Tag.SEARCH).is_equal(17)
	assert_int(AiTag.Tag.keys().size()).is_equal(34)


# 05 s4.3 / S8 discipline (as AI-13's test_brain_sources_hold_no_hidden_state): per-entity state lives in AiState; no
# static state, no clock, no RNG but the bound AI stream, no Node, no await, no signal in the AI-14 sources.
func test_ai14_brain_sources_hold_no_hidden_state() -> void:
	for path: String in ["res://src/sim_ai/brains/lancer_brain.gd", "res://src/sim_ai/brains/bomber_brain.gd",
			"res://src/sim_ai/brains/scout_brain.gd", "res://src/sim_ai/brains/lancer_params.gd",
			"res://src/sim_ai/brains/scout_params.gd", "res://src/sim_ai/brains/attack_run.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_bool(src.is_empty()).override_failure_message(path).is_false()
		for bad: String in ["static var", "randf", "randi", "Time.", "OS.", "await", "signal ", "Node", "RandomNumberGenerator"]:
			assert_bool(src.contains(bad)).override_failure_message("%s contains %s" % [path, bad]).is_false()
