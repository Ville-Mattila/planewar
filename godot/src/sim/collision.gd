class_name Collision extends RefCounted
## Tick step 8 (03 s6.1, R0 B.5, TA-14): reads the coherent Spatial hash of step 7 and writes `Contact` records
## (flat typed arrays, `contact_count` valid entries) for Combat (step 9) and Docking (step 10). Detects and
## classifies only; it never changes HP, flags or positions. Tests in 03 s6.1 order:
##   8  projectile vs entity: segment prev_pos -> pos vs sphere (entity radius + projectile radius), the earliest
##      entry t in [0, 1] wins; same team skipped unless `friendly_fire`, the shooter skipped for
##      `shooter_grace_ticks` from the projectile's first collision tick, wrecks skipped -> C_HIT;
##   8b projectile vs terrain for projectiles without a hit, behind the relief prefilter |p| > PLANET_RADIUS +
##      RELIEF_MAX + radius -> skip, then the hash cell's highest texel (lazy, conservative) -> C_GROUND;
##   ship vs terrain from `report_terrain` (Kinematics' terrain_hit, 03 s5.3 step 6), classified by flight_common
##      thresholds once per contact episode (R0 B.9 A-30: a run of contact ticks plus gaps shorter than
##      `scrape_clear_s`; the first tick's hit_normal_speed decides; a kill-speed hit destroys regardless) -> C_TERRAIN;
##   landing (A-31): every tick a not-DOCKED ship is inside a friendly pad's volume (offset in the pad frame <=
##      pad_radius_m, |altitude above the pad plane| <= radius + 0.5) -> C_PAD with the landing band; its terrain
##      contact is then the landing's, not a scrape or damage (kill speed still destroys);
##   ship vs ship (each pair once) and ship vs structure (from the ship side) sphere-sphere -> C_RAM; a docked ship
##      is exempt against its own pad, a not-docked ship above a friendly pad structure's deck (A-53 widened by BUG-1:
##      altitude above the pad plane >= -(radius + 0.5), any horizontal offset; the sphere's body lies below the deck)
##      against that structure. The landing volume (C_PAD) keeps offset <= pad_radius_m.
## A-87: a ship is never RAM-tested against an own-team structure whose def has `launch_pad: true` (the Shipyard), docked
## or not; enemy ships still ram it.
## The pad plane passes through the structure's `pos` with normal `up` (GD-15 may add a deck offset).
## Per-slot state (`ep_gen`, `ep_last`, `born_gen`, `born_tick`) is sim state for serialization (S4, TA-18).

const C_HIT: int = 0
const C_GROUND: int = 1
const C_TERRAIN: int = 2
const C_RAM: int = 3
const C_PAD: int = 4
## C_TERRAIN classes (03 s6.1 table).
const T_SCRAPE: int = 0
const T_DAMAGE: int = 1
const T_DESTROY: int = 2
## C_PAD landing bands (03 s6.4; LandingGrade and the pad-free rule are Docking's).
const L_SAFE: int = 0
const L_DAMAGE: int = 1
const L_DESTROY: int = 2
const _RAM_CAP: int = 64                                 # rams per ship per tick kept (more are dropped)

## Contact records, index < contact_count. a / b: EntityIds. value: HIT entry t, GROUND terrain height,
## TERRAIN hit_normal_speed, RAM centre distance, PAD horizontal offset. point: HIT entry point, GROUND surface
## point, else the ship position. vec: PAD (v_vert, v_hor, tilt_deg). cls: TERRAIN class or PAD band.
var launch_pad: PackedByteArray = PackedByteArray()   ## by EntityStore.def_id: 1 = `launch_pad: true` structure (A-19, A-87); set by SimWorld
var contact_count: int = 0
var c_kind: PackedByteArray = PackedByteArray()
var c_class: PackedByteArray = PackedByteArray()
var c_a: PackedInt32Array = PackedInt32Array()
var c_b: PackedInt32Array = PackedInt32Array()
var c_value: PackedFloat32Array = PackedFloat32Array()
var c_point: PackedVector3Array = PackedVector3Array()
var c_vec: PackedVector3Array = PackedVector3Array()
var prefilter_passed: int = 0       ## projectiles below PLANET_RADIUS + RELIEF_MAX + radius in the last step (8b prefilter)
var terrain_samples: int = 0        ## height_at calls by 8b in the last step (after the per-cell maximum)
var friendly_fire: bool = false     ## MatchRules.friendly_fire
var shooter_grace_ticks: int = 0    ## 03 s6.1 "skip shooter for 10 ticks"; set by SimWorld from defs
var ep_gen: PackedInt32Array = PackedInt32Array()      ## per entity slot: generation of the open episode, 0 none
var ep_last: PackedInt32Array = PackedInt32Array()     ## per entity slot: last tick with terrain contact
var born_gen: PackedInt32Array = PackedInt32Array()    ## per projectile index: generation first seen by step()
var born_tick: PackedInt32Array = PackedInt32Array()   ## per projectile index: its first collision tick

var _store: EntityStore
var _proj: ProjectileStore
var _spatial: Spatial
var _terrain: Terrain
var _common: FlightCommonDef
var _p_radius: PackedFloat32Array = PackedFloat32Array()
var _pad_radius: PackedFloat32Array = PackedFloat32Array()
var _clear_ticks: float = 0.0
var _ring1: float = 0.0
var _max_pad: float = 0.0
var _t_tick: PackedInt32Array = PackedInt32Array()
var _t_gen: PackedInt32Array = PackedInt32Array()
var _t_hns: PackedFloat32Array = PackedFloat32Array()
var _cells: PackedInt32Array = PackedInt32Array()
var _ram: PackedInt32Array = PackedInt32Array()
var _ram_n: int = 0
var _pad_slot: int = 0
var _pad_off: float = 0.0
var _best_t: float = 0.0
var _hmax: PackedFloat32Array = PackedFloat32Array()
var _hmax_ok: PackedByteArray = PackedByteArray()


func _init(store: EntityStore, projectiles: ProjectileStore, spatial: Spatial, terrain: Terrain) -> void:
	_store = store
	_proj = projectiles
	_spatial = spatial
	_terrain = terrain
	_ring1 = spatial.ring1_m
	var n: int = EntityStore.SLOT_COUNT
	var m: int = ProjectileStore.SLOT_COUNT
	var e: int = ep_gen.resize(n) | ep_last.resize(n) | _t_tick.resize(n) | _t_gen.resize(n) | _t_hns.resize(n)
	e |= _hmax.resize(Spatial.CELL_COUNT) | _hmax_ok.resize(Spatial.CELL_COUNT)
	e |= born_gen.resize(m) | born_tick.resize(m) | _cells.resize(Spatial.ITEM_CAP) | _ram.resize(_RAM_CAP)
	assert(e == OK)
	ep_gen.fill(0)
	ep_last.fill(0)
	_t_gen.fill(0)
	born_gen.fill(0)
	born_tick.fill(0)
	_hmax_ok.fill(0)
	_ensure(Spatial.ITEM_CAP)


## projectile_radius: ProjectileDef.radius_m by ProjectileStore.projectile_def index. pad_radius_by_def:
## StructureDef.pad_radius_m by EntityStore.def_id (0 = no pad; ids beyond the array have none). Call after
## Terrain.load_map (clears the per-cell terrain maxima of 8b).
func configure(projectile_radius: PackedFloat32Array, pad_radius_by_def: PackedFloat32Array,
		common: FlightCommonDef, tick_hz: int) -> void:
	_p_radius = projectile_radius
	_pad_radius = pad_radius_by_def
	_common = common
	_clear_ticks = common.scrape_clear_s * float(tick_hz)
	_max_pad = 0.0
	_hmax_ok.fill(0)                                         # per-cell terrain maxima follow the loaded map
	for r: float in pad_radius_by_def:
		_max_pad = maxf(_max_pad, r)


## Step 5 hands over a ship's terrain contact for `tick` (ShipState.terrain_hit, hit_normal_speed).
func report_terrain(slot: int, tick: int, hit_normal_speed: float) -> void:
	_t_tick[slot] = tick
	_t_gen[slot] = _store.generation[slot]
	_t_hns[slot] = hit_normal_speed


## Runs every test of 03 s6.1 for `tick` against the last Spatial.rebuild(); replaces the contact list.
func step(tick: int) -> void:
	contact_count = 0
	terrain_samples = 0
	prefilter_passed = 0
	_projectile_pass(tick)
	for s: int in _store.ships:
		_ship(s, tick)


## 03 s6.1 ship-terrain classes from flight_common: > terrain_kill_speed destroy, > terrain_damage_speed damage,
## else scrape.
static func classify_terrain(hit_normal_speed: float, common: FlightCommonDef) -> int:
	if hit_normal_speed > common.terrain_kill_speed:
		return T_DESTROY
	if hit_normal_speed > common.terrain_damage_speed:
		return T_DAMAGE
	return T_SCRAPE


## 03 s6.4 / R0 B.5 landing band: safe within all landing_safe_* limits, destroyed beyond any landing_damage_*
## limit (tilt: landing_damage_tilt_deg), else damage. v_vert is the descent speed along the pad normal.
static func landing_band(v_vert: float, v_hor: float, tilt_deg: float, common: FlightCommonDef) -> int:
	if v_vert > common.landing_damage_v_vert or v_hor > common.landing_damage_v_hor \
			or tilt_deg > common.landing_damage_tilt_deg:
		return L_DESTROY
	if v_vert > common.landing_safe_v_vert or v_hor > common.landing_safe_v_hor \
			or tilt_deg > common.landing_safe_pitch_deg:
		return L_DAMAGE
	return L_SAFE


## Entry parameter t in [0, 1] of the segment a -> b into the sphere (c, r); 0 if a starts inside; -1.0 on a miss.
static func sweep_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> float:
	var d: Vector3 = b - a
	var f: Vector3 = a - c
	var cc: float = f.length_squared() - r * r
	if cc <= 0.0:
		return 0.0
	var aa: float = d.length_squared()
	var bb: float = f.dot(d)
	if bb >= 0.0 or aa <= 0.0:
		return -1.0
	var disc: float = bb * bb - aa * cc
	if disc < 0.0:
		return -1.0
	var t: float = (-bb - sqrt(disc)) / aa
	return t if t <= 1.0 else -1.0


# 8 and 8b over every live projectile. Hot path: arrays through locals, ring 1 inside a face by index arithmetic
# (_ring_into otherwise), a bounding-sphere reject before the exact sweep.
func _projectile_pass(tick: int) -> void:
	var items: PackedInt32Array = _spatial.cell_items
	var starts: PackedInt32Array = _spatial.cell_start
	var ents: PackedInt32Array = _spatial.cell_entities
	var epos: PackedVector3Array = _store.pos
	var erad: PackedFloat32Array = _store.radius
	var ppos: PackedVector3Array = _proj.pos
	var pprev: PackedVector3Array = _proj.prev_pos
	var reach0: float = _spatial.max_entity_radius
	var gens: PackedInt32Array = _proj.generation
	for i: int in _proj.live:
		if born_gen[i] != gens[i]:
			born_gen[i] = gens[i]
			born_tick[i] = tick
		var b: Vector3 = ppos[i]
		var a: Vector3 = pprev[i]
		var pr: float = _p_radius[_proj.projectile_def[i]]
		var half: float = a.distance_to(b) * 0.5
		var mid: Vector3 = (a + b) * 0.5
		var nc: int = _ring_into(_proj.hash_cell[i], half + half + pr + reach0)
		var best: int = -1
		for q: int in nc:
			var c: int = _cells[q]
			var s0: int = starts[c]
			for k: int in ents[c]:
				var s: int = items[s0 + k]
				var rr: float = erad[s] + pr
				if mid.distance_squared_to(epos[s]) <= (half + rr) * (half + rr) and _hittable(i, s, tick):
					var t: float = sweep_sphere(a, b, epos[s], rr)
					if t >= 0.0 and (best < 0 or t < _best_t):
						_best_t = t
						best = s
		if best >= 0:
			_emit(C_HIT, 0, _proj.id_of(i), _store.id_of(best), _best_t, a.lerp(b, _best_t), Vector3.ZERO)
		else:
			_ground(i, b, pr, _proj.hash_cell[i])


# Candidate filters of 8: wrecks, same team unless friendly_fire, the shooter within its grace ticks.
func _hittable(i: int, s: int, tick: int) -> bool:
	if _store.kind[s] == EntityStore.K_WRECK or (_proj.team[i] == _store.team[s] and not friendly_fire):
		return false
	return tick - born_tick[i] >= shooter_grace_ticks or _store.id_of(s) != _proj.shooter[i]


# 8b behind the relief prefilter (03 s4.2): skip above PLANET_RADIUS + RELIEF_MAX + radius; then (TA-14) above the
# hash cell's highest texel + radius + 1 m (lazy per-cell maximum, conservative); only the rest sample height_at.
func _ground(i: int, b: Vector3, pr: float, cell: int) -> void:
	var lim: float = Sphere.PLANET_RADIUS + Sphere.RELIEF_MAX + pr
	var r2: float = b.length_squared()
	if r2 > lim * lim:
		return
	prefilter_passed += 1
	if _hmax_ok[cell] == 0:
		_fill_hmax(cell)
	lim = Sphere.PLANET_RADIUS + _hmax[cell] + pr + 1.0
	if r2 > lim * lim:
		return
	terrain_samples += 1
	var h: float = _terrain.height_at(b)
	if sqrt(r2) - Sphere.PLANET_RADIUS < h + pr:
		_emit(C_GROUND, 0, _proj.id_of(i), EntityId.NULL_ID, h, b.normalized() * (Sphere.PLANET_RADIUS + h), Vector3.ZERO)


# Highest baked height over the hash cell, cached (`TerrainCellMax`).
func _fill_hmax(cell: int) -> void:
	_hmax_ok[cell] = 1
	_hmax[cell] = TerrainCellMax.of_cell(_terrain, cell)


# Ship pass: pads, rams, then the terrain episode for one live ship slot. Candidates are rejected by centre
# distance before any pad or ram work (a pad volume lies within r + pad_radius_m + 1 m of the pad centre).
func _ship(s: int, tick: int) -> void:
	var epos: PackedVector3Array = _store.pos
	var erad: PackedFloat32Array = _store.radius
	var ekind: PackedByteArray = _store.kind
	var p: Vector3 = epos[s]
	var r: float = erad[s]
	var docked: bool = (_store.flags[s] & EntityStore.F_DOCKED) != 0
	var nc: int = _ring_into(_store.hash_cell[s], r + maxf(_spatial.max_entity_radius, _max_pad + 1.0))
	_pad_slot = -1
	_pad_off = 0.0
	_ram_n = 0
	var items: PackedInt32Array = _spatial.cell_items
	var starts: PackedInt32Array = _spatial.cell_start
	var ents: PackedInt32Array = _spatial.cell_entities
	for q: int in nc:
		var c: int = _cells[q]
		var s0: int = starts[c]
		for k: int in ents[c]:
			var o: int = items[s0 + k]
			var d2: float = p.distance_squared_to(epos[o])
			var ko: int = ekind[o]
			if ko == EntityStore.K_SHIP:
				if o > s and d2 <= (r + erad[o]) * (r + erad[o]):
					_add_ram(o)
			elif ko == EntityStore.K_STRUCTURE:
				var lim: float = r + maxf(erad[o], _max_pad + 1.0)
				if d2 <= lim * lim:
					_ship_structure(s, o, p, r, docked)
	if not docked:
		if _pad_slot >= 0:
			_emit_pad(s, _pad_slot, p)
		_terrain_episode(s, tick, _pad_slot >= 0)
	for k: int in _ram_n:
		var o: int = _ram[k]
		_emit(C_RAM, 0, _store.id_of(s), _store.id_of(o), p.distance_to(epos[o]), p, Vector3.ZERO)


func _ship_structure(s: int, o: int, p: Vector3, r: float, docked: bool) -> void:
	var d: int = _store.def_id[o]
	if d < launch_pad.size() and launch_pad[d] != 0 and _store.team[o] == _store.team[s]:
		return
	var in_pad: bool = false
	var in_col: bool = false
	var pad_r: float = _pad_radius[d] if d < _pad_radius.size() else 0.0
	if pad_r > 0.0 and _store.team[o] == _store.team[s]:
		if docked:
			in_pad = _store.link[s] == _store.id_of(o)
		else:
			var up_p: Vector3 = _store.up[o]
			var rel: Vector3 = p - _store.pos[o]
			var alt: float = rel.dot(up_p)
			var off: float = (rel - up_p * alt).length()
			in_col = alt >= -(r + 0.5)   # BUG-1: the whole half-space above the deck, not only the column over the pad
			in_pad = in_col and off <= pad_r and alt <= r + 0.5
			if in_pad and (_pad_slot < 0 or off < _pad_off):
				_pad_slot = o
				_pad_off = off
	if not (in_pad or in_col) and p.distance_to(_store.pos[o]) <= r + _store.radius[o]:
		_add_ram(o)


func _emit_pad(s: int, pad: int, p: Vector3) -> void:
	var up_p: Vector3 = _store.up[pad]
	var v: Vector3 = _store.vel[s]
	var v_vert: float = -v.dot(up_p)
	var v_hor: float = (v + up_p * v_vert).length()
	var tilt: float = rad_to_deg(_store.fwd[s].angle_to(up_p))
	_emit(C_PAD, landing_band(v_vert, v_hor, tilt, _common), _store.id_of(s), _store.id_of(pad), _pad_off, p,
		Vector3(v_vert, v_hor, tilt))


# A-30: one classified TERRAIN contact per episode; kill speed destroys at any tick; inside a pad volume only
# kill speed reports (the landing grades the rest).
func _terrain_episode(s: int, tick: int, on_pad: bool) -> void:
	var g: int = _store.generation[s]
	if _t_tick[s] != tick or _t_gen[s] != g:
		return
	var hns: float = _t_hns[s]
	var fresh: bool = ep_gen[s] != g or float(tick - ep_last[s] - 1) >= _clear_ticks
	ep_gen[s] = g
	ep_last[s] = tick
	var cls: int = classify_terrain(hns, _common)
	if cls == T_DESTROY or (fresh and not on_pad):
		_emit(C_TERRAIN, cls, _store.id_of(s), EntityId.NULL_ID, hns, _store.pos[s], Vector3.ZERO)


# Candidate cells for a query of `reach` metres around hash cell `cell` into _cells; returns the count. Ring 1
# inside a face by index arithmetic, otherwise Spatial.ring_cells; beyond ring2_m every touched cell.
func _ring_into(cell: int, reach: float) -> int:
	var n: int = Spatial.N
	var i: int = cell & (n - 1)
	var j: int = (cell >> Spatial.SHIFT) & (n - 1)
	if reach <= _ring1 and i > 0 and j > 0 and i < n - 1 and j < n - 1:
		var c: int = cell - n - 1
		_cells[0] = c
		_cells[1] = c + 1
		_cells[2] = c + 2
		_cells[3] = cell - 1
		_cells[4] = cell
		_cells[5] = cell + 1
		_cells[6] = cell + n - 1
		_cells[7] = cell + n
		_cells[8] = cell + n + 1
		return 9
	var count: int = _spatial.touched_count
	if reach <= _spatial.ring2_m:
		count = _spatial.ring_cells(cell, 1 if reach <= _ring1 else 2)
		for q: int in count:
			_cells[q] = _spatial.ring[q]
		return count
	for q: int in count:
		_cells[q] = _spatial.touched_cells[q]
	return count


func _add_ram(o: int) -> void:
	if _ram_n < _RAM_CAP:
		_ram[_ram_n] = o
		_ram_n += 1


func _emit(kind: int, cls: int, a: int, b: int, value: float, point: Vector3, vec: Vector3) -> void:
	if contact_count >= c_kind.size():
		_ensure(contact_count * 2)
	var n: int = contact_count
	c_kind[n] = kind
	c_class[n] = cls
	c_a[n] = a
	c_b[n] = b
	c_value[n] = value
	c_point[n] = point
	c_vec[n] = vec
	contact_count = n + 1


func _ensure(n: int) -> void:
	var e: int = c_kind.resize(n) | c_class.resize(n) | c_a.resize(n) | c_b.resize(n)
	e |= c_value.resize(n) | c_point.resize(n) | c_vec.resize(n)
	assert(e == OK)
