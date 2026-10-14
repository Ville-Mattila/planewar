class_name Build extends RefCounted
## The one placement validator (02 s6.2, 03 s3.6, R0 C2-12): server, client preview and bots all call
## `can_place`. Checks run in `Reject` order and the first failure wins. Reads the store (only `place` writes it) and
## reuses one footprint array. Deterministic: no RNG, no clock other than `set_clock`. Vision is approximated by
## friendly sensor discs until TA-37 lands (footprint centre only).

enum Reject { OK, ELIMINATED, PREREQ, CAP, OCCUPIED, SLOPE, NODE, NOT_VISIBLE, ENEMY_RADIUS, NO_RADIUS,
		NO_PRESENCE, SPACING, FUNDS, SPEND_LOCKED }

const _STATE: PackedStringArray = ["spent_ore", "delivered_ore", "_tick", "rot"]

var grid: BuildGrid
var spent_ore: PackedInt32Array = PackedInt32Array()       ## per player, Ore paid so far (Economy writes)
var delivered_ore: PackedInt32Array = PackedInt32Array()   ## per player, Ore its Harvesters and Core trickle delivered
var rot: PackedByteArray = PackedByteArray()               ## per entity slot, the rotation (0-3) its structure was placed with

var _defs: WorldDefs
var _store: EntityStore
var _players: PlayerTable
var _rules: MatchRules
var _fp: BuildFootprint
var _tick: int = 0
var _core_def: int = -1
var _outpost_def: int = -1
var _max_slope: float = 0.0        ## economy.json build_max_slope_deg ... site_hp_fraction (02 s6.2, s6.3)
var _presence: float = 0.0
var _spacing_friendly: float = 0.0
var _spacing_enemy: float = 0.0
var _site_hp: float = 0.0


func _init(defs: WorldDefs, store: EntityStore, players: PlayerTable, terrain: Terrain, rules: MatchRules,
		grid_n: int = Sphere.GRID_BUILD) -> void:
	_defs = defs
	_store = store
	_players = players
	_rules = rules
	grid = BuildGrid.new(terrain, grid_n)
	_fp = BuildFootprint.new(grid_n)
	var e: int = spent_ore.resize(PlayerTable.SLOTS) | delivered_ore.resize(PlayerTable.SLOTS) | rot.resize(EntityId.WRECK_SLOT_MIN)
	assert(e == OK)
	spent_ore.fill(0)
	delivered_ore.fill(0)
	rot.fill(0)
	var ec: EconomyDef = defs.economy if defs.economy != null else EconomyDef.new()
	_max_slope = ec.build_max_slope_deg
	_presence = ec.outpost_presence_radius_m
	_spacing_friendly = ec.outpost_spacing_friendly_m
	_spacing_enemy = ec.outpost_spacing_enemy_m
	_site_hp = ec.site_hp_fraction
	_core_def = defs.content.entity_index.get(&"core", -1)
	_outpost_def = defs.content.entity_index.get(&"outpost", -1)


## S4: Ore counters, clock, placed rotations and the grid flags (the "build" section of `SimSerialize`, format 7).
func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)
	grid.write_state(buf)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE) or spent_ore.size() != PlayerTable.SLOTS or delivered_ore.size() != PlayerTable.SLOTS or rot.size() != EntityId.WRECK_SLOT_MIN:
		return false
	return grid.read_state(buf)


func set_clock(tick: int) -> void:
	_tick = tick


## Cells of the footprint of `def_id` anchored (centre cell) at `cell`; crosses cube edges via neighbour_cell.
func footprint_cells(def_id: int, cell: int, rotation: int) -> PackedInt32Array:
	var sd: StructureDef = _defs.base.structure(def_id)
	if sd == null or sd.footprint.size() != 2:
		return PackedInt32Array()
	return _fp.cells(cell, sd.footprint[0], sd.footprint[1], rotation)


func can_place(player: int, def_id: int, cell: int, rotation: int) -> Build.Reject:
	if not _players.is_active(player) or _players.eliminated[player] != 0:
		return Reject.ELIMINATED
	var sd: StructureDef = _defs.resolved(player).structure(def_id)
	var team: int = _players.team[player]
	if sd == null or not sd.buildable or sd.footprint.size() != 2 or cell < 0 or cell >= grid.cell_count() \
			or rotation < 0 or rotation > 3 or not TeamStats.tech_available(_store, _defs, team, def_id):
		return Reject.PREREQ
	if _over_cap(player, def_id, sd):
		return Reject.CAP
	var cells: PackedInt32Array = _fp.cells(cell, sd.footprint[0], sd.footprint[1], rotation)
	var r: Reject = _check_cells(cells, sd)
	if r != Reject.OK:
		return r
	r = _check_vision_and_radius(team, def_id, _fp.centre_dir() * Sphere.PLANET_RADIUS)
	if r != Reject.OK:
		return r
	return _check_funds(player, team, sd)


## Reserves the footprint and creates the construction site (F_BUILDING); 0 when can_place rejects. Payment and the
## construction-slot start are `Construction`'s (sim/build/), not here.
func place(player: int, def_id: int, cell: int, rotation: int) -> int:
	if can_place(player, def_id, cell, rotation) != Reject.OK:
		return 0
	return stamp(player, def_id, cell, rotation, false)


## Creates the structure entity without validating (`place` after can_place; the start kit, finished). 0 when the
## store is full or the def has no footprint. Occupies the footprint cells and records the rotation.
func stamp(player: int, def_id: int, cell: int, rotation: int, finished: bool) -> int:
	var sd: StructureDef = _defs.resolved(player).structure(def_id)
	if sd == null or sd.footprint.size() != 2:
		return 0
	var cells: PackedInt32Array = _fp.cells(cell, sd.footprint[0], sd.footprint[1], rotation)
	var id: int = _store.alloc(EntityStore.K_STRUCTURE, _tick)
	if id == EntityId.NULL_ID:
		return 0
	var s: int = EntityId.slot(id)
	var p: Vector3 = _fp.centre_dir() * Sphere.PLANET_RADIUS
	_store.def_id[s] = def_id
	_store.owner[s] = player
	_store.team[s] = _players.team[player]
	_store.pos[s] = p
	_store.up[s] = p.normalized()
	_store.fwd[s] = Sphere.tangent_frame(p).x
	_store.radius[s] = _defs.radius_of(def_id)
	_store.hp[s] = _defs.hp_max(player, def_id) * (1.0 if finished else _site_hp)
	if not finished:
		_store.flags[s] |= EntityStore.F_BUILDING
	_store.anchor_cell[s] = cell
	rot[s] = rotation
	grid.occupy(cells)
	return id


## Frees the footprint of structure slot `s` (death or cancelled site); the entity itself is the caller's.
func release_site(s: int) -> void:
	var sd: StructureDef = _defs.resolved(_store.owner[s]).structure(_store.def_id[s])
	if sd != null and sd.footprint.size() == 2 and _store.anchor_cell[s] >= 0:
		grid.release(_fp.cells(_store.anchor_cell[s], sd.footprint[0], sd.footprint[1], rot[s]))


func _over_cap(player: int, def_id: int, sd: StructureDef) -> bool:
	var total: int = 0
	var same: int = 0
	for s: int in _store.structures:
		if _store.owner[s] == player:
			total += 1
			if _store.def_id[s] == def_id:
				same += 1
	if _rules.caps != null and _rules.caps.structures > 0 and total >= _rules.caps.structures:
		return true
	return sd.max_per_player > 0 and same >= sd.max_per_player


func _check_cells(cells: PackedInt32Array, sd: StructureDef) -> Reject:
	var cold_seen: bool = false
	var node_bad: bool = false
	var worst: float = 0.0
	var occupied: bool = false
	for c: int in cells:
		var f: int = grid.flags_of(c)
		occupied = occupied or (f & BuildGrid.OCCUPIED) != 0
		if (f & BuildGrid.NODE) != 0:
			if sd.on_node == &"cold_trap" and (f & BuildGrid.COLD_TRAP) != 0:
				cold_seen = true
			else:
				node_bad = true   # any other node cell, e.g. an Ore node under an Ice Extractor (ADR-05)
		worst = maxf(worst, grid.slope_deg(c))
	if occupied:
		return Reject.OCCUPIED
	if worst > _max_slope:
		return Reject.SLOPE
	if node_bad or (sd.on_node != &"" and not cold_seen):
		return Reject.NODE
	return Reject.OK


func _check_vision_and_radius(team: int, def_id: int, centre: Vector3) -> Reject:
	var seen: bool = false
	var in_radius: bool = false
	var present: bool = false
	var spacing: bool = false
	var enemy_radius: bool = false
	var is_outpost: bool = def_id == _outpost_def
	for kind_list: int in 3:
		var list: PackedInt32Array = _store.structures if kind_list == 0 else (_store.ships if kind_list == 1 else _store.ground)
		for s: int in list:
			var mine: bool = _store.team[s] == team
			var built: bool = (_store.flags[s] & EntityStore.F_BUILDING) == 0
			var p: Vector3 = _store.pos[s]
			var sd: StructureDef = _defs.base.structure(_store.def_id[s]) if kind_list == 0 else null
			if mine and built and not seen:
				seen = _sees(s, sd, p, centre)
			if sd == null:
				if mine and is_outpost and (_store.flags[s] & EntityStore.F_DOCKED) == 0 \
						and p.distance_to(centre) <= _presence:
					present = true
				continue
			var gc: float = Sphere.great_circle(p, centre)
			if not mine and built and sd.build_radius > 0.0 and gc <= sd.build_radius:
				enemy_radius = true
			if mine and built and sd.build_radius > 0.0 and gc <= sd.build_radius:
				in_radius = true
			if _store.def_id[s] == _core_def or _store.def_id[s] == _outpost_def:
				if gc < (_spacing_friendly if mine else _spacing_enemy):
					spacing = true
	if not seen:
		return Reject.NOT_VISIBLE   # before ENEMY_RADIUS: never reveal enemy structures through fog (02 s6.2 order)
	if enemy_radius:
		return Reject.ENEMY_RADIUS
	if is_outpost:
		if not present:
			return Reject.NO_PRESENCE
		return Reject.SPACING if spacing else Reject.OK
	return Reject.OK if in_radius else Reject.NO_RADIUS


func _sees(s: int, sd: StructureDef, p: Vector3, centre: Vector3) -> bool:
	var r: float = 0.0
	var d: int = _store.def_id[s]
	if sd != null:
		r = sd.sensor_radius
	elif _store.kind[s] == EntityStore.K_SHIP:
		var sh: ShipDef = _defs.base.ship(d)
		r = sh.sensor_radius if sh != null else 0.0
	else:
		var g: GroundUnitDef = _defs.base.ground_unit(d)
		r = g.sensor_radius if g != null else 0.0
	return p.distance_squared_to(centre) <= r * r   # ground point: datum occlusion is TA-37 Vision


func _check_funds(player: int, team: int, sd: StructureDef) -> Reject:
	if _players.team_ore[team] < sd.cost_ore or _players.team_ice[team] < sd.cost_ice:
		return Reject.FUNDS
	return Reject.SPEND_LOCKED if lock_blocks(player, sd.cost_ore) else Reject.OK


## True while the early share lock (02 s6.4, R0 C3-08) forbids `player` to spend `cost_ore` more: a team of two or more,
## before `early_share_lock_s`, spent + cost over `early_share_ore` + the Ore this player delivered.
func lock_blocks(player: int, cost_ore: int) -> bool:
	var hz: int = _rules.tick_hz
	var econ: EconomyDef = _defs.economy
	if econ == null or hz <= 0 or float(_tick) >= econ.early_share_lock_s * float(hz):
		return false
	var team: int = _players.team[player]
	var mates: int = 0
	for q: int in PlayerTable.SLOTS:
		if _players.is_active(q) and _players.team[q] == team:
			mates += 1
	return mates >= 2 and spent_ore[player] + cost_ore > econ.early_share_ore + delivered_ore[player]
