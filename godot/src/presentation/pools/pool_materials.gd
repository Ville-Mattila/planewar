class_name PoolMaterials
extends RefCounted
## Shared materials of the MultiMesh pools and pooled effects (03 s7.10). One instance of each per process; all
## static. They include the shared light model, so `MoonLight.ensure_globals()` runs first (registers `sun_dir`).

const FAR_SHADER: String = "res://src/presentation/shaders/unit_far.gdshader"
const ICON_SHADER: String = "res://src/presentation/shaders/unit_icon.gdshader"
const DECAL_SHADER: String = "res://src/presentation/shaders/unit_decal.gdshader"
const ADDITIVE_SHADER: String = "res://src/presentation/shaders/vfx_additive.gdshader"

static var _far: ShaderMaterial = null
static var _icon: ShaderMaterial = null
static var _additive: ShaderMaterial = null
static var _decal: ShaderMaterial = null


## Flat team colour from the instance colour, lit (the `_Far` meshes).
static func far_material() -> ShaderMaterial:
	if _far == null:
		_far = _make(FAR_SHADER)
	return _far


## Camera-facing glyph quads (icon band).
static func icon_material() -> ShaderMaterial:
	if _icon == null:
		_icon = _make(ICON_SHADER)
	return _icon


## Additive tint x instance colour (tracers, flashes, trails).
static func additive_material() -> ShaderMaterial:
	if _additive == null:
		_additive = _make(ADDITIVE_SHADER)
	return _additive


## Alpha-blended ground scorch (decals).
static func decal_material() -> ShaderMaterial:
	if _decal == null:
		_decal = _make(DECAL_SHADER)
	return _decal


## A fresh additive material (per-effect tint and intensity; shared by all instances of that effect).
static func make_additive() -> ShaderMaterial:
	return _make(ADDITIVE_SHADER)


static func _make(path: String) -> ShaderMaterial:
	MoonLight.ensure_globals()
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load(path)
	return m
