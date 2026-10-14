class_name SeekerScan extends RefCounted
## Lock seeker scans of `WeaponFire` (extracted under A-73, behaviour unchanged): the nearest-to-boresight hostile and
## the boresight cosine of one candidate. Static and stateless; the caller passes the store arrays as locals.

const _PICK_BITS: PackedInt32Array = [Spatial.MASK_SHIP, Spatial.MASK_GROUND, Spatial.MASK_STRUCTURE]


## The hostile entity of a kind in `mask` within the squared range `r2` and the cone, not below the datum horizon, nearest
## the boresight (ties: the first in ships / ground / structures list order); 0 when none. The horizon test runs only
## for a new best.
static func pick(store: EntityStore, pos: PackedVector3Array, tm: PackedByteArray, s: int, f: Vector3, mask: int,
		r2: float, cone: float) -> int:
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
			if (c > best_c or (best == 0 and c >= best_c)) and not Sphere.is_occluded_by_datum(p, pos[t]):
				best_c = c
				best = t
	return store.id_of(best) if best != 0 else 0


## Boresight cosine of slot `t` seen from `s` (facing `f`), or -2.0 when `t` is friendly, neutral, out of range / cone or
## occluded.
static func score(pos: PackedVector3Array, tm: PackedByteArray, s: int, f: Vector3, t: int, r2: float, cone: float) -> float:
	var team: int = tm[t]
	if team == tm[s] or team == EntityStore.NONE_U8:
		return -2.0
	var p: Vector3 = pos[s]
	var rel: Vector3 = pos[t] - p
	var d2: float = rel.length_squared()
	if d2 <= 0.0 or d2 > r2:
		return -2.0
	var c: float = rel.dot(f) / sqrt(d2)
	if c < cone or Sphere.is_occluded_by_datum(p, pos[t]):
		return -2.0
	return c
