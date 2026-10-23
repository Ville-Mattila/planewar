class_name LocalSimView extends SimView
## `SimView` over a local `SimWorld`'s arrays (03 s15.4): presentation offline, `sim_ai`, tests, `net`'s encoder.
## Reads are valid until the next `step()` and allocate nothing except the list getters (S3): `order_head` /
## `pending_order` refill one reused `OrderSpec` each, `team_state` / `player_state` one reused view per slot.
## Accessors whose system has not landed return the `SimView` default: field_remaining (Economy), scores (GD-27).
## `visible_to` / `visible_ids` (walks every live slot) / `visible_enemy_ships` (Vision's list): `visible_mask` bit t (Vision, sim/vision/, team t's last staggered pass) or the own team.
## basis(id) = Basis(right, up, -fwd) with right = fwd x up (Godot's -Z forward).

var _store: EntityStore
var _proj: ProjectileStore
var _spatial: Spatial
var _terrain: Terrain
var _players: PlayerTable
var _defs: WorldDefs
var _orders: OrderQueue
var _rules: MatchRules
var _state: MatchState
var _head: OrderSpec = OrderSpec.new()
var _pending: OrderSpec = OrderSpec.new()
var _teams: Array[TeamStateView] = []
var _player_views: Array[PlayerStateView] = []
var _pathing: Pathing = null
var production: Production = null   ## set by SimWorld (TA-19): queue and progress reads
var shields: ShieldDomes = null       ## set by SimWorld (GD-38): `shield01` and the CORE_SHIELD_UP flag read it
var vision: Vision = null             ## set by SimWorld (TA-63): `visible_enemy_ships` reads its per-team lists
var docking: Docking = null           ## set by SimWorld (GD-15): service progress, pad queues, landing grades


func _init(store: EntityStore, projectiles: ProjectileStore, spatial: Spatial, terrain: Terrain, players: PlayerTable,
		defs: WorldDefs, orders: OrderQueue, rules: MatchRules, state: MatchState, pathing: Pathing = null) -> void:
	_store = store
	_pathing = pathing
	_proj = projectiles
	_spatial = spatial
	_terrain = terrain
	_players = players
	_defs = defs
	_orders = orders
	_rules = rules
	_state = state
	for _t: int in PlayerTable.TEAMS:
		_teams.append(TeamStateView.new())
	for _p: int in PlayerTable.SLOTS:
		_player_views.append(PlayerStateView.new())


func alive(id: int) -> bool:
	return _store.alive(id) or (EntityId.is_projectile(id) and _proj.alive(id))


func pos(id: int) -> Vector3:
	if _store.alive(id):
		return _store.pos[EntityId.slot(id)]
	return _proj.pos[_proj.index_of(id)] if EntityId.is_projectile(id) and _proj.alive(id) else Vector3.ZERO


func vel(id: int) -> Vector3:
	if _store.alive(id):
		return _store.vel[EntityId.slot(id)]
	return _proj.vel[_proj.index_of(id)] if EntityId.is_projectile(id) and _proj.alive(id) else Vector3.ZERO


func basis(id: int) -> Basis:
	if not _store.alive(id):
		return Basis.IDENTITY
	var s: int = EntityId.slot(id)
	var f: Vector3 = _store.fwd[s]
	var u: Vector3 = _store.up[s]
	return Basis(f.cross(u), u, -f)


func def_id(id: int) -> int:
	return _store.def_id[EntityId.slot(id)] if _store.alive(id) else -1


func owner(id: int) -> int:
	return _u8(_store.owner[EntityId.slot(id)]) if _store.alive(id) else -1


func team(id: int) -> int:
	return _u8(_store.team[EntityId.slot(id)]) if _store.alive(id) else -1


func hp01(id: int) -> float:
	if not _store.alive(id):
		return 0.0
	var s: int = EntityId.slot(id)
	var m: float = _defs.hp_max(_store.owner[s], _store.def_id[s])
	return clampf(_store.hp[s] / m, 0.0, 1.0) if m > 0.0 else 0.0


func fuel01(id: int) -> float:
	var sd: ShipDef = _ship_def(id)
	return clampf(_store.fuel[EntityId.slot(id)] / sd.fuel_s, 0.0, 1.0) if sd != null and sd.fuel_s > 0.0 else 0.0


func ammo(id: int) -> int:
	return _store.ammo[EntityId.slot(id)] if _store.alive(id) else 0


func bombs(id: int) -> int:
	return _store.bombs[EntityId.slot(id)] if _store.alive(id) else 0


func control_state(id: int) -> int:
	return _store.control_state[EntityId.slot(id)] if _store.alive(id) else 0


func possessor(id: int) -> int:
	return _u8(_store.possessor[EntityId.slot(id)]) if _store.alive(id) else -1


func ids_in_cell(cell: int) -> PackedInt32Array:
	return _spatial.ids_in_hash_cell(cell)


func ids_near(p: Vector3, _radius: float, mask: int) -> PackedInt32Array:
	return _spatial.ids_near(p, _radius, mask)


func stockpile(_team: int) -> Vector3:
	if _team < 0 or _team >= PlayerTable.TEAMS:
		return Vector3.ZERO
	var pb: Vector2 = power_balance(_team)
	var ratio: float = 1.0 if pb.y <= 0.0 else minf(pb.x / pb.y, 1.0)
	return Vector3(float(_players.team_ore[_team]), float(_players.team_ice[_team]), ratio)


func visible_to(_team: int, id: int) -> bool:
	if not _store.alive(id) or _team < 0 or _team >= PlayerTable.TEAMS:
		return false
	var s: int = EntityId.slot(id)
	return _store.team[s] == _team or ((_store.visible_mask[s] >> _team) & 1) != 0


func tick() -> int:
	return _state.tick


func visible_ids(_team: int) -> PackedInt32Array:
	return TeamStats.visible_ids(_store, _team)


## Vision's per-team list, not the store (V10, TA-63).
func visible_enemy_ships(_team: int, out: PackedInt32Array) -> int:
	return 0 if vision == null else vision.enemy_ships(_team, out)


func ships() -> PackedInt32Array:
	return _ids_of(_store.ships)


func structures() -> PackedInt32Array:
	return _ids_of(_store.structures)


func wrecks() -> PackedInt32Array:
	return _ids_of(_store.wrecks)


func flags(id: int) -> int:
	return _store.flags[EntityId.slot(id)] if _store.alive(id) else 0


func radius(id: int) -> float:
	return _store.radius[EntityId.slot(id)] if _store.alive(id) else 0.0


func def_kind(id: int) -> int:
	return _store.kind[EntityId.slot(id)] if _store.alive(id) else -1


func cargo(id: int) -> float:
	return _store.cargo[EntityId.slot(id)] if _store.alive(id) else 0.0


func cargo_kind(id: int) -> int:
	return _store.cargo_kind[EntityId.slot(id)] if _store.alive(id) else 0


func link(id: int) -> int:
	return _store.link[EntityId.slot(id)] if _store.alive(id) else 0


func boost_state(id: int) -> int:
	return ShipReads.boost_state(_store, _ship_def(id), id)


func flip_cooldown01(id: int) -> float:
	return ShipReads.flip_cooldown01(_store, _ship_def(id), id)


func rockets(id: int) -> int:
	return _store.rockets[EntityId.slot(id)] if _store.alive(id) else 0


func dock_state(id: int) -> int:
	return ShipReads.dock_state(_store, id)


func service_state(id: int) -> int:
	return ShipReads.service_state(_store, id)


## (fuel01, rearm line, hp01) of a ship docked on a service pad, ZERO otherwise (Docking, GD-15).
func service_progress(id: int) -> Vector3:
	return docking.service_progress(id) if docking != null else Vector3.ZERO


func pad_queue(pad: int) -> PackedInt32Array:
	return docking.pad_queue(pad) if docking != null else PackedInt32Array()


## The docked ship linked to `pad`, or 0 (PadQueries).
func pad_occupant(pad: int) -> int:
	return PadQueries.occupant(_store, _defs, pad)


## Nearest live friendly structure with a pad (`pad_radius_by_def` > 0), or 0.
func nearest_friendly_pad(id: int) -> int:
	return PadQueries.nearest_friendly(_store, _defs, id)


func order_head(id: int) -> OrderSpec:
	return _head if _store.alive(id) and _orders.read(EntityId.slot(id), OrderQueue.STANDING, 0, _head) else null


func order_issuer(id: int) -> int:
	return _orders.head_issuer(EntityId.slot(id)) if _store.alive(id) else -1


func pending_order(id: int) -> OrderSpec:
	return _pending if _store.alive(id) and _orders.read(EntityId.slot(id), OrderQueue.PENDING, 0, _pending) else null


func incoming_rockets(id: int) -> int:
	return ProjectileQueries.incoming_rockets(_proj, id)


func projectiles_near(p: Vector3, r: float, team_mask: int) -> PackedInt32Array:
	return ProjectileQueries.near(_proj, _spatial, p, r, team_mask)


func ai_tag(id: int) -> int:
	return _store.ai_tag[EntityId.slot(id)] if _store.alive(id) else 0


func overlay(id: int) -> int:
	return _store.overlay[EntityId.slot(id)] if _store.alive(id) else 0


func stockpile_cap(_team: int) -> Vector2i:
	return TeamStats.stockpile_cap(_store, _defs, _team)


func power_balance(_team: int) -> Vector2:
	return TeamStats.power_balance(_store, _defs, _team)


func unit_count(player: int) -> int:
	return TeamStats.count_owned(_store, player, _store.ships) + TeamStats.count_owned(_store, player, _store.ground)


func tech_available(_team: int, _def_id: int) -> bool:
	return TeamStats.tech_available(_store, _defs, _team, _def_id)


func team_state(_team: int) -> TeamStateView:
	if _team < 0 or _team >= PlayerTable.TEAMS:
		return null
	TeamStats.fill_team(_teams[_team], _team, _store, _defs, _players, _rules, _state)
	if shields != null and shields.core_up(_team):
		_teams[_team].flags |= TeamStateView.CORE_SHIELD_UP
	return _teams[_team]


func player_state(slot: int) -> PlayerStateView:
	if slot < 0 or slot >= PlayerTable.SLOTS:
		return null
	var v: PlayerStateView = _player_views[slot]
	TeamStats.fill_player(v, _players, slot)
	v.unit_count = unit_count(slot)
	v.structure_count = TeamStats.count_owned(_store, slot, _store.structures)
	return v


## Tower ammo pool fill 0..1 (02 s5.4 pool bars); 0 for a site, a non-tower or a dead id (TeamStats).
func supply01(id: int) -> float:
	return TeamStats.supply01(_store, _defs, id)


## Dome charge / effective cap (SH11); 0 for a collapsed or removed dome and for an entity without one.
func shield01(id: int) -> float:
	return shields.charge01(EntityId.slot(id), _state.tick) if shields != null and _store.alive(id) else 0.0


## Remaining Ore of a live wreck (its `hp`, GD-19); 0.0 for any other entity or a dead id.
func wreck_ore(id: int) -> float:
	return _store.hp[EntityId.slot(id)] if _store.alive(id) and _store.kind[EntityId.slot(id)] == EntityStore.K_WRECK else 0.0


func production_queue(factory: int) -> PackedInt32Array:
	return production.queue_of(EntityId.slot(factory)) if production != null and _store.alive(factory) else PackedInt32Array()


func production_progress01(factory: int) -> float:
	return production.progress01(EntityId.slot(factory)) if production != null and _store.alive(factory) else 0.0


func auto_replenish_target(player: int, _def_id: int) -> int:
	return production.replenish.target_of(player, _def_id) if production != null else 0


func terrain_height(dir: Vector3) -> float:
	return _terrain.height_at(dir)


func match_arc() -> int:
	return _rules.arc(_state.tick)


func match_phase() -> int:
	return MatchRules.Phase.ENDED if _state.ended() else _rules.phase(_state.tick)


func match_clock_s() -> float:
	return float(_state.tick) / float(_rules.tick_hz) if _rules.tick_hz > 0 else 0.0


func landing_grade_last(id: int) -> int:
	return docking.landing_grade_last(id) if docking != null else -1


func read_poses(ids: PackedInt32Array, _pos: PackedVector3Array, _rot: PackedVector4Array) -> int:
	return PoseReader.read(_store, _proj, ids, _pos, _rot)


func _ship_def(id: int) -> ShipDef:
	if not _store.alive(id):
		return null
	var s: int = EntityId.slot(id)
	return _defs.ship(_store.owner[s], _store.def_id[s]) if _store.kind[s] == EntityStore.K_SHIP else null


func _ids_of(live: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var _r: int = out.resize(live.size())
	for k: int in live.size():
		out[k] = _store.id_of(live[k])
	return out


static func _u8(v: int) -> int:
	return -1 if v == EntityStore.NONE_U8 else v


func path_grid_version(face: int) -> int:
	return _pathing.version(face) if _pathing != null and face >= 0 and face < PathGrid.FACES else 0
