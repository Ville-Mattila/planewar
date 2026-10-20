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
		c.run(view, scene)
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
