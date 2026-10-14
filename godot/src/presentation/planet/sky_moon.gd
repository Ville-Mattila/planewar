class_name SkyMoon extends RefCounted
## Hookup of `shaders/sky_moon.gdshader` (07 s1.5, 03 s7.8): black space, stars, the sun disc at `sun_dir` and
## the Earth as a 6 degree disc exactly at -Z above the Midnight Pole (R0 C2-31). All static.

const SHADER_PATH: String = "res://src/presentation/planet/shaders/sky_moon.gdshader"
const EARTH_DIAMETER_DEG: float = 6.0
const SUN_DIAMETER_DEG: float = 2.0


## Direction of the Earth in the sky: -Z (the Midnight Pole), whatever the sun does.
static func earth_dir() -> Vector3:
	return -Sphere.POLE_AXIS


static func make_sky() -> Sky:
	MoonLight.ensure_globals()
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	var sky: Sky = Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	return sky


## Switches `env` (from `MoonLight.make_environment()`) to the moon sky; ambient and reflections stay off.
static func apply(env: Environment) -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = make_sky()
