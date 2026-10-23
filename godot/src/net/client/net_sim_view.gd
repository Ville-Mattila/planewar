class_name NetSimView extends SimView
## SimView over replicated state (04 s5.6, s3.7): the client's roster, its SnapshotDecoder frames sampled at a
## fractional render tick (NetPose), the pilot block of its own possessed unit, POSSESSED / RELEASED events and its
## team's TEAM_STATE. `sample(render_tick)` (R0 C2-12) must be called before reads; reads stay valid until the next
## sample. Ids are EntityIds (roster index == sim slot, generation from ENTITY_META). A field the client does not
## receive returns the SimView default and sets the entity's `unknown` bit (04 s3.7 table): C-tier basis / vel, the
## pilot-block fields of every entity but the own possessed unit, the ai_tag of other teams, everything team-private
## of other teams. Not replicated at all (SimView default): overlay, cargo, cargo_kind, link, TEAM_DETAIL accessors
## (NET-39), shield01 / wreck_ore (-1.0, GD-38 / GD-41), path_grid_version. team_state / player_state / order_head /
## pending_order stay the SimView default until net may name TeamStateView / PlayerStateView / OrderSpec (D1;
## `team_flags` carries TEAM_STATE.flags incl. CORE_SHIELD_UP meanwhile). Constants below mirror EntityStore /
## Spatial / SimView enums; test_net_sim_view.gd pins them.

const K_STRUCTURE: int = 0                  ## EntityStore.K_* (def_kind)
const K_SHIP: int = 1
const K_GROUND: int = 2
const K_WRECK: int = 3
const F_ALIVE: int = 1                      ## EntityStore.F_* (flags)
const F_DOCKED: int = 2
const F_POSSESSABLE: int = 8
const MASK_PROJECTILE: int = 16             ## Spatial.MASK_PROJECTILE (ids_near masks are 1 << kind)
const BOOST_MASK: int = 3                   ## PilotBlock.boost_state bits 0-1 = SimView.boost_state
const SERVICE_DOCKED: int = 1               ## SimView.service_state DOCKED
const BYTE_MAX: float = 255.0               ## u8 fractions (hp, flip_cooldown01, service_progress)
const FUEL_DS: float = 0.1                  ## pilot block fuel unit (04 s3.3)
const NONE: int = 255
const TEAMS: int = 8

var team_id: int = 0                        ## the client's team (WELCOME)
var slot_id: int = -1                       ## the client's player slot (WELCOME)
var possessed_index: int = -1               ## roster index of the own possessed unit (POSSESSED event), -1 none
var render_tick: float = 0.0
var stale: bool = false                     ## render_tick is more than 3 ticks past the newest snapshot: frozen
var team_wire: TeamStateWire = TeamStateWire.new()
var pose: NetPose
var roster: Roster
var decoder: SnapshotDecoder
var defs: NetDefs = NetDefs.new()
var terrain: Terrain = null
var _possessor: PackedByteArray = PackedByteArray()
var _possessor_gen: PackedInt32Array = PackedInt32Array()


func _init(roster_ref: Roster, decoder_ref: SnapshotDecoder) -> void:
	roster = roster_ref
	decoder = decoder_ref
	pose = NetPose.new(decoder.store, roster)
	var _a: int = _possessor.resize(Roster.CAPACITY)
	_possessor.fill(NONE)
	var _b: int = _possessor_gen.resize(Roster.CAPACITY)


## Defs (gravity table, radii, hp) and the map's terrain; the decoder's gravity and dt follow.
func bind(net_defs: NetDefs, map_terrain: Terrain) -> void:
	defs = net_defs
	terrain = map_terrain
	decoder.gravity = defs.gravity
	decoder.dt = 1.0 / float(defs.tick_hz)
	decoder.gravity_def = defs.gravity_def
	pose.gravity = defs.gravity
	pose.dt = decoder.dt
	pose.gravity_def = defs.gravity_def


## Picks the frames for `render_tick` (04 s5.6): interpolation, dead reckoning <= 3 ticks, then frozen + stale.
func sample(at_render_tick: float) -> void:
	render_tick = at_render_tick
	pose.sample(at_render_tick)
	stale = pose.stale


## POSSESSED (player) / RELEASED (player NONE) for roster index `index`; the own slot's possession follows.
func set_possessor(index: int, player: int) -> void:
	if index < 0 or index >= Roster.CAPACITY:
		return
	_possessor[index] = player & 0xFF
	_possessor_gen[index] = roster.generation_of(index)
	if player != NONE and player == slot_id:
		possessed_index = index
	elif possessed_index == index:
		possessed_index = -1


func set_team_state(w: TeamStateWire) -> void:
	if w.tick >= team_wire.tick:
		team_wire.copy_from(w)


## TEAM_STATE.flags (TeamStateView bits: CORE_EXPOSURE 1, LOW_POWER 2, CORE_SHIELD_UP 4, SPEND_LOCK_ACTIVE 8) of
## the own team; 0 for other teams and before the first TEAM_STATE.
func team_flags(t: int) -> int:
	return team_wire.flags if t == team_id and team_wire.tick > 0 else 0


## True when some SimView field of `id` is not received by this client (04 s3.7 "unknown" bit).
func unknown(id: int) -> bool:
	var i: int = index_of(id)
	if i < 0:
		return true
	return i != _own() or not pose.has_ori(i) or roster.team_of(i) != team_id


## Roster index of a live replicated EntityId, else -1.
func index_of(id: int) -> int:
	if id <= 0 or EntityId.is_projectile(id):
		return -1
	var i: int = EntityId.slot(id)
	if i >= Roster.CAPACITY or not roster.has(i) or roster.generation_of(i) != EntityId.gen(id) or not pose.present(i):
		return -1
	return i


## The own possessed unit's index while a pilot block has arrived, else -1.
## True when roster index `i` has an entry and a replicated state (the live set every list accessor walks).
func live(i: int) -> bool:
	return roster.has(i) and pose.present(i)


## EntityId of roster index `i`.
func id_at(i: int) -> int:
	return EntityId.make(i, roster.generation_of(i))


func _own() -> int:
	return possessed_index if possessed_index >= 0 and decoder.pilot_tick > 0 else -1


func _flags_byte(i: int) -> int:
	var f: BaselineFrame = pose.frame()
	return f.flags[i] if f != null else 0


func alive(id: int) -> bool:
	return index_of(id) >= 0


func pos(id: int) -> Vector3:
	var i: int = index_of(id)
	return pose.pos_of(i) if i >= 0 else Vector3.ZERO


func vel(id: int) -> Vector3:
	var i: int = index_of(id)
	return pose.vel_of(i) if i >= 0 else Vector3.ZERO


func basis(id: int) -> Basis:
	var i: int = index_of(id)
	if i < 0 or not pose.has_ori(i):
		return Basis.IDENTITY
	var q: Vector4 = pose.rot_of(i)
	return Basis(Quaternion(q.x, q.y, q.z, q.w))


func def_id(id: int) -> int:
	var i: int = index_of(id)
	return roster.def_of(i) if i >= 0 else -1


func owner(id: int) -> int:
	var i: int = index_of(id)
	return _u8(roster.owner_of(i)) if i >= 0 else -1


func team(id: int) -> int:
	var i: int = index_of(id)
	return _u8(roster.team_of(i)) if i >= 0 else -1


func hp01(id: int) -> float:
	var i: int = index_of(id)
	if i < 0:
		return 0.0
	if i == _own():
		var m: float = defs.hp[roster.def_of(i)] if defs.valid(roster.def_of(i)) else 0.0
		return clampf(float(decoder.pilot.hull) / m, 0.0, 1.0) if m > 0.0 else 0.0
	var f: BaselineFrame = pose.frame()
	return Codec.dequantize_hp(f.hp[i]) if f != null else 0.0


func fuel01(id: int) -> float:
	var i: int = index_of(id)
	if i < 0 or i != _own() or not defs.valid(roster.def_of(i)):
		return 0.0
	var s: float = defs.fuel_s[roster.def_of(i)]
	return clampf(float(decoder.pilot.fuel_ds) * FUEL_DS / s, 0.0, 1.0) if s > 0.0 else 0.0


func ammo(id: int) -> int:
	var i: int = index_of(id)
	return decoder.pilot.ammo if i >= 0 and i == _own() else 0


func bombs(id: int) -> int:
	var i: int = index_of(id)
	return decoder.pilot.bombs if i >= 0 and i == _own() else 0


func rockets(id: int) -> int:
	var i: int = index_of(id)
	return decoder.pilot.rockets if i >= 0 and i == _own() else 0


func control_state(id: int) -> int:
	var i: int = index_of(id)
	return Codec.flags_control(_flags_byte(i)) if i >= 0 else 0


func possessor(id: int) -> int:
	var i: int = index_of(id)
	if i < 0 or _possessor_gen[i] != roster.generation_of(i):
		return -1
	return _u8(_possessor[i])


func ai_tag(id: int) -> int:
	var i: int = index_of(id)
	var f: BaselineFrame = pose.frame()
	return f.ai[i] if i >= 0 and f != null and roster.team_of(i) == team_id else 0


func flags(id: int) -> int:
	var i: int = index_of(id)
	if i < 0:
		return 0
	var out: int = F_ALIVE
	if (_flags_byte(i) & Codec.FLAG_DOCKED) != 0:
		out |= F_DOCKED
	var d: int = roster.def_of(i)
	if defs.valid(d) and defs.possessable[d] != 0 and defs.kind_of(d, i) != K_WRECK:
		out |= F_POSSESSABLE
	return out


func radius(id: int) -> float:
	var i: int = index_of(id)
	return defs.radius[roster.def_of(i)] if i >= 0 and defs.valid(roster.def_of(i)) else 0.0


func def_kind(id: int) -> int:
	var i: int = index_of(id)
	return defs.kind_of(roster.def_of(i), i) if i >= 0 else -1


func boost_state(id: int) -> int:
	var i: int = index_of(id)
	return decoder.pilot.boost_state & BOOST_MASK if i >= 0 and i == _own() else 0


func flip_cooldown01(id: int) -> float:
	var i: int = index_of(id)
	return float(decoder.pilot.flip_cooldown) / BYTE_MAX if i >= 0 and i == _own() else 0.0


func dock_state(id: int) -> int:
	var i: int = index_of(id)
	if i < 0:
		return 0
	if i == _own():
		return decoder.pilot.dock_state
	return Protocol.DockState.DOCKED if (_flags_byte(i) & Codec.FLAG_DOCKED) != 0 else Protocol.DockState.FLYING


func service_progress(id: int) -> Vector3:
	var i: int = index_of(id)
	if i < 0 or i != _own():
		return Vector3.ZERO
	var p: PilotBlock = decoder.pilot
	return Vector3(float(p.service_refuel), float(p.service_rearm), float(p.service_repair)) / BYTE_MAX


func service_state(id: int) -> int:
	var i: int = index_of(id)
	return SERVICE_DOCKED if i >= 0 and (_flags_byte(i) & Codec.FLAG_DOCKED) != 0 else 0


func incoming_rockets(id: int) -> int:
	var i: int = index_of(id)
	return decoder.pilot.incoming_rockets if i >= 0 and i == _own() else 0


func tick() -> int:
	return maxi(floori(render_tick), 0)


func match_clock_s() -> float:
	return maxf(render_tick, 0.0) / float(defs.tick_hz)


func terrain_height(dir: Vector3) -> float:
	return terrain.height_at(dir) if terrain != null else 0.0


func ships() -> PackedInt32Array:
	return NetRosterQueries.of_kinds(self, 1 << K_SHIP)


func structures() -> PackedInt32Array:
	return NetRosterQueries.of_kinds(self, 1 << K_STRUCTURE)


func wrecks() -> PackedInt32Array:
	return NetRosterQueries.of_kinds(self, 1 << K_WRECK)


func visible_ids(t: int) -> PackedInt32Array:
	return NetRosterQueries.visible_ids(self, t)


func visible_to(t: int, id: int) -> bool:
	var i: int = index_of(id)
	return i >= 0 and t >= 0 and t < TEAMS and (t == team_id or roster.team_of(i) == t)


func visible_enemy_ships(t: int, out: PackedInt32Array) -> int:
	return NetRosterQueries.enemy_ships(self, t, out)


func ids_in_cell(cell: int) -> PackedInt32Array:
	return NetRosterQueries.in_cell(self, cell)


func ids_near(p: Vector3, r: float, mask: int) -> PackedInt32Array:
	return NetRosterQueries.near(self, p, r, mask)


func nearest_friendly_pad(id: int) -> int:
	var i: int = index_of(id)
	return NetRosterQueries.nearest_pad(self, i) if i >= 0 else 0


func tech_available(t: int, d: int) -> bool:
	return NetRosterQueries.tech_available(self, t, d)


## TEAM_STATE (own team): ore, ice and the power ratio as SimView.stockpile; other teams ZERO (unknown).
func stockpile(t: int) -> Vector3:
	if team_flags_known(t):
		var s: float = float(team_wire.power_supply)
		var d: float = float(team_wire.power_demand)
		return Vector3(float(team_wire.ore), float(team_wire.ice), 1.0 if d <= 0.0 else minf(s / d, 1.0))
	return Vector3.ZERO


func stockpile_cap(t: int) -> Vector2i:
	return Vector2i(team_wire.ore_cap, team_wire.ice_cap) if team_flags_known(t) else Vector2i.ZERO


func power_balance(t: int) -> Vector2:
	return Vector2(float(team_wire.power_supply), float(team_wire.power_demand)) if team_flags_known(t) else Vector2.ZERO


func unit_count(player: int) -> int:
	var k: int = team_wire.member_index(player) if team_wire.tick > 0 else -1
	return team_wire.member_units[k] if k >= 0 else 0


## True when a TEAM_STATE for team `t` (the own team) has arrived.
func team_flags_known(t: int) -> bool:
	return t == team_id and team_wire.tick > 0


## R0 B.11 A-56 over the sampled mirror: pos / basis element-wise, ZERO + identity for dead or unknown ids. The
## index_of test is inlined (per-entity hot path of EntityViewPool.sync, 03 s12.2 rule 9).
func read_poses(ids: PackedInt32Array, out_pos: PackedVector3Array, out_rot: PackedVector4Array) -> int:
	var n: int = 0
	var f: BaselineFrame = pose.frame()
	for k: int in ids.size():
		var id: int = ids[k]
		var i: int = id & EntityId.SLOT_MASK
		if id <= 0 or f == null or i >= Roster.CAPACITY or f.present[i] == 0 				or roster.generation_of(i) != ((id >> EntityId.GEN_SHIFT) & EntityId.GEN_MASK):
			out_pos[k] = Vector3.ZERO
			out_rot[k] = Vector4(0.0, 0.0, 0.0, 1.0)
			continue
		n += 1
		pose.pose_into(i, out_pos, out_rot, k)
	return n


static func _u8(v: int) -> int:
	return -1 if v == NONE else v
