class_name BenchInstanceUniforms
extends SceneTree
## ART-01: how many unit_lit_instanced instances fit the GLES3 global uniform buffer, and the frame cost of
## instance uniforms vs per-team materials. Windowed only (needs a GPU):
##   godot --path godot --rendering-driver opengl3 -s res://test/perf/bench_instance_uniforms.gd -- --n=300 [--material]
## Every instance with instance uniforms reserves 16 vec4 slots; past capacity Godot prints "Too many instances
## using shader instance variables ... Maximum items supported by this hardware is: <slots>" once per extra
## instance. The script prints IU_BENCH with the expected capacity and the mean frame time.

const FRAMES: int = 240
const WARMUP: int = 30
const SLOTS_PER_INSTANCE: int = 16
const TEAM_HEX: PackedStringArray = ["#E1A633", "#4C64ED", "#3BFAB2", "#17840E", "#B1369D", "#E9A1FD", "#D6F72C", "#F06867"]

var _n: int = 300
var _per_material: bool = false
var _frame: int = 0
var _t0: int = 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			_n = int(a.substr(4))
		elif a == "--material":
			_per_material = true
	MoonLight.ensure_globals()
	var world: Node3D = Node3D.new()
	root.add_child(world)
	world.add_child(MoonLight.make_sun())
	var cam: Camera3D = Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0.0, 0.0, 60.0)
	cam.make_current()
	var mats: Array[ShaderMaterial] = []
	for t: int in TEAM_HEX.size():
		var m: ShaderMaterial = MoonLight.unit_material()
		m.set_shader_parameter(&"team_color", Color(TEAM_HEX[t]))
		mats.append(m)
	var shared: ShaderMaterial = MoonLight.unit_material(true)
	var box: BoxMesh = BoxMesh.new()
	for i: int in _n:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = box
		mi.position = Vector3(float(i % 40) - 20.0, float(i) / 40.0 - 10.0, 0.0)
		if _per_material:
			mi.material_override = mats[i % TEAM_HEX.size()]
		else:
			mi.material_override = shared
		world.add_child(mi)
		if not _per_material:
			mi.set_instance_shader_parameter(&"team_color", Color(TEAM_HEX[i % TEAM_HEX.size()]))
			mi.set_instance_shader_parameter(&"team_index", i % TEAM_HEX.size())


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == WARMUP:
		_t0 = Time.get_ticks_usec()
	if _frame < WARMUP + FRAMES:
		return false
	var ms: float = float(Time.get_ticks_usec() - _t0) / 1000.0 / float(FRAMES)
	var slots: int = int(ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size"))
	print("IU_BENCH n=%d mode=%s frame_ms=%.3f setting_slots=%d slots_per_instance=%d adapter=%s driver=%s" % [
		_n, "material" if _per_material else "instance", ms, slots, SLOTS_PER_INSTANCE,
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name()])
	return true
