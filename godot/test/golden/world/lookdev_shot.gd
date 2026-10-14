class_name LookdevShot
extends Node3D
## ART-01 look-dev golden scene (S-ART-1; 07 s1.5, s4.3). Not shipped (export filters exclude test/**).
## Everything lit by presentation/shaders/moon_light.gdshaderinc through MoonLight. User args after `--`:
##   --view=sphere|pole|samples_day|samples_terminator|samples_night|biomes_day|biomes_night   (default sphere)
##   --instanced      team/state through unit_lit_instanced (instance uniforms) instead of per-team materials
##   --frames=N       quit after N frames (default 20)      --shot=<png>  save the last frame
## `pole` also prints LOOKDEV_MEASURE lines: night mare at the Midnight Pole (moon_terrain and unit_lit plates)
## against the 07 s1.5 target, and the 8 team-glow tiles against their 07 s2.2 hex (exact at rgb.r = 1).

const TEAM_HEX: PackedStringArray = ["#E1A633", "#4C64ED", "#3BFAB2", "#17840E", "#B1369D", "#E9A1FD", "#D6F72C", "#F06867"]
const BIOME_NAMES: PackedStringArray = ["mare", "highland", "crater_floor", "rim_ejecta", "cold_trap", "ore_field", "solar_plateau", "rille_floor"]
const BIOME_MID_HEX: PackedStringArray = ["#404552", "#959189", "#353840", "#C0BBAE", "#5B7C9E", "#8D7648", "#D0CCC0", "#2C2F37"]
const BIOME_DE_MAX: float = 6.0     ## ART-14 acceptance (07 ART-14)
const SAMPLE_SPACING: float = 48.0
const SAMPLE_LAT_DEG: Dictionary = {"samples_day": 50.0, "samples_terminator": 0.0, "samples_night": -70.0}

var cam: Camera3D
var sun: DirectionalLight3D
var _view: String = "sphere"
var _instanced: bool = false
var _frames: int = 20
var _shot: String = ""
var _frame: int = 0
var _team_mats: Array[ShaderMaterial] = []
var _probes: Array[Dictionary] = []
var _biome_probes: Array[Dictionary] = []


func _ready() -> void:
	_parse_args()
	MoonLight.ensure_globals()
	sun = MoonLight.make_sun()
	add_child(sun)
	MoonLight.set_sun_dir(MoonLight.DEFAULT_SUN_DIR, sun)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = MoonLight.make_environment()
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.5
	cam.far = 20000.0
	add_child(cam)
	for t: int in TEAM_HEX.size():
		var m: ShaderMaterial = MoonLight.unit_material()
		m.set_shader_parameter(&"team_index", t)
		m.set_shader_parameter(&"team_color", Color(TEAM_HEX[t]))
		_team_mats.append(m)
	match _view:
		"biomes_day", "biomes_night":
			_build_biomes(_view == "biomes_day")
		"pole":
			_build_pole()
		"sphere":
			_build_sphere()
		_:
			_build_samples(float(SAMPLE_LAT_DEG.get(_view, 0.0)))
	cam.make_current()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			_view = arg.substr(7)
		elif arg == "--instanced":
			_instanced = true
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
		elif arg.begins_with("--shot="):
			_shot = arg.substr(7)


## A unit_lit instance of `mesh` for `team`; per-team material, or the shared instanced material.
func _unit(mesh: Mesh, team: int, xf: Transform3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	if _instanced:
		mi.material_override = _shared_instanced()
		mi.set_instance_shader_parameter(&"team_index", team)
		mi.set_instance_shader_parameter(&"team_color", Color(TEAM_HEX[team]))
	else:
		mi.material_override = _team_mats[team]
	mi.transform = xf
	add_child(mi)
	return mi


var _instanced_mat: ShaderMaterial


func _shared_instanced() -> ShaderMaterial:
	if _instanced_mat == null:
		_instanced_mat = MoonLight.unit_material(true)
	return _instanced_mat


## Test sphere at the moon centre (a 150 m mini-moon: up = its own normal), unit_lit hull_300, seen from the
## terminator so day (top), wrap band, earthshine night (bottom) and the day-side limb rim are all in frame.
func _build_sphere() -> void:
	var s: SphereMesh = SphereMesh.new()
	s.radius = 150.0
	s.height = 300.0
	s.radial_segments = 48
	s.rings = 24
	var painted: ArrayMesh = LookdevMeshes.painted(s, LookdevMeshes.HULL_300)
	var moon: MeshInstance3D = MeshInstance3D.new()
	moon.mesh = _single_swatch(painted, LookdevMeshes.HULL_300)
	moon.material_override = _team_mats[0]
	add_child(moon)
	cam.position = Vector3(560.0, -120.0, 0.0)
	cam.look_at(Vector3.ZERO, Sphere.POLE_AXIS)


## Rewrites every UV of `m` to one swatch (the test sphere is all hull_300).
func _single_swatch(m: ArrayMesh, cell: int) -> ArrayMesh:
	var arr: Array = m.surface_get_arrays(0)
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv: Vector2 = LookdevMeshes.swatch_uv(cell)
	for i: int in uvs.size():
		uvs[i] = uv
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var out: ArrayMesh = ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## Midnight Pole measurement plates: moon_terrain (measure material: ramp value 0.5, no detail -> pure mare mid) left, unit_lit with the
## biome_mare_mid swatch right, a row of 8 team-glow tiles and 8 team-paint tiles in front.
func _build_pole() -> void:
	var pole: Vector3 = -Sphere.POLE_AXIS
	var base: Transform3D = LookdevMeshes.site(pole, 0.0)
	var moon_plate: MeshInstance3D = MeshInstance3D.new()
	moon_plate.mesh = LookdevMeshes.plate(40.0, LookdevMeshes.MARE_MID)
	moon_plate.material_override = MoonTerrain.measure_material()
	moon_plate.transform = base.translated_local(Vector3(-22.0, 0.0, -12.0))
	add_child(moon_plate)
	_probe("mare_moon_terrain", moon_plate.transform.origin, Color("#404552"))
	var unit_plate: MeshInstance3D = _unit(LookdevMeshes.plate(40.0, LookdevMeshes.MARE_MID), 0, base.translated_local(Vector3(22.0, 0.0, -12.0)))
	_probe("mare_unit_lit", unit_plate.transform.origin, Color("#404552"))
	for t: int in TEAM_HEX.size():
		var x: float = -35.0 + 10.0 * float(t)
		var g: MeshInstance3D = _unit(LookdevMeshes.plate(8.0, LookdevMeshes.TEAM_GLOW), t, base.translated_local(Vector3(x, 0.0, 14.0)))
		_probe("team_glow_%d" % t, g.transform.origin, Color(TEAM_HEX[t]), false)
		var _p: MeshInstance3D = _unit(LookdevMeshes.plate(8.0, LookdevMeshes.TEAM_PAINT_MID), t, base.translated_local(Vector3(x, 0.0, 24.0)))
	cam.global_position = base * Vector3(0.0, 95.0, 6.0)
	cam.look_at(base * Vector3(0.0, 0.0, 6.0), base.basis * Vector3(0, 0, -1))


## ART-14: the 8 biome plates (07 s2.1 ids 0-7, ramp value 0.5 = the mid stop) side by side on flat ground at the Noon
## Pole (`day`, sun overhead) or the Midnight Pole (earthshine). Each prints LOOKDEV_BIOME with the dE00 between the
## rendered pixel (per-channel median of a 7 x 7 block, so frost speckle and the tile grid do not bias it) and the CPU
## reference MoonLight.shade_linear of the hex; acceptance dE00 <= BIOME_DE_MAX.
func _build_biomes(day: bool) -> void:
	var pole: Vector3 = Sphere.POLE_AXIS if day else -Sphere.POLE_AXIS
	var base: Transform3D = LookdevMeshes.site(pole, 0.0)
	for i: int in BIOME_MID_HEX.size():
		var plate: MeshInstance3D = MeshInstance3D.new()
		plate.mesh = LookdevMeshes.plate(18.0, LookdevMeshes.MARE_MID)
		plate.material_override = MoonTerrain.measure_material_biome(i)
		plate.transform = base.translated_local(Vector3(-63.0 + 18.0 * float(i), 0.0, 0.0))
		add_child(plate)
		_biome_probes.append({"label": "%s_%s" % ["day" if day else "night", BIOME_NAMES[i]], "pos": plate.transform.origin,
				"hex": Color(BIOME_MID_HEX[i]), "up": pole})
	cam.global_position = base * Vector3(0.0, 80.0, 18.0)
	cam.look_at(base * Vector3(0.0, 0.0, 0.0), base.basis * Vector3(0, 0, -1))


func _measure_biome(img: Image, p: Dictionary) -> void:
	var px: Vector2 = cam.unproject_position(p["pos"])
	var cx: int = clampi(int(px.x), 3, img.get_width() - 4)
	var cy: int = clampi(int(px.y), 3, img.get_height() - 4)
	var rs: PackedFloat32Array = PackedFloat32Array()
	var gs: PackedFloat32Array = PackedFloat32Array()
	var bs: PackedFloat32Array = PackedFloat32Array()
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			var c: Color = img.get_pixel(cx + dx, cy + dy)
			rs.append(c.r)
			gs.append(c.g)
			bs.append(c.b)
	rs.sort()
	gs.sort()
	bs.sort()
	var got: Color = Color(rs[24], gs[24], bs[24])
	var hex: Color = p["hex"]
	var up: Vector3 = p["up"]
	var lit: Vector3 = MoonLight.shade_linear(Vector3(hex.srgb_to_linear().r, hex.srgb_to_linear().g, hex.srgb_to_linear().b), up, up, MoonLight.DEFAULT_SUN_DIR)
	var want: Color = Color(lit.x, lit.y, lit.z).linear_to_srgb()
	var de: float = ColorDeltaE.de00(got, want)
	print("LOOKDEV_BIOME %s got=#%s want=#%s dE00=%.2f pass=%s" % [p["label"], got.to_html(false), want.to_html(false), de, de <= BIOME_DE_MAX])


## `lit` probes compare with the CPU reference MoonLight.shade_linear for a level face; glow probes with 1.0.
func _probe(label: String, world: Vector3, albedo_srgb: Color, lit: bool = true) -> void:
	var up: Vector3 = world.normalized()
	var want: Vector3 = MoonLight.shade_linear(Vector3.ONE, up, up, MoonLight.DEFAULT_SUN_DIR) if lit else Vector3.ONE
	_probes.append({"label": label, "pos": world, "albedo": albedo_srgb, "want": want})


## 12 sample meshes on a hull_600 apron at latitude `lat_deg` (longitude of start slot 0), 3/4 view.
func _build_samples(lat_deg: float) -> void:
	var dir: Vector3 = Sphere.from_lat_lon(deg_to_rad(lat_deg), deg_to_rad(Sphere.SLOT_LON0_DEG), 1.0)
	var base: Transform3D = LookdevMeshes.site(dir, 0.0)
	var apron: MeshInstance3D = MeshInstance3D.new()
	apron.mesh = LookdevMeshes.plate(240.0, LookdevMeshes.HULL_600)
	apron.material_override = _team_mats[0]
	apron.transform = base
	add_child(apron)
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.mesh = LookdevMeshes.plate(2000.0, LookdevMeshes.MARE_MID)
	ground.material_override = MoonLight.moon_material()
	ground.transform = base.translated_local(Vector3(0.0, -0.05, 0.0))
	add_child(ground)
	_probe("apron_hull_600", base * Vector3(100.0, 0.0, -100.0), Color("#333846"))
	_probe("ground_mare", base * Vector3(-150.0, -0.05, -60.0), Color("#404552"))
	for i: int in LookdevMeshes.NAMES.size():
		var prim: PrimitiveMesh = LookdevMeshes.primitive(i)
		var mesh: ArrayMesh = LookdevMeshes.painted(prim, LookdevMeshes.HULL_400 if i % 2 == 0 else LookdevMeshes.HULL_300, i < 7)
		var col: int = i % 4
		var row: int = i >> 2
		var lift: float = -prim.get_aabb().position.y
		var local: Vector3 = Vector3((float(col) - 1.5) * SAMPLE_SPACING, lift, (float(row) - 1.0) * SAMPLE_SPACING)
		var xf: Transform3D = base.translated_local(local).rotated_local(Vector3.UP, deg_to_rad(30.0 * float(i)))
		var _m: MeshInstance3D = _unit(mesh, i % TEAM_HEX.size(), xf)
	cam.global_position = base * Vector3(95.0, 55.0, -125.0)   # north of the apron: the sun is behind the camera
	cam.look_at(base * Vector3(0.0, 0.0, 0.0), base.basis.y)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame >= _frames:
		_finish()


func _finish() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		for p: Dictionary in _probes:
			_measure(img, p)
		for bp: Dictionary in _biome_probes:
			_measure_biome(img, bp)
		if not _shot.is_empty():
			var _e: Error = img.save_png(_shot)
	print("LOOKDEV view=%s instanced=%s adapter=%s driver=%s" % [_view, _instanced, RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name()])
	get_tree().quit(0)


## Mean of a 7 x 7 block around the probe's projected pixel, converted to linear; ratio = linear / albedo.
func _measure(img: Image, p: Dictionary) -> void:
	var px: Vector2 = cam.unproject_position(p["pos"])
	var cx: int = clampi(int(px.x), 3, img.get_width() - 4)
	var cy: int = clampi(int(px.y), 3, img.get_height() - 4)
	var acc: Vector3 = Vector3.ZERO
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			var c: Color = img.get_pixel(cx + dx, cy + dy)
			acc += Vector3(c.r, c.g, c.b)
	acc /= 49.0
	var srgb: Color = Color(acc.x, acc.y, acc.z)
	var lin: Color = srgb.srgb_to_linear()
	var alb: Color = (p["albedo"] as Color).srgb_to_linear()
	var label: String = p["label"]
	var want: Vector3 = p["want"]
	var r: Vector3 = Vector3(lin.r / alb.r, lin.g / alb.g, lin.b / alb.b)
	var err: Vector3 = r / want - Vector3.ONE
	var w: Vector3 = Vector3(0.2126, 0.7152, 0.0722)
	var y_err: float = w.dot(r * Vector3(alb.r, alb.g, alb.b)) / w.dot(want * Vector3(alb.r, alb.g, alb.b)) - 1.0
	print("LOOKDEV_MEASURE %s px=(%d,%d) srgb8=(%d,%d,%d) lin=(%.4f,%.4f,%.4f) ratio=(%.3f,%.3f,%.3f) model=(%.3f,%.3f,%.3f) err=(%+.1f%%,%+.1f%%,%+.1f%%) lum_err=%+.1f%%" % [
		label, cx, cy, srgb.r8, srgb.g8, srgb.b8, lin.r, lin.g, lin.b, r.x, r.y, r.z, want.x, want.y, want.z,
		err.x * 100.0, err.y * 100.0, err.z * 100.0, y_err * 100.0])
	if label.begins_with("mare_"):
		var t: Vector3 = MoonLight.NIGHT_TARGET
		var te: Vector3 = r / t - Vector3.ONE
		var ty: float = w.dot(r * Vector3(alb.r, alb.g, alb.b)) / w.dot(t * Vector3(alb.r, alb.g, alb.b)) - 1.0
		print("LOOKDEV_NIGHT_TARGET %s target=(%.2f,%.2f,%.2f) err=(%+.1f%%,%+.1f%%,%+.1f%%) lum_err=%+.1f%% pass=%s" % [
			label, t.x, t.y, t.z, te.x * 100.0, te.y * 100.0, te.z * 100.0, ty * 100.0, absf(ty) <= MoonLight.NIGHT_TOLERANCE])
