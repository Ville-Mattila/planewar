class_name SeekerScan extends RefCounted
## Lock seeker scans of `WeaponFire` (extracted under A-73, behaviour unchanged): the nearest-to-boresight hostile and
## the boresight cosine of one candidate. Static and stateless; the caller passes the store arrays as locals. A tower's
## envelope (02 s4.4, GD-09) is optional trailing arguments: a candidate must sit with `|p_t| - |p_s|` inside
## [`h_lo`, `h_hi`] and, when `agl_min` > 0, at least `agl_min` m above the terrain (`terrain` non-null).

const _PICK_BITS: PackedInt32Array = [Spatial.MASK_SHIP, Spatial.MASK_GROUND, Spatial.MASK_STRUCTURE]


## The hostile entity of a kind in `mask` within the squared range `r2` and the cone, not below the datum horizon, nearest
## the boresight (ties: the first in ships / ground / structures list order); 0 when none. The horizon test runs only
## for a new best.
static func pick(store: EntityStore, pos: PackedVector3Array, tm: PackedByteArray, s: int, f: Vector3, mask: int,
		r2: float, cone: float, h_lo: float = -INF, h_hi: float = INF, agl_min: float = 0.0, terrain: Terrain = null) -> int:
	var p: Vector3 = pos[s]
	var mine: int = tm[s]
	var best: int = 0
	var best_c: float = cone
	for li: int in 3:
		if (mask & _PICK_BITS[li]) == 0:
			continue
		var list: PackedInt32Array = store.ships if li == 0 else (store.ground if li == 1 else store.structures)
		for t: int in list:
			var team: int = tm[t]
			if team == mine or team == EntityStore.NONE_U8:
				continue
			var rel: Vector3 = pos[t] - p
			var d2: float = rel.length_squared()
			if d2 > r2 or d2 <= 0.0:
				continue
			var c: float = rel.dot(f) / sqrt(d2)
			if (c > best_c or (best == 0 and c >= best_c)) and in_envelope(p, pos[t], h_lo, h_hi, agl_min, terrain) 					and not Sphere.is_occluded_by_datum(p, pos[t]):
				best_c = c
				best = t
	return store.id_of(best) if best != 0 else 0


## Boresight cosine of slot `t` seen from `s` (facing `f`), or -2.0 when `t` is friendly, neutral, out of range / cone or
## occluded.
static func score(pos: PackedVector3Array, tm: PackedByteArray, s: int, f: Vector3, t: int, r2: float, cone: float,
		h_lo: float = -INF, h_hi: float = INF, agl_min: float = 0.0, terrain: Terrain = null) -> float:
	var team: int = tm[t]
	if team == tm[s] or team == EntityStore.NONE_U8:
		return -2.0
	var p: Vector3 = pos[s]
	var rel: Vector3 = pos[t] - p
	var d2: float = rel.length_squared()
	if d2 <= 0.0 or d2 > r2:
		return -2.0
	var c: float = rel.dot(f) / sqrt(d2)
	if c < cone or not in_envelope(p, pos[t], h_lo, h_hi, agl_min, terrain) or Sphere.is_occluded_by_datum(p, pos[t]):
		return -2.0
	return c


## Whether a target at `pt` sits in the seeker's envelope: height relative to the shooter at `p` inside [`h_lo`, `h_hi`]
## and, when `agl_min` > 0, AGL (`|pt| - R - terrain height`) at least `agl_min`. The AGL read costs a terrain lookup, so
## it runs only for a candidate that passed the cheap tests.
static func in_envelope(p: Vector3, pt: Vector3, h_lo: float, h_hi: float, agl_min: float, terrain: Terrain) -> bool:
	var r: float = pt.length()
	var h: float = r - p.length()
	if h < h_lo or h > h_hi:
		return false
	if agl_min > 0.0 and terrain != null:
		return r - Sphere.PLANET_RADIUS - terrain.height_at(pt / r) >= agl_min
	return true
