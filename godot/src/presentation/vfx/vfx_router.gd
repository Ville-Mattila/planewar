class_name VfxRouter
extends RefCounted
## Maps the drained `SimEvent` list to pooled effects (03 s10.1, 07 s6). `route` is the pure kind -> effect id
## table; `handle` / `drain` spawn through the `VfxPool` (and the bomb scorch through the `DecalPool`). HIT adds
## damage-scaled smoke when the target crossed one of the `smoke_hp01` thresholds (0.75 / 0.5 / 0.25 hp, R0 C2-31).
## Kinds without an effect route to the empty id. Reads the sim only through `SimView` and `SimEvent`.

const SMOKE_HP01: PackedFloat32Array = [0.75, 0.5, 0.25]
const SMOKE_ID: StringName = &"vfx_smoke_trail"
## Smoke size multiplier per damage step (light grey, dark, black + fire in the real effect).
const SMOKE_SCALE: PackedFloat32Array = [0.6, 1.0, 1.6]
const HIT_SCALE_PER_DAMAGE: float = 0.01
const HIT_SCALE_MAX: float = 3.0
## Bomb scorch radius in metres (07 s6 `vfx_bomb_impact_s` scorch quad).
const SCORCH_RADIUS_M: float = 14.0

var pool: VfxPool = null
var decals: DecalPool = null
var smoke_hp01: PackedFloat32Array = SMOKE_HP01
var handled: int = 0


func _init(p_pool: VfxPool = null, p_decals: DecalPool = null) -> void:
	pool = p_pool
	decals = p_decals


## Effect id for an event kind; `&""` when the kind has none.
static func route(kind: int) -> StringName:
	match kind:
		SimEvent.Kind.HIT:
			return &"vfx_hit_spark"
		SimEvent.Kind.BOMB_IMPACT:
			return &"vfx_bomb_impact_s"
		SimEvent.Kind.DEATH:
			return &"vfx_explosion_ship"
		SimEvent.Kind.STRUCTURE_LOST:
			return &"vfx_explosion_structure"
		SimEvent.Kind.LAUNCHED, SimEvent.Kind.LANDING:
			return &"vfx_dust_plume"
		SimEvent.Kind.DOCKED:
			return &"vfx_dock_beam"
		SimEvent.Kind.SERVICED:
			return &"vfx_pad_lights"
		SimEvent.Kind.BUILD_DONE:
			return &"vfx_spawn_in"
		SimEvent.Kind.SHIELD_COLLAPSE:
			return &"vfx_shield_hit"
		SimEvent.Kind.POSSESSED:
			return &"vfx_possess_pulse"
	return &""


## Damage step (0 = none, 1..3) of an hp fraction against `smoke_hp01`.
static func smoke_step(hp01: float, thresholds: PackedFloat32Array) -> int:
	var step: int = 0
	for i: int in thresholds.size():
		if hp01 < thresholds[i]:
			step = i + 1
	return step


## Spawns the effects of one event; returns how many effects it spawned.
func handle(ev: SimEvent, view: SimView) -> int:
	var id: StringName = route(ev.kind)
	if id == &"" or pool == null:
		return 0
	var at: Vector3 = ev.pos if ev.pos != Vector3.ZERO else view.pos(ev.a)
	var up: Vector3 = at.normalized()
	var scale_mult: float = 1.0
	if ev.kind == SimEvent.Kind.HIT:
		scale_mult = clampf(ev.value * HIT_SCALE_PER_DAMAGE, HIT_SCALE_PER_DAMAGE, HIT_SCALE_MAX)
	var n: int = 1 if pool.spawn(id, at, scale_mult, up) else 0
	handled += 1
	if ev.kind == SimEvent.Kind.HIT:
		var step: int = smoke_step(view.hp01(ev.a), smoke_hp01)
		if step > 0 and pool.spawn(SMOKE_ID, at, SMOKE_SCALE[mini(step, SMOKE_SCALE.size()) - 1], up):
			n += 1
	elif ev.kind == SimEvent.Kind.BOMB_IMPACT and decals != null:
		decals.add(at, up, SCORCH_RADIUS_M)
	return n


## Handles every event of one tick's drain; returns the number of effects spawned.
func drain(events: Array[SimEvent], view: SimView) -> int:
	var n: int = 0
	for ev: SimEvent in events:
		n += handle(ev, view)
	return n
