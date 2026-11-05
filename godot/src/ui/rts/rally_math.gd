class_name RallyMath extends RefCounted
## Rally flag line (docs/06 s7.2): a great-circle arc from the factory to the rally point, altitude blended,
## ending in a flag pole of rally_flag_height_m.


static func line_points(from: Vector3, to: Vector3) -> PackedVector3Array:
	var n: int = maxi(int(RtsParams.param("rally_segments")), 1)
	var out: PackedVector3Array = PackedVector3Array()
	var ra: float = from.length()
	var rb: float = to.length()
	if ra <= 0.0 or rb <= 0.0:
		return out
	var da: Vector3 = from / ra
	var db: Vector3 = to / rb
	var same: bool = da.dot(db) > 0.9999
	for i: int in n + 1:
		var t: float = float(i) / float(n)
		var d: Vector3 = da.lerp(db, t).normalized() if same else da.slerp(db, t)
		var _a: bool = out.append(d * lerpf(ra, rb, t))
	var _b: bool = out.append(to + db * RtsParams.param("rally_flag_height_m"))
	return out
