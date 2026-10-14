class_name LocalSimView extends SimView
## `SimView` over a local `SimWorld`'s arrays (03 s15.4): presentation offline, `sim_ai`, tests, `net`'s encoder.
## Reads are valid until the next `step()` and allocate nothing except the list getters (S3): `order_head` /
## `pending_order` refill one reused `OrderSpec` each, `team_state` / `player_state` one reused view per slot.
## Accessors whose system has not landed return the `SimView` default: service / pad queue (Docking GD-15),
## production (Production), field_remaining (Economy), scores and landing grade (sim/scoring); path_grid_version: TA-50.
## `visible_to` / `visible_ids`: `visible_mask` bit t (Vision, sim/vision/, team t's last staggered pass) or the own team.
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
	var out: PackedInt32Array = PackedInt32Array()
	for live: PackedInt32Array in [_store.structures, _store.ships, _store.ground, _store.wrecks]:
		for s: int in live:
			if _store.team[s] == _team or (_team >= 0 and _team < PlayerTable.TEAMS and ((_store.visible_mask[s] >> _team) & 1) != 0):
				var _a: bool = out.push_back(_store.id_of(s))
	return out


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


## 0 ready, 1 boosting, 2 cooling down.
func boost_state(id: int) -> int:
	var sd: ShipDef = _ship_def(id)
	if sd == null:
		return 0
	var b: float = _store.boost_time[EntityId.slot(id)]
	return 1 if b > 0.0 else (0 if b <= -sd.boost_cooldown_s else 2)


## Share of the flip cooldown still to run: 1 while flipping, 0 when FLIP is ready.
func flip_cooldown01(id: int) -> float:
	var sd: ShipDef = _ship_def(id)
	if sd == null or sd.flip_cooldown_s <= 0.0:
		return 0.0
	var f: float = _store.flip_time[EntityId.slot(id)]
	return 1.0 if f > 0.0 else clampf(1.0 + f / sd.flip_cooldown_s, 0.0, 1.0)


func rockets(id: int) -> int:
	return _store.rockets[EntityId.slot(id)] if _store.alive(id) else 0


## FLYING (0) or DOCKED (2); LANDING_ASSIST and LAUNCHING arrive with Assist (AI-10) and Docking (GD-15).
func dock_state(id: int) -> int:
	return 2 if _store.alive(id) and (_store.flags[EntityId.slot(id)] & EntityStore.F_DOCKED) != 0 else 0


## DOCKED 1, TOWING 2 (tethered), BUILDING 4 from the entity flags; CAPTURING arrives with Economy.
func service_state(id: int) -> int:
	if not _store.alive(id):
		return 0
	var f: int = _store.flags[EntityId.slot(id)]
	if (f & EntityStore.F_BUILDING) != 0:
		return 4
	if (f & EntityStore.F_DOCKED) != 0:
		return 1
	return 2 if (f & EntityStore.F_TETHERED) != 0 else 0


## The docked ship linked to `pad`, or 0.
func pad_occupant(pad: int) -> int:
	if not _store.alive(pad):
		return 0
	for s: int in _store.ships:
		if (_store.flags[s] & EntityStore.F_DOCKED) != 0 and _store.link[s] == pad:
			return _store.id_of(s)
	return 0


## Nearest live friendly structure with a pad (`pad_radius_by_def` > 0), or 0.
func nearest_friendly_pad(id: int) -> int:
	if not _store.alive(id):
		return 0
	var s0: int = EntityId.slot(id)
	var p: Vector3 = _store.pos[s0]
	var best: int = 0
	var best_d2: float = INF
	for s: int in _store.structures:
		var d: int = _store.def_id[s]
		if _store.team[s] != _store.team[s0] or d >= _defs.pad_radius_by_def.size() or _defs.pad_radius_by_def[d] <= 0.0:
			continue
		var d2: float = p.distance_squared_to(_store.pos[s])
		if d2 < best_d2:
			best_d2 = d2
			best = _store.id_of(s)
	return best


func order_head(id: int) -> OrderSpec:
	return _head if _store.alive(id) and _orders.read(EntityId.slot(id), OrderQueue.STANDING, 0, _head) else null


func order_issuer(id: int) -> int:
	return _orders.head_issuer(EntityId.slot(id)) if _store.alive(id) else -1


func pending_order(id: int) -> OrderSpec:
	return _pending if _store.alive(id) and _orders.read(EntityId.slot(id), OrderQueue.PENDING, 0, _pending) else null


func incoming_rockets(id: int) -> int:
	var n: int = 0
	for i: int in _proj.live:
		if _proj.kind[i] == ProjectileStore.ROCKET and _proj.target[i] == id:
			n += 1
	return n


func projectiles_near(p: Vector3, r: float, team_mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in _spatial.ids_near(p, r, Spatial.MASK_PROJECTILE):
		var t: int = _proj.team[_proj.index_of(id)]
		if t < PlayerTable.TEAMS and ((team_mask >> t) & 1) != 0:
			var _a: bool = out.push_back(id)
	return out


func ai_tag(id: int) -> int:
	return _store.ai_tag[EntityId.slot(id)] if _store.alive(id) else 0


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
	var v: TeamStateView = _teams[_team]
	v.team = _team
	v.ore = _players.team_ore[_team]
	v.ice = _players.team_ice[_team]
	var cap: Vector2i = stockpile_cap(_team)
	v.ore_cap = cap.x
	v.ice_cap = cap.y
	var pb: Vector2 = power_balance(_team)
	v.power_supply = pb.x
	v.power_demand = pb.y
	v.unit_cap = _rules.caps.units
	v.structure_cap = _rules.caps.structures
	_players.members(_team, v.members)
	v.eliminated = false
	v.flags = TeamStateView.CORE_EXPOSURE if _state.exposure_tick >= 0 else 0
	if pb.x < pb.y:
		v.flags |= TeamStateView.LOW_POWER
	return v


func player_state(slot: int) -> PlayerStateView:
	if slot < 0 or slot >= PlayerTable.SLOTS:
		return null
	var v: PlayerStateView = _player_views[slot]
	v.slot = slot
	v.team = _players.team[slot]
	v.kind = _players.kind[slot]
	v.doctrine = StringName(_players.doctrine[slot])
	v.possessed = _players.possessed[slot]
	v.eliminated = _players.eliminated[slot] != 0
	v.commander_rights = _players.is_active(slot) and not v.eliminated
	v.connected = _players.connected[slot] != 0
	v.disconnect_tick = _players.disconnect_tick[slot]
	v.adjutant_profile = _players.adjutant_profile[slot]
	v.adjutant_toggles = _players.adjutant_toggles[slot]
	v.unit_count = unit_count(slot)
	v.structure_count = TeamStats.count_owned(_store, slot, _store.structures)
	return v


func terrain_height(dir: Vector3) -> float:
	return _terrain.height_at(dir)


func match_arc() -> int:
	return _rules.arc(_state.tick)


func match_phase() -> int:
	return MatchRules.Phase.ENDED if _state.ended() else _rules.phase(_state.tick)


func match_clock_s() -> float:
	return float(_state.tick) / float(_rules.tick_hz) if _rules.tick_hz > 0 else 0.0


func read_poses(ids: PackedInt32Array, _pos: PackedVector3Array, _rot: PackedVector4Array) -> int:
	var n_alive: int = 0
	for i: int in ids.size():
		var id: int = ids[i]
		if _store.alive(id):
			var s: int = EntityId.slot(id)
			var f: Vector3 = _store.fwd[s]
			var u: Vector3 = _store.up[s]
			var q: Quaternion = Basis(f.cross(u), u, -f).get_rotation_quaternion()
			_pos[i] = _store.pos[s]
			_rot[i] = Vector4(q.x, q.y, q.z, q.w)
			n_alive += 1
		elif EntityId.is_projectile(id) and _proj.alive(id):
			_pos[i] = _proj.pos[_proj.index_of(id)]
			_rot[i] = Vector4(0.0, 0.0, 0.0, 1.0)
			n_alive += 1
		else:
			_pos[i] = Vector3.ZERO
			_rot[i] = Vector4(0.0, 0.0, 0.0, 1.0)
	return n_alive


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
