class_name NetRosterQueries
## The roster walks behind NetSimView's list and proximity accessors (split out for the 400-line rule). Kind lists walk
## the 1,536 entity indices; cell, proximity and pose reads also walk the projectile block (R0 B.22 A-112), as
## LocalSimView's spatial hash holds projectiles. Each allocates only its result (SimView S3: list getters allocate).

const PROJECTILE_KIND_BIT: int = 4          ## Spatial masks are 1 << kind; projectiles are MASK_PROJECTILE = 1 << 4


static func of_kinds(v: NetSimView, mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in Roster.ENTITY_SLOTS:
		if v.live(i):
			var k: int = v.defs.kind_of(v.roster.def_of(i), i)
			if k >= 0 and (mask & (1 << k)) != 0:
				var _a: bool = out.push_back(v.id_at(i))
	return out


## Own team: every replicated entity (the interest set is the team's vision, 04 s4.1); other teams: their own entities
## this client knows of (an entity always sees itself); bad teams: empty.
static func visible_ids(v: NetSimView, t: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if t < 0 or t >= NetSimView.TEAMS:
		return out
	for i: int in Roster.ENTITY_SLOTS:                  # projectiles are never visible_to (LocalSimView)
		if v.live(i) and (t == v.team_id or v.roster.team_of(i) == t):
			var _a: bool = out.push_back(v.id_at(i))
	return out


## Own team: replicated ships of other teams, ascending id, into the caller's `out` (grown, never shrunk); other teams'
## vision is not received (0).
static func enemy_ships(v: NetSimView, t: int, out: PackedInt32Array) -> int:
	if t != v.team_id or t < 0 or t >= NetSimView.TEAMS:
		return 0
	var n: int = 0
	for i: int in Roster.ENTITY_SLOTS:
		if v.live(i) and v.roster.team_of(i) != t and v.defs.kind_of(v.roster.def_of(i), i) == NetSimView.K_SHIP:
			if n >= out.size():
				var _r: int = out.resize(n + 1)
			out[n] = v.id_at(i)
			n += 1
	return n


## Entities whose sampled position hashes to `cell` (Sphere.GRID_HASH, the Spatial cell).
static func in_cell(v: NetSimView, cell: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in Roster.CAPACITY:
		if v.live(i) and Sphere.cell_of(v.pose.pos_of(i), Sphere.GRID_HASH) == cell:
			var _a: bool = out.push_back(v.id_at(i))
	return out


## Centre distance <= r, kind bit in `mask` (Spatial masks: 1 << kind; a projectile entity is MASK_PROJECTILE).
static func near(v: NetSimView, p: Vector3, r: float, mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if r < 0.0:
		return out
	var r2: float = r * r
	for i: int in Roster.CAPACITY:
		if v.live(i):
			var k: int = PROJECTILE_KIND_BIT if i >= Roster.PROJECTILE_INDEX_MIN else v.defs.kind_of(v.roster.def_of(i), i)
			if k >= 0 and (mask & (1 << k)) != 0 and v.pose.pos_of(i).distance_squared_to(p) <= r2:
				var _a: bool = out.push_back(v.id_at(i))
	return out


## Nearest replicated structure with a service pad of the same team as roster index `i0` (04 s3.7: from the roster).
static func nearest_pad(v: NetSimView, i0: int) -> int:
	var p: Vector3 = v.pose.pos_of(i0)
	var best: int = 0
	var best_d2: float = INF
	for i: int in Roster.ENTITY_SLOTS:
		var d: int = v.roster.def_of(i)
		if v.live(i) and v.roster.team_of(i) == v.roster.team_of(i0) and v.defs.kind_of(d, i) == NetSimView.K_STRUCTURE \
				and v.defs.pad[d] != 0:
			var d2: float = p.distance_squared_to(v.pose.pos_of(i))
			if d2 < best_d2:
				best_d2 = d2
				best = v.id_at(i)
	return best


## Own team: every `requires[]` def has a replicated own-team structure (04 s3.7 "derived from own roster structures");
## other teams: false (not received).
static func tech_available(v: NetSimView, t: int, d: int) -> bool:
	if t != v.team_id or not v.defs.valid(d) or v.defs.kind[d] < 0:
		return false
	for need: int in v.defs.requires_of(d):
		if not _has_structure(v, need):
			return false
	return true


static func _has_structure(v: NetSimView, d: int) -> bool:
	for i: int in Roster.ENTITY_SLOTS:
		if v.live(i) and v.roster.def_of(i) == d and v.roster.team_of(i) == v.team_id \
				and v.defs.kind_of(d, i) == NetSimView.K_STRUCTURE:
			return true
	return false


## Replicated projectile entities (the roster block) within `r` of `p` whose team bit is in `team_mask` (A-112).
static func projectiles_near(v: NetSimView, p: Vector3, r: float, team_mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if r < 0.0:
		return out
	var r2: float = r * r
	for i: int in range(Roster.PROJECTILE_INDEX_MIN, Roster.CAPACITY):
		var t: int = v.roster.team_of(i)
		var hit: bool = t >= 0 and t < NetSimView.TEAMS and ((team_mask >> t) & 1) != 0 and v.live(i)
		if hit and v.pose.pos_of(i).distance_squared_to(p) <= r2:
			var _a: bool = out.push_back(v.id_at(i))
	return out


## NetSimView.read_poses: pos / quaternion of each id from the sampled mirror; ZERO + identity for dead ids. The id test
## is inlined (per-entity hot path of EntityViewPool.sync, 03 s12.2 rule 9); projectile slots map into the block.
static func read_poses(v: NetSimView, ids: PackedInt32Array, out_pos: PackedVector3Array, out_rot: PackedVector4Array) -> int:
	var n: int = 0
	var f: BaselineFrame = v.pose.frame()
	var roster: Roster = v.roster
	for k: int in ids.size():
		var id: int = ids[k]
		var i: int = id & EntityId.SLOT_MASK
		if i >= Roster.ENTITY_SLOTS:
			i = Roster.index_of_slot(i) if i >= EntityId.PROJECTILE_SLOT_MIN else -1
		var ok: bool = id > 0 and f != null and i >= 0 and v.pose.present(i)
		if not ok or roster.generation_of(i) != ((id >> EntityId.GEN_SHIFT) & EntityId.GEN_MASK):
			out_pos[k] = Vector3.ZERO
			out_rot[k] = Vector4(0.0, 0.0, 0.0, 1.0)
			continue
		n += 1
		v.pose.pose_into(i, out_pos, out_rot, k)
	return n
