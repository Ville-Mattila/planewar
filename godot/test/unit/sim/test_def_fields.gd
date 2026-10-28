extends GdUnitTestSuite
## TA-56 / R0 B.12 A-66, A-76: the sim reads structures.structure_bomb_mult, projectiles.fuse_delay_s,
## economy.unsupplied_rate_mult and rules.vision_hz from the defs (changing the value in the fixture changes the
## behaviour), and a structure with F_BUILDING (a site) does not sense while an unpowered finished one does. Each
## value is patched in the shared ContentSet before the world is built (WorldDefs reads it at construction) and put
## back after the test.

const R: float = Sphere.PLANET_RADIUS

var _undo: Array = []     ## [Def, key, old value or null when absent]


func after_test() -> void:
	_undo.reverse()                      # the oldest value goes back last
	for u: Array in _undo:
		var d: Def = u[0]
		if u[2] == null:
			var _e: bool = d.raw.erase(u[1])
		else:
			d.raw[u[1]] = u[2]
	_undo.clear()


func _patch(d: Def, key: String, value: float) -> void:
	_undo.append([d, key, d.raw.get(key)])
	d.raw[key] = value


func _structure(id: StringName) -> StructureDef:
	for sd: StructureDef in WorldTestKit.content().structures:
		if sd.id == id:
			return sd
	return null


func _projectile(id: StringName) -> ProjectileDef:
	for pd: ProjectileDef in WorldTestKit.content().projectiles:
		if pd.id == id:
			return pd
	return null


func _at(alt: float, east: float = 0.0, north: float = 0.0) -> Vector3:
	return FireTestKit.at(alt, east, north)


func _step(w: SimWorld) -> void:
	w.step()
	var _e: Array[SimEvent] = w.drain_events()


# --- structure_bomb_mult -------------------------------------------------------------------------------------

func _hangar_hp_after_bomb() -> float:
	var w: SimWorld = CombatTestKit.world()
	var h: int = CombatTestKit.spawn(w, &"hangar", 0, 0, _at(0.0))
	var _b: int = CombatTestKit.shot(w, &"bomb", &"bomb", _at(0.5, 0.0), 1, 1)
	_step(w)
	return CombatTestKit.hp(w, h)


func test_structure_bomb_mult_scales_the_bomb_damage_on_a_structure() -> void:
	assert_float(_hangar_hp_after_bomb()).is_equal(900.0 - 100.0)       # shipped 0.25 of 400
	_patch(_structure(&"hangar"), "structure_bomb_mult", 0.5)
	assert_float(_hangar_hp_after_bomb()).is_equal(900.0 - 200.0)
	_patch(_structure(&"hangar"), "structure_bomb_mult", 1.0)
	assert_float(_hangar_hp_after_bomb()).is_equal(900.0 - 400.0)


# --- fuse_delay_s --------------------------------------------------------------------------------------------

func _flak_burst_ticks() -> PackedInt32Array:
	var w: SimWorld = CombatTestKit.world()
	var flak: int = CombatTestKit.spawn(w, &"flak_battery", 1, 1, _at(0.0))
	CombatTestKit.power(w, 1, 1)
	var _t: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(400.0, 600.0))
	FireTestKit.hook(w).hold(flak, PilotInput.FIRE1)
	w.step()
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in FireTestKit.fired_by(w, flak):
		out.push_back(w.projectiles().target[i] - w.tick())
	return out


func test_fuse_delay_s_moves_the_flak_burst_tick() -> void:
	var base: PackedInt32Array = _flak_burst_ticks()
	assert_int(base.size()).is_equal(2)
	_patch(_projectile(&"flak_shell"), "fuse_delay_s", 0.6)
	var later: PackedInt32Array = _flak_burst_ticks()
	assert_int(later.size()).is_equal(2)
	for k: int in 2:
		assert_int(later[k] - base[k]).is_between(8, 10)               # +0.3 s = 9 ticks at 30 Hz (before the clamp)
	_patch(_projectile(&"flak_shell"), "fuse_delay_s", 0.0)
	assert_int(_flak_burst_ticks()[0]).is_less(base[0])


# --- unsupplied_rate_mult ------------------------------------------------------------------------------------

func _unsupplied_spent(ticks: int) -> int:
	var w: SimWorld = CombatTestKit.world()
	var cut: int = CombatTestKit.spawn(w, &"autocannon_turret", 1, 1, _at(0.0))
	CombatTestKit.power(w, 1, 1)
	# no supply root in the world: GD-18's network flags the tower unsupplied by itself
	var foe: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(300.0, 300.0))        # CB13a: an envelope target, so the tower may fire
	w.store().hp[EntityId.slot(foe)] = 1000000.0
	FireTestKit.hook(w).hold(cut, PilotInput.FIRE1)
	var s: int = EntityId.slot(cut)
	var before: int = w.store().ammo[s]
	for _k: int in ticks:
		_step(w)
	return before - w.store().ammo[s]


func test_unsupplied_rate_mult_scales_the_tower_rate() -> void:
	assert_int(_unsupplied_spent(216)).is_equal(15)                     # shipped 0.5: 3 bursts of 5
	_patch(WorldTestKit.content().economy, "unsupplied_rate_mult", 0.25)
	assert_int(_unsupplied_spent(216)).is_less(15)
	_patch(WorldTestKit.content().economy, "unsupplied_rate_mult", 1.0)
	assert_int(_unsupplied_spent(216)).is_equal(30)                     # as a fed tower: 6 bursts


# --- vision_hz and the A-76 filter ---------------------------------------------------------------------------

func test_vision_hz_sets_the_pass_rate() -> void:
	assert_int(VisionTestKit.world().vision.hz).is_equal(10)
	_patch(WorldTestKit.content().rules, "vision_hz", 5.0)
	var w: SimWorld = VisionTestKit.world()
	assert_int(w.vision.hz).is_equal(5)
	assert_int(w.vision.period(PackedInt32Array([1]))).is_equal(MathX.floori_div(WorldTestKit.content().rules.tick_hz, 5))


func test_a_site_does_not_sense_and_a_finished_structure_does() -> void:
	var w: SimWorld = VisionTestKit.world()
	var mast: int = VisionTestKit.put(w, &"sensor_mast", 0, VisionTestKit.at(300.0))
	var target: int = VisionTestKit.put(w, &"dart", 1, VisionTestKit.at(300.0, 1000.0))
	var ms: int = EntityId.slot(mast)
	w.store().flags[ms] = w.store().flags[ms] | EntityStore.F_BUILDING
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, target)).is_false()
	assert_array(_mask(w, 0)).is_equal(VisionTestKit.brute(w, 0))
	w.store().flags[ms] = w.store().flags[ms] & ~EntityStore.F_BUILDING
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, target)).is_true()
	assert_array(_mask(w, 0)).is_equal(VisionTestKit.brute(w, 0))


func _mask(w: SimWorld, team: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var _r: int = out.resize(EntityStore.SLOT_COUNT)
	out.fill(0)
	for s: int in EntityStore.SLOT_COUNT:
		out[s] = 1 if (w.store().visible_mask[s] & (1 << team)) != 0 else 0
	return out


# --- determinism and S4 with patched fields -----------------------------------------------------------------

func _fight() -> SimWorld:
	var w: SimWorld = CombatTestKit.world()
	var flak: int = CombatTestKit.spawn(w, &"flak_battery", 1, 1, _at(0.0))
	var cut: int = CombatTestKit.spawn(w, &"autocannon_turret", 1, 1, _at(0.0, 0.0, 300.0))
	var _t: int = CombatTestKit.spawn(w, &"dart", 0, 0, _at(400.0, 600.0))
	CombatTestKit.power(w, 1, 1)
	FireTestKit.combat(w).fire.unsupplied[EntityId.slot(cut)] = 1
	var hook: FireTestKit.TriggerHook = FireTestKit.hook(w)
	hook.hold(flak, PilotInput.FIRE1)
	hook.hold(cut, PilotInput.FIRE1)
	return w


func test_patched_fields_are_deterministic_and_survive_s4() -> void:
	_patch(_projectile(&"flak_shell"), "fuse_delay_s", 0.6)
	_patch(WorldTestKit.content().economy, "unsupplied_rate_mult", 0.25)
	var a: SimWorld = _fight()
	var b: SimWorld = _fight()
	for _k: int in 40:
		_step(a)
		_step(b)
	assert_array(WorldTestKit.store_bytes(a)).is_equal(WorldTestKit.store_bytes(b))
	var c: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), FireTestKit.TriggerHook.new())
	assert_object(c).is_not_null()
	for _k: int in 40:
		_step(a)
		_step(c)
	assert_array(WorldTestKit.store_bytes(a)).is_equal(WorldTestKit.store_bytes(c))
