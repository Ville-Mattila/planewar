class_name ShaderLibraryShot
extends Node3D
## ART-03 shader library plate (test only, not shipped). One site on the ART-01 apron: unit_lit team-paint and
## glow tiles for the 8 teams, the 8 emblems, prop_lit rock, vfx_additive cone, shield_dome (outside and inside
## views), hologram_ghost box. User args after `--`:
##   --sun_deg=N  sun direction N degrees from the Noon Pole towards +X (default 60)   --frames=N  --shot=<png>
##   --inside     camera inside the dome (back faces)
## Prints SHADERLIB_MEASURE lines: team-glow tiles against palette hex.

const SITE_LAT_DEG: float = 20.0
const EMBLEM_CELL_U: float = 0.0625   ## emblem cell 0 spans u 0..0.125 of the 256 px atlas, v 0.875..1.0
var cam: Camera3D
var _sun_deg: float = 60.0
var _frames: int = 20
var _shot: String = ""
var _inside: bool = false
var _frame: int = 0
var _cache: UnitMaterialCache = UnitMaterialCache.new()
var _glow_probes: Array[Dictionary] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--sun_deg="):
			_sun_deg = float(arg.substr(10))
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
		elif arg.begins_with("--shot="):
			_shot = arg.substr(7)
		elif arg == "--inside":
			_inside = true
	MoonLight.ensure_globals()
	var sun: DirectionalLight3D = MoonLight.make_sun()
	add_child(sun)
	var d: float = deg_to_rad(_sun_deg)
	MoonLight.set_sun_dir(Vector3(sin(d), 0.0, cos(d)), sun)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = MoonLight.make_environment()
	add_child(we)
	cam = Camera3D.new()
	cam.near = 0.3
	cam.far = 20000.0
	add_child(cam)
	_build()
	cam.make_current()


func _mi(mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	add_child(mi)
	return mi


func _build() -> void:
	var dir: Vector3 = Sphere.from_lat_lon(deg_to_rad(SITE_LAT_DEG), deg_to_rad(Sphere.SLOT_LON0_DEG), 1.0)
	var base: Transform3D = LookdevMeshes.site(dir, 0.0)
	var atlas: Texture2D = load(MoonLight.ATLAS_PATH)
	var ground: ShaderMaterial = MoonLight.moon_material()
	var _g: MeshInstance3D = _mi(LookdevMeshes.plate(400.0, LookdevMeshes.MARE_MID), ground, base.translated_local(Vector3(0, -0.05, 0)))
	for t: int in UnitMaterialCache.TEAM_COUNT:
		var x: float = -35.0 + 10.0 * float(t)
		var m: ShaderMaterial = _cache.get_material(t, UnitMaterialCache.State.HEALTHY)
		var glow: MeshInstance3D = _mi(LookdevMeshes.plate(8.0, LookdevMeshes.TEAM_GLOW), m, base.translated_local(Vector3(x, 0.0, 14.0)))
		_glow_probes.append({"pos": glow.transform.origin, "hex": UnitMaterialCache.TEAM_HEX[t]})
		var _p: MeshInstance3D = _mi(LookdevMeshes.plate(8.0, LookdevMeshes.TEAM_PAINT_MID), m, base.translated_local(Vector3(x, 0.0, 24.0)))
		var _e: MeshInstance3D = _mi(_emblem_quad(8.0), m, base.translated_local(Vector3(x, 0.0, 34.0)))
	var prop: ShaderMaterial = ShaderMaterial.new()
	prop.shader = load("res://src/presentation/shaders/prop_lit.gdshader")
	prop.set_shader_parameter(&"atlas", atlas)
	var rock: BoxMesh = BoxMesh.new()
	rock.size = Vector3(10, 8, 10)
	var _r: MeshInstance3D = _mi(LookdevMeshes.painted(rock, LookdevMeshes.HULL_300), prop, base.translated_local(Vector3(-30.0, 4.0, -10.0)))
	var vfx: ShaderMaterial = ShaderMaterial.new()
	vfx.shader = load("res://src/presentation/shaders/vfx_additive.gdshader")
	vfx.set_shader_parameter(&"tint", Color(0.5, 0.8, 1.0))
	vfx.set_shader_parameter(&"end_fade", 1.0)
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.0
	cone.height = 12.0
	var _c: MeshInstance3D = _mi(cone, vfx, base.translated_local(Vector3(-14.0, 6.0, -10.0)))
	var holo: ShaderMaterial = ShaderMaterial.new()
	holo.shader = load("res://src/presentation/shaders/hologram_ghost.gdshader")
	var hb: BoxMesh = BoxMesh.new()
	hb.size = Vector3(10, 10, 10)
	var _h: MeshInstance3D = _mi(hb, holo, base.translated_local(Vector3(4.0, 5.0, -10.0)))
	var dome: ShaderMaterial = ShaderMaterial.new()
	dome.shader = load("res://src/presentation/shaders/shield_dome.gdshader")
	dome.set_shader_parameter(&"camera_inside", 1.0 if _inside else 0.0)
	dome.set_shader_parameter(&"ripples", PackedVector4Array([Vector4(0.0, 1.0, 0.2, 0.3), Vector4(1.0, 0.3, 0.0, 0.6), Vector4(0, 0, 1, -1), Vector4(0, 0, 1, -1)]))
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = 14.0
	sph.height = 28.0
	var _d: MeshInstance3D = _mi(sph, dome, base.translated_local(Vector3(30.0, 0.0, -10.0)))
	if _inside:
		cam.global_position = base * Vector3(30.0, 5.0, -8.0)
		cam.look_at(base * Vector3(30.0, 8.0, -30.0), base.basis.y)
	else:
		cam.global_position = base * Vector3(0.0, 70.0, 80.0)
		cam.look_at(base * Vector3(0.0, 0.0, 14.0), base.basis.y)


## A quad whose UVs cover emblem cell 0 (v >= 0.875); the shader shifts u by team_index * 0.125.
func _emblem_quad(size: float) -> ArrayMesh:
	var h: float = size * 0.5
	var verts: PackedVector3Array = [Vector3(-h, 0, h), Vector3(h, 0, h), Vector3(h, 0, -h), Vector3(-h, 0, -h)]
	var uvs: PackedVector2Array = [Vector2(0, 1), Vector2(0.125, 1), Vector2(0.125, 0.875), Vector2(0, 0.875)]
	var nrm: PackedVector3Array = [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _process(_delta: float) -> void:
	_frame += 1
	if _frame >= _frames:
		_finish()


func _finish() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		for p: Dictionary in _glow_probes:
			var px: Vector2 = cam.unproject_position(p["pos"])
			var c: Color = img.get_pixel(clampi(int(px.x), 0, img.get_width() - 1), clampi(int(px.y), 0, img.get_height() - 1))
			var want: Color = Color(p["hex"])
			print("SHADERLIB_MEASURE glow %s got=(%d,%d,%d) want=(%d,%d,%d)" % [p["hex"], c.r8, c.g8, c.b8, want.r8, want.g8, want.b8])
		if not _shot.is_empty():
			var _e: Error = img.save_png(_shot)
	print("SHADERLIB driver=%s" % RenderingServer.get_current_rendering_driver_name())
	get_tree().quit(0)
