class_name UnitMaterialCache
extends RefCounted
## (team, state) cache of shared `unit_lit` materials (07 s4.3 fallback; ART-01 REPORT s5, ART-03). One
## ShaderMaterial per team (8) x state bucket (healthy, three damage steps, wreck) = 40 shared materials,
## created lazily. Per-instance duplicates exist only while a structure is under construction
## (`build_material`), and the caller frees them when `build_progress` reaches 1. Compatibility draws every
## MeshInstance3D separately either way, so draw calls do not change. Not on a sim hot path: lookups are one
## Dictionary hit per view bind, not per frame.

enum State { HEALTHY = 0, DAMAGED_1 = 1, DAMAGED_2 = 2, DAMAGED_3 = 3, WRECK = 4 }

const TEAM_COUNT: int = 8
const STATE_COUNT: int = 5
## 07 s2.2 / tools/blender/palette.json team[].hex, slot order. test_unit_material_cache.gd compares both.
const TEAM_HEX: PackedStringArray = ["#E1A633", "#4C64ED", "#3BFAB2", "#17840E", "#B1369D", "#E9A1FD", "#D6F72C", "#F06867"]
## damage01 uniform value of each State bucket; the bucket is the highest step the unit has reached.
const STATE_DAMAGE01: PackedFloat32Array = [0.0, 0.25, 0.5, 0.75, 1.0]
## Lower bounds of damage01 for DAMAGED_1..3 (presentation.smoke_hp01 = [0.75, 0.5, 0.25] hp, R0 C2-31).
const DAMAGE_STEP_MIN: PackedFloat32Array = [0.25, 0.5, 0.75]

var _cache: Dictionary = {}   ## int key (team * STATE_COUNT + state) -> ShaderMaterial


static func team_color(team: int) -> Color:
	return Color(TEAM_HEX[clampi(team, 0, TEAM_COUNT - 1)])


## State bucket for a unit: wrecks first, then the highest damage step reached.
static func state_for(damage01: float, is_wreck: bool) -> int:
	if is_wreck:
		return State.WRECK
	var s: int = State.HEALTHY
	for i: int in DAMAGE_STEP_MIN.size():
		if damage01 >= DAMAGE_STEP_MIN[i]:
			s = i + 1
	return s


## The shared material for (team, state); the same instance on every call.
func get_material(team: int, state: int) -> ShaderMaterial:
	var t: int = clampi(team, 0, TEAM_COUNT - 1)
	var st: int = clampi(state, 0, STATE_COUNT - 1)
	var key: int = t * STATE_COUNT + st
	if _cache.has(key):
		return _cache[key]
	var m: ShaderMaterial = _make(t, st)
	_cache[key] = m
	return m


## A fresh (uncached) material for a structure still being built; build_progress < 1 dims the unbuilt frame.
func build_material(team: int, build_progress: float) -> ShaderMaterial:
	var m: ShaderMaterial = _make(clampi(team, 0, TEAM_COUNT - 1), State.HEALTHY)
	m.set_shader_parameter(&"build_progress", clampf(build_progress, 0.0, 1.0))
	return m


func size() -> int:
	return _cache.size()


func clear() -> void:
	_cache.clear()


func _make(team: int, state: int) -> ShaderMaterial:
	var m: ShaderMaterial = MoonLight.unit_material()
	m.set_shader_parameter(&"team_index", team)
	m.set_shader_parameter(&"team_color", team_color(team))
	m.set_shader_parameter(&"damage01", STATE_DAMAGE01[state])
	m.set_shader_parameter(&"wreck", 1.0 if state == State.WRECK else 0.0)
	m.set_shader_parameter(&"build_progress", 1.0)
	return m
