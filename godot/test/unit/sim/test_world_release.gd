extends GdUnitTestSuite
## BUG-5 (sim/MODULE.md S18): a freed SimWorld releases every RefCounted part it built. The subsystems point at each
## other (validator -> judge -> applier -> validator, Production <-> AutoReplenish, ...); a RefCounted cycle is never
## freed, so before BUG-5 every load_map world kept ~15 MB alive and the unit-sim shard grew to ~18 GB.
## The walk follows every script variable (objects, arrays, dictionaries, callables) from the world; the shared
## ContentSet and its defs are excluded (they outlive every world by design).

const MAP: StringName = &"tiny_test"

var _shared: Dictionary = {}   # instance id -> true: the ContentSet graph, alive for the whole run
var _refs: Dictionary = {}     # instance id -> WeakRef of a part reached from the world
var _names: Dictionary = {}    # instance id -> class name, for the failure message


func before() -> void:
	_walk(WorldTestKit.content(), _shared, true)


func _cls(o: Object) -> String:
	var s: Script = o.get_script() as Script
	if s != null and s.get_global_name() != &"":
		return String(s.get_global_name())
	return o.get_class()


func _visit(v: Variant, into: Dictionary, shared: bool) -> void:
	if v is Object:
		var o: Object = v
		if o != null and o is RefCounted:
			_walk(o, into, shared)
	elif v is Array:
		var a: Array = v
		for e: Variant in a:
			_visit(e, into, shared)
	elif v is Dictionary:
		var d: Dictionary = v
		for k: Variant in d:
			_visit(k, into, shared)
			_visit(d[k], into, shared)
	elif v is Callable:
		var c: Callable = v
		_visit(c.get_object(), into, shared)


# Depth-first over the script variables of `o`; `into` receives a WeakRef per object (or `true` for the shared set).
func _walk(o: Object, into: Dictionary, shared: bool) -> void:
	var id: int = o.get_instance_id()
	if into.has(id) or (not shared and _shared.has(id)):
		return
	if shared:
		into[id] = true
	else:
		into[id] = weakref(o)
		_names[id] = _cls(o)
	for p: Dictionary in o.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			_visit(o.get(String(p["name"])), into, shared)


# Records the parts of `w`; the caller's reference is the last one, so they must all die when it returns.
func _record(w: SimWorld) -> void:
	for _t: int in 3:
		w.step()
	_refs.clear()
	_names.clear()
	_walk(w, _refs, false)


func _survivors() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: int in _refs:
		if (_refs[id] as WeakRef).get_ref() != null:
			out.append(String(_names[id]))
	out.sort()
	return out


func _kit_world() -> void:
	_record(WorldTestKit.world())


func _map_world() -> void:
	var w: SimWorld = WorldTestKit.world(31, null, MAP)
	var _c: int = WorldTestKit.queue_spawn(w, &"dart", 0, 0, WorldTestKit.at(300.0))
	_record(w)


func _match_world() -> void:
	_record(MatchFlowKit.world(&"pvp_1v1", 1))


func _restored_world() -> void:
	var a: SimWorld = WorldTestKit.world()
	a.step()
	_record(SimWorld.deserialize(a.serialize(), WorldTestKit.content(), null))


func _hooked_world() -> void:
	var w: SimWorld = WorldTestKit.world()
	w.set_ai_hook(AiDriver.new(Rng.new(3)))
	_record(w)


func test_a_freed_world_releases_every_part() -> void:
	_kit_world()
	assert_int(_refs.size()).is_greater(20)
	assert_array(Array(_survivors())).is_empty()


func test_a_freed_map_world_releases_every_part() -> void:
	_map_world()
	assert_array(Array(_survivors())).is_empty()


func test_a_freed_match_world_releases_every_part() -> void:
	_match_world()
	assert_array(Array(_survivors())).is_empty()


func test_a_freed_restored_world_releases_every_part() -> void:
	_restored_world()
	assert_array(Array(_survivors())).is_empty()


func test_a_freed_world_with_an_ai_hook_releases_every_part() -> void:
	_hooked_world()
	assert_array(Array(_survivors())).is_empty()


# Memory returns to the baseline: before BUG-5 each of these worlds kept ~15 MB (~60 MB here).
func test_freed_worlds_return_their_memory() -> void:
	_kit_world()
	var m0: int = OS.get_static_memory_usage()
	for _k: int in 4:
		_kit_world()
	assert_int(OS.get_static_memory_usage() - m0).is_less(1024 * 1024)
