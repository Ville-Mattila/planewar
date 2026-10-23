class_name ProjectileQueries extends RefCounted
## Projectile reads of `LocalSimView` (A-73 extraction): rockets homing on an entity and projectiles near a point.


## Live rockets whose target is `id`.
static func incoming_rockets(proj: ProjectileStore, id: int) -> int:
	var n: int = 0
	for i: int in proj.live:
		if proj.kind[i] == ProjectileStore.ROCKET and proj.target[i] == id:
			n += 1
	return n


## Projectile ids within `r` of `p` whose team bit is in `team_mask`.
static func near(proj: ProjectileStore, spatial: Spatial, p: Vector3, r: float, team_mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in spatial.ids_near(p, r, Spatial.MASK_PROJECTILE):
		var t: int = proj.team[proj.index_of(id)]
		if t < PlayerTable.TEAMS and ((team_mask >> t) & 1) != 0:
			var _a: bool = out.push_back(id)
	return out
