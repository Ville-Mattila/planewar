class_name ThreatMath extends RefCounted
## Pure maths of the threat ring (docs/06 s6.1, UX-19). Forward is -basis.z, right basis.x, up basis.y (03).


## Ring angle of `rel` (world offset to the hostile) in the ship's reticle plane: 0 = up, clockwise positive, (-PI, PI].
static func angle(rel: Vector3, b: Basis) -> float:
	return atan2(rel.dot(b.x), rel.dot(b.y))


## Screen offset of an arrow at `angle` on a ring of `radius` (y grows downwards).
static func ring_pos(a: float, radius: float) -> Vector2:
	return Vector2(sin(a), -cos(a)) * radius


## 1 at the ship, falling linearly to 0 at `range_m`.
static func intensity(dist: float, range_m: float) -> float:
	if range_m <= 0.0:
		return 0.0
	return clampf(1.0 - dist / range_m, 0.0, 1.0)


## True when the hostile lies in front of the nose.
static func ahead(rel: Vector3, b: Basis) -> bool:
	return rel.dot(-b.z) > 0.0
