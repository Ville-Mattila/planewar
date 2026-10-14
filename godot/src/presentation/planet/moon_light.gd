class_name MoonLight
extends RefCounted
## The shared light model's CPU side (07 s1.5; ART-01): registers the `sun_dir` global shader uniform that
## `presentation/shaders/moon_light.gdshaderinc` reads, builds the sun light and the LDR environment, keeps
## them aligned, loads the moon and unit materials after the global exists, and mirrors the shader constants
## as a CPU reference (`shade_linear`) for tests and render measurements. All static; owns no Node.

const SUN_DIR_PARAM: StringName = &"sun_dir"
const DEFAULT_SUN_DIR: Vector3 = Vector3(0, 0, 1)                ## +Z = Noon Pole (Sphere.POLE_AXIS)
const SUN_COLOR: Color = Color("#FFF1DC")
const SUN_ENERGY: float = 1.25
const SPACE_COLOR: Color = Color("#05070C")
const MOON_SHADER_PATH: String = "res://src/presentation/planet/shaders/moon_surface.gdshader"
const UNIT_SHADER_PATH: String = "res://src/presentation/shaders/unit_lit.gdshader"
const UNIT_INSTANCED_SHADER_PATH: String = "res://src/presentation/shaders/unit_lit_instanced.gdshader"
const ATLAS_PATH: String = "res://assets/textures/unit_atlas.png"
const INCLUDE_PATH: String = "res://src/presentation/shaders/moon_light.gdshaderinc"

## Mirror of moon_light.gdshaderinc (linear light). test_moon_light.gd parses the include and asserts equality.
const WRAP: float = 0.30
const AMB_LOW: Vector3 = Vector3(0.00531, 0.00676, 0.01199)
const AMB_HIGH: Vector3 = Vector3(0.10279, 0.13358, 0.21948)
const EARTH: Vector3 = Vector3(0.33716, 0.46778, 0.80695)
const EARTH_GAIN: float = 0.50
const EARTH_BASE: float = 0.45
const NIGHT_LO: float = -0.10
const NIGHT_HI: float = 0.18
const RIM: Vector3 = Vector3(0.10420, 0.11682, 0.14908)
const RIM_NEAR: float = 1.25        ## rim fades in with |camera| / |surface point| from RIM_NEAR to RIM_FAR
const RIM_FAR: float = 1.75
## 07 s1.5 target: night-side mare at the Midnight Pole renders at albedo x NIGHT_TARGET (linear), +-20 %.
const NIGHT_TARGET: Vector3 = Vector3(0.30, 0.36, 0.55)
const NIGHT_TOLERANCE: float = 0.20

static var _registered: bool = false


## Registers `sun_dir` once (default +Z). Call before any material that includes moon_light is created.
## Until the ci lane adds `[shader_globals]` to project.godot (REPORT s6) this is the only registration.
static func ensure_globals() -> void:
	if _registered:
		return
	_registered = true
	if ProjectSettings.has_setting("shader_globals/" + String(SUN_DIR_PARAM)):
		return   # declared in project.godot (get_list() is editor-only, so the project setting is the probe)
	RenderingServer.global_shader_parameter_add(SUN_DIR_PARAM, RenderingServer.GLOBAL_VAR_TYPE_VEC3, DEFAULT_SUN_DIR)


## Points the sun at `dir` (unit vector towards the sun): the global uniform and, if given, the light.
static func set_sun_dir(dir: Vector3, sun: DirectionalLight3D = null) -> void:
	ensure_globals()
	var d: Vector3 = dir.normalized()
	RenderingServer.global_shader_parameter_set(SUN_DIR_PARAM, d)
	if sun != null:
		sun.global_basis = sun_basis(d)


## Light basis whose -Z (the travel direction of a DirectionalLight3D) is -dir.
static func sun_basis(dir: Vector3) -> Basis:
	var d: Vector3 = dir.normalized()
	var ref: Vector3 = Sphere.PRIME_AXIS if absf(d.dot(Sphere.PRIME_AXIS)) < 0.9 else Sphere.POLE_AXIS
	return Basis.looking_at(-d, ref)


static func make_sun() -> DirectionalLight3D:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = false
	sun.basis = sun_basis(DEFAULT_SUN_DIR)
	return sun


## LDR environment of 07 s1.5: space background, no ambient (the shader owns it), no glow/SSAO/fog, linear.
static func make_environment() -> Environment:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SPACE_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	env.fog_enabled = false
	return env


static func moon_material() -> ShaderMaterial:
	return _material(MOON_SHADER_PATH)


## Shared unit material (team and state as material uniforms). `instanced` = the instance-uniform variant.
static func unit_material(instanced: bool = false) -> ShaderMaterial:
	var m: ShaderMaterial = _material(UNIT_INSTANCED_SHADER_PATH if instanced else UNIT_SHADER_PATH)
	m.set_shader_parameter(&"atlas", load(ATLAS_PATH))
	return m


static func _material(path: String) -> ShaderMaterial:
	ensure_globals()
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(path)
	return m


## 1 on the day side, 0 on the night side (smoothstep band of the shader's ml_day).
static func day_factor(up: Vector3, sun: Vector3) -> float:
	return smoothstep(NIGHT_LO, NIGHT_HI, up.dot(sun.normalized()))


static func earth_k(up: Vector3, sun: Vector3) -> float:
	return (EARTH_BASE + (1.0 - EARTH_BASE) * maxf(0.0, -up.z)) * (1.0 - day_factor(up, sun))


## CPU reference of the rendered linear colour for a face with world normal `n` at surface direction `up`
## (rim omitted: it is zero for faces seen head-on). `albedo` is linear.
static func shade_linear(albedo: Vector3, n: Vector3, up: Vector3, sun: Vector3) -> Vector3:
	var amb: Vector3 = AMB_LOW.lerp(AMB_HIGH, 0.5 + 0.5 * n.dot(up))
	var earth: Vector3 = EARTH * (EARTH_GAIN * earth_k(up, sun))
	var lc: Vector3 = Vector3(SUN_COLOR.srgb_to_linear().r, SUN_COLOR.srgb_to_linear().g, SUN_COLOR.srgb_to_linear().b)
	var d: float = clampf((n.dot(sun.normalized()) + WRAP) / (1.0 + WRAP), 0.0, 1.0)
	return albedo * (amb + earth + lc * (SUN_ENERGY * d))


## Rendered / albedo per channel at the Midnight Pole for a level face (the 07 s1.5 night target ratio).
static func night_pole_ratio() -> Vector3:
	var up: Vector3 = -Sphere.POLE_AXIS
	return shade_linear(Vector3.ONE, up, up, DEFAULT_SUN_DIR)
