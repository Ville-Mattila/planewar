class_name GroundMotion extends RefCounted
## Tick-order step 5 for ground units (03 s5.3, R0 B.5, C2-09, C2-11). Input-driven, no velocity integration, no
## inertia: each tick the unit turns by `yaw * ground_turn_rate_dps * dt`, takes the speed its input and the slope
## give it, moves along the great circle of its heading and snaps to `R + height_at(dir) + bounding_radius`.
##   speed = ground_speed (ground_speed_loaded while carrying cargo) x thrust x (1 - loss x slope_deg / max_slope_deg)
##   BRAKE = stop; held `ground_reverse_hold_s` it reverses at `ground_reverse_speed_mps` (x the slope factor).
## A step onto a cell with path weight 0 / 255, or onto terrain steeper than `max_slope_deg` (and steeper than the
## current slope, so a unit can always climb out), is refused: the unit stays and `vel` is zero.
## A stationary unit re-snaps every RESNAP_TICKS (8) ticks, not every tick (perf: idle units are most of them).
## Stored per unit: pos (snapped), up (terrain normal), fwd (heading in the radial tangent plane, unit, perpendicular
## to pos; the tilted body basis is presentation's), vel (fwd x signed speed), timer_b (seconds BRAKE has been held).
## Slope is the baked slope.u8 (Terrain.slope_deg_at_dir), the same source Pathing uses, so a routed cell never trips
## the block. Hot loop (03 s12.2): SoA arrays taken into locals once per tick, written per unit, assigned back.

const RESNAP_TICKS: int = 8   ## power of two

var _store: EntityStore
var _inputs: InputSlots
var _defs: WorldDefs
var _terrain: Terrain
var _pathing: Pathing
var _turn_rad: float
var _rev_speed: float
var _rev_hold: float
var _loss: float
var _tick: int = 0


## `pathing` may be null (weights then never block).
func _init(store: EntityStore, inputs: InputSlots, defs: WorldDefs, terrain: Terrain, pathing: Pathing) -> void:
	_store = store
	_inputs = inputs
	_defs = defs
	_terrain = terrain
	_pathing = pathing
	var r: RulesDef = defs.rules
	_turn_rad = deg_to_rad(r.ground_turn_rate_dps)
	_rev_speed = r.ground_reverse_speed_mps
	_rev_hold = r.ground_reverse_hold_s
	_loss = r.ground_slope_speed_loss


## The 02 slope rule: 1 - loss x slope_deg / max_slope_deg, never below 0; a unit with no slope limit is never slowed.
static func speed_factor(slope_deg: float, max_slope_deg: float, loss: float) -> float:
	if max_slope_deg <= 0.0:
		return 1.0
	return maxf(0.0, 1.0 - loss * slope_deg / max_slope_deg)


func step(t: int, dt: float) -> void:
	_tick = t
	var p: PackedVector3Array = _store.pos
	var v: PackedVector3Array = _store.vel
	var fw: PackedVector3Array = _store.fwd
	var up: PackedVector3Array = _store.up
	for s: int in _store.ground:
		var g: GroundUnitDef = _defs.resolved(_store.owner[s]).ground_unit(_store.def_id[s])
		if g != null:
			_unit(s, g, dt, p, v, fw, up)
	_store.pos = p
	_store.vel = v
	_store.fwd = fw
	_store.up = up


func _unit(s: int, g: GroundUnitDef, dt: float, p: PackedVector3Array, v: PackedVector3Array, fw: PackedVector3Array,
		up: PackedVector3Array) -> void:
	var dir: Vector3 = p[s].normalized()
	var h: Vector3 = Quaternion(dir, _inputs.e_yaw[s] * _turn_rad * dt) * _heading(fw[s], dir)
	var braking: bool = (_inputs.e_buttons[s] & PilotInput.BRAKE) != 0
	var held: float = _store.timer_b[s] + dt if braking else 0.0
	_store.timer_b[s] = held
	var thrust: float = _inputs.e_thrust[s]
	var cur: float = _terrain.slope_deg_at_dir(dir) if braking or thrust > 0.0 else 0.0
	var speed: float = _speed(g, thrust, braking, held, dt, cur, _store.cargo[s])
	var moved: bool = false
	if speed != 0.0:
		var q: Quaternion = Quaternion(dir.cross(h), speed * dt / Sphere.PLANET_RADIUS)
		var nd: Vector3 = (q * dir).normalized()
		if _can_enter(g, dir, nd, cur):
			dir = nd
			h = _heading(q * h, nd)
			moved = true
	fw[s] = h
	v[s] = h * speed if moved else Vector3.ZERO
	if moved or _resnap_due(s):
		p[s] = dir * (Sphere.PLANET_RADIUS + _terrain.height_at(dir) + g.bounding_radius)
		up[s] = _terrain.normal_at(dir)


## A unit that did not move re-snaps to the surface every RESNAP_TICKS ticks (staggered by slot, so the terrain
## sampling of idle units is spread over the period) and on its first two ticks; a moving unit re-snaps every tick.
func _resnap_due(s: int) -> bool:
	return ((_tick + s) & (RESNAP_TICKS - 1)) == 0 or _store.spawn_tick[s] + 1 >= _tick


## Signed speed in m/s for this tick (before the can-enter test): thrust fraction, BRAKE stop, reverse after the hold.
func _speed(g: GroundUnitDef, thrust: float, braking: bool, held: float, dt: float, slope: float, cargo: float) -> float:
	var factor: float = speed_factor(slope, g.max_slope_deg, _loss)
	if braking:
		return -minf(_rev_speed, g.ground_speed) * factor if held >= _rev_hold - dt * 0.5 else 0.0
	var top: float = g.ground_speed_loaded if cargo > 0.0 and g.ground_speed_loaded > 0.0 else g.ground_speed
	return clampf(thrust, 0.0, 1.0) * top * factor


## True when a unit at `dir` (slope `cur`) may step onto `nd`: weight not 0 / 255 (unless already on that cell) and
## baked slope within `max_slope_deg` or no steeper than where it stands.
func _can_enter(g: GroundUnitDef, dir: Vector3, nd: Vector3, cur: float) -> bool:
	var ns: float = _terrain.slope_deg_at_dir(nd)
	if ns > g.max_slope_deg and ns > cur:
		return false
	if _pathing == null:
		return true
	var c: int = PathGrid.cell_of(nd)
	return not PathGrid.blocks(_pathing.weight(c)) or c == PathGrid.cell_of(dir)


## `f` projected onto the tangent plane at `dir`, unit; north (or the prime axis at a pole) when degenerate.
static func _heading(f: Vector3, dir: Vector3) -> Vector3:
	var t: Vector3 = f - dir * f.dot(dir)
	if t.is_zero_approx():
		return Sphere.tangent_frame(dir).y
	return t.normalized()
