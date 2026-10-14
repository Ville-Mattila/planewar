class_name Build extends RefCounted
## The one placement validator (02 s6.2, 03 s3.6, R0 C2-12): server, client preview and bots all call
## `can_place`. Checks run in `Reject` order and the first failure wins. Reads the store (only `place` writes it) and
## reuses one footprint array. Deterministic: no RNG, no clock other than `set_clock`. Vision is approximated by
## friendly sensor discs until TA-37 lands (footprint centre only).

enum Reject { OK, ELIMINATED, PREREQ, CAP, OCCUPIED, SLOPE, NODE, NOT_VISIBLE, ENEMY_RADIUS, NO_RADIUS,
		NO_PRESENCE, SPACING, FUNDS, SPEND_LOCKED }

## needs content: these belong in rules.json (02 s6.2); constants until a content task adds the fields.
const MAX_SLOPE_DEG: float = 15.0
const PRESENCE_RADIUS: float = 300.0
const MIN_SPACING_FRIENDLY: float = 800.0
const MIN_SPACING_ENEMY: float = 1500.0   # warning D6 accepted: needs content
const SITE_HP_FRACTION: float = 0.1   ## 02 s6.3: a site has hp * max(0.1, progress)

const _STATE: PackedStringArray = ["spent_ore", "delivered_ore", "_tick"]

var grid: BuildGrid
var spent_ore: PackedInt32Array = PackedInt32Array()       ## per player, Ore paid so far (Economy writes)
var delivered_ore: PackedInt32Array = PackedInt32Array()   ## per player, Ore its Harvesters and Core trickle delivered

var _defs: WorldDefs
var _store: EntityStore
var _players: PlayerTable
var _rules: MatchRules
var _fp: BuildFootprint
var _tick: int = 0
var _core_def: int = -1
var _outpost_def: int = -1


func _init(defs: WorldDefs, store: EntityStore, players: PlayerTable, terrain: Terrain, rules: MatchRules,
		grid_n: int = Sphere.GRID_BUILD) -> void:
	_defs = defs
	_store = store
	_players = players
	_rules = rules
	grid = BuildGrid.new(terrain, grid_n)
	_fp = BuildFootprint.new(grid_n)
	var e: int = spent_ore.resize(PlayerTable.SLOTS) | delivered_ore.resize(PlayerTable.SLOTS)
	assert(e == OK)
	spent_ore.fill(0)
	delivered_ore.fill(0)
	_core_def = defs.content.entity_index.get(&"core", -1)
	_outpost_def = defs.content.entity_index.get(&"outpost", -1)


## S4: Ore counters, clock and the grid flags. Not yet part of `SimSerialize` (SimWorld owns no Build until Economy lands);
## the section is appended there then (format bump).
func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)
	grid.write_state(buf)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE) or spent_ore.size() != PlayerTable.SLOTS or delivered_ore.size() != PlayerTable.SLOTS:
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
## construction-slot start belong to Economy / Production (later in TA-19), not here.
func place(player: int, def_id: int, cell: int, rotation: int) -> int:
	if can_place(player, def_id, cell, rotation) != Reject.OK:
		return 0
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
	_store.hp[s] = _defs.hp_max(player, def_id) * SITE_HP_FRACTION
	_store.flags[s] |= EntityStore.F_BUILDING
	_store.anchor_cell[s] = cell
	var sd: StructureDef = _defs.resolved(player).structure(def_id)
	grid.occupy(_fp.cells(cell, sd.footprint[0], sd.footprint[1], rotation))
	return id


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
	if worst > MAX_SLOPE_DEG:
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
						and p.distance_to(centre) <= PRESENCE_RADIUS:
					present = true
				continue
			var gc: float = Sphere.great_circle(p, centre)
			if not mine and built and sd.build_radius > 0.0 and gc <= sd.build_radius:
				enemy_radius = true
			if mine and built and sd.build_radius > 0.0 and gc <= sd.build_radius:
				in_radius = true
			if _store.def_id[s] == _core_def or _store.def_id[s] == _outpost_def:
				if gc < (MIN_SPACING_FRIENDLY if mine else MIN_SPACING_ENEMY):
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
	var hz: int = _rules.tick_hz
	var econ: EconomyDef = _defs.economy
	if econ == null or hz <= 0 or float(_tick) >= econ.early_share_lock_s * float(hz):
		return Reject.OK
	var mates: int = 0
	for q: int in PlayerTable.SLOTS:
		if _players.is_active(q) and _players.team[q] == team:
			mates += 1
	if mates >= 2 and spent_ore[player] + sd.cost_ore > econ.early_share_ore + delivered_ore[player]:
		return Reject.SPEND_LOCKED
	return Reject.OK
