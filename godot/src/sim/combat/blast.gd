class_name Blast extends RefCounted
## Area rules of 02 s4.3 (GD-08): bomb kill radius and blast (rules 2-3), flak burst (5) and siege-shell blast.
## Distances to ships and ground units are bounding-sphere edge distances (centre distance minus radius); to
## structures the distance to the footprint rectangle (`edge_distance`). Targets are visited in `Spatial.ids_near`
## order, a function of state alone. Friendly entities are skipped unless `friendly_fire` (rule 8). Lane-internal.

const _BLAST_MASK: int = Spatial.MASK_STRUCTURE | Spatial.MASK_SHIP | Spatial.MASK_GROUND

var friendly_fire: bool = false

var _store: EntityStore
var _spatial: Spatial
var _defs: WorldDefs
var _sink: DamageSink
var _rules: MatchRules
var _events: SimEvents
var _cell_m: float = 0.0


func _init(store: EntityStore, spatial: Spatial, defs: WorldDefs, sink: DamageSink, rules: MatchRules,
		events: SimEvents) -> void:
	_store = store
	_spatial = spatial
	_defs = defs
	_sink = sink
	_rules = rules
	_events = events
	_cell_m = WorldDefs.build_cell_m()


## Bomb detonation at `pos` (rules 2-3): ships whose bounding sphere is within `blast_radius_m` are destroyed
## (a ship docked in a roofed Hangar is immune); ground units and structures within `blast_radius_structure_m` take
## the rolled damage times their multiplier (structures: `bomb_mult`, the Core's exposure factor).
func bomb(pos: Vector3, owner_team: int, attacker: int, w: WeaponDef, p: ProjectileDef, rng: Rng, tick: int) -> void:
	var reach: float = maxf(p.blast_radius_m, p.blast_radius_structure_m) + _spatial.max_entity_radius
	for id: int in _spatial.ids_near(pos, reach, _BLAST_MASK):
		var s: int = EntityId.slot(id)
		if not _hostile(s, owner_team):
			continue
		var k: int = _store.kind[s]
		if k == EntityStore.K_SHIP:
			if _gap(pos, s) <= p.blast_radius_m and not hangar_docked(s):
				var _d: bool = _sink.destroy(s, attacker, tick)
		elif k == EntityStore.K_GROUND:
			if _gap(pos, s) <= p.blast_radius_structure_m:
				var _g: bool = _sink.damage(s, float(Combat.roll_gun_damage(w, k, rng)), attacker, tick)
		elif edge_distance(pos, s) <= p.blast_radius_structure_m:
			var amount: int = Combat.roll_gun_damage(w, k, rng, bomb_mult(s, tick))
			var _t: bool = _sink.damage(s, float(amount), attacker, tick)
	var _e: SimEvent = _events.emit(SimEvent.Kind.BOMB_IMPACT, attacker, 0, pos, p.blast_radius_m, owner_team)


## Flak burst (rule 5): the weapon's damage to every enemy ship whose bounding sphere is within `blast_radius_m`;
## never ground units or structures.
func flak(pos: Vector3, owner_team: int, attacker: int, w: WeaponDef, p: ProjectileDef, rng: Rng, tick: int) -> void:
	for id: int in _spatial.ids_near(pos, p.blast_radius_m + _spatial.max_entity_radius, Spatial.MASK_SHIP):
		var s: int = EntityId.slot(id)
		if _hostile(s, owner_team) and _gap(pos, s) <= p.blast_radius_m:
			var _h: bool = _sink.damage(s, float(Combat.roll_gun_damage(w, EntityStore.K_SHIP, rng)), attacker, tick)


## Siege-shell blast: every hostile ship, ground unit and structure inside the blast radii takes the rolled
## damage times the weapon's own structure / ground multiplier (no other multiplier applies to shells).
func shell(pos: Vector3, owner_team: int, attacker: int, w: WeaponDef, p: ProjectileDef, rng: Rng, tick: int) -> void:
	var reach: float = maxf(p.blast_radius_m, p.blast_radius_structure_m) + _spatial.max_entity_radius
	for id: int in _spatial.ids_near(pos, reach, _BLAST_MASK):
		var s: int = EntityId.slot(id)
		if not _hostile(s, owner_team):
			continue
		var k: int = _store.kind[s]
		var d: float = edge_distance(pos, s) if k == EntityStore.K_STRUCTURE else _gap(pos, s)
		if d <= (p.blast_radius_m if k == EntityStore.K_SHIP else p.blast_radius_structure_m):
			var _h: bool = _sink.damage(s, float(Combat.roll_gun_damage(w, k, rng)), attacker, tick)


## True for a ship docked (DOCKED flag, `link` = a live structure) in a roofed pad: the Hangar (rule 2).
func hangar_docked(s: int) -> bool:
	if (_store.flags[s] & EntityStore.F_DOCKED) == 0 or not _store.alive(_store.link[s]):
		return false
	var h: int = EntityId.slot(_store.link[s])
	if _store.kind[h] != EntityStore.K_STRUCTURE:
		return false
	var sd: StructureDef = _defs.base.structure(_store.def_id[h])
	return sd != null and sd.pad_roofed


## Bomb damage factor of structure slot `s`: a structure its def's `structure_bomb_mult` (the Hangar roof, 02 s4.3 rule 3, A-66), a Core after Exposure
## `match_rules.core_bomb_mult_exposure`, else 1.0.
func bomb_mult(s: int, tick: int) -> float:
	var sd: StructureDef = _defs.base.structure(_store.def_id[s])
	if sd == null:
		return 1.0
	var m: float = _defs.bomb_mult_by_def[_store.def_id[s]]
	if m != 1.0:
		return m
	var mr: MatchRulesDef = _defs.content.match_rules
	if sd.id == &"core" and mr != null and _rules.phase(tick) == MatchRules.Phase.EXPOSURE:
		return mr.core_bomb_mult_exposure
	return 1.0


## Distance from `pos` to structure slot `s`'s footprint: a zero-thickness rectangle in the plane through its
## position with normal `up`, `footprint[0]` cells along the right axis (fwd x up) and `footprint[1]` along fwd.
func edge_distance(pos: Vector3, s: int) -> float:
	var sd: StructureDef = _defs.base.structure(_store.def_id[s])
	var w: int = sd.footprint[0] if sd != null and sd.footprint.size() > 0 else 1
	var h: int = sd.footprint[1] if sd != null and sd.footprint.size() > 1 else w
	return rect_distance(pos - _store.pos[s], _store.fwd[s], _store.up[s], float(w) * _cell_m * 0.5,
		float(h) * _cell_m * 0.5)


## Distance from the point `rel` (relative to the rectangle centre) to the rectangle with half extents `hw` along
## `fwd.cross(up)` and `hh` along `fwd` in the plane normal to `up`. Pure.
static func rect_distance(rel: Vector3, fwd: Vector3, up: Vector3, hw: float, hh: float) -> float:
	var right: Vector3 = fwd.cross(up)
	var dx: float = maxf(absf(rel.dot(right)) - hw, 0.0)
	var dz: float = maxf(absf(rel.dot(fwd)) - hh, 0.0)
	var dy: float = rel.dot(up)
	return sqrt(dx * dx + dz * dz + dy * dy)


func _gap(pos: Vector3, s: int) -> float:
	return pos.distance_to(_store.pos[s]) - _store.radius[s]


func _hostile(s: int, owner_team: int) -> bool:
	return friendly_fire or _store.team[s] != owner_team
