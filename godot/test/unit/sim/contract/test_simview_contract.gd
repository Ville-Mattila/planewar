extends GdUnitTestSuite
## Shared SimView contract (TEST-02; 01 s9.4 contract notes, R0 C2-05 / B.5 / A-56). Every factory registered in
## contract/factories/ (LocalSimView now; NET-17's NetSimView, widened by NET-39) is run through SimViewContract on the
## scripted SimViewScene. The test body never names an implementation: a new view is a new file in factories/.
## test_a_view_broken_in_only_X_fails_clause_X proves the contract can fail, once per accessor.


func test_every_factory_file_loads_as_a_simview_factory() -> void:
	assert_array(Array(SimViewFactories.unloadable())).override_failure_message(
			"factory files that fail to load or do not extend SimViewFactory: %s" % ", ".join(SimViewFactories.unloadable())).is_empty()


func test_contract_holds_for_every_registered_view() -> void:
	var factories: Array[SimViewFactory] = SimViewFactories.all()
	assert_int(factories.size()).is_greater(0)
	for f: SimViewFactory in factories:
		var scene: SimViewScene = SimViewScene.build()
		var view: SimView = f.make(scene)
		assert_object(view).override_failure_message("%s: factory returned no view" % f.label()).is_not_null()
		var c: SimViewContract = SimViewContract.new()
		c.run(view, scene, f)
		var failed: PackedStringArray = PackedStringArray()
		for n: String in c.failed:
			if not f.exempt().has(n):
				var _a: bool = failed.push_back(n)
		assert_array(Array(failed)).override_failure_message("%s violates the SimView contract on: %s" % [f.label(), ", ".join(failed)]).is_empty()


func test_contract_covers_every_simview_accessor() -> void:
	var c: SimViewContract = SimViewContract.new()
	var scene: SimViewScene = SimViewScene.build()
	c.run(scene.world.view(), scene)
	var missing: PackedStringArray = PackedStringArray()
	for n: String in _accessors():
		if not c.covered.has(n):
			var _a: bool = missing.push_back(n)
	assert_array(Array(missing)).override_failure_message("SimView accessors with no contract clause: %s" % ", ".join(missing)).is_empty()
	assert_int(c.covered.size()).is_equal(_accessors().size())    # and no clause names a method SimView lacks


func test_exemptions_name_real_accessors() -> void:
	for f: SimViewFactory in SimViewFactories.all():
		for n: String in f.exempt():
			assert_bool(_accessors().has(n)).override_failure_message("%s exempts unknown accessor %s" % [f.label(), n]).is_true()


func test_a_view_broken_in_only_X_fails_clause_X(accessor: String, test_parameters: Array = _param_rows()) -> void:
	var scene: SimViewScene = SimViewScene.build()
	var clean: SimViewContract = SimViewContract.new()
	clean.run(scene.world.view(), scene)
	assert_bool(clean.failed.has(accessor)).override_failure_message("%s fails on the unbroken view" % accessor).is_false()
	var c: SimViewContract = SimViewContract.new()
	c.run(SimViewMutant.new(scene.world.view(), StringName(accessor)), scene)
	assert_bool(c.failed.has(accessor)).override_failure_message("a view broken in %s passed the contract" % accessor).is_true()


func test_a_view_broken_only_in_the_order_of_visible_enemy_ships_fails_its_clause() -> void:
	var scene: SimViewScene = SimViewScene.build()
	var c: SimViewContract = SimViewContract.new()
	c.run(SimViewMutant.new(scene.world.view(), &"visible_enemy_ships_order"), scene)
	assert_array(Array(c.failed)).is_equal(["visible_enemy_ships"])


func test_a_view_that_returns_every_default_fails_the_contract() -> void:
	var scene: SimViewScene = SimViewScene.build()
	var c: SimViewContract = SimViewContract.new()
	c.run(SimView.new(), scene)
	assert_int(c.failed.size()).is_greater(30)    # the scene is non-default for every accessor whose system has landed
	for n: String in ["alive", "pos", "hp01", "ships", "order_head", "team_state", "read_poses", "tick"]:
		assert_bool(c.failed.has(n)).override_failure_message("default SimView passed %s" % n).is_true()


func test_read_poses_equals_pos_and_basis_element_wise_on_every_view() -> void:
	# R0 B.11 A-56, restated outside the clause table: 1,000 draws, pre-sized arrays, alive count returned.
	for f: SimViewFactory in SimViewFactories.all():
		if f.exempt().has("read_poses"):
			continue
		var scene: SimViewScene = SimViewScene.build()
		var v: SimView = f.make(scene)
		var pool: PackedInt32Array = PackedInt32Array([scene.a, scene.b, scene.c, scene.core, scene.wreck, scene.rocket, scene.dead, 0])
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 56
		var ids: PackedInt32Array = PackedInt32Array()
		var _r: int = ids.resize(1000)
		var want_alive: int = 0
		for i: int in 1000:
			ids[i] = pool[rng.randi_range(0, pool.size() - 1)]
			want_alive += 1 if v.alive(ids[i]) else 0
		var pos: PackedVector3Array = PackedVector3Array()
		var rot: PackedVector4Array = PackedVector4Array()
		var _p: int = pos.resize(1000)
		var _q: int = rot.resize(1000)
		assert_int(v.read_poses(ids, pos, rot)).is_equal(want_alive)
		for i: int in 1000:
			var q: Quaternion = v.basis(ids[i]).get_rotation_quaternion()
			assert_vector(pos[i]).is_equal(v.pos(ids[i]))
			assert_float(rot[i].x).is_equal_approx(q.x, 1e-6)
			assert_float(rot[i].y).is_equal_approx(q.y, 1e-6)
			assert_float(rot[i].z).is_equal_approx(q.z, 1e-6)
			assert_float(rot[i].w).is_equal_approx(q.w, 1e-6)


## A-113 / 01 s9.4: the scene's control state is a legal B.3 value (ControlMachine.State: 0 AUTO, 1 ORDERED, 2 POSSESSED).
func test_scene_control_state_is_possessed() -> void:
	assert_int(SimViewScene.CONTROL).is_equal(2)
	assert_int(SimViewScene.CONTROL).is_equal(ControlMachine.State.POSSESSED)


## A-113: the LocalSimView factory keeps the contract EPS (1e-4) for every accessor; the base factory is the default.
func test_local_factory_keeps_contract_eps_for_every_accessor() -> void:
	assert_float(SimViewContract.EPS).is_equal(0.0001)
	var local: SimViewFactory = LocalSimViewFactory.new()
	var base: SimViewFactory = SimViewFactory.new()
	for n: String in _accessors():
		assert_float(local.tolerance(StringName(n))).override_failure_message("LocalSimViewFactory.tolerance(%s)" % n).is_equal(SimViewContract.EPS)
		assert_float(base.tolerance(StringName(n))).override_failure_message("SimViewFactory.tolerance(%s)" % n).is_equal(SimViewContract.EPS)


## A-113: a replicated view compares u8-encoded fields within one wire quantum (1 / 255, 04 s3.3). With that tolerance
## the clean view still passes the four fields, and every SimViewMutant (delta +0.25 on floats) still fails its accessor.
func test_mutants_on_u8_fields_still_fail_under_one_wire_quantum() -> void:
	var f: WireQuantumFactory = WireQuantumFactory.new()
	for n: String in ["hp01", "flip_cooldown01", "supply01", "shield01"]:
		var scene: SimViewScene = SimViewScene.build()
		var clean: SimViewContract = SimViewContract.new()
		clean.run(scene.world.view(), scene, f)
		assert_bool(clean.failed.has(n)).override_failure_message("%s fails on the unbroken view under 1/255" % n).is_false()
		var c: SimViewContract = SimViewContract.new()
		c.run(SimViewMutant.new(scene.world.view(), StringName(n)), scene, f)
		assert_bool(c.failed.has(n)).override_failure_message("a view broken in %s passed under 1/255" % n).is_true()


## Every public method of SimView (a method is an accessor: SimView holds no other API).
static func _accessors() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for m: Dictionary in SimView.new().get_script().get_script_method_list():
		var n: String = String(m["name"])
		if not n.begins_with("_"):
			var _a: bool = out.push_back(n)
	return out


static func _param_rows() -> Array:
	var rows: Array = []
	for n: String in _accessors():
		rows.append([n])
	return rows


## Test-local stand-in for a replicated factory (A-113): one wire quantum (1 / 255) on the four u8 fields, EPS elsewhere.
class WireQuantumFactory extends SimViewFactory:
	const QUANTUM_FIELDS: PackedStringArray = ["hp01", "flip_cooldown01", "supply01", "shield01"]

	func tolerance(accessor: StringName) -> float:
		return 1.0 / 255.0 if QUANTUM_FIELDS.has(String(accessor)) else SimViewContract.EPS
