class_name ShipMotion extends RefCounted
## Tick-order step 5 for ships (03 s4.1, R0 B.5): `Kinematics.step_ship` for every live ship that is not DOCKED
## (rule 9, A-41), with its input slot and its owner's doctrine-resolved `ShipDef`, through one reused `ShipState`
## scratch; a terrain contact goes to `Collision.report_terrain` for step 8's classification. Hot loop (03 s12.2):
## the SoA arrays are taken into locals once per tick (one copy-on-write each), written per ship, assigned back.
## `over_dive_excess` is Combat's (GD-08 overspeed damage); GroundMotion (TA-38) and turret slew (GD-09) join step 5.

var _store: EntityStore
var _inputs: InputSlots
var _defs: WorldDefs
var _collision: Collision
var _terrain: Terrain
var _st: ShipState = ShipState.new()
var _in: PilotInput = PilotInput.new()


func _init(store: EntityStore, inputs: InputSlots, defs: WorldDefs, collision: Collision, terrain: Terrain) -> void:
	_store = store
	_inputs = inputs
	_defs = defs
	_collision = collision
	_terrain = terrain


func step(t: int, dt: float) -> void:
	var p: PackedVector3Array = _store.pos
	var v: PackedVector3Array = _store.vel
	var fw: PackedVector3Array = _store.fwd
	var up: PackedVector3Array = _store.up
	var rt: PackedVector3Array = _store.rates
	var bt: PackedFloat32Array = _store.boost_time
	var ft: PackedFloat32Array = _store.flip_time
	var fu: PackedFloat32Array = _store.fuel
	var fl: PackedByteArray = _store.flags
	var dy: PackedByteArray = _store.dirty
	var own: PackedByteArray = _store.owner
	var did: PackedInt32Array = _store.def_id
	var it: PackedFloat64Array = _inputs.e_thrust
	var ip: PackedFloat64Array = _inputs.e_pitch
	var iy: PackedFloat64Array = _inputs.e_yaw
	var ir: PackedFloat64Array = _inputs.e_roll
	var ib: PackedByteArray = _inputs.e_buttons
	var table: Array[ShipDef] = _defs.ship_table
	var n: int = _defs.ship_count
	var common: FlightCommonDef = _defs.common
	var rules: RulesDef = _defs.rules
	var st: ShipState = _st
	var inp: PilotInput = _in
	for s: int in _store.ships:
		var f: int = fl[s]
		var d: int = did[s] - DefRanges.SHIP_BASE
		if (f & EntityStore.F_DOCKED) != 0 or d < 0 or d >= n:
			continue
		st.p = p[s]
		st.v = v[s]
		st.fwd = fw[s]
		st.up = up[s]
		st.rates = rt[s]
		st.boost_time = bt[s]
		st.flip_time = ft[s]
		st.fuel = fu[s]
		inp.thrust = it[s]
		inp.pitch = ip[s]
		inp.yaw = iy[s]
		inp.roll = ir[s]
		inp.buttons = ib[s]
		var _r: ShipState = Kinematics.step_ship(st, inp, table[mini(own[s], WorldDefs.NEUTRAL) * n + d], common, rules,
			_terrain, dt)
		p[s] = st.p
		v[s] = st.v
		fw[s] = st.fwd
		up[s] = st.up
		rt[s] = st.rates
		bt[s] = st.boost_time
		ft[s] = st.flip_time
		fu[s] = st.fuel
		fl[s] = (f | EntityStore.F_CEILING_FORCED) if st.ceiling_forced else (f & ~EntityStore.F_CEILING_FORCED)
		dy[s] = dy[s] | EntityStore.DIRTY_POSE
		if st.terrain_hit:
			_collision.report_terrain(s, t, st.hit_normal_speed)
	_store.pos = p
	_store.vel = v
	_store.fwd = fw
	_store.up = up
	_store.rates = rt
	_store.boost_time = bt
	_store.flip_time = ft
	_store.fuel = fu
	_store.flags = fl
	_store.dirty = dy
